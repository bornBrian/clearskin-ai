-- Quotas that can't be raced, rewarded-ad scan credits, and per-call cost.
--
-- Before: an Edge Function counted usage, called Claude, then inserted the
-- usage row. Two parallel requests could both pass the count and both get a
-- free scan. Now a request *reserves* its slot inside one transaction that
-- holds a per-user advisory lock, so the count and the insert are atomic.

alter table public.usage_events
  add column if not exists status text not null default 'done'
    check (status in ('reserved', 'done')),
  -- SHA-256 of the app-scoped Android ID. Free quotas are counted per
  -- account AND per device, so reinstalling or making new anonymous
  -- accounts doesn't reset them. Never linked to the advertising ID.
  add column if not exists device_hash text
    check (device_hash is null or device_hash ~ '^[0-9a-f]{64}$'),
  add column if not exists cache_read_tokens integer,
  add column if not exists cache_write_tokens integer,
  add column if not exists cost_usd numeric(10, 6),
  add column if not exists credit_id bigint,
  -- Spent tokens but given back to the user (e.g. the photo was unusable).
  -- Kept for cost tracking, ignored by quotas.
  add column if not exists refunded boolean not null default false;

-- Deleting an account keeps its usage rows, unlinked from the person
-- (user_id becomes null). Otherwise "delete account, sign in again" would
-- reset the device's free scans. What's left is a hashed device id, a
-- kind, a time and a cost; the 90-day purge removes it.
alter table public.usage_events alter column user_id drop not null;
alter table public.usage_events drop constraint if exists usage_events_user_id_fkey;
alter table public.usage_events
  add constraint usage_events_user_id_fkey
  foreign key (user_id) references auth.users (id) on delete set null;

create index if not exists usage_events_device_kind_time
  on public.usage_events (device_hash, kind, created_at desc)
  where device_hash is not null;

create index if not exists usage_events_time
  on public.usage_events (created_at desc);

-- One row per rewarded video the user finished, verified by AdMob's signed
-- server-side callback. transaction_id is unique, so a replayed callback
-- can never mint a second credit.
create table if not exists public.scan_credits (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  source text not null check (source in ('rewarded_ad')),
  transaction_id text not null unique,
  created_at timestamptz not null default now(),
  consumed_at timestamptz
);

create index if not exists scan_credits_user_open
  on public.scan_credits (user_id, created_at)
  where consumed_at is null;

alter table public.scan_credits enable row level security;

alter table public.usage_events
  drop constraint if exists usage_events_credit_fk;
alter table public.usage_events
  add constraint usage_events_credit_fk
  foreign key (credit_id) references public.scan_credits (id) on delete set null;

-- Reserves one unit of usage, or explains why not. Called only by Edge
-- Functions with the service role. All inputs are typed parameters; no
-- dynamic SQL anywhere.
--
-- Free users: p_free_limit per rolling p_window, counted per account and
-- per device (whichever is higher). When that's used up, an unspent
-- rewarded-ad credit is consumed instead.
-- Premium users: p_daily_limit per UTC day (fair use, abuse protection).
-- Everyone: at most p_attempt_limit attempts per account or device in 24
-- hours, refunded ones included. Unusable photos are refunded, so without
-- this a script could send junk images forever and spend our AI budget
-- without ever using up a scan.
create or replace function public.reserve_usage(
  p_user uuid,
  p_kind text,
  p_device text,
  p_premium boolean,
  p_free_limit integer,
  p_window interval,
  p_daily_limit integer,
  p_attempt_limit integer
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_used integer;
  v_device_used integer := 0;
  v_attempts integer;
  v_credit bigint;
  v_id bigint;
  v_since timestamptz;
begin
  if p_kind not in ('scan', 'coach') then
    raise exception 'bad kind';
  end if;

  -- Serialise this user's reservations (and this device's) for the rest of
  -- the transaction.
  perform pg_advisory_xact_lock(hashtextextended('usage:' || p_user::text, 0));
  if p_device is not null then
    perform pg_advisory_xact_lock(hashtextextended('usage-dev:' || p_device, 0));
  end if;

  -- Reservations older than 3 minutes belong to requests that crashed;
  -- they shouldn't block anyone.
  delete from usage_events
   where user_id = p_user and status = 'reserved'
     and created_at < now() - interval '3 minutes';

  select count(*) into v_attempts from usage_events
   where kind = p_kind and created_at >= now() - interval '1 day'
     and (user_id = p_user or (p_device is not null and device_hash = p_device));
  if v_attempts >= p_attempt_limit then
    return jsonb_build_object('ok', false, 'reason', 'attempt_limit', 'used', v_attempts);
  end if;

  if p_premium then
    select count(*) into v_used from usage_events
     where user_id = p_user and kind = p_kind and not refunded
       and created_at >= date_trunc('day', now() at time zone 'utc') at time zone 'utc';
    if v_used >= p_daily_limit then
      return jsonb_build_object('ok', false, 'reason', 'daily_limit', 'used', v_used);
    end if;
  else
    v_since := now() - p_window;
    select count(*) into v_used from usage_events
     where user_id = p_user and kind = p_kind and created_at >= v_since
       and credit_id is null and not refunded;
    if p_device is not null then
      select count(*) into v_device_used from usage_events
       where device_hash = p_device and kind = p_kind and created_at >= v_since
         and credit_id is null and not refunded;
    end if;
    v_used := greatest(v_used, v_device_used);

    if v_used >= p_free_limit then
      select id into v_credit from scan_credits
       where user_id = p_user and consumed_at is null and p_kind = 'scan'
       order by created_at
       limit 1
       for update skip locked;
      if v_credit is null then
        return jsonb_build_object('ok', false, 'reason', 'free_limit', 'used', v_used);
      end if;
      update scan_credits set consumed_at = now() where id = v_credit;
    end if;
  end if;

  insert into usage_events (user_id, kind, status, device_hash, credit_id)
  values (p_user, p_kind, 'reserved', p_device, v_credit)
  returning id into v_id;

  return jsonb_build_object('ok', true, 'event_id', v_id, 'used', v_used,
                            'used_credit', v_credit is not null);
end;
$$;

-- Gives a reservation back. Never-finished reservations (the AI call
-- failed) are deleted; finished ones (tokens spent, photo unusable) are
-- flagged refunded so their cost stays on the books. A consumed credit is
-- returned to the user either way.
create or replace function public.release_usage(p_event bigint)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_credit bigint;
begin
  delete from usage_events
   where id = p_event and status = 'reserved'
  returning credit_id into v_credit;
  if not found then
    select credit_id into v_credit from usage_events
     where id = p_event and not refunded
     for update;
    update usage_events set refunded = true, credit_id = null
     where id = p_event;
  end if;
  if v_credit is not null then
    update scan_credits set consumed_at = null where id = v_credit;
  end if;
end;
$$;

-- Total estimated AI spend since a moment (the daily circuit breaker).
create or replace function public.ai_spend_since(p_since timestamptz)
returns numeric
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(sum(cost_usd), 0) from usage_events where created_at >= p_since;
$$;

revoke all on function public.ai_spend_since(timestamptz) from public, anon, authenticated;
grant execute on function public.ai_spend_since(timestamptz) to service_role;

-- Edge Functions only. Clients (anon / authenticated) can't call these or
-- read the tables (RLS on, no policies).
revoke all on function public.reserve_usage(uuid, text, text, boolean, integer, interval, integer, integer)
  from public, anon, authenticated;
revoke all on function public.release_usage(bigint) from public, anon, authenticated;
grant execute on function public.reserve_usage(uuid, text, text, boolean, integer, interval, integer, integer)
  to service_role;
grant execute on function public.release_usage(bigint) to service_role;

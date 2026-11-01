-- A third kind of metered request: 'insight', the low-cost, text-only
-- explanation of a scan measured on the phone (skin-insight). It gets its
-- own daily limits and its cost is tracked like scans and coach replies.

alter table public.usage_events drop constraint if exists usage_events_kind_check;
alter table public.usage_events
  add constraint usage_events_kind_check check (kind in ('scan', 'coach', 'insight'));

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
  if p_kind not in ('scan', 'coach', 'insight') then
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

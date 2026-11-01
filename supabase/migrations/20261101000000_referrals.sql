-- Invite a friend: when someone enters a friend's code and then completes a
-- usable scan, both get one free scan credit. Only Edge Functions (service
-- role) touch these tables; RLS is on with no policies, so clients can't.

alter table public.scan_credits drop constraint if exists scan_credits_source_check;
alter table public.scan_credits
  add constraint scan_credits_source_check check (source in ('rewarded_ad', 'referral'));

create table if not exists public.referral_codes (
  user_id uuid primary key references auth.users (id) on delete cascade,
  code text not null unique check (code ~ '^[A-Z2-9]{6}$'),
  created_at timestamptz not null default now()
);
alter table public.referral_codes enable row level security;

create table if not exists public.referrals (
  invitee_id uuid primary key references auth.users (id) on delete cascade,
  inviter_id uuid not null references auth.users (id) on delete cascade,
  invitee_device text,
  created_at timestamptz not null default now(),
  rewarded_at timestamptz,
  check (invitee_id <> inviter_id)
);
-- A phone can be referred once, however many accounts are made on it.
create unique index if not exists referrals_one_per_device
  on public.referrals (invitee_device) where invitee_device is not null;
create index if not exists referrals_inviter_time
  on public.referrals (inviter_id, rewarded_at);
alter table public.referrals enable row level security;

-- Called after a usable scan. Rewards the referral once: a credit each for
-- the invitee and the inviter (the inviter's only while under the monthly
-- cap). transaction_id is unique, so a retry can't pay twice.
create or replace function public.reward_referral(p_invitee uuid, p_monthly_cap integer)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_inviter uuid;
  v_recent integer;
begin
  select inviter_id into v_inviter from referrals
   where invitee_id = p_invitee and rewarded_at is null
   for update;
  if v_inviter is null then
    return false;
  end if;

  update referrals set rewarded_at = now() where invitee_id = p_invitee;

  insert into scan_credits (user_id, source, transaction_id)
  values (p_invitee, 'referral', 'ref:' || p_invitee::text || ':invitee')
  on conflict (transaction_id) do nothing;

  select count(*) into v_recent from referrals
   where inviter_id = v_inviter and rewarded_at >= now() - interval '30 days';
  if v_recent <= p_monthly_cap then
    insert into scan_credits (user_id, source, transaction_id)
    values (v_inviter, 'referral', 'ref:' || p_invitee::text || ':inviter')
    on conflict (transaction_id) do nothing;
  end if;
  return true;
end;
$$;

revoke all on function public.reward_referral(uuid, integer) from public, anon, authenticated;
grant execute on function public.reward_referral(uuid, integer) to service_role;

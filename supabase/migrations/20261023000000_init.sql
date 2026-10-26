-- ClearSkin AI backend schema.
--
-- Deliberately minimal: personal skin data (photos, scans, check-ins,
-- products) lives ONLY on the user's device. The server stores usage events
-- for quotas and abuse prevention — nothing else.

create table if not exists public.usage_events (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  kind text not null check (kind in ('scan', 'coach')),
  model text,
  input_tokens integer,
  output_tokens integer,
  created_at timestamptz not null default now()
);

create index if not exists usage_events_user_kind_time
  on public.usage_events (user_id, kind, created_at desc);

-- Only Edge Functions (service role) touch this table. RLS on with no
-- policies = no access for anon/authenticated clients.
alter table public.usage_events enable row level security;

-- Housekeeping: keep 90 days of events (enough for quotas and cost review).
-- Schedule with pg_cron in the dashboard:
--   select cron.schedule('purge-usage', '0 3 * * *',
--     $$delete from public.usage_events where created_at < now() - interval '90 days'$$);

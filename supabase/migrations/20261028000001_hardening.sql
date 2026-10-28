-- Hardening from the pre-launch database review.

-- 1. Clients get nothing from these tables even if RLS were ever switched
--    off by mistake: no table privileges at all, like the newer tables.
revoke all on public.usage_events, public.scan_credits from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;

-- 2. Values that can never be negative.
alter table public.usage_events drop constraint if exists usage_events_nonnegative;
alter table public.usage_events add constraint usage_events_nonnegative check (
  coalesce(input_tokens, 0) >= 0 and coalesce(output_tokens, 0) >= 0
  and coalesce(cache_read_tokens, 0) >= 0 and coalesce(cache_write_tokens, 0) >= 0
  and coalesce(cost_usd, 0) >= 0
);

-- 3. The daily spend check sums today's cost before every scan and chat.
--    Measured at ~2M rows / 22k a day: 60 ms reading the table, 4 ms from
--    this covering index (an index-only scan). It also serves the purge.
create index if not exists usage_events_time_cost
  on public.usage_events (created_at desc) include (cost_usd);
drop index if exists public.usage_events_time;

-- 4. Retention the privacy policy promises, run nightly by pg_cron (enabled
--    on Supabase; skipped where it isn't installed, e.g. local tests).
do $outer$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron with schema pg_catalog;
    perform cron.schedule('purge-usage', '0 3 * * *',
      $$delete from public.usage_events where created_at < now() - interval '90 days'$$);
    perform cron.schedule('purge-used-credits', '10 3 * * *',
      $$delete from public.scan_credits where consumed_at < now() - interval '90 days'$$);
    -- Keys from installs not seen for 6 months (reinstalls make new ones).
    perform cron.schedule('purge-attest-keys', '20 3 * * *',
      $$delete from public.app_attest_keys
         where coalesce(last_used_at, created_at) < now() - interval '180 days'$$);
  else
    raise notice 'pg_cron not available: retention jobs not scheduled';
  end if;
end
$outer$;

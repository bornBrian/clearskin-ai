-- Clients (anon, authenticated) attacking every table and function. Every
-- row of the result must say "blocked".
\set QUIET on
insert into auth.users values ('11111111-1111-4111-8111-111111111111'), ('22222222-2222-4222-8222-222222222222');
insert into usage_events (user_id, kind) values ('22222222-2222-4222-8222-222222222222', 'scan');
insert into scan_credits (user_id, source, transaction_id) values ('22222222-2222-4222-8222-222222222222', 'rewarded_ad', 'tx1');
insert into app_attest_keys (key_id, public_key, environment, user_id) values (repeat('A',43), decode(repeat('04',65),'hex'), 'production', '22222222-2222-4222-8222-222222222222');
insert into apple_tokens (user_id, refresh_token) values ('22222222-2222-4222-8222-222222222222', 'secret-rt');

create temp table results (role text, action text, outcome text);
grant all on results to anon, authenticated;

create or replace function pg_temp.try(r text, label text, stmt text) returns void language plpgsql as $$
declare n bigint;
begin
  execute format('set local role %I', r);
  begin
    execute stmt;
    get diagnostics n = row_count;
    reset role;
    insert into results values (r, label, 'ALLOWED rows=' || n);
  exception when others then
    reset role;
    insert into results values (r, label, 'blocked: ' || left(sqlerrm, 60));
  end;
end $$;

do $$
declare r text; t text;
begin
  foreach r in array array['anon','authenticated'] loop
    foreach t in array array['usage_events','scan_credits','app_attest_keys','apple_tokens'] loop
      perform pg_temp.try(r, t || ' select', format('select * from public.%I', t));
      perform pg_temp.try(r, t || ' update', format('update public.%I set user_id = user_id', t));
      perform pg_temp.try(r, t || ' delete', format('delete from public.%I', t));
    end loop;
    perform pg_temp.try(r, 'usage_events insert', $q$insert into public.usage_events (user_id, kind) values ('11111111-1111-4111-8111-111111111111','scan')$q$);
    perform pg_temp.try(r, 'scan_credits insert (mint free credit)', $q$insert into public.scan_credits (user_id, source, transaction_id) values ('11111111-1111-4111-8111-111111111111','rewarded_ad','fake')$q$);
    perform pg_temp.try(r, 'app_attest_keys insert (plant key)', $q$insert into public.app_attest_keys (key_id, public_key, environment) values (repeat('B',43), decode(repeat('04',65),'hex'), 'production')$q$);
    perform pg_temp.try(r, 'apple_tokens read others', $q$select refresh_token from public.apple_tokens$q$);
    perform pg_temp.try(r, 'reserve_usage', $q$select public.reserve_usage('11111111-1111-4111-8111-111111111111','scan',null,true,2,'30 days',5,10)$q$);
    perform pg_temp.try(r, 'release_usage', $q$select public.release_usage(1)$q$);
    perform pg_temp.try(r, 'ai_spend_since', $q$select public.ai_spend_since(now() - interval '1 day')$q$);
    perform pg_temp.try(r, 'auth.users read', $q$select * from auth.users$q$);
  end loop;
end $$;
select role, action, outcome from results order by role, action;

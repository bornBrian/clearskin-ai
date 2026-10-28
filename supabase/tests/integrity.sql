-- Bad data must be refused by the database itself, and deleting an
-- account must clean up exactly as the privacy policy says.
\set QUIET on
\pset pager off
create temp table checks (name text, outcome text);
create or replace function pg_temp.must_fail(label text, stmt text) returns void language plpgsql as $$
begin
  begin
    execute stmt;
    insert into checks values (label, 'FAIL: accepted bad data');
  exception when others then
    insert into checks values (label, 'ok (rejected: ' || left(sqlerrm, 50) || ')');
  end;
end $$;
-- Data types and constraints: bad data must be refused.
select pg_temp.must_fail('usage kind outside list', $q$insert into usage_events (kind) values ('hack')$q$);
select pg_temp.must_fail('usage status outside list', $q$insert into usage_events (kind, status) values ('scan','free')$q$);
select pg_temp.must_fail('device hash not sha256', $q$insert into usage_events (kind, device_hash) values ('scan','x'' or 1=1')$q$);
select pg_temp.must_fail('usage for unknown user', $q$insert into usage_events (user_id, kind) values ('99999999-9999-4999-8999-999999999999','scan')$q$);
select pg_temp.must_fail('usage with unknown credit', $q$insert into usage_events (kind, credit_id) values ('scan', 999999)$q$);
select pg_temp.must_fail('credit source outside list', $q$insert into scan_credits (user_id, source, transaction_id) values ('11111111-1111-4111-8111-111111111111','gift','t-x')$q$);
select pg_temp.must_fail('credit replayed transaction', $q$insert into scan_credits (user_id, source, transaction_id) values ('11111111-1111-4111-8111-111111111111','rewarded_ad','tx1')$q$);
select pg_temp.must_fail('credit for unknown user', $q$insert into scan_credits (user_id, source, transaction_id) values ('99999999-9999-4999-8999-999999999999','rewarded_ad','t-y')$q$);
select pg_temp.must_fail('attest key id wrong shape', $q$insert into app_attest_keys (key_id, public_key, environment) values ('short', decode(repeat('04',65),'hex'), 'production')$q$);
select pg_temp.must_fail('attest public key wrong size', $q$insert into app_attest_keys (key_id, public_key, environment) values (repeat('C',43), '\x04', 'production')$q$);
select pg_temp.must_fail('attest negative counter', $q$insert into app_attest_keys (key_id, public_key, environment, sign_count) values (repeat('D',43), decode(repeat('04',65),'hex'), 'production', -1)$q$);
select pg_temp.must_fail('attest unknown environment', $q$insert into app_attest_keys (key_id, public_key, environment) values (repeat('E',43), decode(repeat('04',65),'hex'), 'staging')$q$);
select pg_temp.must_fail('attest duplicate key', $q$insert into app_attest_keys (key_id, public_key, environment) values (repeat('A',43), decode(repeat('04',65),'hex'), 'production')$q$);
select pg_temp.must_fail('apple token empty', $q$insert into apple_tokens (user_id, refresh_token) values ('11111111-1111-4111-8111-111111111111','')$q$);
select pg_temp.must_fail('apple token twice for a user', $q$insert into apple_tokens (user_id, refresh_token) values ('22222222-2222-4222-8222-222222222222','again')$q$);
select pg_temp.must_fail('reserve bad kind', $q$select reserve_usage('11111111-1111-4111-8111-111111111111','hack',null,false,2,'30 days',5,10)$q$);

-- Relationships: deleting an account.
insert into usage_events (user_id, kind, credit_id) select '22222222-2222-4222-8222-222222222222', 'scan', id from scan_credits where transaction_id = 'tx1';
delete from auth.users where id = '22222222-2222-4222-8222-222222222222';
insert into checks select 'delete: usage rows kept, unlinked', case when count(*) = 2 and bool_and(user_id is null) then 'ok' else 'FAIL ' || count(*) end from usage_events;
insert into checks select 'delete: usage credit link cleared', case when bool_and(credit_id is null) then 'ok' else 'FAIL' end from usage_events;
insert into checks select 'delete: credits removed', case when count(*) = 0 then 'ok' else 'FAIL' end from scan_credits where transaction_id = 'tx1';
insert into checks select 'delete: attest key kept, unlinked', case when count(*) = 1 and bool_and(user_id is null) then 'ok' else 'FAIL' end from app_attest_keys;
insert into checks select 'delete: apple token removed', case when count(*) = 0 then 'ok' else 'FAIL' end from apple_tokens;
select * from checks;

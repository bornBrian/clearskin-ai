#!/usr/bin/env bash
# Database tests: roles/permissions, data integrity and simultaneous
# requests, against a throwaway database on a local Postgres (15+).
#
#   PGHOST=127.0.0.1 PGPORT=5432 PGUSER=postgres PGPASSWORD=... supabase/tests/run.sh
#
# Never point this at the real project: it drops and recreates $DB.
set -euo pipefail
cd "$(dirname "$0")"
DB=${DB:-clearskin_qa}
export PGOPTIONS="-c client_min_messages=warning"
psql() { command psql -X -v ON_ERROR_STOP=1 "$@"; }
q() { psql -d "$DB" -Atqc "$1"; }
fail=0
check() { # name, expected, actual
  if [ "$2" == "$3" ]; then echo "  ok    $1"; else echo "  FAIL  $1 (expected $2, got $3)"; fail=1; fi
}

psql -d postgres -qc "drop database if exists $DB" -c "create database $DB"
psql -d "$DB" -q -f supabase_stub.sql
for m in ../migrations/*.sql; do psql -d "$DB" -q -f "$m"; done
echo "Migrations applied. Re-applying (must be idempotent)..."
for m in ../migrations/*.sql; do psql -d "$DB" -q -f "$m"; done

echo "Roles and permissions"
roles=$(psql -d "$DB" -At -f roles.sql)
check "every attack ran" 40 "$(grep -c '|' <<< "$roles")"
check "clients can't touch any table or function" 40 "$(grep -c '|blocked' <<< "$roles")"

echo "Integrity"
integrity=$(psql -d "$DB" -At -f integrity.sql)
check "bad data refused, account deletion cleans up (21 checks)" 21 "$(grep -c '|ok' <<< "$integrity")"

echo "Simultaneous requests"
race() { # n, sql ({i} = 1..n)
  local n=$1 sql=$2 dir; dir=$(mktemp -d)
  for i in $(seq 1 "$n"); do (command psql -X -d "$DB" -Atqc "${sql//\{i\}/$i}" > "$dir/$i" 2>&1) & done
  wait; cat "$dir"/*; rm -rf "$dir"
}
U1=11111111-1111-4111-8111-111111111111
DEV=$(printf 'd%.0s' $(seq 1 64))
reset() { q "delete from usage_events; delete from scan_credits; delete from app_attest_keys; delete from apple_tokens; delete from auth.users; insert into auth.users select ('00000000-0000-4000-8000-' || lpad(g::text, 12, '0'))::uuid from generate_series(1, 40) g; insert into auth.users values ('$U1');"; }
okn() { grep -c '"ok": true' || true; }

reset; check "25 free scans at once, one account -> 2" 2 "$(race 25 "select reserve_usage('$U1','scan',null,false,2,'30 days',5,10)" | okn)"
reset; check "25 accounts on one phone at once -> 2" 2 "$(race 25 "select reserve_usage(('00000000-0000-4000-8000-' || lpad('{i}', 12, '0'))::uuid,'scan','$DEV',false,2,'30 days',5,10)" | okn)"
reset; q "insert into usage_events (user_id, kind) select '$U1','scan' from generate_series(1,2); insert into scan_credits (user_id, source, transaction_id) values ('$U1','rewarded_ad','only-one');"
check "20 scans at once on one rewarded credit -> 1" 1 "$(race 20 "select reserve_usage('$U1','scan',null,false,2,'30 days',5,10)" | okn)"
check "  ...and the credit is used once" 1 "$(q "select count(*) from scan_credits where consumed_at is not null")"
reset; check "30 Premium scans at once (5 a day) -> 5" 5 "$(race 30 "select reserve_usage('$U1','scan',null,true,2,'30 days',5,10)" | okn)"
reset; check "30 coach messages at once (10 attempts) -> 10" 10 "$(race 30 "select reserve_usage('$U1','coach',null,true,2,'30 days',60,10)" | okn)"
reset; q "insert into scan_credits (user_id, source, transaction_id, consumed_at) values ('$U1','rewarded_ad','c1', now());"
EV=$(q "insert into usage_events (user_id, kind, credit_id) select '$U1','scan', id from scan_credits returning id")
race 15 "select release_usage($EV)" > /dev/null
check "one refund applied 15 times at once -> refunded once, credit back" "true|true" "$(q "select (select refunded from usage_events where id=$EV) || '|' || (select consumed_at is null from scan_credits)")"
reset; q "insert into app_attest_keys (key_id, public_key, environment) values (repeat('A',43), decode(repeat('04',65),'hex'), 'production');"
check "one App Attest assertion replayed 20 times at once -> 1" 1 "$(race 20 "update app_attest_keys set sign_count = 7 where key_id = repeat('A',43) and sign_count < 7 returning key_id" | grep -c A || true)"
reset; race 20 "insert into scan_credits (user_id, source, transaction_id) values ('$U1','rewarded_ad','tx-same') on conflict (transaction_id) do nothing" > /dev/null
check "one rewarded-ad callback delivered 20 times at once -> 1 credit" 1 "$(q "select count(*) from scan_credits")"

psql -d postgres -qc "drop database $DB"
[ "$fail" == 0 ] && echo "All database tests passed." || { echo "Database tests FAILED."; exit 1; }

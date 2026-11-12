#!/usr/bin/env bash
# Validation case V8 - each regional application may write only rows of its own region.
# Run on the main 3+1 cluster, right after: MODE=poc ./scripts/01_load_schema.sh
# (it can also run after 12_test_admin_sens.sh). It applies sql/06_write_restriction.sql,
# tries inserts from both profiles through both gateways and checks where the new "eur" row is stored.
# Results go to results/isolation_write_restriction.csv (the checks of tests 10 and 12 are not changed).
set -uo pipefail
source "$(dirname "$0")/lib.sh"
cd "$ROOT"
LOG="$RESULTS/isolation_write_restriction_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee "$LOG") 2>&1

MODE=$(cat "$RESULTS/schema_mode.txt" 2>/dev/null || echo unknown)
echo "# Validation case V8 (write restriction) - schema mode: $MODE - $(now)"
[ "$MODE" = "poc" ] || echo "WARNING: expected schema mode 'poc' (run MODE=poc ./scripts/01_load_schema.sh first)."
require_all_live "write_restriction start" || { echo "ABORTED: not all nodes are live; fix the cluster and run again."; exit 1; }

echo; echo "### Applying the write policies"
docker exec -i usa1 ./cockroach sql --insecure --host=usa1:26257 < sql/06_write_restriction.sql || { echo "ABORTED: could not apply sql/06_write_restriction.sql"; exit 1; }
run_sql usa1 root "SHOW POLICIES FOR patients" || true

CSV="$RESULTS/isolation_write_restriction.csv"
echo "case,expected,actual,result" > "$CSV"
TAG="v8-$(date +%H%M%S)"

# run_retry <gateway> <user> <statement>: like run_sql, but retries (up to 5 times) when the statement fails
# with the transient clock error "remote wall time is too far ahead ... to be trustworthy", which happens
# before the statement is even checked (during login) and says nothing about the policies being tested.
run_retry() {
  local out rc n
  for n in 1 2 3 4 5; do
    out=$(run_sql "$1" "$2" "$3" 2>&1); rc=$?
    if [ $rc -ne 0 ] && echo "$out" | grep -q "too far ahead"; then
      echo "    (attempt $n: transient clock error on $1, retrying in 5 s)" >&2; sleep 5; continue
    fi
    break
  done
  echo "$out"; return $rc
}
check_access() { # label expected(ok|error) gateway user statement
  local label="$1" expected="$2" gw="$3" user="$4" q="$5" out rc actual res
  out=$(run_retry "$gw" "$user" "$q" 2>&1); rc=$?
  if [ $rc -eq 0 ]; then actual=ok; else actual=error; fi
  if [ "$actual" = "$expected" ]; then res=PASS; else res=FAIL; fi
  echo "--- $label | expected=$expected actual=$actual => $res"
  echo "$out" | head -6
  echo "\"$label\",$expected,$actual,$res" >> "$CSV"
}
# denied_by_policy: PASS only if the statement fails WITH the row-level security message
denied_by_policy() { # label gateway user statement
  local label="$1" gw="$2" user="$3" q="$4" out rc actual res
  out=$(run_retry "$gw" "$user" "$q" 2>&1); rc=$?
  if [ $rc -ne 0 ] && echo "$out" | grep -qi "row-level security"; then actual=denied_by_policy
  elif [ $rc -ne 0 ]; then actual=error_other
  else actual=ok; fi
  if [ "$actual" = "denied_by_policy" ]; then res=PASS; else res=FAIL; fi
  echo "--- $label | expected=denied_by_policy actual=$actual => $res"
  echo "$out" | head -6
  echo "\"$label\",denied_by_policy,$actual,$res" >> "$CSV"
}
check_value() { # label expected_value gateway user statement
  local label="$1" expected="$2" gw="$3" user="$4" q="$5" v res
  v=$(scalar "$gw" "$user" "$q")
  if [ "$v" = "$expected" ]; then res=PASS; else res=FAIL; fi
  echo "--- $label | expected=$expected actual=$v => $res"
  echo "\"$label\",$expected,$v,$res" >> "$CSV"
}

echo; echo "### Writes of the regional profiles"
check_access     "app_usa writes a usa row (gateway usa1)"            ok    usa1 app_usa "INSERT INTO patients (crdb_region, name) VALUES ('usa', '$TAG-usa')"
denied_by_policy "app_usa cannot write an eur row (gateway usa1)"           usa1 app_usa "INSERT INTO patients (crdb_region, name) VALUES ('eur', '$TAG-x1')"
denied_by_policy "app_usa cannot write an eur row even through eur1"        eur1 app_usa "INSERT INTO patients (crdb_region, name) VALUES ('eur', '$TAG-x2')"
check_access     "app_eur writes an eur row (gateway eur1)"           ok    eur1 app_eur "INSERT INTO patients (crdb_region, name) VALUES ('eur', '$TAG-eur')"
denied_by_policy "app_eur cannot write a usa row (gateway eur1)"            eur1 app_eur "INSERT INTO patients (crdb_region, name) VALUES ('usa', '$TAG-x3')"
check_access     "app_usa cannot move a row to another region (no UPDATE)" error usa1 app_usa "UPDATE patients SET crdb_region = 'eur' WHERE name = '$TAG-usa'"

echo; echo "### Nothing was written by the denied attempts"
check_value "no row from the denied attempts" 0 usa1 root "SELECT count(*) FROM patients WHERE name IN ('$TAG-x1', '$TAG-x2', '$TAG-x3')"

echo; echo "### Reads through the views still work (views run with the owner's privileges)"
check_value "app_usa still reads its own view (at least 1000 rows)" 1 usa1 app_usa "SELECT (count(*) >= 1000)::INT FROM v_patients_usa"

echo; echo "### Storage of the new eur row"
id=$(scalar usa1 root "SELECT id FROM patients WHERE name = '$TAG-eur'")
wait_placement 180 "region=eur" patients eur "$id" || true
check_placement "$CSV" "patients: new eur row stored only in eur" "region=eur" patients eur "$id"

echo
require_all_live "write_restriction end" || echo "WARNING: a node went down during the test; repeat this run."

echo; echo "### Summary (validation case V8)"
column -s, -t < "$CSV"
echo
echo "PASS: $(grep -c ',PASS$' "$CSV")   FAIL: $(grep -c ',FAIL$' "$CSV")   NOT_VERIFIED: $(grep -c ',NOT_VERIFIED$' "$CSV")"
echo "Log saved to $LOG"

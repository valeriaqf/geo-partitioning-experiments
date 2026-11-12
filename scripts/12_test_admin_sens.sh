#!/usr/bin/env bash
# Validation case V7 - administrator in region "usa" authorized to read personal data of region "eur".
# Run on the main 3+1 cluster, right after: MODE=poc ./scripts/01_load_schema.sh
# It creates the admin_sens profile (sql/05_admin_sens.sql), checks its access through node usa1
# and checks that the "eur" rows it read are still stored only in region "eur".
# It does NOT change the 20 checks of test 10: results go to results/isolation_admin_sens.csv.
set -uo pipefail
source "$(dirname "$0")/lib.sh"
cd "$ROOT"
LOG="$RESULTS/isolation_admin_sens_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee "$LOG") 2>&1

MODE=$(cat "$RESULTS/schema_mode.txt" 2>/dev/null || echo unknown)
echo "# Validation case V7 (admin_sens) - schema mode: $MODE - $(now)"
[ "$MODE" = "poc" ] || echo "WARNING: expected schema mode 'poc' (run MODE=poc ./scripts/01_load_schema.sh first)."
require_all_live "admin_sens start" || { echo "ABORTED: not all nodes are live; fix the cluster and run again."; exit 1; }

echo; echo "### Creating profile admin_sens"
docker exec -i usa1 ./cockroach sql --insecure --host=usa1:26257 < sql/05_admin_sens.sql || { echo "ABORTED: could not create admin_sens"; exit 1; }

CSV="$RESULTS/isolation_admin_sens.csv"
echo "case,expected,actual,result" > "$CSV"

check_access() { # label expected(ok|error) gateway user statement
  local label="$1" expected="$2" gw="$3" user="$4" q="$5" out rc actual res
  out=$(run_sql "$gw" "$user" "$q" 2>&1); rc=$?
  if [ $rc -eq 0 ]; then actual=ok; else actual=error; fi
  if [ "$actual" = "$expected" ]; then res=PASS; else res=FAIL; fi
  echo "--- $label | expected=$expected actual=$actual => $res"
  echo "$out" | head -8
  echo "\"$label\",$expected,$actual,$res" >> "$CSV"
}
check_value() { # label expected_value gateway user statement
  local label="$1" expected="$2" gw="$3" user="$4" q="$5" v res
  v=$(scalar "$gw" "$user" "$q")
  if [ "$v" = "$expected" ]; then res=PASS; else res=FAIL; fi
  echo "--- $label | expected=$expected actual=$v => $res"
  echo "\"$label\",$expected,$v,$res" >> "$CSV"
}

echo; echo "### Access of admin_sens through node usa1 (administrator located in region usa)"
check_access "admin_sens reads patients of region usa"        ok    usa1 admin_sens "SELECT count(*) FROM v_patients_usa"
check_access "admin_sens reads patients of region eur"        ok    usa1 admin_sens "SELECT count(*) FROM v_patients_eur"
check_value  "admin_sens: eur view has 1000 rows"                 1000  usa1 admin_sens "SELECT count(*) FROM v_patients_eur"
check_access "admin_sens cannot read the base table patients" error usa1 admin_sens "SELECT count(*) FROM patients"
check_access "admin_sens cannot read the base table doctors"   error usa1 admin_sens "SELECT count(*) FROM doctors"

echo; echo "### Storage of the eur rows after the cross-region read"
id=$(scalar usa1 root "SELECT id FROM patients WHERE crdb_region='eur' LIMIT 1")
wait_placement 180 "region=eur" patients eur "$id" || true
check_placement "$CSV" "patients: eur rows still stored only in eur after the read" "region=eur" patients eur "$id"
echo "(informational) leaseholder and replicas of that eur row:"
run_sql usa1 root "SELECT lease_holder_locality, replica_localities FROM [SHOW RANGE FROM TABLE patients FOR ROW ('eur', '$id')]" || true

echo
require_all_live "admin_sens end" || echo "WARNING: a node went down during the test; repeat this run."

echo; echo "### Summary (validation case V7)"
column -s, -t < "$CSV"
echo
echo "PASS: $(grep -c ',PASS$' "$CSV")   FAIL: $(grep -c ',FAIL$' "$CSV")   NOT_VERIFIED: $(grep -c ',NOT_VERIFIED$' "$CSV")"
echo "Log saved to $LOG"

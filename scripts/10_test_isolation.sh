#!/usr/bin/env bash
# Test 1 - Regional isolation: (A) physical replica placement and (B) role-based access control.
# Run right after scripts/01_load_schema.sh. Outputs are named after the placement mode (poc, baseline, restricted).
set -uo pipefail
source "$(dirname "$0")/lib.sh"
MODE=$(cat "$RESULTS/schema_mode.txt" 2>/dev/null || echo unknown)
LOG="$RESULTS/isolation_${MODE}_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee "$LOG") 2>&1

CSV="$RESULTS/isolation_${MODE}.csv"
echo "case,expected,actual,result" > "$CSV"

echo "# Isolation test - mode: $MODE - $(now)"
require_all_live "isolation start ($MODE)" || { echo "ABORTED: not all nodes are live; fix the cluster and run again."; exit 1; }

echo; echo "### A1. Database regions"
run_sql usa1 root "SHOW REGIONS FROM DATABASE $DB;"

echo; echo "### A2. Rows per region"
run_sql usa1 root "SELECT 'doctors' AS tbl, crdb_region, count(*) FROM doctors GROUP BY crdb_region
UNION ALL SELECT 'patients', crdb_region, count(*) FROM patients GROUP BY crdb_region
UNION ALL SELECT 'doctor_research_projects', crdb_region, count(*) FROM doctor_research_projects GROUP BY crdb_region
ORDER BY 1, 2;"

echo; echo "### A3. Ranges and replica localities of table patients"
run_sql usa1 root "SELECT start_key, lease_holder_locality, replica_localities FROM [SHOW RANGES FROM TABLE patients WITH DETAILS] ORDER BY start_key;" \
  || run_sql usa1 root "SHOW RANGES FROM TABLE patients;"

echo; echo "### A4. Automatic check of physical replica placement (the 3 REGIONAL BY ROW tables)"
# patients waits up to 180 s per region for the replicas to settle; the other tables, up to 30 s more.
for tbl in patients doctors doctor_research_projects; do
  limit=30; [ "$tbl" = patients ] && limit=180
  for reg in eur usa; do
    id=$(scalar usa1 root "SELECT id FROM $tbl WHERE crdb_region='$reg' LIMIT 1")
    wait_placement "$limit" "region=$reg" "$tbl" "$reg" "$id" || true
    check_placement "$CSV" "$tbl: replicas of $reg rows stay only in $reg" "region=$reg" "$tbl" "$reg" "$id"
  done
done

echo; echo "### B. Role-based access control"

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

check_access "app_usa reads patients of its own region"  ok    usa1 app_usa "SELECT count(*) FROM v_patients_usa"
check_access "app_usa cannot read the base table"            error usa1 app_usa "SELECT count(*) FROM patients"
check_access "app_usa cannot read the other region's view"   error usa1 app_usa "SELECT count(*) FROM v_patients_eur"
check_value  "app_usa: usa view has 1000 rows"               1000  usa1 app_usa "SELECT count(*) FROM v_patients_usa"
check_value  "app_usa: no EUR rows in usa view"              0     usa1 app_usa "SELECT count(*) FROM v_patients_usa WHERE name LIKE '%EUR%'"

check_access "app_eur reads patients of its own region"  ok    eur1 app_eur "SELECT count(*) FROM v_patients_eur"
check_access "app_eur cannot read the base table"            error eur1 app_eur "SELECT count(*) FROM patients"
check_access "app_eur cannot read the other region's view"   error eur1 app_eur "SELECT count(*) FROM v_patients_usa"
check_value  "app_eur: eur view has 1000 rows"               1000  eur1 app_eur "SELECT count(*) FROM v_patients_eur"
check_value  "app_eur: no USA rows in eur view"              0     eur1 app_eur "SELECT count(*) FROM v_patients_eur WHERE name LIKE '%USA%'"

check_access "admin_meta reads consolidated metadata"        ok    usa1 admin_meta "SELECT * FROM v_region_metadata ORDER BY 1,2"
check_access "admin_meta cannot read patients (usa)"     error usa1 admin_meta "SELECT count(*) FROM v_patients_usa"
check_access "admin_meta cannot read patients (eur)"     error usa1 admin_meta "SELECT count(*) FROM v_patients_eur"
check_access "admin_meta cannot read doctors (base)"      error usa1 admin_meta "SELECT count(*) FROM doctors"

echo
require_all_live "isolation end ($MODE)" || echo "WARNING: a node went down during the test; repeat this run."

echo; echo "### Summary (mode: $MODE)"
column -s, -t < "$CSV"
echo
echo "PASS: $(grep -c ',PASS$' "$CSV")   FAIL: $(grep -c ',FAIL$' "$CSV")   NOT_VERIFIED: $(grep -c ',NOT_VERIFIED$' "$CSV")"
echo "Log saved to $LOG"

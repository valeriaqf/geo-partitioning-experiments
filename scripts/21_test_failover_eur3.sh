#!/usr/bin/env bash
# Test 2 for the complementary 3+3 scenario (region eur with eur1, eur2, eur3).
#   G0: baseline (all 6 nodes up)
#   G1: one eur node down (eur2)            -> eur data should stay available
#   G2: whole eur region down (eur1..eur3)  -> eur data unavailable + recovery time
# Run with: EXPECTED_NODES=6 ./scripts/21_test_failover_eur3.sh
set -uo pipefail
source "$(dirname "$0")/lib.sh"
LOG="$RESULTS/failover_eur3_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee "$LOG") 2>&1

CSV="$RESULTS/failover_eur3.csv"
echo "scenario,operation,gateway,status,duration_s" > "$CSV"

op() { # scenario operation gateway statement
  local scn="$1" name="$2" gw="$3" q="$4" t0 t1 rc st dur err
  err=$(mktemp)
  t0=$(date +%s.%N)
  timeout 25 docker exec "$gw" ./cockroach sql --insecure --host="$gw:26257" --database="$DB" \
    -e "SET statement_timeout='20s'; $q" >/dev/null 2>"$err"
  rc=$?
  t1=$(date +%s.%N)
  case $rc in
    0)   st=OK ;;
    124) st=TIMEOUT ;;
    *)   st="ERROR: $(head -c 70 "$err" | tr '\n,"' '   ')" ;;
  esac
  rm -f "$err"
  dur=$(awk -v a="$t0" -v b="$t1" 'BEGIN{printf "%.2f", b-a}')
  printf '%-22s %-14s gw=%-5s %-10s %ss\n' "$scn" "$name" "$gw" "${st:0:10}" "$dur"
  echo "\"$scn\",\"$name\",$gw,\"$st\",$dur" >> "$CSV"
}

battery() { # scenario gateway
  local scn="$1" gw="$2"
  op "$scn" read_usa     "$gw" "SELECT count(*) FROM patients WHERE crdb_region='usa'"
  op "$scn" read_eur     "$gw" "SELECT count(*) FROM patients WHERE crdb_region='eur'"
  op "$scn" write_usa    "$gw" "INSERT INTO patients (crdb_region, name) VALUES ('usa', 'failover-$scn')"
  op "$scn" write_eur    "$gw" "INSERT INTO patients (crdb_region, name) VALUES ('eur', 'failover-$scn')"
  op "$scn" read_global  "$gw" "SELECT count(*) FROM research_projects"
}

recover() { # scenario gateway region limit_s
  local scn="$1" gw="$2" reg="$3" limit="$4" t0 d
  t0=$(date +%s)
  until timeout 10 docker exec "$gw" ./cockroach sql --insecure --host="$gw:26257" --database="$DB" \
          -e "SELECT count(*) FROM patients WHERE crdb_region='$reg'" >/dev/null 2>&1; do
    d=$(( $(date +%s) - t0 ))
    if [ "$d" -gt "$limit" ]; then
      echo "Did not recover within ${limit}s"
      echo "\"$scn\",\"recovery_time\",$gw,\"NOT_RECOVERED\",$d" >> "$CSV"; return
    fi
    sleep 2
  done
  d=$(( $(date +%s) - t0 ))
  echo "Recovered in ${d}s"
  echo "\"$scn\",\"recovery_time\",$gw,\"OK\",$d" >> "$CSV"
}

echo "# Failover test, 3+3 scenario - $(now)"
require_all_live "failover eur3 start" || { echo "ABORTED: not all nodes are live; fix the cluster and run again."; exit 1; }
printf '%-22s %-14s %-9s %-10s %s\n' scenario operation gateway status duration

echo; echo "## G0 - baseline (6 nodes)"
battery G0_baseline usa1
battery G0_baseline eur1

echo; echo "## G1 - one eur node down (eur2)"
docker kill eur2 >/dev/null; sleep 15
battery G1_eur_node_down usa1
battery G1_eur_node_down eur1
docker start eur2 >/dev/null
wait_all_live 120 "failover eur3 after G1 (eur2 back)" || echo "WARNING: eur2 did not come back; G2 results are not valid."

echo; echo "## G2 - eur region down (eur1, eur2, eur3)"
docker kill eur1 eur2 eur3 >/dev/null; sleep 15
battery G2_eur_region_down usa1
docker start eur1 eur2 eur3 >/dev/null
echo "eur1..3 restarted; measuring time until eur rows are readable again..."
recover G2_eur_region_down usa1 eur 180

echo
wait_all_live 300 "failover eur3 end" || echo "WARNING: not all nodes came back after the test."
echo; echo "Cluster at the end:"
docker exec usa1 ./cockroach node status --insecure --host=usa1:26257 || true
echo "Results in $CSV and $LOG"

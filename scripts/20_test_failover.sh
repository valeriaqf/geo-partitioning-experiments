#!/usr/bin/env bash
# Test 2 - Fault tolerance.
#   F0: baseline (everything up)
#   F1: one usa node down
#   F2: the only eur node down (whole eur region) + recovery time
#   F3 (optional, --full-usa): all 3 usa nodes down
set -uo pipefail
source "$(dirname "$0")/lib.sh"
LOG="$RESULTS/failover_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee "$LOG") 2>&1

CSV="$RESULTS/failover.csv"
# One CSV per run (the timestamped log keeps the history); appending mixed old and new runs.
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
  printf '%-20s %-14s gw=%-5s %-10s %ss\n' "$scn" "$name" "$gw" "${st:0:10}" "$dur"
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

echo "# Failover test - $(now)"
require_all_live "failover start" || { echo "ABORTED: not all nodes are live; fix the cluster and run again."; exit 1; }
printf '%-20s %-14s %-9s %-10s %s\n' scenario operation gateway status duration

echo; echo "## F0 - baseline"
battery F0_baseline usa1
battery F0_baseline eur1

echo; echo "## F1 - one usa node down (usa3)"
docker kill usa3 >/dev/null; sleep 15
battery F1_usa_node_down usa1
battery F1_usa_node_down eur1
docker start usa3 >/dev/null
wait_all_live 120 "failover after F1 (usa3 back)" || echo "WARNING: usa3 did not come back; F2 results are not valid."

echo; echo "## F2 - eur region down (eur1 is the only eur node)"
docker kill eur1 >/dev/null; sleep 15
battery F2_eur_region_down usa1
docker start eur1 >/dev/null
echo "eur1 restarted; measuring time until eur rows are readable again..."
recover F2_eur_region_down usa1 eur 180

if [ "${1:-}" = "--full-usa" ]; then
  echo; echo "## F3 - all 3 usa nodes down"
  docker kill usa1 usa2 usa3 >/dev/null; sleep 20
  battery F3_usa_region_down eur1
  docker start usa1 usa2 usa3 >/dev/null
  echo "usa1..3 restarted; measuring time until usa rows are readable again..."
  recover F3_usa_region_down eur1 usa 300
fi

echo
wait_all_live 300 "failover end" || echo "WARNING: not all nodes came back after the test."
echo; echo "Cluster at the end:"
docker exec usa1 ./cockroach node status --insecure --host=usa1:26257 || true
echo "Results in $CSV and $LOG"

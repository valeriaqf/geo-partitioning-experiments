#!/usr/bin/env bash
# Shared helpers. Usage: source "$(dirname "$0")/lib.sh"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS="$ROOT/results"
DB="geo_db"
# Number of nodes the cluster should have: 4 in the main setup (3+1), 6 in the 3+3 scenario.
EXPECTED_NODES="${EXPECTED_NODES:-4}"
mkdir -p "$RESULTS"

now() { date '+%Y-%m-%d %H:%M:%S'; }

# run_sql <gateway> <user> <statement>  -> table output
run_sql() {
  docker exec "$1" ./cockroach sql --insecure --host="$1:26257" --user="$2" --database="$DB" --format=table -e "$3"
}

# scalar <gateway> <user> <statement>  -> last CSV line (the value)
scalar() {
  docker exec "$1" ./cockroach sql --insecure --host="$1:26257" --user="$2" --database="$DB" --format=csv -e "$3" 2>&1 | tail -n 1
}

# replica_regions <table> <region_key> <id>
# Prints the regions that hold replicas of that row (e.g. "region=eur region=usa"); empty if the query failed.
replica_regions() {
  docker exec usa1 ./cockroach sql --insecure --host=usa1:26257 --format=csv \
    -e "SELECT replica_localities::STRING FROM [SHOW RANGE FROM TABLE $DB.$1 FOR ROW ('$2', '$3')]" 2>&1 \
    | grep -o 'region=[a-z]*' | sort -u | tr '\n' ' ' | sed 's/ $//'
}

# check_placement <csv> <label> <expected> <table> <region_key> <id>
# PASS if replicas are ONLY in the expected region; FAIL otherwise; NOT_VERIFIED if the query failed.
check_placement() {
  local csv="$1" label="$2" expected="$3" actual res
  [ -f "$csv" ] || echo "case,expected,actual,result" > "$csv"
  actual=$(replica_regions "$4" "$5" "$6")
  if [ -z "$actual" ]; then res=NOT_VERIFIED
  elif [ "$actual" = "$expected" ]; then res=PASS
  else res=FAIL; fi
  echo "--- $label | expected=[$expected] actual=[$actual] => $res"
  echo "\"$label\",\"$expected\",\"$actual\",$res" >> "$csv"
}

# live_nodes -> how many nodes report is_live=true (asks usa1; falls back to eur1 if usa1 is down)
live_nodes() {
  local gw out
  for gw in usa1 eur1; do
    out=$(docker exec "$gw" ./cockroach node status --insecure --host="$gw:26257" --format=tsv 2>/dev/null) || continue
    printf '%s\n' "$out" | awk -F'\t' '
      !c { for (i = 1; i <= NF; i++) if ($i == "is_live") c = i; next }
      $c == "true" { n++ }
      END { print n + 0 }'
    return 0
  done
  echo 0
}

# require_all_live <checkpoint>: records the live-node count in results/liveness.csv; fails if not all EXPECTED_NODES are live
require_all_live() {
  local n
  n=$(live_nodes)
  [ -f "$RESULTS/liveness.csv" ] || echo "time,checkpoint,live_nodes" > "$RESULTS/liveness.csv"
  echo "$(now),\"$1\",$n" >> "$RESULTS/liveness.csv"
  echo "[liveness] $1: $n/$EXPECTED_NODES nodes live"
  [ "$n" = "$EXPECTED_NODES" ]
}

# wait_all_live <timeout_s> <checkpoint>: waits until all EXPECTED_NODES are live, then records the check
wait_all_live() {
  local limit="$1" t0
  t0=$(date +%s)
  until [ "$(live_nodes)" = "$EXPECTED_NODES" ]; do
    [ $(( $(date +%s) - t0 )) -ge "$limit" ] && break
    sleep 5
  done
  require_all_live "$2"
}

# wait_placement <timeout_s> <expected> <table> <region_key> <id>
# Polls every 10 s until the row's replicas are only in the expected region.
wait_placement() {
  local limit="$1" expected="$2" t0 actual
  t0=$(date +%s)
  while :; do
    actual=$(replica_regions "$3" "$4" "$5")
    if [ "$actual" = "$expected" ]; then echo "converged in $(( $(date +%s) - t0 ))s: [$actual]"; return 0; fi
    if [ $(( $(date +%s) - t0 )) -ge "$limit" ]; then echo "did NOT converge in ${limit}s; last: [$actual]"; return 1; fi
    sleep 10
  done
}

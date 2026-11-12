#!/usr/bin/env bash
# Records the environment (never the license key) and packs results/ to send to the advisor.
set -uo pipefail
source "$(dirname "$0")/lib.sh"

{
  echo "Date: $(now)"
  echo "--- Machine"
  uname -a
  echo "CPUs: $(nproc)"
  free -h
  echo "--- Docker"
  docker --version
  docker compose version
  echo "--- CockroachDB"
  docker exec usa1 ./cockroach version 2>&1 | head -5
  docker exec usa1 ./cockroach node status --insecure --host=usa1:26257 2>&1
  echo "--- Image"
  docker inspect usa1 --format '{{.Config.Image}}' 2>&1
  echo "--- Placement mode loaded last"
  cat "$RESULTS/schema_mode.txt" 2>/dev/null || echo unknown
} > "$RESULTS/environment.txt"

# Zone configurations actually in force (evidence for the appendix)
docker exec usa1 ./cockroach sql --insecure --host=usa1:26257 --format=table \
  -e "SELECT target, raw_config_sql FROM [SHOW ALL ZONE CONFIGURATIONS] WHERE target LIKE '%geo_db%';" \
  > "$RESULTS/zone_configs.txt" 2>&1

OUT="$ROOT/results_$(date +%Y%m%d_%H%M).tar.gz"
tar czf "$OUT" -C "$ROOT" results
echo "Environment recorded in results/environment.txt"
echo "Package to send: $OUT"

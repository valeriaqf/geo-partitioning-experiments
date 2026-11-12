#!/usr/bin/env bash
# (Re)creates the multi-region database from scratch: schema, placement configuration, synthetic data, roles and views.
# Safe to re-run: it drops and recreates the database "geo_db".
#   ./scripts/01_load_schema.sh                    -> MODE=poc: manual zone overrides from the original PoC (main setup)
#   MODE=baseline   ./scripts/01_load_schema.sh    -> default REGIONAL BY ROW placement (no overrides)
#   MODE=restricted ./scripts/01_load_schema.sh    -> native ALTER DATABASE ... PLACEMENT RESTRICTED (no overrides)
#   MODE=poc3       ./scripts/01_load_schema.sh    -> 3+3 scenario only: zone overrides with 3 replicas in eur
#   MODE=superregion ./scripts/01_load_schema.sh   -> super regions "eua" (usa) and "europa" (eur), no overrides
#   BASELINE=1 still works and means MODE=baseline.
set -euo pipefail
cd "$(dirname "$0")/.."

MODE="${MODE:-poc}"
[ "${BASELINE:-0}" = "1" ] && MODE=baseline

case "$MODE" in
  poc)        FILES="01_schema 02_zone_overrides 03_seed_data 04_roles_views" ;;
  baseline)   FILES="01_schema 03_seed_data 04_roles_views" ;;
  restricted) FILES="01_schema 02b_placement_restricted 03_seed_data 04_roles_views" ;;
  poc3)       FILES="01_schema 02c_zone_overrides_eur3 03_seed_data 04_roles_views" ;;
  superregion) FILES="01_schema 02d_super_regions 03_seed_data 04_roles_views" ;;
  *) echo "Unknown MODE=$MODE (use poc, baseline, restricted, poc3 or superregion)"; exit 1 ;;
esac
echo "(placement mode: $MODE)"

for f in $FILES; do
  echo "== Running sql/$f.sql"
  docker exec -i usa1 ./cockroach sql --insecure --host=usa1:26257 < "sql/$f.sql"
done

# The isolation test reads this file to name its outputs (isolation_poc.csv, isolation_baseline.csv, ...).
mkdir -p results
echo "$MODE" > results/schema_mode.txt

echo
echo "Done. The isolation test (10) waits for replicas to settle and checks their placement."

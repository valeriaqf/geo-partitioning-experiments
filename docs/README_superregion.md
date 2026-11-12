# Super regions (complementary run)

Adds MODE=superregion (sql/02d_super_regions.sql). Nothing else changes; the previous results stay valid.
Run in Ubuntu/WSL, inside the folder.

```bash
# 0. Keep new outputs apart from the old ones
mkdir -p results/superregion_3x1 results/superregion_3x3

# 1. 3+1 (main topology) - only Test 1
docker compose down -v
unset COMPOSE_FILE; export EXPECTED_NODES=4
./scripts/00_start_cluster.sh
MODE=superregion ./scripts/01_load_schema.sh && ./scripts/10_test_isolation.sh
./scripts/99_collect_evidence.sh
mv results/*.csv results/*.log results/*.txt results/superregion_3x1/ 2>/dev/null

# 2. 3+3 - Test 1 and Test 2
docker compose down -v
export COMPOSE_FILE=docker-compose.yml:docker-compose.eur3.yml
export EXPECTED_NODES=6
./scripts/00_start_cluster.sh
MODE=superregion ./scripts/01_load_schema.sh && ./scripts/10_test_isolation.sh
./scripts/21_test_failover_eur3.sh
./scripts/99_collect_evidence.sh
mv results/*.csv results/*.log results/*.txt results/superregion_3x3/ 2>/dev/null

# 3. Back to normal
docker compose down -v
unset COMPOSE_FILE EXPECTED_NODES
```

If 01_load_schema.sh stops at `SET enable_super_regions` ("unrecognized configuration parameter"),
delete that line from sql/02d_super_regions.sql and run step 1 again.

# Complementary scenario: 3 nodes in region eur (3+3)

The main setup reproduces the PoC (3 nodes in usa, 1 in eur). This scenario adds eur2 and eur3 (zones 2 and 3)
to check, with measurements, what changes when region eur has its own quorum:
- Test 1, MODE=restricted: does the native PLACEMENT RESTRICTED isolate eur now?
- Test 1, MODE=poc3: the PoC's manual zones with 3 replicas in eur.
- Test 2 (script 21): one eur node down (G1) and the whole eur region down (G2).
Test 3 is not repeated: the cross-region latency does not depend on the number of eur nodes.

## Run order (in Ubuntu/WSL, inside the folder)
```bash
# 0. Keep the 3+1 results apart
mv results results_3x1_20261110 && mkdir results

# 1. Clean start with 6 nodes
docker compose down -v
export COMPOSE_FILE=docker-compose.yml:docker-compose.eur3.yml
export EXPECTED_NODES=6
./scripts/00_start_cluster.sh

# 2. Test 1 in two configurations
MODE=restricted ./scripts/01_load_schema.sh && ./scripts/10_test_isolation.sh
MODE=poc3       ./scripts/01_load_schema.sh && ./scripts/10_test_isolation.sh

# 3. Test 2 for the 3+3 scenario (runs on poc3, loaded last)
./scripts/21_test_failover_eur3.sh

# 4. Evidence
./scripts/99_collect_evidence.sh

# 5. Back to the main setup afterwards
docker compose down -v
unset COMPOSE_FILE EXPECTED_NODES
```
The two `export` lines hold only for that terminal: if you open another one, run them again before any script.

# Complementary scenario: three nodes in region `eur` (3+3)

The main topology reproduces the original proof of concept (3 nodes in `usa`, 1 in `eur`). This scenario adds
`eur2` and `eur3` (zones 2 and 3) to show what changes when region `eur` has its own quorum.
Results: `results/3x3_complementary/`.

What is run:
- Experiment 1 with `MODE=restricted` (native PLACEMENT RESTRICTED) and `MODE=poc3` (manual zone configs with
  three replicas in `eur`).
- Experiment 2 with `scripts/21_test_failover_eur3.sh`: G0 (all nodes up), G1 (`eur2` down) and G2 (the whole
  `eur` region down).
- Experiment 3 is not repeated: cross-region latency does not depend on the number of nodes per region.

```bash
docker compose down -v
export COMPOSE_FILE=docker-compose.yml:docker-compose.eur3.yml   # 6 nodes
export EXPECTED_NODES=6
./scripts/00_start_cluster.sh

MODE=restricted ./scripts/01_load_schema.sh && ./scripts/10_test_isolation.sh
MODE=poc3       ./scripts/01_load_schema.sh && ./scripts/10_test_isolation.sh
./scripts/21_test_failover_eur3.sh          # runs on the configuration loaded last (poc3)
./scripts/99_collect_evidence.sh

docker compose down -v                      # back to the main topology
unset COMPOSE_FILE EXPECTED_NODES
```
The two `export` lines apply only to the current terminal.

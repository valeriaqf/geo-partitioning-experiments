# Super regions

Cockroach Labs currently recommends super regions, rather than PLACEMENT RESTRICTED, for data domiciling.
`MODE=superregion` (`sql/02d_super_regions.sql`) creates one super region per database region: `eua` = {`usa`}
and `europa` = {`eur`}. In v26.2.6 the feature needs no flag (`SET enable_super_regions` only prints a notice).
Results: `results/superregion_3x1/` (17/20: `eur` has a single node and cannot hold three voting replicas)
and `results/superregion_3x3/` (20/20, plus Experiment 2).

```bash
# 3+1: Experiment 1 only
docker compose down -v
unset COMPOSE_FILE; export EXPECTED_NODES=4
./scripts/00_start_cluster.sh
MODE=superregion ./scripts/01_load_schema.sh && ./scripts/10_test_isolation.sh
./scripts/99_collect_evidence.sh

# 3+3: Experiments 1 and 2
docker compose down -v
export COMPOSE_FILE=docker-compose.yml:docker-compose.eur3.yml
export EXPECTED_NODES=6
./scripts/00_start_cluster.sh
MODE=superregion ./scripts/01_load_schema.sh && ./scripts/10_test_isolation.sh
./scripts/21_test_failover_eur3.sh
./scripts/99_collect_evidence.sh

docker compose down -v
unset COMPOSE_FILE EXPECTED_NODES
```
Each run writes its files to `results/`; move them to a folder of their own before the next run.

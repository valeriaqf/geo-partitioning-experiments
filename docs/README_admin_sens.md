# Validation case V7: administrator allowed to read both regions

Profile `admin_sens` (`sql/05_admin_sens.sql`) may read personal data of both regions, but only through the
region-filtered views, never through the base tables. The test (`scripts/12_test_admin_sens.sh`, 6 checks)
also confirms that reading `eur` rows from a `usa` node does not move their replicas out of `eur`.
Results: `results/v7_admin_sens/`.

Run on the main topology (3+1) with the manual zone configs:
```bash
docker compose down -v
unset COMPOSE_FILE; export EXPECTED_NODES=4
./scripts/00_start_cluster.sh
MODE=poc ./scripts/01_load_schema.sh
./scripts/12_test_admin_sens.sh
./scripts/99_collect_evidence.sh
```
Expected: 6 PASS, 0 FAIL. Most of the ~5 minutes is the wait for replicas to settle.

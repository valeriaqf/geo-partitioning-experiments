# Geo-partitioning experiments with CockroachDB (local cluster, synthetic data)

Experiments of the undergraduate thesis *Particionamento Geográfico de Dados em Bancos Distribuídos para
Conformidade Regulatória: uma Avaliação Experimental com CockroachDB* (IFRN, 2026).
They check whether CockroachDB's geo-partitioning keeps each region's rows inside that region, how the
cluster behaves when nodes or a whole region fail, and how much cross-region access costs in latency.

All data is synthetic. Nothing here depends on any real system, infrastructure or dataset.

## Setup
- CockroachDB v26.2.6 (image pinned in `docker-compose.yml`), `--insecure` mode, free license (asked at run time,
  never written to any file).
- Main topology **3+1**: region `usa` = usa1, usa2, usa3 (zones 1-3); region `eur` = eur1.
- Complementary topology **3+3**: adds eur2 and eur3 (`docker-compose.eur3.yml`).
- Data model: `research_projects` and `units` (GLOBAL tables, no personal data); `doctors`, `patients` and
  `doctor_research_projects` (REGIONAL BY ROW, each row stored in its home region).
- Access profiles: `app_usa`, `app_eur` (regional applications), `admin_meta` (counts per region only),
  `admin_sens` (reads both regions through views only). Profiles read through region-filtered views.

## Layout
```
docker-compose.yml            4-node cluster (3+1)
docker-compose.eur3.yml       extra nodes eur2, eur3 (3+3, used together with the file above)
sql/01_schema.sql             database geo_db, regions, GLOBAL and REGIONAL BY ROW tables
sql/02_zone_overrides.sql     manual zone configs (usa: 3 replicas / eur: 1 replica)   MODE=poc
sql/02b_placement_restricted.sql  native PLACEMENT RESTRICTED                          MODE=restricted
sql/02c_zone_overrides_eur3.sql   manual zone configs with 3 replicas in eur (3+3)     MODE=poc3
sql/02d_super_regions.sql     super regions "eua" (usa) and "europa" (eur)         MODE=superregion
sql/03_seed_data.sql          synthetic data (1,000 patients and 100 doctors per region)
sql/04_roles_views.sql        access profiles and region-filtered views
sql/05_admin_sens.sql         profile admin_sens (validation case V7)
sql/06_write_restriction.sql  row-level security: each regional app writes only its own region (case V8)
scripts/                      numbered scripts (see below)
results/                      raw results (CSV and logs), one folder per scenario
docs/                         step-by-step notes for the 3+3 scenario, case V7 and super regions
```

## Scripts
| Script | What it does |
|---|---|
| 00_start_cluster.sh | starts the nodes, initializes the cluster, applies the license |
| 01_load_schema.sh | recreates the database; `MODE=baseline\|restricted\|poc\|poc3\|superregion` selects the placement |
| 10_test_isolation.sh | Experiment 1: replica placement (6 checks) + access control, cases V1-V6 (14 checks) |
| 12_test_admin_sens.sh | case V7: administrator reading both regions through views (6 checks) |
| 13_test_write_restriction.sh | case V8: each regional app may write only rows of its own region (9 checks) |
| 20_test_failover.sh | Experiment 2 (3+1): scenarios F0, F1 (usa3 down), F2 (eur1 down) |
| 21_test_failover_eur3.sh | Experiment 2 (3+3): scenarios G0, G1 (eur2 down), G2 (region eur down) |
| 30_test_performance.sh | Experiment 3: latency with 0, 80 or 150 ms of delay on eur1 (`tc netem`) |
| 99_collect_evidence.sh | records environment and zone configs, packs the results |

Run order of the main scenario (Ubuntu on WSL, inside this folder):
```bash
./scripts/00_start_cluster.sh
MODE=baseline   ./scripts/01_load_schema.sh && ./scripts/10_test_isolation.sh
MODE=restricted ./scripts/01_load_schema.sh && ./scripts/10_test_isolation.sh
MODE=poc        ./scripts/01_load_schema.sh && ./scripts/10_test_isolation.sh
./scripts/12_test_admin_sens.sh
./scripts/20_test_failover.sh
for r in 1 2 3; do for d in 0 80 150; do ./scripts/30_test_performance.sh $d 300 $r; done; done
./scripts/99_collect_evidence.sh
```
Case V8 ran in a separate session: `00`, then `MODE=poc 01`, then `13`.
The 3+3 scenario is described in `docs/README_3x3.md`; the super-region runs (both topologies, in a later
session) in `docs/README_superregion.md`.

## Results
| Folder | Content | Run date |
|---|---|---|
| results/preliminary_2026-10-19 | first run, with an earlier version of the scripts (one placement configuration, 0 and 80 ms, one round) | 2026-10-19 |
| results/3x1_main | Experiments 1, 2 and 3, main topology | 2026-11-10 |
| results/3x3_complementary | Experiments 1 and 2, topology 3+3 | 2026-11-10 |
| results/v7_admin_sens | case V7 (6/6 PASS) | 2026-11-10 |
| results/v8_write_restriction | case V8 (9/9 PASS) | 2026-11-11 |
| results/superregion_3x1 | Experiment 1 with super regions, topology 3+1 (17/20: eur has a single node) | 2026-11-11 |
| results/superregion_3x3 | Experiments 1 and 2 with super regions, topology 3+3 (20/20) | 2026-11-11 |
| results/other | last state of the working results folder (environment, liveness, zone configs) | 2026-11-11 |

Every log has the run date and time in its name and first line. Every test checks that all nodes are live at
the start and at the end (`liveness.csv`).

**Note on identifiers:** after the runs, the table, column and profile-view names were renamed to neutral ones in the
code and, consistently, in the result files (`research_projects`, `units`, `doctors`, `patients`,
`doctor_research_projects`, `file_ref`). Only names were changed; no value, count or measurement was altered.

## Limitations
- Everything runs on one machine; cross-region latency is simulated with fixed delays.
- Region `eur` has a single node in the main topology: isolating its data leaves one replica, so it does not survive
  the loss of that node.
- Only two regions: no scenario survives the loss of a whole region (that needs at least three regions).
- `--insecure` mode, small synthetic dataset.

## Start over
```bash
docker compose down -v
```

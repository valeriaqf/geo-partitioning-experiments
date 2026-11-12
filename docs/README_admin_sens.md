# Caso de validação V7 — administrador com acesso a dados pessoais das duas regiões

Arquivos novos (copie para dentro de ~/geo-partitioning-experiments, mantendo as pastas):
- sql/05_admin_sens.sql — cria o perfil admin_sens (lê as visões das duas regiões, nunca as tabelas base)
- scripts/12_test_admin_sens.sh — 6 verificações, salvas em results/isolation_admin_sens.csv

Nada dos testes 10, 20 e 30 muda.

## Passo a passo (cluster principal 3+1, modo poc)

    cd ~/geo-partitioning-experiments
    unset COMPOSE_FILE            # volta para o docker-compose.yml de 4 nós
    export EXPECTED_NODES=4
    cp -r results ~/results_backup_$(date +%Y%m%d_%H%M)   # cópia de segurança dos resultados

    docker compose ps             # se aparecerem eur2/eur3 (3+3) ou nada rodando:
    docker compose -f docker-compose.yml -f docker-compose.eur3.yml down -v   # só se o 3+3 estiver de pé
    ./scripts/00_start_cluster.sh # pede a licença (não é gravada)

    MODE=poc ./scripts/01_load_schema.sh
    ./scripts/12_test_admin_sens.sh
    ./scripts/99_collect_evidence.sh

Resultado esperado: PASS 6, FAIL 0. Leva uns 5 minutos (a maior parte é a espera pelas réplicas).

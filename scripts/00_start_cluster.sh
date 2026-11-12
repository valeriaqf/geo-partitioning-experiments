#!/usr/bin/env bash
# Starts the 4 nodes, initializes the cluster and applies the license (asked at run time; never written to disk).
# SKIP_LICENSE=1 skips the license step.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh

docker compose up -d

echo "Initializing the cluster..."
ok=0
for i in $(seq 1 30); do
  if docker exec usa1 ./cockroach init --insecure --host=usa1:26257 2>/tmp/crdb_init.err; then
    echo "Cluster initialized."; ok=1; break
  elif grep -q "already been initialized" /tmp/crdb_init.err; then
    echo "Cluster was already initialized."; ok=1; break
  fi
  sleep 2
done
[ "$ok" = 1 ] || { echo "ERROR: could not initialize. Check: docker logs usa1"; exit 1; }

echo "Waiting for the 4 nodes to be live..."
# Counts only LIVE nodes (a node that crashed still appears in "node status", with is_live=false).
wait_all_live 120 "cluster start" || { echo "ERROR: not all 4 nodes are live. Check: docker ps -a; docker logs <node>"; exit 1; }
docker exec usa1 ./cockroach version 2>&1 | head -1

if [ "${SKIP_LICENSE:-0}" != "1" ]; then
  read -rp "Organization name (the one used when requesting the license): " ORG
  read -rsp "Paste the license key (hidden): " LIC; echo
  LIC=$(printf '%s' "$LIC" | tr -d '[:space:]"'"'")
  printf "SET CLUSTER SETTING cluster.organization = '%s';\nSET CLUSTER SETTING enterprise.license = '%s';\n" "$ORG" "$LIC" \
    | docker exec -i usa1 ./cockroach sql --insecure --host=usa1:26257 >/dev/null \
    && echo "License applied."
  unset LIC ORG
fi

docker exec usa1 ./cockroach node status --insecure --host=usa1:26257
echo "Web console: http://localhost:8080"

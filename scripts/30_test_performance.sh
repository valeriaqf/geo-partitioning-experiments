#!/usr/bin/env bash
# Test 3 - Read/write latency: local vs. cross-region.
# Usage: ./scripts/30_test_performance.sh [delay_ms] [N] [round]
#   round (optional): run number, added to the output names (e.g. delay80ms_r2) so repeated runs are kept.
#   delay_ms: extra delay (netem) on everything that LEAVES eur1 over the network, i.e. the inter-region link.
#   The client for the eur gateway runs INSIDE eur1's network namespace and talks to it over localhost, which
#   is not delayed, so "eur -> eur" stays local while "eur -> usa" and "usa -> eur" pay the inter-region delay.
#   Run once with 0 and once with e.g. 80 to simulate geographic distance.
set -uo pipefail
source "$(dirname "$0")/lib.sh"
DELAY="${1:-0}"
N="${2:-300}"
ROUND="${3:-}"
NET="crdb_geo_net"

netshoot() { docker run --rm --net=container:eur1 --cap-add=NET_ADMIN nicolaka/netshoot sh -c "$1"; }
clear_delay() { netshoot "tc qdisc del dev eth0 root" >/dev/null 2>&1 || true; }
trap clear_delay EXIT

require_all_live "performance start (delay ${DELAY}ms ${ROUND:+round $ROUND})" || { echo "ABORTED: not all nodes are live; fix the cluster and run again."; exit 1; }

clear_delay
LABEL="delay${DELAY}ms"
if [ "$DELAY" -gt 0 ]; then
  if netshoot "tc qdisc add dev eth0 root netem delay ${DELAY}ms"; then
    echo "Added ${DELAY}ms of delay on the eur1 network link."
  else
    echo "WARNING: could not apply the delay (WSL kernel without netem?)."
    echo "Running WITHOUT artificial delay; record this limitation in the thesis."
    LABEL="delay0ms"
  fi
fi
[ -n "$ROUND" ] && LABEL="${LABEL}_r${ROUND}"

PIP="pip install -q --disable-pip-version-check --root-user-action=ignore psycopg2-binary"

echo "== Client in region usa (gateway usa1)"
docker run --rm --network "$NET" -v "$ROOT":/w -w /w python:3.12-slim \
  sh -c "$PIP && python scripts/perf.py --gateway usa --host usa1 --n $N --label $LABEL"

echo "== Client in region eur (inside eur1's network namespace, gateway localhost)"
docker run --rm --net=container:eur1 -v "$ROOT":/w -w /w python:3.12-slim \
  sh -c "$PIP && python scripts/perf.py --gateway eur --host localhost --n $N --label $LABEL"

clear_delay
require_all_live "performance end ($LABEL)" \
  || echo "INVALID RUN: a node went down during the test (see results/liveness.csv). Discard $LABEL and repeat it."

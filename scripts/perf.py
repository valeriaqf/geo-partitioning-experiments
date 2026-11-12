"""Read/write latency by gateway region and data region.

Runs inside a container on the same network as the nodes (hosts usa1 and eur1).
Usage: python scripts/perf.py --gateway usa --host usa1 --n 300 --label delay0ms
"""
import argparse
import csv
import os
import time
import uuid

import psycopg2

REGIONS = ["usa", "eur"]


def connect(host):
    c = psycopg2.connect(host=host, port=26257, user="root", dbname="geo_db",
                         sslmode="disable", connect_timeout=10)
    c.autocommit = True
    return c


def pct(values, p):
    s = sorted(values)
    return s[min(len(s) - 1, int(len(s) * p / 100))]


def measure(fn, n, warmup=20):
    for i in range(warmup):
        fn(i)
    lat = []
    for i in range(n):
        t = time.perf_counter()
        fn(warmup + i)
        lat.append((time.perf_counter() - t) * 1000)
    return lat


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--gateway", required=True, choices=REGIONS)
    ap.add_argument("--host", required=True)
    ap.add_argument("--n", type=int, default=300)
    ap.add_argument("--label", default="test")
    args = ap.parse_args()

    conn = connect(args.host)
    cur = conn.cursor()

    ids = {}
    for reg in REGIONS:
        cur.execute("SELECT id FROM patients WHERE crdb_region = %s LIMIT 400", (reg,))
        ids[reg] = [str(r[0]) for r in cur.fetchall()]
        if len(ids[reg]) < 50:
            raise SystemExit(f"Too little data in region {reg}; run scripts/01_load_schema.sh")

    rows = []

    def record(data_region, operation, lat):
        rows.append({
            "scenario": args.label, "gateway": args.gateway, "data_region": data_region,
            "operation": operation, "n": len(lat),
            "mean_ms": round(sum(lat) / len(lat), 2),
            "p50_ms": round(pct(lat, 50), 2),
            "p95_ms": round(pct(lat, 95), 2),
            "p99_ms": round(pct(lat, 99), 2),
        })

    for data_region in REGIONS:
        id_list = ids[data_region]

        def read_with_region(i, id_list=id_list, data_region=data_region):
            cur.execute("SELECT id, name FROM patients WHERE crdb_region = %s AND id = %s",
                        (data_region, id_list[i % len(id_list)]))
            cur.fetchall()

        record(data_region, "read_with_region", measure(read_with_region, args.n))

        def read_without_region(i, id_list=id_list):
            cur.execute("SELECT id, name FROM patients WHERE id = %s", (id_list[i % len(id_list)],))
            cur.fetchall()

        record(data_region, "read_without_region", measure(read_without_region, args.n))

        def write(i, data_region=data_region):
            cur.execute("INSERT INTO patients (crdb_region, name, file_ref) VALUES (%s, %s, %s)",
                        (data_region, "perf-" + uuid.uuid4().hex[:12], "s3://synthetic/perf.jpg"))

        record(data_region, "write", measure(write, args.n))

    cur.execute("DELETE FROM patients WHERE name LIKE 'perf-%'")

    os.makedirs("results", exist_ok=True)
    path = f"results/performance_{args.label}_{args.gateway}.csv"
    with open(path, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)

    print(f"{'gateway':8}{'data':6}{'operation':22}{'n':>5}{'mean':>9}{'p50':>9}{'p95':>9}{'p99':>9}  (ms)")
    for r in rows:
        print(f"{r['gateway']:8}{r['data_region']:6}{r['operation']:22}{r['n']:>5}"
              f"{r['mean_ms']:>9}{r['p50_ms']:>9}{r['p95_ms']:>9}{r['p99_ms']:>9}")
    print(f"Saved to {path}")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""
systolic_model.py - cycle model, performance analysis and charts (Phase II)

  python3 tools/systolic_model.py            trace + tables (no extra packages)
  python3 tools/systolic_model.py --plot     also writes docs/figures/*.png
                                             (pip install matplotlib)

1. reference()  plain triple-loop C = A x B
2. simulate()   cycle-by-cycle model of the RTL: lane i delayed i cycles,
                a moves right and b moves down one PE per cycle
3. tables       latency / throughput vs N (formulas checked against the RTL
                testbenches at N = 2..16), and wall-clock results from
                synth/results.csv
"""
import csv
import random
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FIG = ROOT / "docs" / "figures"


def reference(A, B):
    n = len(A)
    return [[sum(A[i][k] * B[k][j] for k in range(n)) for j in range(n)] for i in range(n)]


def simulate(A, B, trace=False):
    """Cycle model of matmul_accel. Returns (C, compute_cycles)."""
    n = len(A)
    a_lane = [[0] * i + [A[i][k] for k in range(n)] for i in range(n)]   # skew_buffer contents
    b_lane = [[0] * j + [B[k][j] for k in range(n)] for j in range(n)]
    a_reg = [[0] * n for _ in range(n)]
    b_reg = [[0] * n for _ in range(n)]
    acc = [[0] * n for _ in range(n)]
    for t in range(3 * n - 2):
        a_edge = [a_lane[i][t] if t < len(a_lane[i]) else 0 for i in range(n)]
        b_edge = [b_lane[j][t] if t < len(b_lane[j]) else 0 for j in range(n)]
        a_in = [[a_edge[i] if j == 0 else a_reg[i][j - 1] for j in range(n)] for i in range(n)]
        b_in = [[b_edge[j] if i == 0 else b_reg[i - 1][j] for j in range(n)] for i in range(n)]
        if trace:
            busy = [f"PE{i}{j}:{a_in[i][j]}x{b_in[i][j]}" for i in range(n) for j in range(n)
                    if a_in[i][j] and b_in[i][j]]
            print(f"  t={t}: " + ", ".join(busy))
        for i in range(n):
            for j in range(n):
                acc[i][j] += a_in[i][j] * b_in[i][j]
        a_reg, b_reg = a_in, b_in
    return acc, 3 * n - 2


def self_check(trials=300):
    rng = random.Random(2026)
    for n in (2, 3, 4, 5, 8):
        for _ in range(trials):
            A = [[rng.randint(-128, 127) for _ in range(n)] for _ in range(n)]
            B = [[rng.randint(-128, 127) for _ in range(n)] for _ in range(n)]
            assert simulate(A, B)[0] == reference(A, B)
    print(f"model == reference for {trials} random matrices at N = 2, 3, 4, 5, 8")


def synth_results():
    path = ROOT / "synth" / "results.csv"
    if not path.exists():
        return []
    rows = list(csv.DictReader(path.open()))
    for r in rows:
        n = int(r["N"])
        r["cycles"] = n ** 3 + 1 if r["design"] == "sequential" else 3 * n - 1
        r["ns"] = r["cycles"] * 1000.0 / float(r["Fmax_MHz"])
    return rows


def plot(rows):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    FIG.mkdir(parents=True, exist_ok=True)
    ns = list(range(2, 17))
    teal, amber, grey = "#1F6F8B", "#A3500F", "#8A94A3"

    fig, ax = plt.subplots(figsize=(6.4, 3.4), dpi=200)
    ax.plot(ns, [n ** 3 + 1 for n in ns], "o-", color=amber, label="sequential (1 MAC): N³ + 1")
    ax.plot(ns, [3 * n - 1 for n in ns], "s-", color=teal, label="systolic (N² PEs): 3N − 1")
    ax.set_yscale("log"); ax.set_xlabel("matrix size N"); ax.set_ylabel("latency (cycles, log scale)")
    ax.grid(True, which="both", alpha=0.3); ax.legend(frameon=False)
    fig.tight_layout(); fig.savefig(FIG / "latency_vs_n.png"); plt.close(fig)

    if rows:
        fig, axes = plt.subplots(1, 2, figsize=(7.2, 3.0), dpi=200)
        names = {"systolic": "systolic\n(Phase II)", "phase1": "systolic\n(Phase I)", "sequential": "sequential\nbaseline"}
        colors = {"systolic": teal, "phase1": grey, "sequential": amber}
        for ax, key, label in ((axes[0], "Fmax_MHz", "max clock (MHz)"), (axes[1], "ns", "time per 4×4 product (ns)")):
            sub = [r for r in rows if r["N"] == "4"]
            vals = [float(r[key]) for r in sub]
            bars = ax.bar([names[r["design"]] for r in sub], vals, color=[colors[r["design"]] for r in sub])
            for b, v in zip(bars, vals):
                ax.annotate(f"{v:.0f}", (b.get_x() + b.get_width() / 2, v), ha="center", va="bottom", fontsize=8)
            ax.set_ylabel(label); ax.grid(True, axis="y", alpha=0.3)
            ax.tick_params(axis="x", labelsize=7.5)
        fig.tight_layout(); fig.savefig(FIG / "synthesis_n4.png"); plt.close(fig)
    print("charts written to", FIG)


def main():
    A = [[1, 2, 3], [4, 5, 6], [7, 8, 9]]
    B = [[9, 8, 7], [6, 5, 4], [3, 2, 1]]
    print("3x3 trace (products each PE adds per cycle):")
    C, _ = simulate(A, B, trace=True)
    print("  C =", C, "matches reference:", C == reference(A, B))
    self_check()

    print("\n  N | latency systolic | latency sequential | cycle speed-up | MAC/cycle")
    for n in (2, 3, 4, 5, 8, 16):
        ls, lq = 3 * n - 1, n ** 3 + 1
        print(f"{n:3d} | {ls:16d} | {lq:18d} | {lq / ls:13.2f}x | {n ** 3 / ls:8.2f}")

    rows = synth_results()
    if rows:
        print("\n design      N  Fmax(MHz)  cycles  time(ns)")
        for r in rows:
            print(f" {r['design']:<11} {r['N']}  {float(r['Fmax_MHz']):8.2f}  {r['cycles']:6d}  {r['ns']:8.1f}")
        for n in ("3", "4"):
            s = next(r for r in rows if r["design"] == "systolic" and r["N"] == n)
            q = next(r for r in rows if r["design"] == "sequential" and r["N"] == n)
            p = next(r for r in rows if r["design"] == "phase1" and r["N"] == n)
            print(f" N={n}: wall-clock speed-up vs sequential {q['ns'] / s['ns']:.2f}x, "
                  f"vs Phase I {p['ns'] / s['ns']:.2f}x")
    if "--plot" in sys.argv:
        plot(rows)


if __name__ == "__main__":
    main()

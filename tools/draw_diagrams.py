#!/usr/bin/env python3
"""
draw_diagrams.py - architecture figures for the report and README (Phase II)

  python3 tools/draw_diagrams.py        (needs matplotlib)

Writes docs/figures/block_diagram.png, pe_microarch.png, fsm.png
"""
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, Circle, FancyArrowPatch

OUT = Path(__file__).resolve().parent.parent / "docs" / "figures"
OUT.mkdir(parents=True, exist_ok=True)
TEAL, AMBER, INK, GREY, TINT = "#1F6F8B", "#A3500F", "#14213D", "#6B7685", "#F1F0EB"


def box(ax, x, y, w, h, text="", fc="white", ec=INK, fs=8.5, lw=1.2, ls="-"):
    ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.02,rounding_size=0.08",
                                fc=fc, ec=ec, lw=lw, ls=ls))
    if text:
        ax.text(x + w / 2, y + h / 2, text, ha="center", va="center", fontsize=fs, color=INK)


def label(ax, x, y, text, fs=8.5, color=INK, weight="normal", ha="left"):
    ax.text(x, y, text, fontsize=fs, color=color, weight=weight, ha=ha, va="center")


def arrow(ax, x0, y0, x1, y1, color=INK, lw=1.1):
    ax.add_patch(FancyArrowPatch((x0, y0), (x1, y1), arrowstyle="-|>", mutation_scale=9,
                                 color=color, lw=lw, shrinkA=0, shrinkB=0))


def block_diagram():
    fig, ax = plt.subplots(figsize=(10, 6.6), dpi=200)
    ax.set_xlim(0, 15); ax.set_ylim(0, 10); ax.axis("off")

    # matmul_top (data interface)
    box(ax, 1.9, 0.3, 11.2, 9.2, fc="#FAFAF7", ec=GREY, ls="--")
    label(ax, 2.1, 9.15, "matmul_top.v  -  matrix data interface (registered narrow port)", fs=9, weight="bold")
    box(ax, 2.2, 7.3, 2.4, 1.4, "A and B\nregister files\n(write one element\nper clock)", fc=TINT, fs=7.5)
    for y, t in ((8.4, "we, sel_b"), (8.0, "addr, wdata"), (7.6, "start")):
        label(ax, 0.1, y, t, fs=7.5, color=AMBER); arrow(ax, 1.3, y, 2.2, y, color=AMBER)

    # matmul_accel
    box(ax, 5.0, 0.6, 7.8, 8.2, fc="#E6F0F3", ec=TEAL, lw=1.6)
    label(ax, 5.2, 8.5, "matmul_accel.v  (systolic core)", fs=9, weight="bold", color=TEAL)
    box(ax, 5.3, 6.9, 7.2, 1.2, "Controller: IDLE / RUN, cycle counter t\n"
                                "start -> load buffers + clear PEs;  RUN for 3N-2 cycles;  done = 1",
        fc="white", fs=7.8)
    arrow(ax, 4.6, 8.0, 5.3, 7.5, color=AMBER)

    # skew buffers for B (top) and A (left)
    for j in range(3):
        x = 8.05 + j * 1.45
        box(ax, x, 5.65, 1.1, 0.75, f"B col {j}\ndelay {j}", fc="white", ec=TEAL, fs=7)
        arrow(ax, x + 0.55, 5.65, x + 0.55, 5.15, color=TEAL)
    label(ax, 10.25, 6.6, "skew_buffer.v (input buffers)", fs=7.5, color=TEAL, ha="center")
    for i in range(3):
        y = 4.3 - i * 1.45
        box(ax, 5.4, y, 1.25, 0.75, f"A row {i}\ndelay {i}", fc="white", ec=AMBER, fs=7)
        arrow(ax, 6.65, y + 0.37, 7.75, y + 0.37, color=AMBER)
    arrow(ax, 4.6, 7.6, 5.0, 5.2, color=GREY)
    label(ax, 5.35, 5.35, "loaded on start", fs=7, color=GREY)

    # PE grid
    for i in range(3):
        for j in range(3):
            x, y = 7.75 + j * 1.45, 4.15 - i * 1.45
            box(ax, x, y, 1.0, 1.0, f"PE{i}{j}\nMAC", fc="white", fs=7.5)
            if j < 2:
                arrow(ax, x + 1.0, y + 0.52, x + 1.45, y + 0.52, color=AMBER)
            if i < 2:
                arrow(ax, x + 0.5, y, x + 0.5, y - 0.45, color=TEAL)
    label(ax, 9.9, 0.95, "systolic_array.v: N x N pe.v (each = mac_unit.v + 2 registers)", fs=7.5, ha="center")

    # outputs
    arrow(ax, 12.8, 3.0, 13.6, 3.0); label(ax, 13.7, 3.0, "C[i][j]\nfrom each\nPE's acc", fs=7.5)
    arrow(ax, 13.1, 6.0, 13.6, 6.0); label(ax, 13.7, 6.0, "rdata\n(raddr)", fs=7.5)
    arrow(ax, 13.1, 7.5, 13.6, 7.5); label(ax, 13.7, 7.5, "busy, done", fs=7.5)
    ax.text(7.5, 9.85, "Fig. 1  Phase II architecture (N = 3 shown); seq_matmul.v can replace "
            "matmul_accel inside matmul_top (ARCH = 1)", ha="center", fontsize=9)
    fig.tight_layout(); fig.savefig(OUT / "block_diagram.png", facecolor="white"); plt.close(fig)


def pe_diagram():
    fig, ax = plt.subplots(figsize=(8, 4.9), dpi=200)
    ax.set_xlim(0, 10); ax.set_ylim(0, 6.7); ax.axis("off")
    box(ax, 1.6, 0.6, 6.4, 4.9, fc="#FAFAF7", ec=INK, ls="--", lw=1.3)
    label(ax, 1.75, 5.2, "pe.v", fs=9, weight="bold")
    box(ax, 3.35, 2.65, 4.5, 1.45, fc="none", ec=TEAL, lw=1.0)
    label(ax, 5.6, 4.3, "mac_unit.v", fs=8.5, color=TEAL, ha="center")
    for cx, sym in ((4.0, "×"), (5.6, "+")):
        ax.add_patch(Circle((cx, 3.37), 0.42, fc="white", ec=INK, lw=1.2))
        ax.text(cx, 3.37, sym, ha="center", va="center", fontsize=15)
    box(ax, 6.5, 2.95, 1.2, 0.85, "acc\n(24 bit)", fc="#E6F0F3", ec=TEAL, fs=8)
    box(ax, 6.5, 1.0, 1.2, 0.8, "a_out\nreg", fs=8)
    box(ax, 2.2, 1.0, 1.2, 0.8, "b_out\nreg", fs=8)
    arrow(ax, 0.2, 3.37, 3.58, 3.37, color=AMBER); label(ax, 0.2, 3.6, "a_in (8 bit, from left)", fs=8, color=AMBER)
    ax.plot([2.0, 2.0, 6.2, 6.2], [3.37, 2.3, 2.3, 1.4], color=AMBER, lw=1.1)
    arrow(ax, 6.2, 1.4, 6.5, 1.4, color=AMBER)
    arrow(ax, 4.0, 6.1, 4.0, 3.79, color=TEAL); label(ax, 4.1, 5.85, "b_in (8 bit, from top)", fs=8, color=TEAL)
    ax.plot([4.0, 2.8, 2.8], [4.9, 4.9, 1.8], color=TEAL, lw=1.1)
    arrow(ax, 2.8, 2.0, 2.8, 1.8, color=TEAL)
    arrow(ax, 4.42, 3.37, 5.18, 3.37); label(ax, 4.5, 3.6, "16 b", fs=7)
    arrow(ax, 6.02, 3.37, 6.5, 3.37)
    ax.plot([7.1, 7.1, 5.6], [2.95, 2.75, 2.75], color=INK, lw=1.1); arrow(ax, 5.6, 2.75, 5.6, 2.95)
    arrow(ax, 7.7, 3.37, 9.8, 3.37, color=TEAL); label(ax, 8.15, 3.6, "acc = C[i][j]", fs=8, color=TEAL)
    arrow(ax, 7.7, 1.4, 9.8, 1.4, color=AMBER); label(ax, 8.15, 1.62, "a_out (to right)", fs=8, color=AMBER)
    arrow(ax, 2.8, 1.0, 2.8, 0.05, color=TEAL); label(ax, 2.95, 0.2, "b_out (down)", fs=8, color=TEAL)
    label(ax, 4.6, 0.2, "control: clk, rst, clr, en", fs=8, color=GREY)
    ax.text(5, 6.55, "Fig. 2  Processing element: one MAC per clock, operands forwarded one clock later",
            ha="center", fontsize=9)
    fig.tight_layout(); fig.savefig(OUT / "pe_microarch.png", facecolor="white"); plt.close(fig)


def fsm_diagram():
    fig, ax = plt.subplots(figsize=(8, 3.4), dpi=200)
    ax.set_xlim(0, 10); ax.set_ylim(0, 4.4); ax.axis("off")
    for (x, name, sub, fc) in ((2.4, "IDLE", "wait for start\ndone holds", "white"),
                               (7.6, "RUN", "en = 1, busy = 1\nt = 0 ... 3N-3", "#E6F0F3")):
        ax.add_patch(Circle((x, 2.1), 1.0, fc=fc, ec=INK, lw=1.4))
        ax.text(x, 2.35, name, ha="center", va="center", fontsize=12, weight="bold", color=INK)
        ax.text(x, 1.8, sub, ha="center", va="center", fontsize=7.5, color=INK)
    ax.add_patch(FancyArrowPatch((3.3, 2.6), (6.7, 2.6), connectionstyle="arc3,rad=-0.25",
                                 arrowstyle="-|>", mutation_scale=10, color=INK, lw=1.2))
    ax.text(5.0, 3.55, "start = 1\nload buffers, clear PEs, t = 0, done = 0", ha="center", fontsize=8, color=TEAL)
    ax.add_patch(FancyArrowPatch((6.7, 1.6), (3.3, 1.6), connectionstyle="arc3,rad=-0.25",
                                 arrowstyle="-|>", mutation_scale=10, color=INK, lw=1.2))
    ax.text(5.0, 0.55, "t = 3N-3\ndone = 1", ha="center", fontsize=8, color=TEAL)
    ax.text(5.0, 4.25, "Fig. 3  Controller states (latency start -> done = 1 + (3N-2) = 3N-1 cycles)",
            ha="center", fontsize=9)
    fig.tight_layout(); fig.savefig(OUT / "fsm.png", facecolor="white"); plt.close(fig)


if __name__ == "__main__":
    block_diagram()
    pe_diagram()
    fsm_diagram()
    print("wrote", ", ".join(p.name for p in sorted(OUT.glob("*.png"))))

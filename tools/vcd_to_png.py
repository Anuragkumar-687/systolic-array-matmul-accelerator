"""
vcd_to_png.py - render the simulation waveform of one 3x3 multiplication

  make sim N=3                      (writes build/waves.vcd)
  python3 tools/vcd_to_png.py       (writes docs/figures/waveform_n3.png; needs matplotlib)

Shows the second test of tb_matmul_accel ("counting": A = 1..9, B = 9..1):
start, the controller state and counter t, and the inputs and accumulators of
the diagonal PEs. PE11 starts 2 cycles after PE00 and PE22 4 cycles after
(the skew), and they finish at 30, 69 and 90, the diagonal of C.
"""
import sys
from pathlib import Path
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

ROOT = Path(__file__).resolve().parent.parent
VCD = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "build" / "waves.vcd"
OUT = Path(sys.argv[2]) if len(sys.argv) > 2 else ROOT / "docs" / "figures" / "waveform_n3.png"
TB = "tb_matmul_accel"; D = f"{TB}.dut"
pe = lambda i, j, s: f"{D}.u_array.g_row[{i}].g_col[{j}].u_pe.{s}"
SIGS = [
    ("clk", f"{TB}.clk", "bit"), ("start", f"{TB}.start", "bit"),
    ("state", f"{D}.state", "state"), ("t (counter)", f"{D}.t", "ubus"),
    ("PE00 a_in", pe(0, 0, "a_in"), "bus"), ("PE00 b_in", pe(0, 0, "b_in"), "bus"),
    ("PE00 acc", pe(0, 0, "acc"), "bus"),
    ("PE11 a_in", pe(1, 1, "a_in"), "bus"), ("PE11 b_in", pe(1, 1, "b_in"), "bus"),
    ("PE11 acc", pe(1, 1, "acc"), "bus"),
    ("PE22 a_in", pe(2, 2, "a_in"), "bus"), ("PE22 b_in", pe(2, 2, "b_in"), "bus"),
    ("PE22 acc", pe(2, 2, "acc"), "bus"),
    ("done", f"{D}.done", "bit"),
]
want = {s[1]: s[2] for s in SIGS}
ids, scope, data, t = {}, [], {s[1]: [] for s in SIGS}, 0
with open(VCD) as f:
    hdr = True
    for line in f:
        tok = line.split()
        if not tok: continue
        if hdr:
            if tok[0] == "$scope": scope.append(tok[2])
            elif tok[0] == "$upscope": scope.pop()
            elif tok[0] == "$var":
                name = ".".join(scope + [tok[4]])
                if name in data: ids.setdefault(tok[3], []).append((name, int(tok[2])))
            elif tok[0] == "$enddefinitions": hdr = False
            continue
        c = tok[0][0]
        if c == "#": t = int(tok[0][1:])
        elif c in "01xz" and len(tok) == 1:
            for n, _ in ids.get(tok[0][1:], []): data[n].append((t, int(c) if c in "01" else None))
        elif c == "b":
            for n, w in ids.get(tok[1], []):
                b = tok[0][1:]
                v = None if any(x in "xz" for x in b) else int(b, 2)
                if v is not None and want[n] == "bus" and v >= 1 << (w - 1): v -= 1 << w
                data[n].append((t, v))
missing = [k for k, v in data.items() if not v]
if missing: sys.exit(f"missing {missing}")

def at(ser, tt):
    v = None
    for ts, val in ser:
        if ts > tt: break
        v = val
    return v

st = data[f"{TB}.start"]
rises = [b[0] for a, b in zip(st, st[1:]) if a[1] == 0 and b[1] == 1]
P = 10_000
t0 = rises[1] - P // 2; t1 = rises[2] + P // 2   # exactly the "counting" test
INK, GRN, GRID = "#1d2a3a", "#1f6f8b", "#d9dee5"
fig, ax = plt.subplots(figsize=(13, 0.5 * len(SIGS) + 0.9), dpi=170)
fig.patch.set_facecolor("#fbfaf7"); ax.set_facecolor("#fbfaf7")
for row, (lab, name, kind) in enumerate(SIGS):
    y = len(SIGS) - 1 - row
    ser = [(a, b) for a, b in data[name] if a <= t1]
    pts = [(t0, at(ser, t0))] + [(a, b) for a, b in ser if t0 < a <= t1] + [(t1, None)]
    ax.text(t0 - 0.25 * P, y + 0.33, lab, ha="right", va="center", fontsize=9,
            family="monospace", color=INK)
    for (ta, va), (tb, _) in zip(pts[:-1], pts[1:]):
        if kind == "bit":
            yy = y + (0.66 if va else 0)
            ax.plot([ta, tb], [yy, yy], color=GRN, lw=1.3)
            ax.plot([tb, tb], [y, y + 0.66], color=GRN, lw=0.7)
        else:
            hl = name.endswith("acc") and va not in (0, None)
            ax.fill_between([ta, tb], y, y + 0.66, color="#e6f1f4" if hl else "#fbfaf7", lw=0)
            for yy in (y, y + 0.66): ax.plot([ta, tb], [yy, yy], color=GRN, lw=0.8)
            ax.plot([tb, tb], [y, y + 0.66], color=GRN, lw=0.8)
            txt = {0: "IDLE", 1: "RUN"}.get(va) if kind == "state" else str(va)
            if tb - ta >= 0.6 * P:
                ax.text((ta + tb) / 2, y + 0.33, txt, ha="center", va="center", fontsize=8,
                        family="monospace", color=INK)
for k in range(int((t1 - t0) / P) + 1):
    ax.axvline(t0 + k * P + P / 2, color=GRID, lw=0.5, zorder=0)
ax.set_xlim(t0 - 2.3 * P, t1); ax.set_ylim(-0.4, len(SIGS))
ax.set_yticks([]); ax.set_xticks([])
for s in ax.spines.values(): s.set_visible(False)
fig.tight_layout(); fig.savefig(OUT, facecolor=fig.get_facecolor())
print("wrote", OUT)

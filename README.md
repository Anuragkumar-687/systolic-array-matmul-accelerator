# Systolic Array Matrix Multiplication Accelerator

A parameterised N × N systolic array that computes `C = A × B` for signed integer
matrices, written in synthesisable Verilog-2005 and verified with a self-checking
testbench.

**Course:** Modern Computer Architecture · **Team:** `MCA_Project_2024_C_Team1` (Section C) · **Phase I submission**

| Deliverable | Where |
| --- | --- |
| Project report (IEEE format) | [`report/report.pdf`](report/report.pdf) · source: [`report/report.tex`](report/report.tex) |
| Prototype / demo video | [Google Drive folder](https://drive.google.com/drive/folders/1Z8AsM1CW7a-qBB9LZiPCugjUo8qW30LH?usp=sharing) |
| RTL implementation | [`rtl/`](rtl) |
| Testbench | [`tb/`](tb) |
| Simulation log | [`docs/sim_results.txt`](docs/sim_results.txt) |

## Team

| Name | Enrolment No. | Email |
| --- | --- | --- |
| Anurag Kumar (Team Lead) | 2401010088 | anurag.kumar2024@nst.rishihood.edu.in |
| Augustya Purohit | 2401010114 | augustya.purohit2024@nst.rishihood.edu.in |
| Harsh Raj | 2401010180 | harsh.raj2024@nst.rishihood.edu.in |
| Sumit Yadav | 2401010464 | sumit.yadav2024@nst.rishihood.edu.in |
| Adil Mirza | 2401020005 | adil.mirza2024@nst.rishihood.edu.in |

## Idea

Multiplying two N × N matrices takes N³ multiply-accumulate (MAC) operations. A
processor pushes them through one arithmetic unit, one after another. A systolic
array instead lays out N² tiny MAC cells in a grid: operands of `A` flow left to
right, operands of `B` flow top to bottom, and every cell multiplies whatever
meets inside it and adds it to a running sum. All cells work on every clock
cycle, and every wire only reaches the next cell.

```
              col 0 of B   col 1 of B   col 2 of B
                  |            |            |
                  v            v            v
row 0 of A --> [PE 00] ---> [PE 01] ---> [PE 02]
                  |            |            |
                  v            v            v
row 1 of A --> [PE 10] ---> [PE 11] ---> [PE 12]
                  |            |            |
                  v            v            v
row 2 of A --> [PE 20] ---> [PE 21] ---> [PE 22]

PE(i,j):   acc <= acc + a_in * b_in;   a_out <= a_in;   b_out <= b_in;
           after the run, acc holds C[i][j]
```

Row `i` of `A` is delayed by `i` cycles and column `j` of `B` by `j` cycles, so
`A[i][k]` and `B[k][j]` meet in `PE(i,j)` at cycle `t = i + j + k`. The whole
product is ready after **3N − 1 clock cycles** instead of N³.

## Repository layout

```
rtl/pe.v               processing element: multiplier + accumulator + 2 forwarding registers
rtl/systolic_array.v   N x N mesh of processing elements (generate loops)
rtl/matmul_accel.v     top level: start/busy/done controller and skewed input feeders
tb/tb_matmul_accel.v   self-checking testbench with a behavioural reference model
report/                IEEE-format project report (LaTeX source and PDF)
docs/sim_results.txt   captured simulation output
Makefile               simulation and report build
```

## Top-level interface (`matmul_accel`)

| Port | Dir | Width | Description |
| --- | --- | --- | --- |
| `clk`, `rst` | in | 1 | clock, synchronous active-high reset |
| `start` | in | 1 | pulse to latch `a_flat`/`b_flat` and begin |
| `a_flat`, `b_flat` | in | `N*N*DATA_W` | input matrices, element `[r][c]` at index `r*N + c` |
| `c_flat` | out | `N*N*ACC_W` | result matrix, same indexing |
| `busy` | out | 1 | high while the array is computing |
| `done` | out | 1 | high when `c_flat` is valid; stays high until the next `start` |

Parameters: `N` (default 4), `DATA_W` (default 8, signed), `ACC_W` (default 24).
Overflow cannot occur when `ACC_W >= 2*DATA_W + ceil(log2(N))`.

## Running the prototype

Requires [Icarus Verilog](https://steveicarus.github.io/iverilog/) (`brew install icarus-verilog` or `apt install iverilog`).

```bash
make sim            # 4 x 4 array, 8-bit operands
make sim N=8        # 8 x 8 array
make sim N=4 DATA_W=16 ACC_W=40
make waves          # open build/waves.vcd in GTKWave
```

Expected ending of the output:

```
    ... 100 random multiplications checked
==============================================================
 ALL 104 TESTS PASSED
==============================================================
```

## Verification results

Each run applies 4 directed tests (identity, counting pattern, all operands at the
most negative value, mixed-sign extremes) and 100 back-to-back random
multiplications, comparing all N² outputs with a triple-loop reference model.

| N | Processing elements | Measured latency (cycles) | Single-MAC datapath (N³ cycles) | Tests |
| --- | --- | --- | --- | --- |
| 2 | 4 | 5 | 8 | 104 / 104 pass |
| 3 | 9 | 8 | 27 | 104 / 104 pass |
| 4 | 16 | 11 | 64 | 104 / 104 pass |
| 5 | 25 | 14 | 125 | 104 / 104 pass |
| 8 | 64 | 23 | 512 | 104 / 104 pass |
| 16 | 256 | 47 | 4096 | 104 / 104 pass |

The N³ column is an analytical cycle count for a datapath with one MAC unit, not a
measurement of a real processor. Synthesis results (area, f<sub>max</sub>, power)
are not available yet; they are planned for Phase II.

## Roadmap (Phase II)

Tracked in the repository's [issues](../../issues): FPGA synthesis, a streaming
input interface, rectangular matrices, a pipelined multiplier and a sequential
baseline for comparison.

#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# run_synth.sh - open-source synthesis and place-and-route (Phase II)
#
#   make synth          (needs yosys and nextpnr-ice40;
#                        macOS: brew install yosys nextpnr-ice40)
#
# For N = 3 and N = 4, three designs, all wrapped in matmul_top (registered
# narrow I/O, so the numbers describe the core, not the pins):
#   systolic  : matmul_accel, BUFFERED = 1  (Phase II input buffers)
#   phase1    : matmul_accel, BUFFERED = 0  (Phase I multiplexer feeders)
#   sequential: seq_matmul                  (one shared MAC)
#
# 1. Yosys synth_xilinx  -> LUT / FF / DSP48E1 / CARRY4 for a Xilinx 7-series
#                           (Artix-7, e.g. Basys-3 or Nexys A7)
# 2. Yosys synth_ice40 + nextpnr-ice40 -> placed and routed maximum clock
#                           frequency on a Lattice iCE40 HX8K (ct256)
#
# Results: synth/reports/*  and the table in synth/results.csv
# Vivado users: synth/vivado_synth.tcl runs the Xilinx flow in Vivado.
# -----------------------------------------------------------------------------
set -u
cd "$(dirname "$0")"
mkdir -p reports

RTL="../rtl/mac_unit.v ../rtl/pe.v ../rtl/skew_buffer.v ../rtl/systolic_array.v \
     ../rtl/matmul_accel.v ../rtl/seq_matmul.v ../rtl/matmul_top.v"

params() {   # $1 = design name -> chparam arguments
  case "$1" in
    systolic)   echo "-set ARCH 0 -set BUFFERED 1" ;;
    phase1)     echo "-set ARCH 0 -set BUFFERED 0" ;;
    sequential) echo "-set ARCH 1" ;;
  esac
}

count() {    # $1 = report, $2 = cell-name prefix
  awk -v c="$2" '$2 ~ "^"c {s += $1} END {print s + 0}' "$1"
}

echo "design,N,LUT,FF,DSP48E1,CARRY4,iCE40_LC,Fmax_MHz" > results.csv
printf "%-11s %-2s %6s %6s %5s %7s %9s %10s\n" design N LUT FF DSP CARRY4 iCE40_LC Fmax_MHz

for N in 3 4; do
  for D in systolic phase1 sequential; do
    name=${D}_n${N}
    P="-set N $N $(params $D)"

    # 1. Xilinx 7-series resources
    yosys -q -p "read_verilog $RTL; chparam $P matmul_top; \
                 synth_xilinx -top matmul_top -flatten; \
                 tee -q -o reports/${name}_xc7.txt stat" > /dev/null
    lut=$(count reports/${name}_xc7.txt LUT)
    ff=$(count reports/${name}_xc7.txt FD)
    dsp=$(count reports/${name}_xc7.txt DSP48E1)
    carry=$(count reports/${name}_xc7.txt CARRY4)

    # 2. iCE40 HX8K place and route -> Fmax
    yosys -q -p "read_verilog $RTL; chparam $P matmul_top; \
                 synth_ice40 -top matmul_top -json reports/${name}_ice40.json" > /dev/null
    nextpnr-ice40 --hx8k --package ct256 --json reports/${name}_ice40.json \
                  --pcf-allow-unconstrained --freq 50 --seed 1 \
                  > reports/${name}_ice40_pnr.log 2>&1
    lc=$(grep -E "ICESTORM_LC:" reports/${name}_ice40_pnr.log | tail -1 | awk '{print $3}' | cut -d/ -f1)
    fmax=$(grep -E "Max frequency for clock" reports/${name}_ice40_pnr.log | tail -1 \
           | sed -E 's/.*: ([0-9.]+) MHz.*/\1/')
    rm -f reports/${name}_ice40.json          # large intermediate file

    echo "$D,$N,$lut,$ff,$dsp,$carry,$lc,$fmax" >> results.csv
    printf "%-11s %-2s %6s %6s %5s %7s %9s %10s\n" "$D" "$N" "$lut" "$ff" "$dsp" "$carry" "$lc" "$fmax"
  done
done

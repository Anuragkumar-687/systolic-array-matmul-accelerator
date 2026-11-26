# -----------------------------------------------------------------------------
# vivado_synth.tcl - Vivado synthesis + timing for the accelerator (Phase II)
#
#   vivado -mode batch -source synth/vivado_synth.tcl
#
# Target: Artix-7 xc7a35tcpg236-1 (Basys-3). Change N, ARCH and BUFFERED
# below to synthesise the 3x3 array, the Phase I version or the baseline.
# Reports land in synth/vivado_reports/.
# -----------------------------------------------------------------------------
set N        4
set ARCH     0
set BUFFERED 1
set part     xc7a35tcpg236-1
set here     [file dirname [info script]]
set out      $here/vivado_reports
file mkdir $out

read_verilog [glob $here/../rtl/*.v]
synth_design -top matmul_top -part $part \
    -generic N=$N -generic ARCH=$ARCH -generic BUFFERED=$BUFFERED

create_clock -name clk -period 5.000 [get_ports clk]     ;# 200 MHz target

set tag "n${N}_arch${ARCH}_buf${BUFFERED}"
report_utilization    -file $out/utilization_$tag.rpt
report_timing_summary -file $out/timing_$tag.rpt
puts "Fmax = 1000 / (5.000 - WNS) MHz, WNS from $out/timing_$tag.rpt"

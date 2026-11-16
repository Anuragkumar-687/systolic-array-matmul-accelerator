# Systolic Array Matrix Multiplication Accelerator - simulation flow
#
#   make sim              run the self-checking testbench (N=4, 8-bit operands)
#   make sim N=8          same, for an 8 x 8 array
#   make waves            open the waveform in GTKWave
#   make report           build report/report.pdf (needs tectonic)

IVERILOG ?= iverilog
VVP      ?= vvp
N        ?= 4
DATA_W   ?= 8
ACC_W    ?= 24

RTL := rtl/pe.v rtl/systolic_array.v rtl/matmul_accel.v
TB  := tb/tb_matmul_accel.v
TOP := tb_matmul_accel

.PHONY: sim waves report clean

sim:
	@mkdir -p build
	$(IVERILOG) -g2005 -Wall \
		-P $(TOP).N=$(N) -P $(TOP).DATA_W=$(DATA_W) -P $(TOP).ACC_W=$(ACC_W) \
		-o build/tb $(RTL) $(TB)
	cd build && $(VVP) tb

waves: sim
	gtkwave build/waves.vcd

report:
	cd report && tectonic report.tex

clean:
	rm -rf build

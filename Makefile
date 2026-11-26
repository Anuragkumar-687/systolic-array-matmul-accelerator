# Systolic Array Matrix Multiplication Accelerator - simulation flow
#
#   make sim              run the self-checking testbench (N=4, 8-bit operands)
#   make sim N=8          same, for an 8 x 8 array
#   make sim-pe           unit test of one processing element
#   make compare          systolic array vs sequential baseline (N=4; make compare N=3)
#   make sim-top          matrix data interface (narrow FPGA port), both cores
#   make all-tests        every testbench above
#   make waves            open the waveform in GTKWave
#   make report           build report/report.pdf (needs tectonic)

IVERILOG ?= iverilog
VVP      ?= vvp
N        ?= 4
DATA_W   ?= 8
ACC_W    ?= 24

RTL := rtl/mac_unit.v rtl/pe.v rtl/skew_buffer.v rtl/systolic_array.v rtl/matmul_accel.v
SEQ := rtl/seq_matmul.v
TB  := tb/tb_matmul_accel.v
TOP := tb_matmul_accel

.PHONY: sim sim-pe compare sim-top all-tests waves report clean

# unit test of a single processing element
sim-pe:
	@mkdir -p build
	$(IVERILOG) -g2005 -Wall -o build/tb_pe rtl/mac_unit.v rtl/pe.v tb/tb_pe.v
	cd build && $(VVP) tb_pe

sim:
	@mkdir -p build
	$(IVERILOG) -g2005 -Wall \
		-P $(TOP).N=$(N) -P $(TOP).DATA_W=$(DATA_W) -P $(TOP).ACC_W=$(ACC_W) \
		-o build/tb $(RTL) $(TB)
	cd build && $(VVP) tb

# systolic array (buffered + Phase I) vs sequential baseline, same inputs
compare:
	@mkdir -p build
	$(IVERILOG) -g2005 -Wall -P tb_compare.N=$(N) \
		-o build/tb_compare $(RTL) $(SEQ) tb/tb_compare.v
	cd build && $(VVP) tb_compare

# matrix data interface: write elements, start, read results back
sim-top:
	@mkdir -p build
	$(IVERILOG) -g2005 -Wall -P tb_matmul_top.N=$(N) \
		-o build/tb_top $(RTL) $(SEQ) rtl/matmul_top.v tb/tb_matmul_top.v
	cd build && $(VVP) tb_top

all-tests: sim-pe sim compare sim-top

waves: sim
	gtkwave build/waves.vcd

report:
	cd report && tectonic report.tex

clean:
	rm -rf build

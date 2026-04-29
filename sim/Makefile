##################################################################################################
#This file created by Huy Nguyen
#Updated date: 6/30/2019
#Example run string: make TESTNAME={name_of_testcase} {optional}
#             make TESTNAME=counter_test all 
##################################################################################################
#Define variables
TESTNAME 	?= test
TB_NAME 	?= test_bench
RADIX		?= hex
RUN_ARGS    ?=
VSIM_RUN_MODE ?= -batch
VSIM_DO ?= run -all; quit -f
QUESTA_ROOT ?= $(abspath ../../questasim)
QUESTA_BIN  ?= $(QUESTA_ROOT)/linux_x86_64
QUESTA_LICENSE ?= $(QUESTA_ROOT)/license.dat
LICGEN_DIR ?= $(abspath ../licGen)

ifneq ($(wildcard $(QUESTA_BIN)/vsim),)
export PATH := $(QUESTA_BIN):$(PATH)
endif

ifneq ($(wildcard $(QUESTA_LICENSE)),)
export MGLS_LICENSE_FILE ?= $(QUESTA_LICENSE)
export LM_LICENSE_FILE ?= $(QUESTA_LICENSE)
endif

TESTCASE_DIR ?= ../testcase
RV_GCC ?= riscv64-unknown-elf-gcc
RV_OBJCOPY ?= riscv64-unknown-elf-objcopy
VIVADO_BAT ?= H:\From_software\Vivado\Vivado\Vivado\2024.2\bin\vivado.bat
VIVADO_FPGA_TOP ?= rv32_soc_fpga_demo_top
VIVADO_RAW_TOP ?= rv32_soc_top
VIVADO_BOARD_XDC ?= vivado/constraints/zedboard_demo.xdc
VIVADO_PROJECT ?= rv32_soc_synth_tx
VIVADO_BUILD ?= tx_only
VIVADO_REUSE_SYNTH ?= 1
VIVADO_REUSE_IMPL ?= 1
VIVADO_BIT_REUSE_SYNTH ?= 0
VIVADO_CLOCK_MHZ ?= 50
VIVADO_TOP ?= $(VIVADO_FPGA_TOP)
VIVADO_XDC ?= $(VIVADO_BOARD_XDC)
VIVADO_BIT_DIR ?= vivado_bitstreams
VIVADO_XPR := H:\Academic\senior_project\DATN\work\luc\AES_huffman_all6\vivado\build\$(VIVADO_PROJECT)\$(VIVADO_PROJECT).xpr

# Program compile variables
C_SRC ?= test_mmio_dma.c
C_SRC_PATH := $(if $(wildcard $(C_SRC)),$(C_SRC),$(TESTCASE_DIR)/$(C_SRC))
C_STEM := $(basename $(notdir $(C_SRC_PATH)))
ASM_OUT ?= $(TESTCASE_DIR)/$(C_STEM).S
ELF_OUT ?= $(TESTCASE_DIR)/$(C_STEM).elf
BIN_OUT ?= $(TESTCASE_DIR)/$(C_STEM).bin
MEM_OUT ?= $(TESTCASE_DIR)/$(C_STEM).mem
SIM_MEM_OUT ?= instruction.mem
UART_LOADER ?= ../tools/uart_dmem_loader.py
UART_PORT ?= /dev/ttyUSB0
UART_INPUT ?= input1.txt
UART_BAUD ?= 115200
UART_TIMEOUT ?= 5
#==============================
all:  build run

all_wave: build run wave

all_cov: build_cov run_cov

drc:
	#verilator --lint-only -Wall -f rtl.f
	verilator --lint-only -Wall -I../rtl -f rtl.f

build_cov:
	mkdir -p log ucdb
	cp -rf $(TESTCASE_DIR)/$(TESTNAME).v run_test.v
	vlib work
	vmap work work
	vlog +cover=bcesft -f compile.f

build:
	mkdir -p log
	cp -rf $(TESTCASE_DIR)/$(TESTNAME).v run_test.v
	vlib work
	vmap work work
	vlog -f compile.f

run:
	mkdir -p log
	vsim $(VSIM_RUN_MODE) -l $(TESTNAME).log -voptargs=+acc -assertdebug $(TB_NAME) $(RUN_ARGS) -do "$(VSIM_DO)"
	@test -s $(TESTNAME).log || (echo "[FAIL] vsim produced an empty log; check Questa license/socket startup"; exit 1)
	@! grep -E "Trouble making server|couldn't open socket|License Issue|Unable to checkout|Failure to obtain|Invalid license|Error loading design" $(TESTNAME).log || (echo "[FAIL] vsim startup failed; see $(TESTNAME).log"; exit 1)
	cp -rf $(TESTNAME).log sim.log 
	mv $(TESTNAME).log log/
	
run_cov:
	mkdir -p log ucdb
	vsim -debugDB -coverage -l $(TESTNAME).log -c $(TB_NAME) $(RUN_ARGS) -voptargs="+access+cover=bcesft" -assertdebug -do "coverage save -onexit $(TESTNAME).ucdb; log -r /*; run -all"
	@test -s $(TESTNAME).log || (echo "[FAIL] vsim produced an empty log; check Questa license/socket startup"; exit 1)
	@! grep -E "Trouble making server|couldn't open socket|License Issue|Unable to checkout|Failure to obtain|Invalid license|Error loading design" $(TESTNAME).log || (echo "[FAIL] vsim startup failed; see $(TESTNAME).log"; exit 1)
	cp -rf $(TESTNAME).log sim.log
	mv $(TESTNAME).log log/
	mv $(TESTNAME).ucdb ucdb/

view_cov:
	vsim -gui -viewcov IP.ucdb &

gen_cov:
	mkdir -p coverage
	vcover merge IP.ucdb ucdb/*.ucdb
	vcover report IP.ucdb -output coverage/summary_report.txt
	vcover report -zeros -detail -code bcesft -annotate -All -codeAll IP.ucdb -output coverage/detail_report.txt

gen_html:
	mkdir -p coverage
	vcover merge IP.ucdb ucdb/*.ucdb
	vcover report -zeros -details -code bcesft -annotate -testhitdataAll -html IP.ucdb

wave:
	vsim -i -view vsim.wlf -do "add wave vsim:/$(TB_NAME)/*; radix -$(RADIX)" &

clean:
	rm -rf work
	rm -rf work_*
	rm -rf vsim.dbg
	rm -rf *.ini
	rm -rf *.log
	rm -rf  *.log
	rm -rf *.wlf
	rm -rf wlft*
	rm -rf transcript
	rm -rf *.ucdb
	rm -rf coverage
	rm -rf covhtmlreport
	rm -rf log ucdb
	rm -rf loopback preprocess dmem_dump debug_mmio tx_only
	rm -rf hostbench*.log rv32_preproc*.log sim.log
	rm -rf regfile_dump_*.txt vsim_stacktrace.vstf vi
	rm -rf .input.txt.swp
	rm -rf run_test.v
	rm -rf $(SIM_MEM_OUT)
	rm -rf $(TESTCASE_DIR)/*.elf
	rm -rf $(TESTCASE_DIR)/*.bin
	rm -rf $(TESTCASE_DIR)/*.mem
	rm -rf $(TESTCASE_DIR)/*.S
	mkdir -p log ucdb loopback preprocess dmem_dump

clean_vivado:
	rm -rf ../vivado/build
	rm -rf vivado_reports
	rm -rf $(VIVADO_BIT_DIR)
	rm -rf ../vivado/logs/root_runs/*
	rm -f ../vivado*.jou ../vivado*.log ../vivado_pid*.str
	rm -f ../IMEM_ip.mif ../min_area_pfile.tmp
	rm -rf ../.Xil
compile:
	mkdir -p $(TESTCASE_DIR)
	$(RV_GCC) -march=rv32i -mabi=ilp32 -Os -S $(C_SRC_PATH) -o $(ASM_OUT)
	$(RV_GCC) -march=rv32i -mabi=ilp32 -O1 -nostdlib -ffreestanding -Ttext=0x0 -Wl,-e,_start $(C_SRC_PATH) -o $(ELF_OUT)
	$(RV_OBJCOPY) -O binary $(ELF_OUT) $(BIN_OUT)
	python3 -c "from pathlib import Path; data = Path('$(BIN_OUT)').read_bytes(); data += b'\\x00' * ((4 - len(data) % 4) % 4); Path('$(MEM_OUT)').write_text(''.join(f'{int.from_bytes(data[i:i+4], \"little\"):08x}\\n' for i in range(0, len(data), 4)))"
	cp $(MEM_OUT) $(SIM_MEM_OUT)

uart_load:
	python3 $(UART_LOADER) --port $(UART_PORT) --input $(UART_INPUT) --baud $(UART_BAUD) --timeout $(UART_TIMEOUT)

vivado_synth:
	cmd.exe /C "cd /d H:\Academic\senior_project\DATN\work\luc\AES_huffman_all6 && set PROJECT_NAME=$(VIVADO_PROJECT)&& set TOP_NAME=$(VIVADO_TOP)&& set FPGA_BUILD=$(VIVADO_BUILD)&& set VIVADO_FLOW=synth&& set VIVADO_CLOCK_MHZ=$(VIVADO_CLOCK_MHZ)&& set VIVADO_XDC=$(VIVADO_XDC)&& $(VIVADO_BAT) -mode batch -source vivado\synth_soc.tcl"

vivado_synth_full:
	$(MAKE) vivado_synth VIVADO_PROJECT=rv32_soc_synth_ip VIVADO_BUILD=full VIVADO_TOP=$(VIVADO_RAW_TOP) VIVADO_XDC=

vivado_synth_tx:
	$(MAKE) vivado_synth VIVADO_PROJECT=rv32_soc_synth_tx VIVADO_BUILD=tx_only VIVADO_TOP=$(VIVADO_FPGA_TOP) VIVADO_XDC=$(VIVADO_BOARD_XDC) VIVADO_CLOCK_MHZ=$(VIVADO_CLOCK_MHZ)

vivado_synth_rx:
	$(MAKE) vivado_synth VIVADO_PROJECT=rv32_soc_synth_rx VIVADO_BUILD=rx_only VIVADO_TOP=$(VIVADO_FPGA_TOP) VIVADO_XDC=$(VIVADO_BOARD_XDC) VIVADO_CLOCK_MHZ=$(VIVADO_CLOCK_MHZ)

vivado_impl:
	cmd.exe /C "cd /d H:\Academic\senior_project\DATN\work\luc\AES_huffman_all6 && set PROJECT_NAME=$(VIVADO_PROJECT)&& set TOP_NAME=$(VIVADO_TOP)&& set FPGA_BUILD=$(VIVADO_BUILD)&& set VIVADO_FLOW=impl&& set VIVADO_REUSE_SYNTH=$(VIVADO_REUSE_SYNTH)&& set VIVADO_REUSE_IMPL=$(VIVADO_REUSE_IMPL)&& set VIVADO_CLOCK_MHZ=$(VIVADO_CLOCK_MHZ)&& set VIVADO_XDC=$(VIVADO_XDC)&& $(VIVADO_BAT) -mode batch -source vivado\synth_soc.tcl"

vivado_impl_tx:
	$(MAKE) vivado_impl VIVADO_PROJECT=rv32_soc_synth_tx VIVADO_BUILD=tx_only VIVADO_TOP=$(VIVADO_FPGA_TOP) VIVADO_XDC=$(VIVADO_BOARD_XDC) VIVADO_CLOCK_MHZ=$(VIVADO_CLOCK_MHZ)

vivado_impl_rx:
	$(MAKE) vivado_impl VIVADO_PROJECT=rv32_soc_synth_rx VIVADO_BUILD=rx_only VIVADO_TOP=$(VIVADO_FPGA_TOP) VIVADO_XDC=$(VIVADO_BOARD_XDC) VIVADO_CLOCK_MHZ=$(VIVADO_CLOCK_MHZ)

vivado_bit:
	cmd.exe /C "cd /d H:\Academic\senior_project\DATN\work\luc\AES_huffman_all6 && set PROJECT_NAME=$(VIVADO_PROJECT)&& set TOP_NAME=$(VIVADO_TOP)&& set FPGA_BUILD=$(VIVADO_BUILD)&& set VIVADO_FLOW=bit&& set VIVADO_REUSE_SYNTH=$(VIVADO_BIT_REUSE_SYNTH)&& set VIVADO_REUSE_IMPL=$(VIVADO_REUSE_IMPL)&& set VIVADO_CLOCK_MHZ=$(VIVADO_CLOCK_MHZ)&& set VIVADO_XDC=$(VIVADO_XDC)&& $(VIVADO_BAT) -mode batch -source vivado\synth_soc.tcl"

vivado_bit_tx:
	$(MAKE) vivado_bit VIVADO_PROJECT=rv32_soc_synth_tx VIVADO_BUILD=tx_only VIVADO_TOP=$(VIVADO_FPGA_TOP) VIVADO_XDC=$(VIVADO_BOARD_XDC) VIVADO_CLOCK_MHZ=$(VIVADO_CLOCK_MHZ) VIVADO_BIT_REUSE_SYNTH=$(VIVADO_BIT_REUSE_SYNTH)

vivado_bit_rx:
	$(MAKE) vivado_bit VIVADO_PROJECT=rv32_soc_synth_rx VIVADO_BUILD=rx_only VIVADO_TOP=$(VIVADO_FPGA_TOP) VIVADO_XDC=$(VIVADO_BOARD_XDC) VIVADO_CLOCK_MHZ=$(VIVADO_CLOCK_MHZ) VIVADO_BIT_REUSE_SYNTH=$(VIVADO_BIT_REUSE_SYNTH)

vivado_flow_tx:
	$(MAKE) vivado_synth_tx VIVADO_CLOCK_MHZ=$(VIVADO_CLOCK_MHZ)
	$(MAKE) vivado_impl_tx VIVADO_CLOCK_MHZ=$(VIVADO_CLOCK_MHZ) VIVADO_REUSE_SYNTH=1
	$(MAKE) vivado_bit_tx VIVADO_CLOCK_MHZ=$(VIVADO_CLOCK_MHZ) VIVADO_BIT_REUSE_SYNTH=1 VIVADO_REUSE_IMPL=1

vivado_flow_rx:
	$(MAKE) vivado_synth_rx VIVADO_CLOCK_MHZ=$(VIVADO_CLOCK_MHZ)
	$(MAKE) vivado_impl_rx VIVADO_CLOCK_MHZ=$(VIVADO_CLOCK_MHZ) VIVADO_REUSE_SYNTH=1
	$(MAKE) vivado_bit_rx VIVADO_CLOCK_MHZ=$(VIVADO_CLOCK_MHZ) VIVADO_BIT_REUSE_SYNTH=1 VIVADO_REUSE_IMPL=1

vivado_flow_split:
	$(MAKE) vivado_flow_tx VIVADO_CLOCK_MHZ=$(VIVADO_CLOCK_MHZ)
	$(MAKE) vivado_flow_rx VIVADO_CLOCK_MHZ=$(VIVADO_CLOCK_MHZ)

vivado_gui:
	powershell.exe -NoProfile -Command "Start-Process -FilePath '$(VIVADO_BAT)' -ArgumentList '$(VIVADO_XPR)'"

vivado_gui_tx:
	$(MAKE) vivado_gui VIVADO_PROJECT=rv32_soc_synth_tx

vivado_gui_rx:
	$(MAKE) vivado_gui VIVADO_PROJECT=rv32_soc_synth_rx

vivado_report:
	powershell.exe -NoProfile -Command "Invoke-Item 'H:\Academic\senior_project\DATN\work\luc\AES_huffman_all6\sim\vivado_reports\$(VIVADO_PROJECT)'"

license:
	@set -e; \
	WSL_MAC="$$(ip link show eth0 2>/dev/null | awk '/link\/ether/ {print $$2; exit}')"; \
	if [ -z "$$WSL_MAC" ]; then \
		WSL_MAC="$$(ip link 2>/dev/null | awk '/link\/ether/ {print $$2; exit}')"; \
	fi; \
	if [ -z "$$WSL_MAC" ]; then \
		echo "[FAIL] could not detect a WSL MAC address"; \
		exit 1; \
	fi; \
	echo "Using WSL MAC: $$WSL_MAC"; \
	if cd "$(LICGEN_DIR)" && python3 mgclicgen.py "$$WSL_MAC"; then \
		echo "[PASS] generated license.dat in $(LICGEN_DIR)"; \
	else \
		echo "[FAIL] mgclicgen.py failed"; \
		exit 1; \
	fi; \
	if cp "$(LICGEN_DIR)/license.dat" "$(QUESTA_LICENSE)"; then \
		echo "[PASS] copied license.dat to $(QUESTA_LICENSE)"; \
	else \
		echo "[FAIL] could not copy license.dat to $(QUESTA_LICENSE)"; \
		exit 1; \
	fi; \
	if cd "$(QUESTA_ROOT)" && sudo -S ./pubkey_verify -y .; then \
		echo "[PASS] pubkey_verify completed"; \
		echo "[PASS] Questa license is ready: $(QUESTA_LICENSE)"; \
	else \
		echo "[FAIL] pubkey_verify failed"; \
		exit 1; \
	fi
push_github:
	cd ..
	./push_source.sh
help:
	@echo ""
	@echo "****************************************"
	@echo "** make clean    : clean simulation outputs only"
	@echo "** make clean_vivado : clean Vivado build/report/bitstream outputs only"
	@echo "** make build    : build the design"
	@echo "** make build_cov: build the design in coverage mode"
	@echo "** make run      : run simulation"
	@echo "** make run_cov  : run simulation in coverage mode"
	@echo "** make all      : build and run simulation"
	@echo "** make all_cov  : build and run simulation in coverage mode"
	@echo "** make wave     : open waveform"
	@echo "** make gen_cov  : merge, generate coverage data base and text coverage report"
	@echo "** make gen_html : merge, generate coverage data base and html coverage report"
	@echo "** make compile C_SRC=test_mmio_dma.c"
	@echo "**    build source from ../testcase/, write outputs to ../testcase/, copy mem to ./instruction.mem"
	@echo "** make license  : generate license.dat from WSL MAC and verify Questa"
	@echo "** make vivado_synth : synthesize current FPGA demo target"
	@echo "** make vivado_synth_full : synthesize raw full SoC top for analysis only"
	@echo "** make vivado_synth_tx : synthesize TX-only FPGA build"
	@echo "** make vivado_synth_rx : synthesize RX-only FPGA build"
	@echo "** make vivado_impl : implement current FPGA demo target through route_design"
	@echo "** make vivado_impl_tx : synthesize and implement TX-only FPGA build"
	@echo "** make vivado_impl_rx : synthesize and implement RX-only FPGA build"
	@echo "** make vivado_bit_tx  : generate TX-only FPGA demo bitstream"
	@echo "** make vivado_bit_rx  : generate RX-only FPGA demo bitstream"
	@echo "** make vivado_flow_tx : run TX-only synth -> impl -> bitstream"
	@echo "** make vivado_flow_rx : run RX-only synth -> impl -> bitstream"
	@echo "** make vivado_flow_split : run TX-only flow first, then RX-only flow"
	@echo "** make uart_load UART_PORT=/dev/ttyUSB0 UART_INPUT=input1.txt"
	@echo "**    host-side command: send a text/binary file over UART into DMEM on FPGA"
	@echo "**    not used by simulation; use only after programming the FPGA bitstream"
	@echo "**    Vivado clock default: VIVADO_CLOCK_MHZ=50; override with VIVADO_CLOCK_MHZ=100"
	@echo "**    TX/RX FPGA targets use VIVADO_FPGA_TOP=rv32_soc_fpga_demo_top and VIVADO_BOARD_XDC=vivado/constraints/zedboard_demo.xdc"
	@echo "**    Separated bitstreams are copied to ./vivado_bitstreams/rv32_soc_synth_tx.bit and ./vivado_bitstreams/rv32_soc_synth_rx.bit"
	@echo "**    Bitstream flow reruns needed Vivado stages by default; set VIVADO_BIT_REUSE_SYNTH=1 or VIVADO_REUSE_IMPL=1 for faster reuse"
	@echo "** make vivado_gui   : open Vivado GUI project"
	@echo "** make vivado_gui_tx: open Vivado GUI TX-only project"
	@echo "** make vivado_gui_rx: open Vivado GUI RX-only project"
	@echo "** make vivado_report VIVADO_PROJECT=rv32_soc_synth_tx : open a Vivado report folder"
	@echo "****************************************"
	@echo ""

group:
	make all_cov TESTNAME=sanity_test
	make all_cov TESTNAME=ro_check
	make all_cov TESTNAME=check_non_existed_addr
	make all_cov TESTNAME=resv_addr
	make all_cov TESTNAME=rw1c_check

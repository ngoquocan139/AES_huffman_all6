##################################################################################################
#This file created by Huy Nguyen
#Updated date: 6/30/2019
#Example run string: make TESTNAME={name_of_testcase} {optional}
#             make TESTNAME=dma_compress_aes_input1 all
##################################################################################################
#Define variables
TESTNAME 	?= dma_compress_aes_input1
TB_NAME 	?= test_bench
RADIX		?= hex
RUN_ARGS    ?=
VSIM_RUN_MODE ?= -batch
VSIM_DO ?= log -r /*; run -all; quit -f
WLF_OUT ?= $(TESTNAME).wlf
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
VIVADO_WIN_ROOT ?= H:\Academic\senior_project\DATN\work\luc\AES_huffman_all6
VIVADO_FPGA_TOP ?= rv32_soc_fpga_demo_top
VIVADO_RAW_TOP ?= rv32_soc_top
VIVADO_BOARD_XDC ?= vivado/constraints/zedboard_demo.xdc
VIVADO_TX_PROJECT ?= rv32_soc_synth_tx_opt4
VIVADO_RX_PROJECT ?= rv32_soc_synth_rx
VIVADO_FULL_PROJECT ?= rv32_soc_synth_full_fpga
VIVADO_PROJECT ?= $(VIVADO_TX_PROJECT)
VIVADO_BUILD ?= tx_only
VIVADO_REUSE_SYNTH ?= 1
VIVADO_REUSE_IMPL ?= 1
VIVADO_BIT_REUSE_SYNTH ?= 0
VIVADO_CLOCK_MHZ ?= 50
VIVADO_SYNTH_DIRECTIVE ?= AreaOptimized_high
VIVADO_OPT_DIRECTIVE ?=
VIVADO_PLACE_DIRECTIVE ?=
VIVADO_PHYS_OPT_DIRECTIVE ?=
VIVADO_ROUTE_DIRECTIVE ?=
VIVADO_POWER_OPT ?= 0
VIVADO_POWER_OPT_POST_PLACE ?= $(VIVADO_POWER_OPT)
VIVADO_TOP ?= $(VIVADO_FPGA_TOP)
VIVADO_XDC ?= $(VIVADO_BOARD_XDC)
VIVADO_BIT_DIR ?= vivado_bitstreams
VIVADO_XPR ?= $(VIVADO_WIN_ROOT)\vivado\build\$(VIVADO_PROJECT)\$(VIVADO_PROJECT).xpr
VIVADO_XPR_WSL ?= ../vivado/build/$(VIVADO_PROJECT)/$(VIVADO_PROJECT).xpr
VIVADO_REPORT_WIN_DIR ?= $(VIVADO_WIN_ROOT)\sim\vivado_reports\$(VIVADO_PROJECT)
SUDO_PASS ?=

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
	@if [ ! -d work ]; then vlib work; fi
	vmap work work
	@sed -i 's/^; FecUdpEffort = 1/FecUdpEffort = 2/' modelsim.ini
	vlog +cover=bcesft -f compile.f

build:
	mkdir -p log
	cp -rf $(TESTCASE_DIR)/$(TESTNAME).v run_test.v
	@if [ ! -d work ]; then vlib work; fi
	vmap work work
	vlog -f compile.f

run:
	mkdir -p log
	vsim $(VSIM_RUN_MODE) -wlf $(WLF_OUT) -l $(TESTNAME).log -voptargs=+acc -assertdebug $(TB_NAME) $(RUN_ARGS) -do "$(VSIM_DO)"
	@test -s $(TESTNAME).log || (echo "[FAIL] vsim produced an empty log; check Questa license/socket startup"; exit 1)
	@! grep -E "Trouble making server|couldn't open socket|License Issue|Unable to checkout|Failure to obtain|Invalid license|Error loading design" $(TESTNAME).log || (echo "[FAIL] vsim startup failed; see $(TESTNAME).log"; exit 1)
	cp -rf $(TESTNAME).log sim.log 
	@if [ -f $(WLF_OUT) ]; then cp -f $(WLF_OUT) sim.wlf; cp -f $(WLF_OUT) log/$(TESTNAME).wlf; fi
	mv $(TESTNAME).log log/
	$(MAKE) archive_case_outputs TESTNAME=$(TESTNAME)
	
run_cov:
	mkdir -p log ucdb
	vsim -coverage -l $(TESTNAME).log -c $(TB_NAME) $(RUN_ARGS) -voptargs="+cover=bcesft" -assertdebug -do "coverage save -onexit $(TESTNAME).ucdb; run -all; quit -f"
	@test -s $(TESTNAME).log || (echo "[FAIL] vsim produced an empty log; check Questa license/socket startup"; exit 1)
	@! grep -E "Trouble making server|couldn't open socket|License Issue|Unable to checkout|Failure to obtain|Invalid license|Error loading design" $(TESTNAME).log || (echo "[FAIL] vsim startup failed; see $(TESTNAME).log"; exit 1)
	cp -rf $(TESTNAME).log sim.log
	mv $(TESTNAME).log log/
	mv $(TESTNAME).ucdb ucdb/
	$(MAKE) archive_case_outputs TESTNAME=$(TESTNAME)

archive_case_outputs:
	@mkdir -p loopback dmem_dump
	@if [ -f loopback/tb_rv32_soc_mmio_dma_summary.txt ]; then cp loopback/tb_rv32_soc_mmio_dma_summary.txt loopback/$(TESTNAME)_summary.txt; fi
	@if [ -f loopback/tb_rv32_soc_mmio_dma_compare.txt ]; then cp loopback/tb_rv32_soc_mmio_dma_compare.txt loopback/$(TESTNAME)_compare.txt; fi
	@if [ -f dmem_dump/tb_rv32_soc_mmio_dma_src.txt ]; then cp dmem_dump/tb_rv32_soc_mmio_dma_src.txt dmem_dump/$(TESTNAME)_src.txt; fi
	@if [ -f dmem_dump/tb_rv32_soc_mmio_dma_tx.txt ]; then cp dmem_dump/tb_rv32_soc_mmio_dma_tx.txt dmem_dump/$(TESTNAME)_tx.txt; fi
	@if [ -f dmem_dump/tb_rv32_soc_mmio_dma_rx.txt ]; then cp dmem_dump/tb_rv32_soc_mmio_dma_rx.txt dmem_dump/$(TESTNAME)_rx.txt; fi

view_cov:
	vsim -gui -viewcov IP.ucdb &

gen_cov:
	mkdir -p coverage
	vcover merge IP.ucdb ucdb/*.ucdb
	vcover report IP.ucdb -output coverage/summary_report.txt
	vcover report -zeros -detail -code bcesft -annotate -All -codeAll IP.ucdb -output coverage/detail_report.txt
	vcover report -instance=/test_bench/dut -recursive -code bcesft IP.ucdb -output coverage/dut_raw_bcesft_report.txt
	vcover report -instance=/test_bench/dut -recursive -code bcesf IP.ucdb -output coverage/dut_raw_bcesf_report.txt
	vcover report -instance=/test_bench/dut -recursive -code bs IP.ucdb -output coverage/dut_raw_bs_report.txt
	cp IP.ucdb IP_closed.ucdb
	vsim -c -viewcov IP_closed.ucdb -do "do coverage_close.do"
	vcover report -instance=/test_bench/dut -recursive IP_closed.ucdb -output coverage/dut_closed_report.txt

gen_html:
	mkdir -p coverage
	vcover merge IP.ucdb ucdb/*.ucdb
	vcover report -zeros -details -code bcesft -annotate -testhitdataAll -html IP.ucdb

wave:
	@test -f sim.wlf || (echo "[FAIL] sim.wlf not found. Run 'make all' or 'make all TESTNAME=...' first."; exit 1)
	@echo "[INFO] Opening sim.wlf in Questa GUI waveform viewer"
	vsim -gui -view sim.wlf -do "view wave; delete wave *; \
	add wave /test_bench/clk; \
	add wave /test_bench/rst; \
	add wave /test_bench/wf_if_pc; \
	add wave /test_bench/wf_if_instr; \
	add wave /test_bench/wf_cpu_hold; \
	add wave /test_bench/wf_mmio_sel; \
	add wave /test_bench/wf_mmio_stall; \
	add wave /test_bench/wf_apb_psel; \
	add wave /test_bench/wf_apb_penable; \
	add wave /test_bench/wf_apb_pwrite; \
	add wave /test_bench/wf_apb_paddr; \
	add wave /test_bench/wf_apb_pwdata; \
	add wave /test_bench/wf_apb_prdata; \
	add wave /test_bench/wf_dma_src; \
	add wave /test_bench/wf_dma_dst; \
	add wave /test_bench/wf_dma_len; \
	add wave /test_bench/wf_dma_dir; \
	add wave /test_bench/wf_dma_compress_only; \
	add wave /test_bench/wf_dma_whole_file; \
	add wave /test_bench/wf_dma_block_size; \
	add wave /test_bench/wf_dma_start; \
	add wave /test_bench/wf_tx_state; \
	add wave /test_bench/wf_tx_busy; \
	add wave /test_bench/wf_tx_done; \
	add wave /test_bench/wf_tx_error; \
	add wave /test_bench/wf_tx_bytes_done; \
	add wave /test_bench/wf_rx_state; \
	add wave /test_bench/wf_rx_busy; \
	add wave /test_bench/wf_rx_done; \
	add wave /test_bench/wf_rx_error; \
	add wave /test_bench/wf_rx_bytes_done; \
	add wave /test_bench/wf_result_signature; \
	add wave /test_bench/wf_error_mask; \
	add wave /test_bench/wf_input_len_bytes; \
	add wave /test_bench/wf_tx_ciphertext_bytes; \
	add wave /test_bench/wf_rx_plaintext_bytes; \
	radix -$(RADIX)" &

kill_wave:
	-@pids="$$(ps -eo pid=,cmd= | rg -i 'vish -- -vsim .*sim\\.wlf|/questasim/linux_x86_64/vlm|/questasim/linux_x86_64/mgls/lib/mgls_asynch' | awk '{print $$1}')" ; \
	if [ -n "$$pids" ]; then kill $$pids || true; fi
	-@cmd.exe /C "taskkill /F /IM msrdc.exe >NUL 2>NUL" || true

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
	rm -rf loopback_*.txt
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
	@test -f ../vivado/synth_soc.tcl || (echo "[FAIL] missing ../vivado/synth_soc.tcl"; exit 1)
	cmd.exe /C "cd /d H:\Academic\senior_project\DATN\work\luc\AES_huffman_all6 && set PROJECT_NAME=$(VIVADO_PROJECT)&& set TOP_NAME=$(VIVADO_TOP)&& set FPGA_BUILD=$(VIVADO_BUILD)&& set VIVADO_FLOW=synth&& set VIVADO_CLOCK_MHZ=$(VIVADO_CLOCK_MHZ)&& set VIVADO_SYNTH_DIRECTIVE=$(VIVADO_SYNTH_DIRECTIVE)&& set VIVADO_OPT_DIRECTIVE=$(VIVADO_OPT_DIRECTIVE)&& set VIVADO_PLACE_DIRECTIVE=$(VIVADO_PLACE_DIRECTIVE)&& set VIVADO_PHYS_OPT_DIRECTIVE=$(VIVADO_PHYS_OPT_DIRECTIVE)&& set VIVADO_ROUTE_DIRECTIVE=$(VIVADO_ROUTE_DIRECTIVE)&& set VIVADO_POWER_OPT=$(VIVADO_POWER_OPT)&& set VIVADO_POWER_OPT_POST_PLACE=$(VIVADO_POWER_OPT_POST_PLACE)&& set VIVADO_XDC=$(VIVADO_XDC)&& $(VIVADO_BAT) -mode batch -source vivado\synth_soc.tcl"

vivado_synth_full:
	$(MAKE) vivado_synth VIVADO_PROJECT=$(VIVADO_FULL_PROJECT) VIVADO_BUILD=full VIVADO_TOP=$(VIVADO_FPGA_TOP) VIVADO_XDC=$(VIVADO_BOARD_XDC) VIVADO_CLOCK_MHZ=$(VIVADO_CLOCK_MHZ)

vivado_synth_tx:
	$(MAKE) vivado_synth VIVADO_PROJECT=$(VIVADO_TX_PROJECT) VIVADO_BUILD=tx_only VIVADO_TOP=$(VIVADO_FPGA_TOP) VIVADO_XDC=$(VIVADO_BOARD_XDC) VIVADO_CLOCK_MHZ=$(VIVADO_CLOCK_MHZ)

vivado_synth_rx:
	$(MAKE) vivado_synth VIVADO_PROJECT=$(VIVADO_RX_PROJECT) VIVADO_BUILD=rx_only VIVADO_TOP=$(VIVADO_FPGA_TOP) VIVADO_XDC=$(VIVADO_BOARD_XDC) VIVADO_CLOCK_MHZ=$(VIVADO_CLOCK_MHZ)

vivado_impl:
	@test -f ../vivado/synth_soc.tcl || (echo "[FAIL] missing ../vivado/synth_soc.tcl"; exit 1)
	cmd.exe /C "cd /d H:\Academic\senior_project\DATN\work\luc\AES_huffman_all6 && set PROJECT_NAME=$(VIVADO_PROJECT)&& set TOP_NAME=$(VIVADO_TOP)&& set FPGA_BUILD=$(VIVADO_BUILD)&& set VIVADO_FLOW=impl&& set VIVADO_REUSE_SYNTH=$(VIVADO_REUSE_SYNTH)&& set VIVADO_REUSE_IMPL=$(VIVADO_REUSE_IMPL)&& set VIVADO_CLOCK_MHZ=$(VIVADO_CLOCK_MHZ)&& set VIVADO_SYNTH_DIRECTIVE=$(VIVADO_SYNTH_DIRECTIVE)&& set VIVADO_OPT_DIRECTIVE=$(VIVADO_OPT_DIRECTIVE)&& set VIVADO_PLACE_DIRECTIVE=$(VIVADO_PLACE_DIRECTIVE)&& set VIVADO_PHYS_OPT_DIRECTIVE=$(VIVADO_PHYS_OPT_DIRECTIVE)&& set VIVADO_ROUTE_DIRECTIVE=$(VIVADO_ROUTE_DIRECTIVE)&& set VIVADO_POWER_OPT=$(VIVADO_POWER_OPT)&& set VIVADO_POWER_OPT_POST_PLACE=$(VIVADO_POWER_OPT_POST_PLACE)&& set VIVADO_XDC=$(VIVADO_XDC)&& $(VIVADO_BAT) -mode batch -source vivado\synth_soc.tcl"

vivado_impl_tx:
	$(MAKE) vivado_impl VIVADO_PROJECT=$(VIVADO_TX_PROJECT) VIVADO_BUILD=tx_only VIVADO_TOP=$(VIVADO_FPGA_TOP) VIVADO_XDC=$(VIVADO_BOARD_XDC) VIVADO_CLOCK_MHZ=$(VIVADO_CLOCK_MHZ)

vivado_impl_rx:
	$(MAKE) vivado_impl VIVADO_PROJECT=$(VIVADO_RX_PROJECT) VIVADO_BUILD=rx_only VIVADO_TOP=$(VIVADO_FPGA_TOP) VIVADO_XDC=$(VIVADO_BOARD_XDC) VIVADO_CLOCK_MHZ=$(VIVADO_CLOCK_MHZ)

vivado_impl_full:
	$(MAKE) vivado_impl VIVADO_PROJECT=$(VIVADO_FULL_PROJECT) VIVADO_BUILD=full VIVADO_TOP=$(VIVADO_FPGA_TOP) VIVADO_XDC=$(VIVADO_BOARD_XDC) VIVADO_CLOCK_MHZ=$(VIVADO_CLOCK_MHZ)

vivado_bit:
	@test -f ../vivado/synth_soc.tcl || (echo "[FAIL] missing ../vivado/synth_soc.tcl"; exit 1)
	cmd.exe /C "cd /d H:\Academic\senior_project\DATN\work\luc\AES_huffman_all6 && set PROJECT_NAME=$(VIVADO_PROJECT)&& set TOP_NAME=$(VIVADO_TOP)&& set FPGA_BUILD=$(VIVADO_BUILD)&& set VIVADO_FLOW=bit&& set VIVADO_REUSE_SYNTH=$(VIVADO_BIT_REUSE_SYNTH)&& set VIVADO_REUSE_IMPL=$(VIVADO_REUSE_IMPL)&& set VIVADO_CLOCK_MHZ=$(VIVADO_CLOCK_MHZ)&& set VIVADO_SYNTH_DIRECTIVE=$(VIVADO_SYNTH_DIRECTIVE)&& set VIVADO_OPT_DIRECTIVE=$(VIVADO_OPT_DIRECTIVE)&& set VIVADO_PLACE_DIRECTIVE=$(VIVADO_PLACE_DIRECTIVE)&& set VIVADO_PHYS_OPT_DIRECTIVE=$(VIVADO_PHYS_OPT_DIRECTIVE)&& set VIVADO_ROUTE_DIRECTIVE=$(VIVADO_ROUTE_DIRECTIVE)&& set VIVADO_POWER_OPT=$(VIVADO_POWER_OPT)&& set VIVADO_POWER_OPT_POST_PLACE=$(VIVADO_POWER_OPT_POST_PLACE)&& set VIVADO_XDC=$(VIVADO_XDC)&& $(VIVADO_BAT) -mode batch -source vivado\synth_soc.tcl"

vivado_bit_tx:
	$(MAKE) vivado_bit VIVADO_PROJECT=$(VIVADO_TX_PROJECT) VIVADO_BUILD=tx_only VIVADO_TOP=$(VIVADO_FPGA_TOP) VIVADO_XDC=$(VIVADO_BOARD_XDC) VIVADO_CLOCK_MHZ=$(VIVADO_CLOCK_MHZ) VIVADO_BIT_REUSE_SYNTH=$(VIVADO_BIT_REUSE_SYNTH)

vivado_bit_rx:
	$(MAKE) vivado_bit VIVADO_PROJECT=$(VIVADO_RX_PROJECT) VIVADO_BUILD=rx_only VIVADO_TOP=$(VIVADO_FPGA_TOP) VIVADO_XDC=$(VIVADO_BOARD_XDC) VIVADO_CLOCK_MHZ=$(VIVADO_CLOCK_MHZ) VIVADO_BIT_REUSE_SYNTH=$(VIVADO_BIT_REUSE_SYNTH)

vivado_flow_tx:
	$(MAKE) vivado_synth_tx VIVADO_CLOCK_MHZ=$(VIVADO_CLOCK_MHZ)
	$(MAKE) vivado_impl_tx VIVADO_CLOCK_MHZ=$(VIVADO_CLOCK_MHZ) VIVADO_REUSE_SYNTH=1
	$(MAKE) vivado_bit_tx VIVADO_CLOCK_MHZ=$(VIVADO_CLOCK_MHZ) VIVADO_BIT_REUSE_SYNTH=1 VIVADO_REUSE_IMPL=1

vivado_flow_rx:
	$(MAKE) vivado_synth_rx VIVADO_CLOCK_MHZ=$(VIVADO_CLOCK_MHZ)
	$(MAKE) vivado_impl_rx VIVADO_CLOCK_MHZ=$(VIVADO_CLOCK_MHZ) VIVADO_REUSE_SYNTH=1
	$(MAKE) vivado_bit_rx VIVADO_CLOCK_MHZ=$(VIVADO_CLOCK_MHZ) VIVADO_BIT_REUSE_SYNTH=1 VIVADO_REUSE_IMPL=1

vivado_flow_full:
	$(MAKE) vivado_synth_full VIVADO_CLOCK_MHZ=$(VIVADO_CLOCK_MHZ)
	$(MAKE) vivado_impl_full VIVADO_CLOCK_MHZ=$(VIVADO_CLOCK_MHZ) VIVADO_REUSE_SYNTH=1

vivado_flow:
	$(MAKE) vivado_flow_full VIVADO_CLOCK_MHZ=$(VIVADO_CLOCK_MHZ)

vivado_flow_split:
	$(MAKE) vivado_flow_tx VIVADO_CLOCK_MHZ=$(VIVADO_CLOCK_MHZ)
	$(MAKE) vivado_flow_rx VIVADO_CLOCK_MHZ=$(VIVADO_CLOCK_MHZ)

_vivado_gui_open:
	@test -f "$(VIVADO_XPR_WSL)" || (echo "[FAIL] missing Vivado project: $(VIVADO_XPR_WSL). Run make vivado_synth/vivado_impl first or set VIVADO_PROJECT=<project>."; exit 1)
	cmd.exe /C "$(VIVADO_BAT) -mode gui $(VIVADO_XPR)"

vivado_gui:
	$(MAKE) vivado_gui_full

vivado_gui_tx:
	$(MAKE) _vivado_gui_open VIVADO_PROJECT=$(VIVADO_TX_PROJECT)

vivado_gui_rx:
	$(MAKE) _vivado_gui_open VIVADO_PROJECT=$(VIVADO_RX_PROJECT)

vivado_gui_full:
	$(MAKE) _vivado_gui_open VIVADO_PROJECT=$(VIVADO_FULL_PROJECT)

vivado_report:
	powershell.exe -NoProfile -Command '$$dir="$(VIVADO_REPORT_WIN_DIR)"; if (!(Test-Path -LiteralPath $$dir)) { Write-Error "Missing Vivado report directory: $$dir"; exit 1 }; Invoke-Item $$dir'

license:
	@set -e; \
	if [ ! -x "$(QUESTA_ROOT)/pubkey_verify" ]; then \
		echo "[FAIL] missing or non-executable $(QUESTA_ROOT)/pubkey_verify"; \
		exit 1; \
	fi; \
	if [ -f "$(LICGEN_DIR)/mgclicgen.py" ]; then \
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
	else \
		echo "[WARN] missing $(LICGEN_DIR)/mgclicgen.py; skip license generation"; \
		if [ -f "$(QUESTA_LICENSE)" ]; then \
			echo "[PASS] existing license.dat found: $(QUESTA_LICENSE)"; \
		else \
			echo "[FAIL] no generator and no existing license.dat at $(QUESTA_LICENSE)"; \
			exit 1; \
		fi; \
	fi; \
	if [ -n "$(SUDO_PASS)" ]; then \
		SUDO_CMD="printf '%s\n' '$(SUDO_PASS)' | sudo -S ./pubkey_verify -y ."; \
	else \
		SUDO_CMD="sudo -S ./pubkey_verify -y ."; \
	fi; \
	if cd "$(QUESTA_ROOT)" && sh -c "$$SUDO_CMD"; then \
		echo "[PASS] pubkey_verify completed"; \
		echo "[PASS] Questa license is ready: $(QUESTA_LICENSE)"; \
	else \
		echo "[FAIL] pubkey_verify failed"; \
		exit 1; \
	fi
push_github:
	cd .. && ./push_source.sh	
help:
	@echo ""
	@echo "****************************************"
	@echo "** make clean    : clean simulation outputs only"
	@echo "** make clean_vivado : clean Vivado build/report/bitstream outputs only"
	@echo "** make build    : build the design"
	@echo "** make build_cov: build the design in coverage mode"
	@echo "** make run      : run simulation"
	@echo "** make run_cov  : run simulation in coverage mode"
	@echo "** make all      : build and run simulation (default TESTNAME=dma_compress_aes_input1)"
	@echo "** make all_cov  : build and run simulation in coverage mode"
	@echo "** make wave     : open waveform"
	@echo "** make gen_cov  : merge, generate coverage data base and text coverage report"
	@echo "** make gen_html : merge, generate coverage data base and html coverage report"
	@echo "** make compile C_SRC=test_mmio_dma.c"
	@echo "**    build source from ../testcase/, write outputs to ../testcase/, copy mem to ./instruction.mem"
	@echo "** make license  : generate license.dat from WSL MAC and verify Questa"
	@echo "** make vivado_synth : synthesize current FPGA demo target"
	@echo "** make vivado_synth_full : synthesize full FPGA demo SoC top"
	@echo "** make vivado_synth_tx : synthesize TX-only FPGA build"
	@echo "** make vivado_synth_rx : synthesize RX-only FPGA build"
	@echo "** make vivado_impl : implement current FPGA demo target through route_design"
	@echo "** make vivado_impl_tx : synthesize and implement TX-only FPGA build"
	@echo "** make vivado_impl_rx : synthesize and implement RX-only FPGA build"
	@echo "** make vivado_impl_full : implement full FPGA demo SoC top"
	@echo "**    set VIVADO_POWER_OPT=1 to run pre/post-place Vivado power_opt_design"
	@echo "** make vivado_bit_tx  : generate TX-only FPGA demo bitstream"
	@echo "** make vivado_bit_rx  : generate RX-only FPGA demo bitstream"
	@echo "** make vivado_flow_tx : run TX-only synth -> impl -> bitstream"
	@echo "** make vivado_flow_rx : run RX-only synth -> impl -> bitstream"
	@echo "** make vivado_flow_full : run full FPGA demo SoC synth -> implementation"
	@echo "** make vivado_flow : alias for vivado_flow_full"
	@echo "** make vivado_flow_split : run TX-only flow first, then RX-only flow"
	@echo "** make uart_load UART_PORT=/dev/ttyUSB0 UART_INPUT=input1.txt"
	@echo "**    host-side command: send a text/binary file over UART into DMEM on FPGA"
	@echo "**    not used by simulation; use only after programming the FPGA bitstream"
	@echo "**    Vivado clock default: VIVADO_CLOCK_MHZ=50; override with VIVADO_CLOCK_MHZ=100"
	@echo "**    TX/RX FPGA targets use VIVADO_FPGA_TOP=rv32_soc_fpga_demo_top and VIVADO_BOARD_XDC=vivado/constraints/zedboard_demo.xdc"
	@echo "**    Project names: TX=$(VIVADO_TX_PROJECT), RX=$(VIVADO_RX_PROJECT), FULL=$(VIVADO_FULL_PROJECT)"
	@echo "**    Separated bitstreams are copied to ./vivado_bitstreams/$(VIVADO_TX_PROJECT).bit and ./vivado_bitstreams/$(VIVADO_RX_PROJECT).bit"
	@echo "**    Bitstream flow reruns needed Vivado stages by default; set VIVADO_BIT_REUSE_SYNTH=1 or VIVADO_REUSE_IMPL=1 for faster reuse"
	@echo "** make vivado_gui_tx: open optimized TX-only Vivado project"
	@echo "** make vivado_gui_rx: open Vivado GUI RX-only project"
	@echo "** make vivado_gui_full: open optimized full TX+RX Vivado project"
	@echo "** make vivado_report VIVADO_PROJECT=$(VIVADO_TX_PROJECT) : open a Vivado report folder"
	@echo "****************************************"
	@echo ""

group:
	make all_cov TESTNAME=sanity_test
	make all_cov TESTNAME=ro_check
	make all_cov TESTNAME=check_non_existed_addr
	make all_cov TESTNAME=resv_addr
	make all_cov TESTNAME=rw1c_check

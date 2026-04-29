# Active SoC MMIO DMA testbench + required support models
../tb/tb_rv32_soc_mmio_dma.v
../tb/tb_rv32_soc_tx_only.v
../tb/tb_rv32_soc_mmio_regfile.v

# Host-preprocess benchmark: Python/script preprocesses input, RV32I only controls DMA/TX.
../tb/tb_rv32_log_preprocess.v

# Deprecated branch: RV32I-side preprocess/parser is no longer part of the main flow.
#../tb/tb_rv32_sensor_phi_preprocess_rv32.v
#../rtl/registers_file.v
#../rtl/imem_sync.v

# RV32I sync standalone testbench + TB-owned models
#../tb/tb_risc_v_sync_mem.v
#../rtl/registers_file.v
#../rtl/imem_sync.v
#../rtl/dmem_sync.v
#../rtl/dmem_sync_wrab.v

# Alternate async RV32I testbench + TB-owned models
#../tb/tb_risc_v.v
#../rtl/registers_file.v
#../rtl/imem.v
#../rtl/dmem.v
#../rtl/dmem_wrab.v

# APB Huffman/AES testbench
#../tb/test_bench_apb_huffman_aes_rx_only.v

// Minimal RV32I system top for the synchronous-BRAM bring-up path:
// - top_rv32_sync core
// - external register file with write-through reads
// - synchronous instruction memory model
// - DMEM Vivado IP wrapper / behavioral model
//
// Notes:
// - This top is intended as the next integration step before adding DMA/UART.
// - Port B of DMEM is exposed as a generic auxiliary master interface.
// - Both IMEM and DMEM model synchronous BRAM behavior so the bring-up path
//   matches FPGA timing more closely than the original async test setup.
module rv32_soc_top (
  input  wire        clk_i,
  input  wire        rst_i,

  // Auxiliary DMEM port for DMA or UART loader.
  input  wire        aux_en_i,
  input  wire [3:0]  aux_we_i,
  input  wire [31:0] aux_addr_i,
  input  wire [31:0] aux_wdata_i,
  output wire [31:0] aux_rdata_o,

  // Optional control hooks for future system integration.
  input  wire        cpu_if_flush_i,
  input  wire        cpu_stall_i,

  output wire [1:0]  mem_err_o,

  // Board/debug status outputs. Done/error are one-cycle pulses from the DMA
  // engines; board wrappers can latch them for LEDs.
  output wire        tx_dma_busy_o,
  output wire        tx_dma_done_o,
  output wire        tx_dma_error_o,
  output wire        rx_dma_busy_o,
  output wire        rx_dma_done_o,
  output wire        rx_dma_error_o,
  output wire        imem_program_seen_o,

  // Live CPU debug snapshot for board UART readback.
  output wire [31:0] cpu_debug_status_o,
  output wire [31:0] cpu_debug_fetch_pc_o,
  output wire [31:0] cpu_debug_fetch_instr_o,
  output wire [31:0] cpu_debug_cycle_count_o,
  output wire [31:0] cpu_debug_fetch_count_o,
  output wire [31:0] cpu_debug_dmem_access_count_o,
  output wire [31:0] cpu_debug_mmio_access_count_o,
  output wire [31:0] cpu_debug_last_dmem_addr_o,
  output wire [31:0] cpu_debug_last_dmem_wdata_o,
  output wire [31:0] cpu_debug_last_dmem_ctrl_o,
  output wire [31:0] cpu_debug_wb_count_o,
  output wire [31:0] cpu_debug_last_wb_info_o,
  output wire [31:0] cpu_debug_last_wb_data_o
);

  localparam [31:0] DMA_APB_BASE_W = 32'h4000_0000;
  localparam [31:0] DMA_APB_MASK_W = 32'hFFFF_FF00;
  localparam [1:0]  DMA_DIR_TX_W   = 2'b01;
  localparam [1:0]  DMA_DIR_RX_W   = 2'b10;

  // ------------------------------------------------------------
  // CPU <-> IMEM
  // ------------------------------------------------------------
  wire        imem_en_w;
  wire [31:0] imem_addr_w;
  wire [31:0] imem_instr_w;

  // ------------------------------------------------------------
  // CPU <-> DMEM
  // ------------------------------------------------------------
  wire        dmem_en_w;
  wire [3:0]  dmem_we_w;
  wire [31:0] dmem_addr_w;
  wire [31:0] dmem_wdata_w;
  wire [31:0] dmem_rdata_w;
  wire [31:0] dmem_port_a_rdata_w;
  wire [31:0] dmem_port_b_rdata_w;
  wire        dmem_load_resp_is_mmio_w;

  wire        cpu_mmio_sel_w;
  wire        cpu_dmem_sel_w;
  wire        cpu_mmio_write_w;
  wire        cpu_global_hold_w;
  wire [31:0] bridge_mmio_rdata_w;
  wire        bridge_mmio_done_w;
  wire        bridge_mmio_error_w;
  wire        bridge_mmio_busy_w;
  wire        bridge_cpu_stall_req_w;
  wire        soc_debug_unused_w;

  wire        bridge_psel_w;
  wire        bridge_penable_w;
  wire        bridge_pwrite_w;
  wire [31:0] bridge_paddr_w;
  wire [31:0] bridge_pwdata_w;
  wire [31:0] dma_apb_prdata_w;
  wire        dma_apb_pready_w;
  wire        dma_apb_pslverr_w;
  wire [31:0] dma_apb_local_addr_w;

  wire [31:0] dma_src_addr_w;
  wire [31:0] dma_dst_addr_w;
  wire [31:0] dma_len_bytes_w;
  wire [1:0]  dma_direction_w;
  wire        dma_compress_only_w;
  wire        dma_whole_file_w;
  wire [127:0] dma_iv_w;
  wire [5:0]  dma_block_size_w;
  wire        dma_engine_busy_w;
  wire        dma_engine_done_w;
  wire        dma_engine_error_w;
  wire [31:0] dma_engine_bytes_done_w;
  wire [7:0]  dma_engine_last_error_w;
  wire [3:0]  dma_engine_state_w;
  wire        dma_start_pulse_w;
  wire        dma_soft_reset_pulse_w;
  wire        dma_clear_done_pulse_w;
  wire        dma_clear_error_pulse_w;

  wire        dma_port_b_en_w;
  wire [3:0]  dma_port_b_we_w;
  wire [31:0] dma_port_b_addr_w;
  wire [31:0] dma_port_b_wdata_w;
  wire        tx_dma_port_b_en_w;
  wire [3:0]  tx_dma_port_b_we_w;
  wire [31:0] tx_dma_port_b_addr_w;
  wire [31:0] tx_dma_port_b_wdata_w;
  wire        rx_dma_port_b_en_w;
  wire [3:0]  rx_dma_port_b_we_w;
  wire [31:0] rx_dma_port_b_addr_w;
  wire [31:0] rx_dma_port_b_wdata_w;
  wire [1:0]  dmem_port_b_owner_sel_w;
  reg  [1:0]  dma_active_dir_r;

  wire        tx_psel_w;
  wire        tx_penable_w;
  wire        tx_pwrite_w;
  wire [31:0] tx_paddr_w;
  wire [31:0] tx_pwdata_w;
  wire [31:0] tx_prdata_w;
  wire        tx_pready_w;
  wire        tx_pslverr_w;
  wire [127:0] tx_aes_data_out_w;
  wire         tx_aes_ready_out_w;
  wire         tx_busy_dbg_w;
  wire         tx_done_dbg_w;
  wire         tx_error_dbg_w;
  wire         tx_encoder_busy_w;
  wire         tx_encoder_done_w;
  wire         tx_encoder_error_w;
  wire [1:0]   tx_selected_mode_w;
  wire [3:0]   tx_fsm_state_w;
  wire         tx_packer_busy_w;
  wire         tx_packer_done_w;
  wire         tx_packer_error_w;
  wire [127:0] tx_transport_word_dbg_w;
  wire         tx_transport_word_valid_dbg_w;
  wire         tx_adapter_error_dbg_w;
  wire         tx_apb_start_block_dbg_w;
  wire [5:0]   tx_apb_block_size_dbg_w;
  wire [31:0]  tx_apb_word_in_dbg_w;
  wire         tx_apb_word_valid_dbg_w;
  wire         tx_apb_word_ready_dbg_w;
  wire         tx_cipher_en_dbg_w;
  wire         tx_decipher_en_dbg_w;
  wire         tx_chain_en_dbg_w;
  wire [127:0] tx_data_in_dbg_w;
  wire [127:0] tx_key_dbg_w;
  wire [3:0]   tx_mode_dbg_w;
  wire [127:0] tx_init_vector_dbg_w;
  wire [15:0]  tx_segment_len_dbg_w;
  wire         tx_dma_busy_w;
  wire         tx_dma_done_w;
  wire         tx_dma_error_w;
  wire [31:0]  tx_dma_bytes_done_w;
  wire [7:0]   tx_dma_last_error_w;
  wire [3:0]   tx_dma_state_w;

  wire        rx_psel_w;
  wire        rx_penable_w;
  wire        rx_pwrite_w;
  wire [31:0] rx_paddr_w;
  wire [31:0] rx_pwdata_w;
  wire [31:0] rx_prdata_w;
  wire        rx_pready_w;
  wire        rx_pslverr_w;
  wire        rx_busy_dbg_w;
  wire        rx_done_dbg_w;
  wire        rx_error_dbg_w;
  wire        rx_aes_ready_out_w;
  wire        rx_depacker_busy_w;
  wire        rx_depacker_done_w;
  wire        rx_depacker_error_w;
  wire        rx_parser_busy_w;
  wire        rx_parser_block_done_w;
  wire        rx_parser_frame_done_w;
  wire        rx_parser_error_w;
  wire        rx_decoder_busy_w;
  wire        rx_decoder_block_done_w;
  wire        rx_decoder_frame_done_w;
  wire        rx_decoder_error_w;
  wire        rx_word_packer_busy_w;
  wire        rx_word_packer_block_done_w;
  wire        rx_word_packer_frame_done_w;
  wire        rx_word_packer_error_w;
  wire [127:0] rx_transport_word_dbg_w;
  wire         rx_transport_word_valid_dbg_w;
  wire [31:0]  rx_word_dbg_w;
  wire [2:0]   rx_word_valid_bytes_dbg_w;
  wire         rx_word_last_in_block_dbg_w;
  wire         rx_word_last_in_frame_dbg_w;
  wire         rx_word_valid_dbg_w;
  wire         rx_ciphertext_word_ready_unused_w;
  wire [127:0] rx_ciphertext_word_w;
  wire         rx_ciphertext_word_valid_w;
  wire         rx_dma_busy_w;
  wire         rx_dma_done_w;
  wire         rx_dma_error_w;
  wire [31:0]  rx_dma_bytes_done_w;
  wire [7:0]   rx_dma_last_error_w;
  wire [3:0]   rx_dma_state_w;

  // ------------------------------------------------------------
  // CPU <-> Register file
  // ------------------------------------------------------------
  wire [4:0]  rs1_addr_w;
  wire [4:0]  rs2_addr_w;
  wire [31:0] rs1_data_w;
  wire [31:0] rs2_data_w;
  wire        reg_write_w;
  wire [4:0]  rd_addr_w;
  wire [31:0] rd_data_w;
  reg         imem_program_seen_r;
  reg [31:0] cpu_debug_cycle_count_r;
  reg [31:0] cpu_debug_fetch_count_r;
  reg [31:0] cpu_debug_dmem_access_count_r;
  reg [31:0] cpu_debug_mmio_access_count_r;
  reg [31:0] cpu_debug_last_dmem_addr_r;
  reg [31:0] cpu_debug_last_dmem_wdata_r;
  reg [31:0] cpu_debug_last_dmem_ctrl_r;
  reg [31:0] cpu_debug_wb_count_r;
  reg [31:0] cpu_debug_last_wb_info_r;
  reg [31:0] cpu_debug_last_wb_data_r;

  assign cpu_mmio_sel_w = dmem_en_w &&
                          ((dmem_addr_w & DMA_APB_MASK_W) == DMA_APB_BASE_W);
  assign cpu_dmem_sel_w = dmem_en_w && (!cpu_mmio_sel_w);
  assign cpu_mmio_write_w = |dmem_we_w;
  assign cpu_global_hold_w = cpu_stall_i | bridge_cpu_stall_req_w;
  assign dma_engine_busy_w = tx_dma_busy_w | rx_dma_busy_w;
  assign dmem_port_b_owner_sel_w = tx_dma_busy_w ? DMA_DIR_TX_W :
                                   (rx_dma_busy_w ? DMA_DIR_RX_W : 2'b00);
  assign aux_rdata_o = (dmem_port_b_owner_sel_w != 2'b00) ? 32'b0 : dmem_port_b_rdata_w;

  assign dma_apb_local_addr_w = bridge_paddr_w - DMA_APB_BASE_W;
  assign dma_engine_done_w = (dma_active_dir_r == DMA_DIR_RX_W) ? rx_dma_done_w : tx_dma_done_w;
  assign dma_engine_error_w = (dma_active_dir_r == DMA_DIR_RX_W) ? rx_dma_error_w : tx_dma_error_w;
  assign dma_engine_bytes_done_w = (dma_active_dir_r == DMA_DIR_RX_W) ? rx_dma_bytes_done_w : tx_dma_bytes_done_w;
  assign dma_engine_last_error_w = (dma_active_dir_r == DMA_DIR_RX_W) ? rx_dma_last_error_w : tx_dma_last_error_w;
  assign dma_engine_state_w = (dma_active_dir_r == DMA_DIR_RX_W) ? rx_dma_state_w : tx_dma_state_w;
  assign tx_dma_busy_o = tx_dma_busy_w;
  assign tx_dma_done_o = tx_dma_done_w;
  assign tx_dma_error_o = tx_dma_error_w;
  assign rx_dma_busy_o = rx_dma_busy_w;
  assign rx_dma_done_o = rx_dma_done_w;
  assign rx_dma_error_o = rx_dma_error_w;
  assign imem_program_seen_o = imem_program_seen_r;
  assign cpu_debug_status_o = {
    12'b0,
    dmem_we_w,
    2'b0,
    dmem_load_resp_is_mmio_w,
    bridge_cpu_stall_req_w,
    rx_dma_error_w,
    tx_dma_error_w,
    rx_dma_done_w,
    tx_dma_done_w,
    rx_dma_busy_w,
    tx_dma_busy_w,
    cpu_mmio_sel_w,
    dmem_en_w,
    imem_en_w,
    imem_program_seen_r,
    cpu_global_hold_w,
    rst_i
  };
  assign cpu_debug_fetch_pc_o = imem_addr_w;
  assign cpu_debug_fetch_instr_o = imem_instr_w;
  assign cpu_debug_cycle_count_o = cpu_debug_cycle_count_r;
  assign cpu_debug_fetch_count_o = cpu_debug_fetch_count_r;
  assign cpu_debug_dmem_access_count_o = cpu_debug_dmem_access_count_r;
  assign cpu_debug_mmio_access_count_o = cpu_debug_mmio_access_count_r;
  assign cpu_debug_last_dmem_addr_o = cpu_debug_last_dmem_addr_r;
  assign cpu_debug_last_dmem_wdata_o = cpu_debug_last_dmem_wdata_r;
  assign cpu_debug_last_dmem_ctrl_o = cpu_debug_last_dmem_ctrl_r;
  assign cpu_debug_wb_count_o = cpu_debug_wb_count_r;
  assign cpu_debug_last_wb_info_o = cpu_debug_last_wb_info_r;
  assign cpu_debug_last_wb_data_o = cpu_debug_last_wb_data_r;
  assign dma_port_b_en_w = (dmem_port_b_owner_sel_w == DMA_DIR_TX_W) ? tx_dma_port_b_en_w :
                           ((dmem_port_b_owner_sel_w == DMA_DIR_RX_W) ? rx_dma_port_b_en_w : 1'b0);
  assign dma_port_b_we_w = (dmem_port_b_owner_sel_w == DMA_DIR_TX_W) ? tx_dma_port_b_we_w :
                           ((dmem_port_b_owner_sel_w == DMA_DIR_RX_W) ? rx_dma_port_b_we_w : 4'b0000);
  assign dma_port_b_addr_w = (dmem_port_b_owner_sel_w == DMA_DIR_TX_W) ? tx_dma_port_b_addr_w :
                             ((dmem_port_b_owner_sel_w == DMA_DIR_RX_W) ? rx_dma_port_b_addr_w : 32'b0);
  assign dma_port_b_wdata_w = (dmem_port_b_owner_sel_w == DMA_DIR_TX_W) ? tx_dma_port_b_wdata_w :
                              ((dmem_port_b_owner_sel_w == DMA_DIR_RX_W) ? rx_dma_port_b_wdata_w : 32'b0);
  assign soc_debug_unused_w = (|imem_addr_w[31:12]) ||
                              (|imem_addr_w[1:0])   ||
                              bridge_mmio_done_w ||
                              bridge_mmio_error_w ||
                              bridge_mmio_busy_w ||
                              (|dma_src_addr_w) ||
                              (|dma_dst_addr_w) ||
                              (|dma_len_bytes_w) ||
                              (|dma_direction_w) ||
                              dma_compress_only_w ||
                              dma_whole_file_w ||
                              (|dma_iv_w) ||
                              (|dma_block_size_w) ||
                              dma_start_pulse_w ||
                              dma_soft_reset_pulse_w ||
                              dma_clear_done_pulse_w ||
                              dma_clear_error_pulse_w ||
                              tx_psel_w ||
                              tx_penable_w ||
                              tx_pwrite_w ||
                              (|tx_paddr_w) ||
                              (|tx_pwdata_w) ||
                              (|tx_prdata_w) ||
                              tx_pready_w ||
                              tx_pslverr_w ||
                              (|tx_aes_data_out_w) ||
                              tx_aes_ready_out_w ||
                              tx_busy_dbg_w ||
                              tx_done_dbg_w ||
                              tx_error_dbg_w ||
                              tx_encoder_busy_w ||
                              tx_encoder_done_w ||
                              tx_encoder_error_w ||
                              (|tx_selected_mode_w) ||
                              (|tx_fsm_state_w) ||
                              tx_packer_busy_w ||
                              tx_packer_done_w ||
                              tx_packer_error_w ||
                              (|tx_transport_word_dbg_w) ||
                              tx_transport_word_valid_dbg_w ||
                              tx_adapter_error_dbg_w ||
                              tx_apb_start_block_dbg_w ||
                              (|tx_apb_block_size_dbg_w) ||
                              (|tx_apb_word_in_dbg_w) ||
                              tx_apb_word_valid_dbg_w ||
                              tx_apb_word_ready_dbg_w ||
                              tx_cipher_en_dbg_w ||
                              tx_decipher_en_dbg_w ||
                              tx_chain_en_dbg_w ||
                              (|tx_data_in_dbg_w) ||
                              (|tx_key_dbg_w) ||
                              (|tx_mode_dbg_w) ||
                              (|tx_init_vector_dbg_w) ||
                              (|tx_segment_len_dbg_w) ||
                              rx_psel_w ||
                              rx_penable_w ||
                              rx_pwrite_w ||
                              (|rx_paddr_w) ||
                              (|rx_pwdata_w) ||
                              (|rx_prdata_w) ||
                              rx_pready_w ||
                              rx_pslverr_w ||
                              rx_busy_dbg_w ||
                              rx_done_dbg_w ||
                              rx_error_dbg_w ||
                              rx_aes_ready_out_w ||
                              rx_depacker_busy_w ||
                              rx_depacker_done_w ||
                              rx_depacker_error_w ||
                              rx_parser_busy_w ||
                              rx_parser_block_done_w ||
                              rx_parser_frame_done_w ||
                              rx_parser_error_w ||
                              rx_decoder_busy_w ||
                              rx_decoder_block_done_w ||
                              rx_decoder_frame_done_w ||
                              rx_decoder_error_w ||
                              rx_word_packer_busy_w ||
                              rx_word_packer_block_done_w ||
                              rx_word_packer_frame_done_w ||
                              rx_word_packer_error_w ||
                              (|rx_transport_word_dbg_w) ||
                              rx_transport_word_valid_dbg_w ||
                              (|rx_word_dbg_w) ||
                              (|rx_word_valid_bytes_dbg_w) ||
                              rx_word_last_in_block_dbg_w ||
                              rx_word_last_in_frame_dbg_w ||
                              rx_word_valid_dbg_w ||
                              rx_ciphertext_word_ready_unused_w ||
                              (|rx_ciphertext_word_w) ||
                              rx_ciphertext_word_valid_w ||
                              (|dma_engine_bytes_done_w) ||
                              (|dma_engine_last_error_w) ||
                              (|dma_engine_state_w) ||
                              (|dma_active_dir_r);
  assign dmem_rdata_w = (dmem_load_resp_is_mmio_w ? bridge_mmio_rdata_w : dmem_port_a_rdata_w) ^
                        {32{1'b0 & soc_debug_unused_w}};

  always @(posedge clk_i) begin
    if (rst_i) begin
      dma_active_dir_r <= 2'b00;
      imem_program_seen_r <= 1'b0;
      cpu_debug_cycle_count_r <= 32'd0;
      cpu_debug_fetch_count_r <= 32'd0;
      cpu_debug_dmem_access_count_r <= 32'd0;
      cpu_debug_mmio_access_count_r <= 32'd0;
      cpu_debug_last_dmem_addr_r <= 32'd0;
      cpu_debug_last_dmem_wdata_r <= 32'd0;
      cpu_debug_last_dmem_ctrl_r <= 32'd0;
      cpu_debug_wb_count_r <= 32'd0;
      cpu_debug_last_wb_info_r <= 32'd0;
      cpu_debug_last_wb_data_r <= 32'd0;
    end else begin
      cpu_debug_cycle_count_r <= cpu_debug_cycle_count_r + 32'd1;

      if (imem_en_w)
        cpu_debug_fetch_count_r <= cpu_debug_fetch_count_r + 32'd1;

      if (imem_en_w && (imem_instr_w != 32'b0))
        imem_program_seen_r <= 1'b1;

      if (dmem_en_w) begin
        cpu_debug_dmem_access_count_r <= cpu_debug_dmem_access_count_r + 32'd1;
        cpu_debug_last_dmem_addr_r <= dmem_addr_w;
        cpu_debug_last_dmem_wdata_r <= dmem_wdata_w;
        cpu_debug_last_dmem_ctrl_r <= {27'b0, cpu_mmio_sel_w, dmem_we_w};
      end

      if (cpu_mmio_sel_w)
        cpu_debug_mmio_access_count_r <= cpu_debug_mmio_access_count_r + 32'd1;

      if (reg_write_w) begin
        cpu_debug_wb_count_r <= cpu_debug_wb_count_r + 32'd1;
        cpu_debug_last_wb_info_r <= {26'b0, reg_write_w, rd_addr_w};
        cpu_debug_last_wb_data_r <= rd_data_w;
      end

      if (dma_soft_reset_pulse_w)
        dma_active_dir_r <= 2'b00;
      else if (dma_start_pulse_w)
        dma_active_dir_r <= dma_direction_w;
    end
  end

  top_rv32_sync u_cpu (
    .clk_i        (clk_i),
    .rst_i        (rst_i),

    .imem_en_o    (imem_en_w),
    .imem_addr_o  (imem_addr_w),
    .imem_instr_i (imem_instr_w),

    .dmem_en_o    (dmem_en_w),
    .dmem_we_o    (dmem_we_w),
    .dmem_addr_o  (dmem_addr_w),
    .dmem_w_data_o(dmem_wdata_w),
    .dmem_r_data_i(dmem_rdata_w),
    .dmem_is_mmio_i(cpu_mmio_sel_w),
    .dmem_load_resp_is_mmio_o(dmem_load_resp_is_mmio_w),

    .rs1_addr     (rs1_addr_w),
    .rs2_addr     (rs2_addr_w),
    .rs1_data     (rs1_data_w),
    .rs2_data     (rs2_data_w),
    .reg_write    (reg_write_w),
    .rd_addr      (rd_addr_w),
    .rd_data      (rd_data_w),

    .if_flush_i   (cpu_if_flush_i),
    .stall_i      (cpu_global_hold_w),
    .mem_err_o    (mem_err_o)
  );

  registers_file u_reg_file (
    .clk      (clk_i),
    .rst      (rst_i),
    .rs1_addr (rs1_addr_w),
    .rs2_addr (rs2_addr_w),
    .rs1_data (rs1_data_w),
    .rs2_data (rs2_data_w),
    .reg_write(reg_write_w),
    .rd_addr  (rd_addr_w),
    .rd_data  (rd_data_w)
  );

  imem_sync u_imem (
    .clk_i         (clk_i),
    .en_i          (imem_en_w),
    .instr_addr_i  (imem_addr_w[12:2]),
    .instruction_o (imem_instr_w)
  );

  dmem_ip_wrapper u_dmem (
    .clk_i       (clk_i),
    .cpu_en_i    (cpu_dmem_sel_w),
    .cpu_we_i    (dmem_we_w),
    .cpu_addr_i  (dmem_addr_w),
    .cpu_wdata_i (dmem_wdata_w),
    .cpu_rdata_o (dmem_port_a_rdata_w),
    .aux_en_i    ((dmem_port_b_owner_sel_w != 2'b00) ? dma_port_b_en_w    : aux_en_i),
    .aux_we_i    ((dmem_port_b_owner_sel_w != 2'b00) ? dma_port_b_we_w    : aux_we_i),
    .aux_addr_i  ((dmem_port_b_owner_sel_w != 2'b00) ? dma_port_b_addr_w  : aux_addr_i),
    .aux_wdata_i ((dmem_port_b_owner_sel_w != 2'b00) ? dma_port_b_wdata_w : aux_wdata_i),
    .aux_rdata_o (dmem_port_b_rdata_w)
  );

`ifndef FPGA_RX_ONLY
  apb_huffman_aes_tx_top u_tx_top (
    .PCLK                   (clk_i),
    .PRESETn                (~rst_i),
    .PSEL                   (tx_psel_w),
    .PENABLE                (tx_penable_w),
    .PWRITE                 (tx_pwrite_w),
    .PADDR                  (tx_paddr_w),
    .PWDATA                 (tx_pwdata_w),
    .PRDATA                 (tx_prdata_w),
    .PREADY                 (tx_pready_w),
    .PSLVERR                (tx_pslverr_w),
    .cbc_iv_i               (dma_iv_w),
    .aes_data_out           (tx_aes_data_out_w),
    .aes_ready_out          (tx_aes_ready_out_w),
    .tx_busy                (tx_busy_dbg_w),
    .tx_done                (tx_done_dbg_w),
    .tx_error               (tx_error_dbg_w),
    .encoder_busy           (tx_encoder_busy_w),
    .encoder_done           (tx_encoder_done_w),
    .encoder_error          (tx_encoder_error_w),
    .selected_mode_out      (tx_selected_mode_w),
    .fsm_state              (tx_fsm_state_w),
    .packer_busy            (tx_packer_busy_w),
    .packer_done            (tx_packer_done_w),
    .packer_error           (tx_packer_error_w),
    .transport_word_dbg     (tx_transport_word_dbg_w),
    .transport_word_valid_dbg(tx_transport_word_valid_dbg_w),
    .adapter_error_dbg      (tx_adapter_error_dbg_w),
    .apb_start_block_dbg    (tx_apb_start_block_dbg_w),
    .apb_block_size_dbg     (tx_apb_block_size_dbg_w),
    .apb_word_in_dbg        (tx_apb_word_in_dbg_w),
    .apb_word_valid_dbg     (tx_apb_word_valid_dbg_w),
    .apb_word_ready_dbg     (tx_apb_word_ready_dbg_w),
    .cipher_en_dbg          (tx_cipher_en_dbg_w),
    .decipher_en_dbg        (tx_decipher_en_dbg_w),
    .chain_en_dbg           (tx_chain_en_dbg_w),
    .data_in_dbg            (tx_data_in_dbg_w),
    .key_dbg                (tx_key_dbg_w),
    .mode_dbg               (tx_mode_dbg_w),
    .init_vector_dbg        (tx_init_vector_dbg_w),
    .segment_len_dbg        (tx_segment_len_dbg_w)
  );
`else
  assign tx_prdata_w = 32'b0;
  assign tx_pready_w = 1'b1;
  assign tx_pslverr_w = 1'b0;
  assign tx_aes_data_out_w = 128'b0;
  assign tx_aes_ready_out_w = 1'b0;
  assign tx_busy_dbg_w = 1'b0;
  assign tx_done_dbg_w = 1'b0;
  assign tx_error_dbg_w = 1'b0;
  assign tx_encoder_busy_w = 1'b0;
  assign tx_encoder_done_w = 1'b0;
  assign tx_encoder_error_w = 1'b0;
  assign tx_selected_mode_w = 2'b0;
  assign tx_fsm_state_w = 4'b0;
  assign tx_packer_busy_w = 1'b0;
  assign tx_packer_done_w = 1'b0;
  assign tx_packer_error_w = 1'b0;
  assign tx_transport_word_dbg_w = 128'b0;
  assign tx_transport_word_valid_dbg_w = 1'b0;
  assign tx_adapter_error_dbg_w = 1'b0;
  assign tx_apb_start_block_dbg_w = 1'b0;
  assign tx_apb_block_size_dbg_w = 6'b0;
  assign tx_apb_word_in_dbg_w = 32'b0;
  assign tx_apb_word_valid_dbg_w = 1'b0;
  assign tx_apb_word_ready_dbg_w = 1'b0;
  assign tx_cipher_en_dbg_w = 1'b0;
  assign tx_decipher_en_dbg_w = 1'b0;
  assign tx_chain_en_dbg_w = 1'b0;
  assign tx_data_in_dbg_w = 128'b0;
  assign tx_key_dbg_w = 128'b0;
  assign tx_mode_dbg_w = 4'b0;
  assign tx_init_vector_dbg_w = 128'b0;
  assign tx_segment_len_dbg_w = 16'b0;
`endif

`ifndef FPGA_TX_ONLY
  apb_huffman_aes_rx_top u_rx_top (
    .PCLK                    (clk_i),
    .PRESETn                 (~rst_i),
    .rst_i                   (rst_i),
    .ciphertext_word_in      (rx_ciphertext_word_w),
    .ciphertext_word_valid   (rx_ciphertext_word_valid_w),
    .ciphertext_word_ready   (rx_ciphertext_word_ready_unused_w),
    .PSEL                    (rx_psel_w),
    .PENABLE                 (rx_penable_w),
    .PWRITE                  (rx_pwrite_w),
    .PADDR                   (rx_paddr_w),
    .PWDATA                  (rx_pwdata_w),
    .PRDATA                  (rx_prdata_w),
    .PREADY                  (rx_pready_w),
    .PSLVERR                 (rx_pslverr_w),
    .cbc_iv_i                (dma_iv_w),
    .rx_busy                 (rx_busy_dbg_w),
    .rx_done                 (rx_done_dbg_w),
    .rx_error                (rx_error_dbg_w),
    .aes_ready_out           (rx_aes_ready_out_w),
    .depacker_busy           (rx_depacker_busy_w),
    .depacker_done           (rx_depacker_done_w),
    .depacker_error          (rx_depacker_error_w),
    .parser_busy             (rx_parser_busy_w),
    .parser_block_done       (rx_parser_block_done_w),
    .parser_frame_done       (rx_parser_frame_done_w),
    .parser_error            (rx_parser_error_w),
    .decoder_busy            (rx_decoder_busy_w),
    .decoder_block_done      (rx_decoder_block_done_w),
    .decoder_frame_done      (rx_decoder_frame_done_w),
    .decoder_error           (rx_decoder_error_w),
    .word_packer_busy        (rx_word_packer_busy_w),
    .word_packer_block_done  (rx_word_packer_block_done_w),
    .word_packer_frame_done  (rx_word_packer_frame_done_w),
    .word_packer_error       (rx_word_packer_error_w),
    .transport_word_dbg      (rx_transport_word_dbg_w),
    .transport_word_valid_dbg(rx_transport_word_valid_dbg_w),
    .rx_word_dbg             (rx_word_dbg_w),
    .rx_word_valid_bytes_dbg (rx_word_valid_bytes_dbg_w),
    .rx_word_last_in_block_dbg(rx_word_last_in_block_dbg_w),
    .rx_word_last_in_frame_dbg(rx_word_last_in_frame_dbg_w),
    .rx_word_valid_dbg       (rx_word_valid_dbg_w)
  );
`else
  assign rx_prdata_w = 32'b0;
  assign rx_pready_w = 1'b1;
  assign rx_pslverr_w = 1'b0;
  assign rx_busy_dbg_w = 1'b0;
  assign rx_done_dbg_w = 1'b0;
  assign rx_error_dbg_w = 1'b0;
  assign rx_aes_ready_out_w = 1'b0;
  assign rx_depacker_busy_w = 1'b0;
  assign rx_depacker_done_w = 1'b0;
  assign rx_depacker_error_w = 1'b0;
  assign rx_parser_busy_w = 1'b0;
  assign rx_parser_block_done_w = 1'b0;
  assign rx_parser_frame_done_w = 1'b0;
  assign rx_parser_error_w = 1'b0;
  assign rx_decoder_busy_w = 1'b0;
  assign rx_decoder_block_done_w = 1'b0;
  assign rx_decoder_frame_done_w = 1'b0;
  assign rx_decoder_error_w = 1'b0;
  assign rx_word_packer_busy_w = 1'b0;
  assign rx_word_packer_block_done_w = 1'b0;
  assign rx_word_packer_frame_done_w = 1'b0;
  assign rx_word_packer_error_w = 1'b0;
  assign rx_transport_word_dbg_w = 128'b0;
  assign rx_transport_word_valid_dbg_w = 1'b0;
  assign rx_word_dbg_w = 32'b0;
  assign rx_word_valid_bytes_dbg_w = 3'b0;
  assign rx_word_last_in_block_dbg_w = 1'b0;
  assign rx_word_last_in_frame_dbg_w = 1'b0;
  assign rx_word_valid_dbg_w = 1'b0;
  assign rx_ciphertext_word_ready_unused_w = 1'b0;
`endif

  // CPU MMIO requests go through an APB bridge with ACCESS-only pipeline hold.
  // Pending synchronous loads also carry their response source (DMEM vs MMIO),
  // so readback no longer depends on the instruction currently at MEM input.
  // This path is verified with dma_regfile and should be revalidated when
  // enabling new APB slaves with different wait-state behavior.
  cpu_mmio_to_apb_bridge u_cpu_mmio_to_apb_bridge (
    .clk_i          (clk_i),
    .rst_i          (rst_i),
    .mmio_req_i     (cpu_mmio_sel_w),
    .mmio_write_i   (cpu_mmio_write_w),
    .mmio_addr_i    (dmem_addr_w),
    .mmio_wdata_i   (dmem_wdata_w),
    .mmio_wstrb_i   (dmem_we_w),
    .mmio_rdata_o   (bridge_mmio_rdata_w),
    .mmio_done_o    (bridge_mmio_done_w),
    .mmio_error_o   (bridge_mmio_error_w),
    .mmio_busy_o    (bridge_mmio_busy_w),
    .cpu_stall_req_o(bridge_cpu_stall_req_w),
    .PSEL_o         (bridge_psel_w),
    .PENABLE_o      (bridge_penable_w),
    .PWRITE_o       (bridge_pwrite_w),
    .PADDR_o        (bridge_paddr_w),
    .PWDATA_o       (bridge_pwdata_w),
    .PRDATA_i       (dma_apb_prdata_w),
    .PREADY_i       (dma_apb_pready_w),
    .PSLVERR_i      (dma_apb_pslverr_w)
  );

  dma_regfile u_dma_regfile (
    .PCLK                (clk_i),
    .rst_i               (rst_i),
    .PSEL                (bridge_psel_w),
    .PENABLE             (bridge_penable_w),
    .PWRITE              (bridge_pwrite_w),
    .PADDR               (dma_apb_local_addr_w),
    .PWDATA              (bridge_pwdata_w),
    .PRDATA              (dma_apb_prdata_w),
    .PREADY              (dma_apb_pready_w),
    .PSLVERR             (dma_apb_pslverr_w),
    .src_addr_o          (dma_src_addr_w),
    .dst_addr_o          (dma_dst_addr_w),
    .len_bytes_o         (dma_len_bytes_w),
    .direction_o         (dma_direction_w),
    .compress_only_o     (dma_compress_only_w),
    .whole_file_o        (dma_whole_file_w),
    .iv_o                (dma_iv_w),
    .block_size_o        (dma_block_size_w),
    .start_pulse_o       (dma_start_pulse_w),
    .soft_reset_pulse_o  (dma_soft_reset_pulse_w),
    .clear_done_pulse_o  (dma_clear_done_pulse_w),
    .clear_error_pulse_o (dma_clear_error_pulse_w),
    .dma_busy_i          (dma_engine_busy_w),
    .dma_done_i          (dma_engine_done_w),
    .dma_error_i         (dma_engine_error_w),
    .bytes_done_i        (dma_engine_bytes_done_w),
    .ciphertext_bytes_produced_i(tx_dma_bytes_done_w),
    .last_error_code_i   (dma_engine_last_error_w),
    .engine_state_i      (dma_engine_state_w)
  );

`ifndef FPGA_RX_ONLY
  dma_tx_engine u_dma_tx_engine (
    .clk_i             (clk_i),
    .rst_i             (rst_i),
    .start_i           (dma_start_pulse_w),
    .soft_reset_i      (dma_soft_reset_pulse_w),
    .clear_done_i      (dma_clear_done_pulse_w),
    .clear_error_i     (dma_clear_error_pulse_w),
    .src_addr_i        (dma_src_addr_w),
    .dst_addr_i        (dma_dst_addr_w),
    .len_bytes_i       (dma_len_bytes_w),
    .direction_i       (dma_direction_w),
    .compress_only_i   (dma_compress_only_w),
    .whole_file_i      (dma_whole_file_w),
    .block_size_i      (dma_block_size_w),
    .dmem_en_o         (tx_dma_port_b_en_w),
    .dmem_we_o         (tx_dma_port_b_we_w),
    .dmem_addr_o       (tx_dma_port_b_addr_w),
    .dmem_wdata_o      (tx_dma_port_b_wdata_w),
    .dmem_rdata_i      (dmem_port_b_rdata_w),
    .tx_psel_o         (tx_psel_w),
    .tx_penable_o      (tx_penable_w),
    .tx_pwrite_o       (tx_pwrite_w),
    .tx_paddr_o        (tx_paddr_w),
    .tx_pwdata_o       (tx_pwdata_w),
    .tx_prdata_i       (tx_prdata_w),
    .tx_pready_i       (tx_pready_w),
    .tx_pslverr_i      (tx_pslverr_w),
    .dma_busy_o        (tx_dma_busy_w),
    .dma_done_o        (tx_dma_done_w),
    .dma_error_o       (tx_dma_error_w),
    .bytes_done_o      (tx_dma_bytes_done_w),
    .last_error_code_o (tx_dma_last_error_w),
    .engine_state_o    (tx_dma_state_w)
  );
`else
  assign tx_dma_port_b_en_w = 1'b0;
  assign tx_dma_port_b_we_w = 4'b0000;
  assign tx_dma_port_b_addr_w = 32'b0;
  assign tx_dma_port_b_wdata_w = 32'b0;
  assign tx_psel_w = 1'b0;
  assign tx_penable_w = 1'b0;
  assign tx_pwrite_w = 1'b0;
  assign tx_paddr_w = 32'b0;
  assign tx_pwdata_w = 32'b0;
  assign tx_dma_busy_w = 1'b0;
  assign tx_dma_done_w = 1'b0;
  assign tx_dma_error_w = 1'b0;
  assign tx_dma_bytes_done_w = 32'b0;
  assign tx_dma_last_error_w = 8'b0;
  assign tx_dma_state_w = 4'b0;
`endif

`ifndef FPGA_TX_ONLY
  dma_rx_engine u_dma_rx_engine (
    .clk_i             (clk_i),
    .rst_i             (rst_i),
    .start_i           (dma_start_pulse_w),
    .soft_reset_i      (dma_soft_reset_pulse_w),
    .clear_done_i      (dma_clear_done_pulse_w),
    .clear_error_i     (dma_clear_error_pulse_w),
    .src_addr_i        (dma_src_addr_w),
    .dst_addr_i        (dma_dst_addr_w),
    .len_bytes_i       (dma_len_bytes_w),
    .direction_i       (dma_direction_w),
    .block_size_i      (dma_block_size_w),
    .dmem_en_o         (rx_dma_port_b_en_w),
    .dmem_we_o         (rx_dma_port_b_we_w),
    .dmem_addr_o       (rx_dma_port_b_addr_w),
    .dmem_wdata_o      (rx_dma_port_b_wdata_w),
    .dmem_rdata_i      (dmem_port_b_rdata_w),
    .rx_ciphertext_word_o (rx_ciphertext_word_w),
    .rx_ciphertext_word_valid_o (rx_ciphertext_word_valid_w),
    .rx_ciphertext_word_ready_i (rx_ciphertext_word_ready_unused_w),
    .rx_psel_o         (rx_psel_w),
    .rx_penable_o      (rx_penable_w),
    .rx_pwrite_o       (rx_pwrite_w),
    .rx_paddr_o        (rx_paddr_w),
    .rx_pwdata_o       (rx_pwdata_w),
    .rx_prdata_i       (rx_prdata_w),
    .rx_pready_i       (rx_pready_w),
    .rx_pslverr_i      (rx_pslverr_w),
    .dma_busy_o        (rx_dma_busy_w),
    .dma_done_o        (rx_dma_done_w),
    .dma_error_o       (rx_dma_error_w),
    .bytes_done_o      (rx_dma_bytes_done_w),
    .last_error_code_o (rx_dma_last_error_w),
    .engine_state_o    (rx_dma_state_w)
  );
`else
  assign rx_dma_port_b_en_w = 1'b0;
  assign rx_dma_port_b_we_w = 4'b0000;
  assign rx_dma_port_b_addr_w = 32'b0;
  assign rx_dma_port_b_wdata_w = 32'b0;
  assign rx_ciphertext_word_w = 128'b0;
  assign rx_ciphertext_word_valid_w = 1'b0;
  assign rx_psel_w = 1'b0;
  assign rx_penable_w = 1'b0;
  assign rx_pwrite_w = 1'b0;
  assign rx_paddr_w = 32'b0;
  assign rx_pwdata_w = 32'b0;
  assign rx_dma_busy_w = 1'b0;
  assign rx_dma_done_w = 1'b0;
  assign rx_dma_error_w = 1'b0;
  assign rx_dma_bytes_done_w = 32'b0;
  assign rx_dma_last_error_w = 8'b0;
  assign rx_dma_state_w = 4'b0;
`endif

`ifdef MMIO_DEBUG
  always @(posedge clk_i) begin
    if (!rst_i && dmem_en_w) begin
      $display("[SOC_DMEM] t=%0t we=0x%x addr=0x%08x wdata=0x%08x rdata=0x%08x mmio=%0b hold=%0b",
               $time, dmem_we_w, dmem_addr_w, dmem_wdata_w, dmem_rdata_w, cpu_mmio_sel_w, cpu_global_hold_w);
    end
  end
`endif

endmodule

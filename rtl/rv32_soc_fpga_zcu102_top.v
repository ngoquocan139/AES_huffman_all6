// ZCU102 FPGA demo wrapper for rv32_soc_top.
//
// The ZCU102 USER_SI570 clock enters the PL as a 300 MHz differential clock.
// This wrapper divides it by 6 so the SoC and UART loader keep the existing
// 50 MHz timing/baud assumptions used by rv32_soc_fpga_demo_top.
module rv32_soc_fpga_zcu102_top (
  input  wire       clk_p_i,
  input  wire       clk_n_i,
  input  wire       uart_rx_i,
  output wire       uart_tx_o,
  input  wire       btn_reset_i,
  input  wire       btn_run_i,
  input  wire       btn_zeroize_i,
  input  wire       btn_file_next_i,
  input  wire       btn_file_prev_i,
  input  wire       btn_snapshot_i,
  output wire [7:0] led_o
);

  wire clk_300m_w;
  wire clk_50m_w;

  IBUFDS #(
    .DIFF_TERM    ("FALSE"),
    .IBUF_LOW_PWR ("TRUE"),
    .IOSTANDARD   ("DIFF_SSTL12")
  ) u_user_si570_ibufds (
    .I  (clk_p_i),
    .IB (clk_n_i),
    .O  (clk_300m_w)
  );

  BUFGCE_DIV #(
    .BUFGCE_DIVIDE   (6),
    .IS_CE_INVERTED  (1'b0),
    .IS_CLR_INVERTED (1'b0),
    .IS_I_INVERTED   (1'b0)
  ) u_user_si570_div6 (
    .I   (clk_300m_w),
    .CE  (1'b1),
    .CLR (1'b0),
    .O   (clk_50m_w)
  );

  reg [15:0] por_shift_r = 16'hffff;
  reg [25:0] heartbeat_r = 26'b0;
  reg        btn_reset_meta_r = 1'b0;
  reg        btn_reset_sync_r = 1'b0;
  reg [24:0] loader_activity_cnt_r = 25'b0;
  reg [24:0] tx_activity_cnt_r = 25'b0;
  reg [24:0] rx_activity_cnt_r = 25'b0;
  reg [19:0] soc_release_delay_r = 20'd0;
  reg        tx_done_latched_r = 1'b0;
  reg        rx_done_latched_r = 1'b0;
  reg        error_latched_r = 1'b0;

  localparam [24:0] ACTIVITY_STRETCH_CYCLES = 25'd25000000;
  localparam [19:0] SOC_RELEASE_DELAY_CYCLES = 20'd1000000;

  wire [31:0] aux_rdata_w;
  wire [1:0]  mem_err_w;
  wire        por_rst_w;
  wire        fpga_rst_w;
  wire        soc_rst_w;
  wire        use_loader_aux_w;
  wire        soc_aux_en_w;
  wire [3:0]  soc_aux_we_w;
  wire [31:0] soc_aux_addr_w;
  wire [31:0] soc_aux_wdata_w;
  wire        loader_aux_en_w;
  wire [3:0]  loader_aux_we_w;
  wire [31:0] loader_aux_addr_w;
  wire [31:0] loader_aux_wdata_w;
  wire        button_aux_en_w;
  wire [3:0]  button_aux_we_w;
  wire [31:0] button_aux_addr_w;
  wire [31:0] button_aux_wdata_w;
  wire        loader_busy_w;
  wire        loader_done_w;
  wire        loader_error_w;
  wire [31:0] loader_bytes_loaded_w;
  wire        button_busy_w;
  wire        button_soc_hold_w;
  wire        run_latched_w;
  wire        zeroize_done_w;
  wire        snapshot_valid_w;
  wire [31:0] selected_file_id_w;
  wire        tx_dma_busy_w;
  wire        tx_dma_done_w;
  wire        tx_dma_error_w;
  wire        rx_dma_busy_w;
  wire        rx_dma_done_w;
  wire        rx_dma_error_w;
  wire        imem_program_seen_w;
  wire        heartbeat_led_w;
  wire        led_blink_w;
  wire        loader_activity_w;
  wire        tx_activity_w;
  wire        rx_activity_w;
  wire        file_id_bit0_led_w;
  wire        file_id_bit1_led_w;
  wire        soc_release_delay_active_w;
  wire        unused_loader_status_w;
  wire [31:0] cpu_debug_status_w;
  wire [31:0] cpu_debug_fetch_pc_w;
  wire [31:0] cpu_debug_fetch_instr_w;
  wire [31:0] cpu_debug_cycle_count_w;
  wire [31:0] cpu_debug_fetch_count_w;
  wire [31:0] cpu_debug_dmem_access_count_w;
  wire [31:0] cpu_debug_mmio_access_count_w;
  wire [31:0] cpu_debug_last_dmem_addr_w;
  wire [31:0] cpu_debug_last_dmem_wdata_w;
  wire [31:0] cpu_debug_last_dmem_ctrl_w;
  wire [31:0] cpu_debug_wb_count_w;
  wire [31:0] cpu_debug_last_wb_info_w;
  wire [31:0] cpu_debug_last_wb_data_w;
  wire [31:0] perf_tx_dma_cycles_w;
  wire [31:0] perf_rx_dma_cycles_w;
  wire [31:0] perf_tx_huffman_cycles_w;
  wire [31:0] perf_tx_aes_cycles_w;
  wire [31:0] perf_rx_huffman_cycles_w;
  wire [31:0] perf_rx_aes_cycles_w;

  assign por_rst_w = |por_shift_r;
  assign fpga_rst_w = por_rst_w | btn_reset_sync_r;
  assign soc_release_delay_active_w = (soc_release_delay_r != 20'd0);
  assign soc_rst_w = fpga_rst_w | (!loader_done_w) | soc_release_delay_active_w |
                     (!run_latched_w) | button_soc_hold_w;
  assign use_loader_aux_w = loader_busy_w | loader_aux_en_w;
  assign soc_aux_en_w = use_loader_aux_w ? loader_aux_en_w : button_aux_en_w;
  assign soc_aux_we_w = use_loader_aux_w ? loader_aux_we_w : button_aux_we_w;
  assign soc_aux_addr_w = use_loader_aux_w ? loader_aux_addr_w : button_aux_addr_w;
  assign soc_aux_wdata_w = use_loader_aux_w ? loader_aux_wdata_w : button_aux_wdata_w;

  always @(posedge clk_50m_w) begin
    btn_reset_meta_r <= btn_reset_i;
    btn_reset_sync_r <= btn_reset_meta_r;

    if (btn_reset_sync_r) begin
      por_shift_r <= 16'hffff;
      heartbeat_r <= 26'b0;
      loader_activity_cnt_r <= 25'b0;
      tx_activity_cnt_r <= 25'b0;
      rx_activity_cnt_r <= 25'b0;
      soc_release_delay_r <= SOC_RELEASE_DELAY_CYCLES;
      tx_done_latched_r <= 1'b0;
      rx_done_latched_r <= 1'b0;
      error_latched_r <= 1'b0;
    end else if (por_rst_w) begin
      por_shift_r <= {por_shift_r[14:0], 1'b0};
      heartbeat_r <= 26'b0;
      loader_activity_cnt_r <= 25'b0;
      tx_activity_cnt_r <= 25'b0;
      rx_activity_cnt_r <= 25'b0;
      soc_release_delay_r <= SOC_RELEASE_DELAY_CYCLES;
      tx_done_latched_r <= 1'b0;
      rx_done_latched_r <= 1'b0;
      error_latched_r <= 1'b0;
    end else begin
      heartbeat_r <= heartbeat_r + 26'd1;

      if (!loader_done_w)
        soc_release_delay_r <= SOC_RELEASE_DELAY_CYCLES;
      else if (soc_release_delay_r != 20'd0)
        soc_release_delay_r <= soc_release_delay_r - 20'd1;

      if (loader_busy_w)
        loader_activity_cnt_r <= ACTIVITY_STRETCH_CYCLES;
      else if (loader_activity_cnt_r != 25'b0)
        loader_activity_cnt_r <= loader_activity_cnt_r - 25'd1;

      if (tx_dma_busy_w)
        tx_activity_cnt_r <= ACTIVITY_STRETCH_CYCLES;
      else if (tx_activity_cnt_r != 25'b0)
        tx_activity_cnt_r <= tx_activity_cnt_r - 25'd1;

      if (rx_dma_busy_w)
        rx_activity_cnt_r <= ACTIVITY_STRETCH_CYCLES;
      else if (rx_activity_cnt_r != 25'b0)
        rx_activity_cnt_r <= rx_activity_cnt_r - 25'd1;

      if (tx_dma_done_w)
        tx_done_latched_r <= 1'b1;
      if (rx_dma_done_w)
        rx_done_latched_r <= 1'b1;
      if (loader_error_w || tx_dma_error_w || rx_dma_error_w || (|mem_err_w))
        error_latched_r <= 1'b1;
    end
  end

  assign heartbeat_led_w = heartbeat_r[25];
  assign led_blink_w = heartbeat_r[23];
  assign loader_activity_w = (loader_activity_cnt_r != 25'b0);
  assign tx_activity_w = (tx_activity_cnt_r != 25'b0);
  assign rx_activity_w = (rx_activity_cnt_r != 25'b0);
  assign file_id_bit0_led_w = selected_file_id_w[0];
  assign file_id_bit1_led_w = selected_file_id_w[1];

  assign led_o[0] = heartbeat_led_w;
  assign led_o[1] = imem_program_seen_w;
  assign led_o[2] = loader_activity_w ? led_blink_w : loader_done_w;
  assign led_o[3] = tx_activity_w ? led_blink_w : tx_done_latched_r;
  assign led_o[4] = rx_activity_w ? led_blink_w : rx_done_latched_r;
  assign led_o[5] = error_latched_r;
  assign led_o[6] = file_id_bit0_led_w;
  assign led_o[7] = file_id_bit1_led_w;
  assign unused_loader_status_w = (|loader_bytes_loaded_w) | (^aux_rdata_w) |
                                  run_latched_w | button_busy_w |
                                  zeroize_done_w | snapshot_valid_w;

  uart_dmem_loader #(
    .CLK_HZ          (50000000),
    .BAUD_RATE       (115200),
    .SRC_BASE_ADDR   (32'h0000_0800),
    .INPUT_LEN_ADDR  (32'h0000_0040),
    .MAX_INPUT_BYTES (12288),
    .MAX_READ_BYTES  (32768)
  ) u_uart_dmem_loader (
    .clk_i           (clk_50m_w),
    .rst_i           (fpga_rst_w),
    .uart_rx_i       (uart_rx_i),
    .uart_tx_o       (uart_tx_o),
    .aux_rdata_i     (aux_rdata_w),
    .aux_en_o        (loader_aux_en_w),
    .aux_we_o        (loader_aux_we_w),
    .aux_addr_o      (loader_aux_addr_w),
    .aux_wdata_o     (loader_aux_wdata_w),
    .busy_o          (loader_busy_w),
    .done_o          (loader_done_w),
    .error_o         (loader_error_w),
    .bytes_loaded_o  (loader_bytes_loaded_w),
    .cpu_debug_status_i(cpu_debug_status_w),
    .cpu_debug_fetch_pc_i(cpu_debug_fetch_pc_w),
    .cpu_debug_fetch_instr_i(cpu_debug_fetch_instr_w),
    .cpu_debug_cycle_count_i(cpu_debug_cycle_count_w),
    .cpu_debug_fetch_count_i(cpu_debug_fetch_count_w),
    .cpu_debug_dmem_access_count_i(cpu_debug_dmem_access_count_w),
    .cpu_debug_mmio_access_count_i(cpu_debug_mmio_access_count_w),
    .cpu_debug_last_dmem_addr_i(cpu_debug_last_dmem_addr_w),
    .cpu_debug_last_dmem_wdata_i(cpu_debug_last_dmem_wdata_w),
    .cpu_debug_last_dmem_ctrl_i(cpu_debug_last_dmem_ctrl_w),
    .cpu_debug_wb_count_i(cpu_debug_wb_count_w),
    .cpu_debug_last_wb_info_i(cpu_debug_last_wb_info_w),
    .cpu_debug_last_wb_data_i(cpu_debug_last_wb_data_w),
    .perf_tx_dma_cycles_i(perf_tx_dma_cycles_w),
    .perf_rx_dma_cycles_i(perf_rx_dma_cycles_w),
    .perf_tx_huffman_cycles_i(perf_tx_huffman_cycles_w),
    .perf_tx_aes_cycles_i(perf_tx_aes_cycles_w),
    .perf_rx_huffman_cycles_i(perf_rx_huffman_cycles_w),
    .perf_rx_aes_cycles_i(perf_rx_aes_cycles_w)
  );

  fpga_button_board_ctrl #(
    .DEBOUNCE_CYCLES    (500000),
    .BOARD_STATUS_ADDR  (32'h0000_0050),
    .BOARD_FILE_ID_ADDR (32'h0000_0054),
    .BOARD_EVENT_ADDR   (32'h0000_0058),
    .BOARD_SNAPSHOT_ADDR(32'h0000_0200),
    .BOARD_SNAPSHOT_META(32'h0000_0240),
    .RESULT_BASE_ADDR   (32'h0000_0000),
    .RESULT_WORDS       (16),
    .ZEROIZE_BASE_ADDR  (32'h0000_0100),
    .ZEROIZE_WORDS      (8128),
    .FILE_ID_A          (32'd1),
    .FILE_ID_B          (32'd2),
    .FILE_ID_C          (32'd3)
  ) u_fpga_button_board_ctrl (
    .clk_i             (clk_50m_w),
    .rst_i             (fpga_rst_w),
    .btn_run_i         (btn_run_i),
    .btn_zeroize_i     (btn_zeroize_i),
    .btn_file_next_i   (btn_file_next_i),
    .btn_file_prev_i   (btn_file_prev_i),
    .btn_snapshot_i    (btn_snapshot_i),
    .loader_done_i     (loader_done_w),
    .loader_busy_i     (loader_busy_w),
    .aux_rdata_i       (aux_rdata_w),
    .aux_en_o          (button_aux_en_w),
    .aux_we_o          (button_aux_we_w),
    .aux_addr_o        (button_aux_addr_w),
    .aux_wdata_o       (button_aux_wdata_w),
    .busy_o            (button_busy_w),
    .soc_hold_o        (button_soc_hold_w),
    .run_latched_o     (run_latched_w),
    .zeroize_done_o    (zeroize_done_w),
    .snapshot_valid_o  (snapshot_valid_w),
    .selected_file_id_o(selected_file_id_w)
  );

  (* DONT_TOUCH = "yes" *) rv32_soc_top u_soc (
    .clk_i          (clk_50m_w),
    .rst_i          (soc_rst_w),
    .aux_en_i       (soc_aux_en_w),
    .aux_we_i       (soc_aux_we_w),
    .aux_addr_i     (soc_aux_addr_w),
    .aux_wdata_i    (soc_aux_wdata_w),
    .aux_rdata_o    (aux_rdata_w),
    .cpu_if_flush_i (1'b0),
    .cpu_stall_i    (1'b0),
    .mem_err_o      (mem_err_w),
    .tx_dma_busy_o  (tx_dma_busy_w),
    .tx_dma_done_o  (tx_dma_done_w),
    .tx_dma_error_o (tx_dma_error_w),
    .rx_dma_busy_o  (rx_dma_busy_w),
    .rx_dma_done_o  (rx_dma_done_w),
    .rx_dma_error_o (rx_dma_error_w),
    .imem_program_seen_o(imem_program_seen_w),
    .cpu_debug_status_o(cpu_debug_status_w),
    .cpu_debug_fetch_pc_o(cpu_debug_fetch_pc_w),
    .cpu_debug_fetch_instr_o(cpu_debug_fetch_instr_w),
    .cpu_debug_cycle_count_o(cpu_debug_cycle_count_w),
    .cpu_debug_fetch_count_o(cpu_debug_fetch_count_w),
    .cpu_debug_dmem_access_count_o(cpu_debug_dmem_access_count_w),
    .cpu_debug_mmio_access_count_o(cpu_debug_mmio_access_count_w),
    .cpu_debug_last_dmem_addr_o(cpu_debug_last_dmem_addr_w),
    .cpu_debug_last_dmem_wdata_o(cpu_debug_last_dmem_wdata_w),
    .cpu_debug_last_dmem_ctrl_o(cpu_debug_last_dmem_ctrl_w),
    .cpu_debug_wb_count_o(cpu_debug_wb_count_w),
    .cpu_debug_last_wb_info_o(cpu_debug_last_wb_info_w),
    .cpu_debug_last_wb_data_o(cpu_debug_last_wb_data_w),
    .perf_tx_dma_cycles_o(perf_tx_dma_cycles_w),
    .perf_rx_dma_cycles_o(perf_rx_dma_cycles_w),
    .perf_tx_huffman_cycles_o(perf_tx_huffman_cycles_w),
    .perf_tx_aes_cycles_o(perf_tx_aes_cycles_w),
    .perf_rx_huffman_cycles_o(perf_rx_huffman_cycles_w),
    .perf_rx_aes_cycles_o(perf_rx_aes_cycles_w)
  );

endmodule

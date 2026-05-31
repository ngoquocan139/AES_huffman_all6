// FPGA demo wrapper for rv32_soc_top.
//
// This wrapper keeps the simulation/integration top unchanged while providing
// a board-friendly top level for bitstream generation. A small UART loader
// preloads DMEM source bytes before the CPU is released from reset.
module rv32_soc_fpga_demo_top (
  input  wire       clk_i,
  input  wire       uart_rx_i,
  output wire       uart_tx_o,
  output wire [3:0] led_o
);

  reg [15:0] por_shift_r = 16'hffff;
  reg [25:0] heartbeat_r = 26'b0;
  reg [24:0] loader_activity_cnt_r = 25'b0;
  reg [24:0] dma_activity_cnt_r = 25'b0;
  reg        dma_done_latched_r = 1'b0;
  reg        error_latched_r = 1'b0;

  localparam [24:0] ACTIVITY_STRETCH_CYCLES = 25'd25000000;

  wire [31:0] aux_rdata_w;
  wire [1:0]  mem_err_w;
  wire        por_rst_w;
  wire        soc_rst_w;
  wire        loader_aux_en_w;
  wire [3:0]  loader_aux_we_w;
  wire [31:0] loader_aux_addr_w;
  wire [31:0] loader_aux_wdata_w;
  wire        loader_busy_w;
  wire        loader_done_w;
  wire        loader_error_w;
  wire [31:0] loader_bytes_loaded_w;
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
  wire        dma_activity_w;
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

  assign por_rst_w = |por_shift_r;
  assign soc_rst_w = por_rst_w | (!loader_done_w);

  always @(posedge clk_i) begin
    if (por_rst_w) begin
      por_shift_r <= {por_shift_r[14:0], 1'b0};
      heartbeat_r <= 26'b0;
      loader_activity_cnt_r <= 25'b0;
      dma_activity_cnt_r <= 25'b0;
      dma_done_latched_r <= 1'b0;
      error_latched_r <= 1'b0;
    end else begin
      heartbeat_r <= heartbeat_r + 26'd1;

      if (loader_busy_w)
        loader_activity_cnt_r <= ACTIVITY_STRETCH_CYCLES;
      else if (loader_activity_cnt_r != 25'b0)
        loader_activity_cnt_r <= loader_activity_cnt_r - 25'd1;

      if (tx_dma_busy_w || rx_dma_busy_w)
        dma_activity_cnt_r <= ACTIVITY_STRETCH_CYCLES;
      else if (dma_activity_cnt_r != 25'b0)
        dma_activity_cnt_r <= dma_activity_cnt_r - 25'd1;

      if (tx_dma_done_w || rx_dma_done_w)
        dma_done_latched_r <= 1'b1;
      if (loader_error_w || tx_dma_error_w || rx_dma_error_w || (|mem_err_w))
        error_latched_r <= 1'b1;
    end
  end

  assign heartbeat_led_w = heartbeat_r[25];
  assign led_blink_w = heartbeat_r[23];
  assign loader_activity_w = (loader_activity_cnt_r != 25'b0);
  assign dma_activity_w = (dma_activity_cnt_r != 25'b0);

  assign led_o[0] = heartbeat_led_w;
  assign led_o[1] = imem_program_seen_w;
  assign led_o[2] = (loader_activity_w || dma_activity_w) ? led_blink_w :
                    (loader_done_w || dma_done_latched_r);
  assign led_o[3] = error_latched_r;
  assign unused_loader_status_w = (|loader_bytes_loaded_w) | (^aux_rdata_w);

  uart_dmem_loader #(
    .CLK_HZ          (50000000),
    .BAUD_RATE       (115200),
    .SRC_BASE_ADDR   (32'h0000_2000),
    .INPUT_LEN_ADDR  (32'h0000_0040),
    .MAX_INPUT_BYTES (7168),
    .MAX_READ_BYTES  (32768)
  ) u_uart_dmem_loader (
    .clk_i           (clk_i),
    .rst_i           (por_rst_w),
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
    .cpu_debug_last_wb_data_i(cpu_debug_last_wb_data_w)
  );

  (* DONT_TOUCH = "yes" *) rv32_soc_top u_soc (
    .clk_i          (clk_i),
    .rst_i          (soc_rst_w),
    .aux_en_i       (loader_aux_en_w),
    .aux_we_i       (loader_aux_we_w),
    .aux_addr_i     (loader_aux_addr_w),
    .aux_wdata_i    (loader_aux_wdata_w),
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
    .cpu_debug_last_wb_data_o(cpu_debug_last_wb_data_w)
  );

endmodule

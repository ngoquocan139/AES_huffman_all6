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
  wire        unused_loader_status_w;

  assign por_rst_w = |por_shift_r;
  assign soc_rst_w = por_rst_w | (!loader_done_w);

  always @(posedge clk_i) begin
    if (por_rst_w) begin
      por_shift_r <= {por_shift_r[14:0], 1'b0};
      heartbeat_r <= 26'b0;
    end else begin
      heartbeat_r <= heartbeat_r + 26'd1;
    end
  end

  assign led_o[0] = heartbeat_r[25];
  assign led_o[1] = loader_busy_w;
  assign led_o[2] = loader_done_w;
  assign led_o[3] = loader_error_w | (|mem_err_w);
  assign unused_loader_status_w = (|loader_bytes_loaded_w) | (^aux_rdata_w);

  uart_dmem_loader #(
    .CLK_HZ          (50000000),
    .BAUD_RATE       (115200),
    .SRC_BASE_ADDR   (32'h0000_0400),
    .INPUT_LEN_ADDR  (32'h0000_0040),
    .MAX_INPUT_BYTES (7168)
  ) u_uart_dmem_loader (
    .clk_i           (clk_i),
    .rst_i           (por_rst_w),
    .uart_rx_i       (uart_rx_i),
    .uart_tx_o       (uart_tx_o),
    .aux_en_o        (loader_aux_en_w),
    .aux_we_o        (loader_aux_we_w),
    .aux_addr_o      (loader_aux_addr_w),
    .aux_wdata_o     (loader_aux_wdata_w),
    .busy_o          (loader_busy_w),
    .done_o          (loader_done_w),
    .error_o         (loader_error_w),
    .bytes_loaded_o  (loader_bytes_loaded_w)
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
    .mem_err_o      (mem_err_w)
  );

endmodule

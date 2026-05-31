`timescale 1ns/1ps

module tb_uart_dmem_loader;
  localparam integer CLK_HZ = 100000000;
  localparam integer BAUD_RATE = 1000000;
  localparam integer BIT_NS = 1000000000 / BAUD_RATE;

  reg clk = 1'b0;
  reg rst = 1'b1;
  reg uart_rx = 1'b1;
  wire uart_tx;
  wire [31:0] aux_rdata;
  wire aux_en;
  wire [3:0] aux_we;
  wire [31:0] aux_addr;
  wire [31:0] aux_wdata;
  wire busy;
  wire done;
  wire error;
  wire [31:0] bytes_loaded;

  reg [31:0] mem [0:8191];
  reg [31:0] aux_rdata_r = 32'd0;
  reg [7:0] rx_fifo [0:31];
  integer rx_wr = 0;
  integer rx_rd = 0;
  assign aux_rdata = aux_rdata_r;

  always #5 clk = ~clk;

  always @(posedge clk) begin
    if (aux_en) begin
      aux_rdata_r <= mem[aux_addr[14:2]];
      if (aux_we[0]) mem[aux_addr[14:2]][7:0]   <= aux_wdata[7:0];
      if (aux_we[1]) mem[aux_addr[14:2]][15:8]  <= aux_wdata[15:8];
      if (aux_we[2]) mem[aux_addr[14:2]][23:16] <= aux_wdata[23:16];
      if (aux_we[3]) mem[aux_addr[14:2]][31:24] <= aux_wdata[31:24];
    end
  end

  uart_dmem_loader #(
    .CLK_HZ(CLK_HZ),
    .BAUD_RATE(BAUD_RATE),
    .SRC_BASE_ADDR(32'h0000_2000),
    .INPUT_LEN_ADDR(32'h0000_0040),
    .MAX_INPUT_BYTES(7168),
    .MAX_READ_BYTES(32768)
  ) dut (
    .clk_i(clk),
    .rst_i(rst),
    .uart_rx_i(uart_rx),
    .uart_tx_o(uart_tx),
    .aux_rdata_i(aux_rdata),
    .aux_en_o(aux_en),
    .aux_we_o(aux_we),
    .aux_addr_o(aux_addr),
    .aux_wdata_o(aux_wdata),
    .busy_o(busy),
    .done_o(done),
    .error_o(error),
    .bytes_loaded_o(bytes_loaded),
    .cpu_debug_status_i(32'h0000_0005),
    .cpu_debug_fetch_pc_i(32'h0000_0120),
    .cpu_debug_fetch_instr_i(32'h0010_0113),
    .cpu_debug_cycle_count_i(32'd1234),
    .cpu_debug_fetch_count_i(32'd99),
    .cpu_debug_dmem_access_count_i(32'd7),
    .cpu_debug_mmio_access_count_i(32'd3),
    .cpu_debug_last_dmem_addr_i(32'h4000_0004),
    .cpu_debug_last_dmem_wdata_i(32'hdead_beef),
    .cpu_debug_last_dmem_ctrl_i(32'h0000_001f),
    .cpu_debug_wb_count_i(32'd42),
    .cpu_debug_last_wb_info_i(32'h0000_000a),
    .cpu_debug_last_wb_data_i(32'h1234_5678)
  );

  task send_byte;
    input [7:0] data;
    integer bit_idx;
    begin
      uart_rx = 1'b0;
      #(BIT_NS);
      for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
        uart_rx = data[bit_idx];
        #(BIT_NS);
      end
      uart_rx = 1'b1;
      #(BIT_NS);
      #(BIT_NS);
    end
  endtask

  task recv_byte;
    output [7:0] data;
    begin
      while (rx_rd == rx_wr) @(posedge clk);
      data = rx_fifo[rx_rd & 31];
      rx_rd = rx_rd + 1;
    end
  endtask

  initial begin : uart_tx_monitor
    integer bit_idx;
    reg [7:0] data;
    forever begin
      @(negedge uart_tx);
      #(BIT_NS + (BIT_NS / 2));
      for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
        data[bit_idx] = uart_tx;
        #(BIT_NS);
      end
      rx_fifo[rx_wr & 31] = data;
      rx_wr = rx_wr + 1;
      #(BIT_NS / 2);
    end
  end

  initial begin : sim_timeout
    #10000000;
    $display("UART loader READ smoke TIMEOUT");
    $finish;
  end


  task expect_byte;
    input [7:0] expected;
    reg [7:0] got;
    begin
      recv_byte(got);
      if (got !== expected) begin
        $display("expected 0x%02x got 0x%02x", expected, got);
        $fflush();
        $fatal;
      end
    end
  endtask

  initial begin
    repeat (20) @(posedge clk);
    rst = 1'b0;
    repeat (20) @(posedge clk);

    send_byte("L");
    send_byte("O");
    send_byte("A");
    send_byte("D");
    send_byte(8'd4);
    send_byte(8'd0);
    send_byte(8'd0);
    send_byte(8'd0);
    send_byte(8'h11);
    send_byte(8'h22);
    send_byte(8'h33);
    send_byte(8'h44);
    expect_byte(8'h79);

    if (!done || error || (bytes_loaded != 32'd4)) begin
      $display("LOAD status failed done=%0d error=%0d bytes=%0d", done, error, bytes_loaded);
      $fatal;
    end

    send_byte("R");
    send_byte("E");
    send_byte("A");
    send_byte("D");
    send_byte(8'h40);
    send_byte(8'h00);
    send_byte(8'h00);
    send_byte(8'h00);
    send_byte(8'h04);
    send_byte(8'h00);
    send_byte(8'h00);
    send_byte(8'h00);
    expect_byte(8'h79);
    expect_byte(8'h04);
    expect_byte(8'h00);
    expect_byte(8'h00);
    expect_byte(8'h00);

    send_byte("R");
    send_byte("E");
    send_byte("A");
    send_byte("D");
    send_byte(8'h00);
    send_byte(8'h20);
    send_byte(8'h00);
    send_byte(8'h00);
    send_byte(8'h04);
    send_byte(8'h00);
    send_byte(8'h00);
    send_byte(8'h00);
    expect_byte(8'h79);
    expect_byte(8'h11);
    expect_byte(8'h22);
    expect_byte(8'h33);
    expect_byte(8'h44);

    send_byte("R");
    send_byte("E");
    send_byte("A");
    send_byte("D");
    send_byte(8'h80);
    send_byte(8'h7f);
    send_byte(8'h00);
    send_byte(8'h00);
    send_byte(8'h10);
    send_byte(8'h00);
    send_byte(8'h00);
    send_byte(8'h00);
    expect_byte(8'h79);
    expect_byte(8'h43);
    expect_byte(8'h50);
    expect_byte(8'h55);
    expect_byte(8'h31);
    expect_byte(8'h05);
    expect_byte(8'h00);
    expect_byte(8'h00);
    expect_byte(8'h00);
    expect_byte(8'h20);
    expect_byte(8'h01);
    expect_byte(8'h00);
    expect_byte(8'h00);
    expect_byte(8'h13);
    expect_byte(8'h01);
    expect_byte(8'h10);
    expect_byte(8'h00);

    $display("UART loader READ smoke PASS");
    $finish;
  end
endmodule

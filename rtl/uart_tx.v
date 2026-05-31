module uart_tx #(
  parameter integer DATA_BITS = 8
) (
  input  wire                 clk_i,
  input  wire                 rst_i,
  input  wire [DATA_BITS-1:0] data_i,
  input  wire                 data_valid_i,
  output wire                 data_ready_o,
  output wire                 txd_o,
  output wire                 busy_o,
  input  wire [15:0]          prescale_i
);

  reg                        ready_r;
  reg                        txd_r;
  reg                        busy_r;
  reg [DATA_BITS:0]          shift_r;
  reg [7:0]                  bit_cnt_r;
  reg [18:0]                 baud_cnt_r;

  localparam [7:0] FRAME_BITS_W = DATA_BITS + 1;
  wire [18:0] prescale_w = (prescale_i == 16'd0) ? 19'd1 : {3'b000, prescale_i};

  assign data_ready_o = ready_r && !data_valid_i;
  assign txd_o        = txd_r;
  assign busy_o       = busy_r;

  always @(posedge clk_i) begin
    if (rst_i) begin
      ready_r    <= 1'b1;
      txd_r      <= 1'b1;
      busy_r     <= 1'b0;
      shift_r    <= {(DATA_BITS + 1){1'b0}};
      bit_cnt_r  <= 8'd0;
      baud_cnt_r <= 19'd0;
    end else if (!busy_r) begin
      ready_r <= 1'b1;
      txd_r   <= 1'b1;
      if (data_valid_i) begin
        ready_r    <= 1'b0;
        txd_r      <= 1'b0;
        busy_r     <= 1'b1;
        shift_r    <= {1'b1, data_i};
        bit_cnt_r  <= FRAME_BITS_W;
        baud_cnt_r <= prescale_w - 19'd1;
      end
    end else if (baud_cnt_r != 19'd0) begin
      baud_cnt_r <= baud_cnt_r - 19'd1;
    end else if (bit_cnt_r != 8'd0) begin
      txd_r      <= shift_r[0];
      shift_r    <= {1'b1, shift_r[DATA_BITS:1]};
      baud_cnt_r <= prescale_w - 19'd1;
      bit_cnt_r  <= bit_cnt_r - 8'd1;
    end else begin
      txd_r    <= 1'b1;
      busy_r   <= 1'b0;
      ready_r  <= 1'b1;
    end
  end

endmodule

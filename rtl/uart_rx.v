module uart_rx #(
  parameter integer DATA_BITS = 8
) (
  input  wire                   clk_i,
  input  wire                   rst_i,
  input  wire                   rxd_i,
  input  wire [15:0]            prescale_i,
  output reg  [DATA_BITS-1:0]   data_o,
  output reg                    data_valid_o,
  output wire                   busy_o
);

  localparam [1:0] ST_IDLE  = 2'd0;
  localparam [1:0] ST_START = 2'd1;
  localparam [1:0] ST_DATA  = 2'd2;
  localparam [1:0] ST_STOP  = 2'd3;

  reg [1:0]                 state_r;
  reg [15:0]                baud_cnt_r;
  reg [2:0]                 bit_idx_r;
  reg [DATA_BITS-1:0]       shift_r;
  reg                       rxd_meta_r;
  reg                       rxd_sync_r;

  localparam [2:0] LAST_BIT_IDX_W = DATA_BITS - 1;
  wire [15:0] prescale_w = (prescale_i == 16'd0) ? 16'd1 : prescale_i;

  assign busy_o = (state_r != ST_IDLE);

  always @(posedge clk_i) begin
    if (rst_i) begin
      state_r      <= ST_IDLE;
      baud_cnt_r   <= 16'd0;
      bit_idx_r    <= 3'd0;
      shift_r      <= {DATA_BITS{1'b0}};
      data_o       <= {DATA_BITS{1'b0}};
      data_valid_o <= 1'b0;
      rxd_meta_r   <= 1'b1;
      rxd_sync_r   <= 1'b1;
    end else begin
      rxd_meta_r   <= rxd_i;
      rxd_sync_r   <= rxd_meta_r;
      data_valid_o <= 1'b0;

      case (state_r)
        ST_IDLE: begin
          if (!rxd_sync_r) begin
            state_r    <= ST_START;
            baud_cnt_r <= (prescale_w >> 1);
          end
        end

        ST_START: begin
          if (baud_cnt_r != 16'd0) begin
            baud_cnt_r <= baud_cnt_r - 16'd1;
          end else if (!rxd_sync_r) begin
            state_r    <= ST_DATA;
            baud_cnt_r <= prescale_w - 16'd1;
            bit_idx_r  <= 3'd0;
          end else begin
            state_r <= ST_IDLE;
          end
        end

        ST_DATA: begin
          if (baud_cnt_r != 16'd0) begin
            baud_cnt_r <= baud_cnt_r - 16'd1;
          end else begin
            shift_r[bit_idx_r] <= rxd_sync_r;
            baud_cnt_r         <= prescale_w - 16'd1;
            if (bit_idx_r == LAST_BIT_IDX_W) begin
              state_r <= ST_STOP;
            end else begin
              bit_idx_r <= bit_idx_r + 3'd1;
            end
          end
        end

        ST_STOP: begin
          if (baud_cnt_r != 16'd0) begin
            baud_cnt_r <= baud_cnt_r - 16'd1;
          end else begin
            if (rxd_sync_r) begin
              data_o       <= shift_r;
              data_valid_o <= 1'b1;
            end
            state_r <= ST_IDLE;
          end
        end

        default: begin
          state_r <= ST_IDLE;
        end
      endcase
    end
  end

endmodule

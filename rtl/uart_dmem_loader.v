module uart_dmem_loader #(
  parameter integer CLK_HZ          = 50000000,
  parameter integer BAUD_RATE       = 115200,
  parameter [31:0]  SRC_BASE_ADDR   = 32'h0000_2000,
  parameter [31:0]  INPUT_LEN_ADDR  = 32'h0000_0040,
  parameter integer MAX_INPUT_BYTES = 7168
) (
  input  wire        clk_i,
  input  wire        rst_i,
  input  wire        uart_rx_i,
  output wire        uart_tx_o,
  output reg         aux_en_o,
  output reg  [3:0]  aux_we_o,
  output reg  [31:0] aux_addr_o,
  output reg  [31:0] aux_wdata_o,
  output wire        busy_o,
  output wire        done_o,
  output wire        error_o,
  output wire [31:0] bytes_loaded_o
);

  localparam [7:0] MAGIC0 = 8'h4c; // 'L'
  localparam [7:0] MAGIC1 = 8'h4f; // 'O'
  localparam [7:0] MAGIC2 = 8'h41; // 'A'
  localparam [7:0] MAGIC3 = 8'h44; // 'D'
  localparam [7:0] ACK_OK = 8'h79;
  localparam [7:0] ACK_ERR = 8'h1f;

  localparam [3:0] ST_MAGIC0        = 4'd0;
  localparam [3:0] ST_MAGIC1        = 4'd1;
  localparam [3:0] ST_MAGIC2        = 4'd2;
  localparam [3:0] ST_MAGIC3        = 4'd3;
  localparam [3:0] ST_LEN0          = 4'd4;
  localparam [3:0] ST_LEN1          = 4'd5;
  localparam [3:0] ST_LEN2          = 4'd6;
  localparam [3:0] ST_LEN3          = 4'd7;
  localparam [3:0] ST_PAYLOAD       = 4'd8;
  localparam [3:0] ST_WRITE_PAYLOAD = 4'd9;
  localparam [3:0] ST_WRITE_LEN     = 4'd10;
  localparam [3:0] ST_SEND_ACK      = 4'd11;
  localparam [3:0] ST_SEND_ERR      = 4'd12;
  localparam [3:0] ST_DONE          = 4'd13;
  localparam [3:0] ST_ERROR         = 4'd14;

  localparam integer UART_PRESCALE_INT = (CLK_HZ / BAUD_RATE);
  localparam [15:0] UART_PRESCALE_W = (UART_PRESCALE_INT <= 0) ? 16'd1 :
                                      (UART_PRESCALE_INT > 65535) ? 16'hffff :
                                      UART_PRESCALE_INT[15:0];

  reg [3:0]  state_r;
  reg [31:0] payload_len_r;
  reg [31:0] payload_rem_r;
  reg [31:0] bytes_loaded_r;
  reg [31:0] curr_word_addr_r;
  reg [1:0]  curr_lane_r;
  reg [31:0] pack_word_r;
  reg [3:0]  pack_we_r;
  reg [31:0] pending_addr_r;
  reg [31:0] pending_data_r;
  reg [3:0]  pending_we_r;
  reg [7:0]  tx_byte_r;
  reg        tx_valid_r;
  reg        done_r;
  reg        error_r;
  reg [31:0] merged_word_v;
  reg [3:0]  merged_we_v;
  reg [31:0] next_rem_v;
  reg [31:0] candidate_len_v;

  wire [7:0] rx_byte_w;
  wire       rx_valid_w;
  wire       rx_busy_unused_w;
  wire       tx_ready_w;
  wire       tx_busy_unused_w;

  function [31:0] insert_byte32;
    input [31:0] word_i;
    input [1:0]  lane_i;
    input [7:0]  byte_i;
    begin
      insert_byte32 = word_i;
      case (lane_i)
        2'd0: insert_byte32[7:0]   = byte_i;
        2'd1: insert_byte32[15:8]  = byte_i;
        2'd2: insert_byte32[23:16] = byte_i;
        default: insert_byte32[31:24] = byte_i;
      endcase
    end
  endfunction

  function [3:0] lane_mask;
    input [1:0] lane_i;
    begin
      case (lane_i)
        2'd0: lane_mask = 4'b0001;
        2'd1: lane_mask = 4'b0010;
        2'd2: lane_mask = 4'b0100;
        default: lane_mask = 4'b1000;
      endcase
    end
  endfunction

  uart_rx u_uart_rx (
    .clk_i       (clk_i),
    .rst_i       (rst_i),
    .rxd_i       (uart_rx_i),
    .prescale_i  (UART_PRESCALE_W),
    .data_o      (rx_byte_w),
    .data_valid_o(rx_valid_w),
    .busy_o      (rx_busy_unused_w)
  );

  uart_tx u_uart_tx (
    .clk_i       (clk_i),
    .rst_i       (rst_i),
    .data_i      (tx_byte_r),
    .data_valid_i(tx_valid_r),
    .data_ready_o(tx_ready_w),
    .txd_o       (uart_tx_o),
    .busy_o      (tx_busy_unused_w),
    .prescale_i  (UART_PRESCALE_W)
  );

  assign busy_o = (state_r != ST_MAGIC0) && (state_r != ST_DONE) && (state_r != ST_ERROR);
  assign done_o = done_r;
  assign error_o = error_r;
  assign bytes_loaded_o = bytes_loaded_r;

  always @(posedge clk_i) begin
    if (rst_i) begin
      state_r          <= ST_MAGIC0;
      payload_len_r    <= 32'd0;
      payload_rem_r    <= 32'd0;
      bytes_loaded_r   <= 32'd0;
      curr_word_addr_r <= (SRC_BASE_ADDR & 32'hffff_fffc);
      curr_lane_r      <= SRC_BASE_ADDR[1:0];
      pack_word_r      <= 32'd0;
      pack_we_r        <= 4'd0;
      pending_addr_r   <= 32'd0;
      pending_data_r   <= 32'd0;
      pending_we_r     <= 4'd0;
      tx_byte_r        <= 8'd0;
      tx_valid_r       <= 1'b0;
      aux_en_o         <= 1'b0;
      aux_we_o         <= 4'b0000;
      aux_addr_o       <= 32'd0;
      aux_wdata_o      <= 32'd0;
      done_r           <= 1'b0;
      error_r          <= 1'b0;
    end else begin
      tx_valid_r  <= 1'b0;
      aux_en_o    <= 1'b0;
      aux_we_o    <= 4'b0000;
      aux_addr_o  <= 32'd0;
      aux_wdata_o <= 32'd0;

      case (state_r)
        ST_MAGIC0: begin
          if (rx_valid_w) begin
            if (rx_byte_w == MAGIC0)
              state_r <= ST_MAGIC1;
          end
        end

        ST_MAGIC1: begin
          if (rx_valid_w) begin
            if (rx_byte_w == MAGIC1)
              state_r <= ST_MAGIC2;
            else if (rx_byte_w == MAGIC0)
              state_r <= ST_MAGIC1;
            else
              state_r <= ST_MAGIC0;
          end
        end

        ST_MAGIC2: begin
          if (rx_valid_w) begin
            if (rx_byte_w == MAGIC2)
              state_r <= ST_MAGIC3;
            else if (rx_byte_w == MAGIC0)
              state_r <= ST_MAGIC1;
            else
              state_r <= ST_MAGIC0;
          end
        end

        ST_MAGIC3: begin
          if (rx_valid_w) begin
            if (rx_byte_w == MAGIC3) begin
              state_r        <= ST_LEN0;
              payload_len_r  <= 32'd0;
              payload_rem_r  <= 32'd0;
              bytes_loaded_r <= 32'd0;
              done_r         <= 1'b0;
              error_r        <= 1'b0;
              pack_word_r    <= 32'd0;
              pack_we_r      <= 4'd0;
            end else if (rx_byte_w == MAGIC0) begin
              state_r <= ST_MAGIC1;
            end else begin
              state_r <= ST_MAGIC0;
            end
          end
        end

        ST_LEN0: begin
          if (rx_valid_w) begin
            payload_len_r[7:0] <= rx_byte_w;
            state_r            <= ST_LEN1;
          end
        end

        ST_LEN1: begin
          if (rx_valid_w) begin
            payload_len_r[15:8] <= rx_byte_w;
            state_r             <= ST_LEN2;
          end
        end

        ST_LEN2: begin
          if (rx_valid_w) begin
            payload_len_r[23:16] <= rx_byte_w;
            state_r              <= ST_LEN3;
          end
        end

        ST_LEN3: begin
          if (rx_valid_w) begin
            candidate_len_v = {rx_byte_w, payload_len_r[23:0]};
            payload_len_r   <= candidate_len_v;
            payload_rem_r   <= candidate_len_v;
            curr_word_addr_r<= (SRC_BASE_ADDR & 32'hffff_fffc);
            curr_lane_r     <= SRC_BASE_ADDR[1:0];
            pack_word_r     <= 32'd0;
            pack_we_r       <= 4'd0;
            if ((candidate_len_v == 32'd0) ||
                (candidate_len_v > MAX_INPUT_BYTES)) begin
              error_r <= 1'b1;
              state_r <= ST_SEND_ERR;
            end else begin
              state_r <= ST_PAYLOAD;
            end
          end
        end

        ST_PAYLOAD: begin
          if (rx_valid_w) begin
            merged_word_v            = insert_byte32(pack_word_r, curr_lane_r, rx_byte_w);
            merged_we_v              = pack_we_r | lane_mask(curr_lane_r);
            next_rem_v               = payload_rem_r - 32'd1;
            bytes_loaded_r           <= bytes_loaded_r + 32'd1;
            if ((curr_lane_r == 2'd3) || (payload_rem_r == 32'd1)) begin
              pending_addr_r         <= curr_word_addr_r;
              pending_data_r         <= merged_word_v;
              pending_we_r           <= merged_we_v;
              curr_word_addr_r       <= curr_word_addr_r + 32'd4;
              curr_lane_r            <= 2'd0;
              pack_word_r            <= 32'd0;
              pack_we_r              <= 4'd0;
              payload_rem_r          <= next_rem_v;
              state_r                <= ST_WRITE_PAYLOAD;
            end else begin
              pack_word_r            <= merged_word_v;
              pack_we_r              <= merged_we_v;
              curr_lane_r            <= curr_lane_r + 2'd1;
              payload_rem_r          <= next_rem_v;
            end
          end
        end

        ST_WRITE_PAYLOAD: begin
          aux_en_o    <= 1'b1;
          aux_we_o    <= pending_we_r;
          aux_addr_o  <= pending_addr_r;
          aux_wdata_o <= pending_data_r;
          if (payload_rem_r == 32'd0)
            state_r <= ST_WRITE_LEN;
          else
            state_r <= ST_PAYLOAD;
        end

        ST_WRITE_LEN: begin
          aux_en_o    <= 1'b1;
          aux_we_o    <= 4'b1111;
          aux_addr_o  <= INPUT_LEN_ADDR;
          aux_wdata_o <= payload_len_r;
          done_r      <= 1'b1;
          state_r     <= ST_SEND_ACK;
        end

        ST_SEND_ACK: begin
          if (tx_ready_w) begin
            tx_byte_r  <= ACK_OK;
            tx_valid_r <= 1'b1;
            state_r    <= ST_DONE;
          end
        end

        ST_SEND_ERR: begin
          if (tx_ready_w) begin
            tx_byte_r  <= ACK_ERR;
            tx_valid_r <= 1'b1;
            state_r    <= ST_ERROR;
          end
        end

        ST_DONE: begin
        end

        ST_ERROR: begin
        end

        default: begin
          state_r <= ST_MAGIC0;
        end
      endcase
    end
  end

endmodule

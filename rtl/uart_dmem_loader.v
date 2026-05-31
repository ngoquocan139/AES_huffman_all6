module uart_dmem_loader #(
  parameter integer CLK_HZ          = 50000000,
  parameter integer BAUD_RATE       = 115200,
  parameter [31:0]  SRC_BASE_ADDR   = 32'h0000_2000,
  parameter [31:0]  INPUT_LEN_ADDR  = 32'h0000_0040,
  parameter [31:0]  CPU_DEBUG_BASE_ADDR = 32'h0000_7f80,
  parameter integer MAX_INPUT_BYTES = 7168,
  parameter integer MAX_READ_BYTES  = 32768
) (
  input  wire        clk_i,
  input  wire        rst_i,
  input  wire        uart_rx_i,
  output wire        uart_tx_o,
  input  wire [31:0] aux_rdata_i,
  output reg         aux_en_o,
  output reg  [3:0]  aux_we_o,
  output reg  [31:0] aux_addr_o,
  output reg  [31:0] aux_wdata_o,
  output wire        busy_o,
  output wire        done_o,
  output wire        error_o,
  output wire [31:0] bytes_loaded_o,
  input  wire [31:0] cpu_debug_status_i,
  input  wire [31:0] cpu_debug_fetch_pc_i,
  input  wire [31:0] cpu_debug_fetch_instr_i,
  input  wire [31:0] cpu_debug_cycle_count_i,
  input  wire [31:0] cpu_debug_fetch_count_i,
  input  wire [31:0] cpu_debug_dmem_access_count_i,
  input  wire [31:0] cpu_debug_mmio_access_count_i,
  input  wire [31:0] cpu_debug_last_dmem_addr_i,
  input  wire [31:0] cpu_debug_last_dmem_wdata_i,
  input  wire [31:0] cpu_debug_last_dmem_ctrl_i,
  input  wire [31:0] cpu_debug_wb_count_i,
  input  wire [31:0] cpu_debug_last_wb_info_i,
  input  wire [31:0] cpu_debug_last_wb_data_i
);

  localparam [7:0] MAGIC0 = 8'h4c; // 'L'
  localparam [7:0] MAGIC1 = 8'h4f; // 'O'
  localparam [7:0] MAGIC2 = 8'h41; // 'A'
  localparam [7:0] MAGIC3 = 8'h44; // 'D'
  localparam [7:0] READ0  = 8'h52; // 'R'
  localparam [7:0] READ1  = 8'h45; // 'E'
  localparam [7:0] READ2  = 8'h41; // 'A'
  localparam [7:0] READ3  = 8'h44; // 'D'
  localparam [7:0] ACK_OK = 8'h79;
  localparam [7:0] ACK_ERR = 8'h1f;

  localparam [5:0] ST_MAGIC0        = 6'd0;
  localparam [5:0] ST_MAGIC1        = 6'd1;
  localparam [5:0] ST_MAGIC2        = 6'd2;
  localparam [5:0] ST_MAGIC3        = 6'd3;
  localparam [5:0] ST_LEN0          = 6'd4;
  localparam [5:0] ST_LEN1          = 6'd5;
  localparam [5:0] ST_LEN2          = 6'd6;
  localparam [5:0] ST_LEN3          = 6'd7;
  localparam [5:0] ST_PAYLOAD       = 6'd8;
  localparam [5:0] ST_WRITE_PAYLOAD = 6'd9;
  localparam [5:0] ST_WRITE_LEN     = 6'd10;
  localparam [5:0] ST_SEND_ACK      = 6'd11;
  localparam [5:0] ST_SEND_ERR      = 6'd12;
  localparam [5:0] ST_DONE          = 6'd13;
  localparam [5:0] ST_ERROR         = 6'd14;
  localparam [5:0] ST_READ1         = 6'd15;
  localparam [5:0] ST_READ2         = 6'd16;
  localparam [5:0] ST_READ3         = 6'd17;
  localparam [5:0] ST_READ_ADDR0    = 6'd18;
  localparam [5:0] ST_READ_ADDR1    = 6'd19;
  localparam [5:0] ST_READ_ADDR2    = 6'd20;
  localparam [5:0] ST_READ_ADDR3    = 6'd21;
  localparam [5:0] ST_READ_LEN0     = 6'd22;
  localparam [5:0] ST_READ_LEN1     = 6'd23;
  localparam [5:0] ST_READ_LEN2     = 6'd24;
  localparam [5:0] ST_READ_LEN3     = 6'd25;
  localparam [5:0] ST_READ_ACK      = 6'd26;
  localparam [5:0] ST_READ_REQ      = 6'd27;
  localparam [5:0] ST_READ_WAIT     = 6'd28;
  localparam [5:0] ST_READ_CAPTURE  = 6'd29;
  localparam [5:0] ST_READ_SEND0    = 6'd30;
  localparam [5:0] ST_READ_SEND1    = 6'd31;
  localparam [5:0] ST_READ_SEND2    = 6'd32;
  localparam [5:0] ST_READ_SEND3    = 6'd33;

  localparam [31:0] MAX_READ_BYTES_W = MAX_READ_BYTES;
  localparam [15:0] DMEM_BYTES_W     = 16'd32768;
  localparam [31:0] CPU_DEBUG_SIGNATURE_W = 32'h3155_5043; // "CPU1"
  localparam [31:0] CPU_DEBUG_VERSION_W   = 32'h0001_0000;

  localparam integer UART_PRESCALE_INT = (CLK_HZ / BAUD_RATE);
  localparam [15:0] UART_PRESCALE_W = (UART_PRESCALE_INT <= 0) ? 16'd1 :
                                      (UART_PRESCALE_INT > 65535) ? 16'hffff :
                                      UART_PRESCALE_INT[15:0];

  reg [5:0]  state_r;
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
  reg [31:0] read_addr_r;
  reg [31:0] read_len_r;
  reg [31:0] read_rem_r;
  reg [31:0] read_word_r;
  reg [7:0]  tx_byte_r;
  reg        tx_valid_r;
  reg        done_r;
  reg        error_r;
  reg [31:0] merged_word_v;
  reg [3:0]  merged_we_v;
  reg [31:0] next_rem_v;
  reg [31:0] candidate_len_v;
  reg [15:0] read_end_v;

  wire [7:0] rx_byte_w;
  wire       rx_valid_w;
  wire       rx_busy_unused_w;
  wire       tx_ready_w;
  wire       tx_busy_unused_w;
  wire       read_len_upper_unused_w;
  wire       read_cpu_debug_w;

  assign read_cpu_debug_w = (read_addr_r >= CPU_DEBUG_BASE_ADDR) &&
                            (read_addr_r < (CPU_DEBUG_BASE_ADDR + 32'd64));

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

  function [31:0] cpu_debug_word;
    input [31:0] addr_i;
    begin
      case ((addr_i - CPU_DEBUG_BASE_ADDR) >> 2)
        32'd0:  cpu_debug_word = CPU_DEBUG_SIGNATURE_W;
        32'd1:  cpu_debug_word = cpu_debug_status_i;
        32'd2:  cpu_debug_word = cpu_debug_fetch_pc_i;
        32'd3:  cpu_debug_word = cpu_debug_fetch_instr_i;
        32'd4:  cpu_debug_word = cpu_debug_cycle_count_i;
        32'd5:  cpu_debug_word = cpu_debug_fetch_count_i;
        32'd6:  cpu_debug_word = cpu_debug_dmem_access_count_i;
        32'd7:  cpu_debug_word = cpu_debug_mmio_access_count_i;
        32'd8:  cpu_debug_word = cpu_debug_last_dmem_addr_i;
        32'd9:  cpu_debug_word = cpu_debug_last_dmem_wdata_i;
        32'd10: cpu_debug_word = cpu_debug_last_dmem_ctrl_i;
        32'd11: cpu_debug_word = cpu_debug_wb_count_i;
        32'd12: cpu_debug_word = cpu_debug_last_wb_info_i;
        32'd13: cpu_debug_word = cpu_debug_last_wb_data_i;
        32'd14: cpu_debug_word = bytes_loaded_r;
        32'd15: cpu_debug_word = CPU_DEBUG_VERSION_W;
        default: cpu_debug_word = 32'd0;
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

  assign read_len_upper_unused_w = |read_len_r[31:24];
  assign busy_o = ((state_r != ST_MAGIC0) && (state_r != ST_DONE) && (state_r != ST_ERROR)) ||
                  (1'b0 & read_len_upper_unused_w);
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
      read_addr_r      <= 32'd0;
      read_len_r       <= 32'd0;
      read_rem_r       <= 32'd0;
      read_word_r      <= 32'd0;
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
        ST_MAGIC0, ST_DONE: begin
          if (rx_valid_w) begin
            if (rx_byte_w == MAGIC0) begin
              state_r <= ST_MAGIC1;
            end else if (rx_byte_w == READ0) begin
              state_r <= ST_READ1;
              error_r <= 1'b0;
            end
          end
        end

        ST_MAGIC1: begin
          if (rx_valid_w) begin
            if (rx_byte_w == MAGIC1)
              state_r <= ST_MAGIC2;
            else if (rx_byte_w == READ0)
              state_r <= ST_READ1;
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
            else if (rx_byte_w == READ0)
              state_r <= ST_READ1;
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
            end else if (rx_byte_w == READ0) begin
              state_r <= ST_READ1;
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
            state_r    <= done_r ? ST_DONE : ST_ERROR;
          end
        end

        ST_READ1: begin
          if (rx_valid_w) begin
            if (rx_byte_w == READ1)
              state_r <= ST_READ2;
            else if (rx_byte_w == READ0)
              state_r <= ST_READ1;
            else if (rx_byte_w == MAGIC0)
              state_r <= ST_MAGIC1;
            else
              state_r <= done_r ? ST_DONE : ST_MAGIC0;
          end
        end

        ST_READ2: begin
          if (rx_valid_w) begin
            if (rx_byte_w == READ2)
              state_r <= ST_READ3;
            else if (rx_byte_w == READ0)
              state_r <= ST_READ1;
            else if (rx_byte_w == MAGIC0)
              state_r <= ST_MAGIC1;
            else
              state_r <= done_r ? ST_DONE : ST_MAGIC0;
          end
        end

        ST_READ3: begin
          if (rx_valid_w) begin
            if (rx_byte_w == READ3) begin
              read_addr_r <= 32'd0;
              read_len_r  <= 32'd0;
              read_rem_r  <= 32'd0;
              read_word_r <= 32'd0;
              state_r     <= ST_READ_ADDR0;
            end else if (rx_byte_w == READ0) begin
              state_r <= ST_READ1;
            end else if (rx_byte_w == MAGIC0) begin
              state_r <= ST_MAGIC1;
            end else begin
              state_r <= done_r ? ST_DONE : ST_MAGIC0;
            end
          end
        end

        ST_READ_ADDR0: begin
          if (rx_valid_w) begin
            read_addr_r[7:0] <= rx_byte_w;
            state_r          <= ST_READ_ADDR1;
          end
        end

        ST_READ_ADDR1: begin
          if (rx_valid_w) begin
            read_addr_r[15:8] <= rx_byte_w;
            state_r           <= ST_READ_ADDR2;
          end
        end

        ST_READ_ADDR2: begin
          if (rx_valid_w) begin
            read_addr_r[23:16] <= rx_byte_w;
            state_r            <= ST_READ_ADDR3;
          end
        end

        ST_READ_ADDR3: begin
          if (rx_valid_w) begin
            read_addr_r[31:24] <= rx_byte_w;
            state_r            <= ST_READ_LEN0;
          end
        end

        ST_READ_LEN0: begin
          if (rx_valid_w) begin
            read_len_r[7:0] <= rx_byte_w;
            state_r         <= ST_READ_LEN1;
          end
        end

        ST_READ_LEN1: begin
          if (rx_valid_w) begin
            read_len_r[15:8] <= rx_byte_w;
            state_r          <= ST_READ_LEN2;
          end
        end

        ST_READ_LEN2: begin
          if (rx_valid_w) begin
            read_len_r[23:16] <= rx_byte_w;
            state_r           <= ST_READ_LEN3;
          end
        end

        ST_READ_LEN3: begin
          if (rx_valid_w) begin
            candidate_len_v = {rx_byte_w, read_len_r[23:0]};
            read_end_v     = {1'b0, read_addr_r[14:0]} + candidate_len_v[15:0];
            read_len_r     <= candidate_len_v;
            read_rem_r     <= candidate_len_v;
            if ((candidate_len_v == 32'd0) ||
                (candidate_len_v > MAX_READ_BYTES_W) ||
                (|candidate_len_v[1:0]) ||
                (|candidate_len_v[31:16]) ||
                (|read_addr_r[1:0]) ||
                (|read_addr_r[31:15]) ||
                (read_end_v > DMEM_BYTES_W)) begin
              error_r <= 1'b1;
              state_r <= ST_SEND_ERR;
            end else begin
              state_r <= ST_READ_ACK;
            end
          end
        end

        ST_READ_ACK: begin
          if (tx_ready_w) begin
            tx_byte_r  <= ACK_OK;
            tx_valid_r <= 1'b1;
            state_r    <= ST_READ_REQ;
          end
        end

        ST_READ_REQ: begin
          aux_en_o    <= !read_cpu_debug_w;
          aux_we_o    <= 4'b0000;
          aux_addr_o  <= read_addr_r;
          aux_wdata_o <= 32'd0;
          state_r     <= ST_READ_WAIT;
        end

        ST_READ_WAIT: begin
          state_r     <= ST_READ_CAPTURE;
        end

        ST_READ_CAPTURE: begin
          read_word_r <= read_cpu_debug_w ? cpu_debug_word(read_addr_r) : aux_rdata_i;
          state_r     <= ST_READ_SEND0;
        end

        ST_READ_SEND0: begin
          if (tx_ready_w) begin
            tx_byte_r  <= read_word_r[7:0];
            tx_valid_r <= 1'b1;
            state_r    <= ST_READ_SEND1;
          end
        end

        ST_READ_SEND1: begin
          if (tx_ready_w) begin
            tx_byte_r  <= read_word_r[15:8];
            tx_valid_r <= 1'b1;
            state_r    <= ST_READ_SEND2;
          end
        end

        ST_READ_SEND2: begin
          if (tx_ready_w) begin
            tx_byte_r  <= read_word_r[23:16];
            tx_valid_r <= 1'b1;
            state_r    <= ST_READ_SEND3;
          end
        end

        ST_READ_SEND3: begin
          if (tx_ready_w) begin
            tx_byte_r  <= read_word_r[31:24];
            tx_valid_r <= 1'b1;
            if (read_rem_r == 32'd4) begin
              read_rem_r <= 32'd0;
              state_r    <= ST_DONE;
            end else begin
              read_rem_r  <= read_rem_r - 32'd4;
              read_addr_r <= read_addr_r + 32'd4;
              state_r     <= ST_READ_REQ;
            end
          end
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

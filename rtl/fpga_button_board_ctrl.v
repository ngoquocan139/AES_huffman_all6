module fpga_button_board_ctrl #(
  parameter integer DEBOUNCE_CYCLES       = 500000,
  parameter [31:0]  BOARD_STATUS_ADDR     = 32'h0000_0050,
  parameter [31:0]  BOARD_FILE_ID_ADDR    = 32'h0000_0054,
  parameter [31:0]  BOARD_EVENT_ADDR      = 32'h0000_0058,
  parameter [31:0]  BOARD_SNAPSHOT_ADDR   = 32'h0000_0200,
  parameter [31:0]  BOARD_SNAPSHOT_META   = 32'h0000_0240,
  parameter [31:0]  RESULT_BASE_ADDR      = 32'h0000_0000,
  parameter integer RESULT_WORDS          = 16,
  parameter [31:0]  ZEROIZE_BASE_ADDR     = 32'h0000_0100,
  parameter integer ZEROIZE_WORDS         = 64,
  parameter [31:0]  FILE_ID_A             = 32'd1,
  parameter [31:0]  FILE_ID_B             = 32'd3
) (
  input  wire        clk_i,
  input  wire        rst_i,
  input  wire        btn_run_i,
  input  wire        btn_zeroize_i,
  input  wire        btn_file_next_i,
  input  wire        btn_file_prev_i,
  input  wire        btn_snapshot_i,
  input  wire        loader_done_i,
  input  wire        loader_busy_i,
  input  wire [31:0] aux_rdata_i,
  output reg         aux_en_o,
  output reg  [3:0]  aux_we_o,
  output reg  [31:0] aux_addr_o,
  output reg  [31:0] aux_wdata_o,
  output wire        busy_o,
  output wire        soc_hold_o,
  output wire        run_latched_o,
  output wire        zeroize_done_o,
  output wire        snapshot_valid_o,
  output wire [31:0] selected_file_id_o
);
  localparam [3:0] ST_IDLE             = 4'd0;
  localparam [3:0] ST_WRITE_FILE       = 4'd1;
  localparam [3:0] ST_WRITE_EVENT      = 4'd2;
  localparam [3:0] ST_WRITE_STATUS     = 4'd3;
  localparam [3:0] ST_ZEROIZE_WRITE    = 4'd4;
  localparam [3:0] ST_SNAPSHOT_READ    = 4'd5;
  localparam [3:0] ST_SNAPSHOT_WAIT    = 4'd6;
  localparam [3:0] ST_SNAPSHOT_WRITE   = 4'd7;
  localparam [3:0] ST_SNAPSHOT_META0   = 4'd8;
  localparam [3:0] ST_SNAPSHOT_META1   = 4'd9;
  localparam [3:0] ST_SNAPSHOT_META2   = 4'd10;
  localparam [3:0] ST_SNAPSHOT_META3   = 4'd11;

  localparam [31:0] SNAPSHOT_MAGIC = 32'h534e4150; // "SNAP"
  localparam [7:0] ZEROIZE_LAST_W = ZEROIZE_WORDS - 1;
  localparam [7:0] SNAPSHOT_LAST_W = RESULT_WORDS - 1;

  wire run_level_w;
  wire run_pulse_w;
  wire zeroize_level_unused_w;
  wire file_next_level_unused_w;
  wire file_prev_level_unused_w;
  wire snapshot_level_unused_w;
  wire zeroize_pulse_w;
  wire file_next_pulse_w;
  wire file_prev_pulse_w;
  wire snapshot_pulse_w;
  wire level_unused_w;
  wire unused_level_term_w;

  reg [3:0]  state_r;
  reg        run_latched_r;
  reg        pending_file_r;
  reg        pending_event_r;
  reg        pending_status_r;
  reg        pending_zeroize_r;
  reg        pending_snapshot_r;
  reg        zeroize_active_r;
  reg        zeroize_done_r;
  reg        snapshot_active_r;
  reg        snapshot_valid_r;
  reg        loader_done_d_r;
  reg [31:0] selected_file_id_r;
  reg [31:0] event_count_r;
  reg [31:0] zeroize_count_r;
  reg [31:0] snapshot_count_r;
  reg [7:0]  zeroize_idx_r;
  reg [7:0]  snapshot_idx_r;
  reg [31:0] snapshot_word_r;

  wire loader_done_pulse_w = loader_done_i & ~loader_done_d_r;
  wire control_busy_w = (state_r != ST_IDLE) ||
                        pending_file_r ||
                        pending_event_r ||
                        pending_status_r ||
                        pending_zeroize_r ||
                        pending_snapshot_r ||
                        zeroize_active_r ||
                        snapshot_active_r ||
                        unused_level_term_w;
  wire status_busy_w = ((state_r != ST_IDLE) && (state_r != ST_WRITE_STATUS)) ||
                       pending_file_r ||
                       pending_event_r ||
                       pending_zeroize_r ||
                       pending_snapshot_r ||
                       zeroize_active_r ||
                       snapshot_active_r ||
                       unused_level_term_w;
  wire [31:0] status_word_w = {
    snapshot_count_r[7:0],
    zeroize_count_r[7:0],
    selected_file_id_r[7:0],
    4'b0000,
    snapshot_valid_r,
    zeroize_done_r,
    status_busy_w,
    run_latched_r
  };

  assign busy_o             = control_busy_w;
  assign soc_hold_o         = zeroize_active_r;
  assign run_latched_o      = run_latched_r;
  assign zeroize_done_o     = zeroize_done_r;
  assign snapshot_valid_o   = snapshot_valid_r;
  assign selected_file_id_o = selected_file_id_r;

  fpga_button_sync_pulse #(
    .DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)
  ) u_run_button (
    .clk_i  (clk_i),
    .rst_i  (rst_i),
    .btn_i  (btn_run_i),
    .level_o(run_level_w),
    .pulse_o(run_pulse_w)
  );

  fpga_button_sync_pulse #(
    .DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)
  ) u_zeroize_button (
    .clk_i  (clk_i),
    .rst_i  (rst_i),
    .btn_i  (btn_zeroize_i),
    .level_o(zeroize_level_unused_w),
    .pulse_o(zeroize_pulse_w)
  );

  fpga_button_sync_pulse #(
    .DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)
  ) u_file_next_button (
    .clk_i  (clk_i),
    .rst_i  (rst_i),
    .btn_i  (btn_file_next_i),
    .level_o(file_next_level_unused_w),
    .pulse_o(file_next_pulse_w)
  );

  fpga_button_sync_pulse #(
    .DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)
  ) u_file_prev_button (
    .clk_i  (clk_i),
    .rst_i  (rst_i),
    .btn_i  (btn_file_prev_i),
    .level_o(file_prev_level_unused_w),
    .pulse_o(file_prev_pulse_w)
  );

  fpga_button_sync_pulse #(
    .DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)
  ) u_snapshot_button (
    .clk_i  (clk_i),
    .rst_i  (rst_i),
    .btn_i  (btn_snapshot_i),
    .level_o(snapshot_level_unused_w),
    .pulse_o(snapshot_pulse_w)
  );

  assign level_unused_w = zeroize_level_unused_w |
                          file_next_level_unused_w |
                          file_prev_level_unused_w |
                          snapshot_level_unused_w;
  assign unused_level_term_w = 1'b0 & level_unused_w;

  always @(posedge clk_i) begin
    if (rst_i) begin
      state_r            <= ST_IDLE;
      run_latched_r      <= 1'b0;
      pending_file_r     <= 1'b0;
      pending_event_r    <= 1'b0;
      pending_status_r   <= 1'b0;
      pending_zeroize_r  <= 1'b0;
      pending_snapshot_r <= 1'b0;
      zeroize_active_r   <= 1'b0;
      zeroize_done_r     <= 1'b0;
      snapshot_active_r  <= 1'b0;
      snapshot_valid_r   <= 1'b0;
      loader_done_d_r    <= 1'b0;
      selected_file_id_r <= FILE_ID_A;
      event_count_r      <= 32'd0;
      zeroize_count_r    <= 32'd0;
      snapshot_count_r   <= 32'd0;
      zeroize_idx_r      <= 8'd0;
      snapshot_idx_r     <= 8'd0;
      snapshot_word_r    <= 32'd0;
      aux_en_o           <= 1'b0;
      aux_we_o           <= 4'b0000;
      aux_addr_o         <= 32'd0;
      aux_wdata_o        <= 32'd0;
    end else begin
      aux_en_o        <= 1'b0;
      aux_we_o        <= 4'b0000;
      aux_addr_o      <= 32'd0;
      aux_wdata_o     <= 32'd0;
      loader_done_d_r <= loader_done_i;

      if (loader_done_pulse_w) begin
        run_latched_r    <= 1'b1;
        pending_file_r   <= 1'b1;
        pending_event_r  <= 1'b1;
        pending_status_r <= 1'b1;
      end

      if ((run_pulse_w || run_level_w) && loader_done_i && !zeroize_active_r) begin
        run_latched_r    <= 1'b1;
        pending_status_r <= 1'b1;
      end

      if (file_next_pulse_w) begin
        selected_file_id_r <= (selected_file_id_r == FILE_ID_A) ? FILE_ID_B : FILE_ID_A;
        pending_file_r     <= 1'b1;
        pending_event_r    <= 1'b1;
        pending_status_r   <= 1'b1;
      end

      if (file_prev_pulse_w) begin
        selected_file_id_r <= (selected_file_id_r == FILE_ID_B) ? FILE_ID_A : FILE_ID_B;
        pending_file_r     <= 1'b1;
        pending_event_r    <= 1'b1;
        pending_status_r   <= 1'b1;
      end

      if (zeroize_pulse_w && !zeroize_active_r) begin
        run_latched_r      <= 1'b0;
        pending_zeroize_r  <= 1'b1;
        pending_event_r    <= 1'b1;
        pending_status_r   <= 1'b1;
        zeroize_done_r     <= 1'b0;
      end

      if (snapshot_pulse_w && !snapshot_active_r) begin
        pending_snapshot_r <= 1'b1;
        pending_event_r    <= 1'b1;
        pending_status_r   <= 1'b1;
        snapshot_valid_r   <= 1'b0;
      end

      case (state_r)
        ST_IDLE: begin
          if (!loader_busy_i) begin
            if (pending_zeroize_r) begin
              pending_zeroize_r <= 1'b0;
              zeroize_active_r  <= 1'b1;
              zeroize_idx_r     <= 8'd0;
              state_r           <= ST_ZEROIZE_WRITE;
            end else if (pending_snapshot_r) begin
              pending_snapshot_r <= 1'b0;
              snapshot_active_r  <= 1'b1;
              snapshot_idx_r     <= 8'd0;
              state_r            <= ST_SNAPSHOT_READ;
            end else if (pending_file_r) begin
              pending_file_r <= 1'b0;
              state_r        <= ST_WRITE_FILE;
            end else if (pending_event_r) begin
              pending_event_r <= 1'b0;
              state_r         <= ST_WRITE_EVENT;
            end else if (pending_status_r) begin
              pending_status_r <= 1'b0;
              state_r          <= ST_WRITE_STATUS;
            end
          end
        end

        ST_WRITE_FILE: begin
          if (!loader_busy_i) begin
            aux_en_o    <= 1'b1;
            aux_we_o    <= 4'b1111;
            aux_addr_o  <= BOARD_FILE_ID_ADDR;
            aux_wdata_o <= selected_file_id_r;
            state_r     <= ST_WRITE_EVENT;
          end
        end

        ST_WRITE_EVENT: begin
          if (!loader_busy_i) begin
            aux_en_o       <= 1'b1;
            aux_we_o       <= 4'b1111;
            aux_addr_o     <= BOARD_EVENT_ADDR;
            aux_wdata_o    <= event_count_r;
            event_count_r  <= event_count_r + 32'd1;
            pending_event_r <= 1'b0;
            state_r        <= ST_WRITE_STATUS;
          end
        end

        ST_WRITE_STATUS: begin
          if (!loader_busy_i) begin
            aux_en_o    <= 1'b1;
            aux_we_o    <= 4'b1111;
            aux_addr_o  <= BOARD_STATUS_ADDR;
            aux_wdata_o <= status_word_w;
            pending_status_r <= 1'b0;
            state_r     <= ST_IDLE;
          end
        end

        ST_ZEROIZE_WRITE: begin
          if (!loader_busy_i) begin
            aux_en_o    <= 1'b1;
            aux_we_o    <= 4'b1111;
            aux_addr_o  <= ZEROIZE_BASE_ADDR + {22'd0, zeroize_idx_r, 2'b00};
            aux_wdata_o <= 32'd0;
            if (zeroize_idx_r == ZEROIZE_LAST_W) begin
              zeroize_idx_r     <= 8'd0;
              zeroize_active_r  <= 1'b0;
              zeroize_done_r    <= 1'b1;
              zeroize_count_r   <= zeroize_count_r + 32'd1;
              pending_status_r  <= 1'b1;
              state_r           <= ST_IDLE;
            end else begin
              zeroize_idx_r <= zeroize_idx_r + 8'd1;
            end
          end
        end

        ST_SNAPSHOT_READ: begin
          if (!loader_busy_i) begin
            aux_en_o    <= 1'b1;
            aux_we_o    <= 4'b0000;
            aux_addr_o  <= RESULT_BASE_ADDR + {22'd0, snapshot_idx_r, 2'b00};
            aux_wdata_o <= 32'd0;
            state_r     <= ST_SNAPSHOT_WAIT;
          end
        end

        ST_SNAPSHOT_WAIT: begin
          if (loader_busy_i) begin
            state_r <= ST_SNAPSHOT_READ;
          end else begin
            snapshot_word_r <= aux_rdata_i;
            state_r         <= ST_SNAPSHOT_WRITE;
          end
        end

        ST_SNAPSHOT_WRITE: begin
          if (!loader_busy_i) begin
            aux_en_o    <= 1'b1;
            aux_we_o    <= 4'b1111;
            aux_addr_o  <= BOARD_SNAPSHOT_ADDR + {22'd0, snapshot_idx_r, 2'b00};
            aux_wdata_o <= snapshot_word_r;
            if (snapshot_idx_r == SNAPSHOT_LAST_W) begin
              snapshot_idx_r <= 8'd0;
              state_r        <= ST_SNAPSHOT_META0;
            end else begin
              snapshot_idx_r <= snapshot_idx_r + 8'd1;
              state_r        <= ST_SNAPSHOT_READ;
            end
          end
        end

        ST_SNAPSHOT_META0: begin
          if (!loader_busy_i) begin
            aux_en_o    <= 1'b1;
            aux_we_o    <= 4'b1111;
            aux_addr_o  <= BOARD_SNAPSHOT_META;
            aux_wdata_o <= SNAPSHOT_MAGIC;
            state_r     <= ST_SNAPSHOT_META1;
          end
        end

        ST_SNAPSHOT_META1: begin
          if (!loader_busy_i) begin
            aux_en_o    <= 1'b1;
            aux_we_o    <= 4'b1111;
            aux_addr_o  <= BOARD_SNAPSHOT_META + 32'd4;
            aux_wdata_o <= selected_file_id_r;
            state_r     <= ST_SNAPSHOT_META2;
          end
        end

        ST_SNAPSHOT_META2: begin
          if (!loader_busy_i) begin
            aux_en_o        <= 1'b1;
            aux_we_o        <= 4'b1111;
            aux_addr_o      <= BOARD_SNAPSHOT_META + 32'd8;
            aux_wdata_o     <= snapshot_count_r + 32'd1;
            snapshot_count_r <= snapshot_count_r + 32'd1;
            snapshot_valid_r <= 1'b1;
            snapshot_active_r<= 1'b0;
            pending_status_r <= 1'b1;
            state_r          <= ST_SNAPSHOT_META3;
          end
        end

        ST_SNAPSHOT_META3: begin
          if (!loader_busy_i) begin
            aux_en_o    <= 1'b1;
            aux_we_o    <= 4'b1111;
            aux_addr_o  <= BOARD_SNAPSHOT_META + 32'd12;
            aux_wdata_o <= status_word_w;
            state_r     <= ST_IDLE;
          end
        end

        default: begin
          state_r <= ST_IDLE;
        end
      endcase
    end
  end
endmodule

module input_collect_unit #(
    parameter BLOCK_SIZE          = 32,
    parameter SYMBOL_WIDTH        = 8,
    parameter ALPHABET_SIZE       = 96,
    parameter ASCII_MIN           = 8'h20,
    parameter ASCII_MAX           = 8'h7E,
    parameter DEFAULT_REMAP       = 8'h20,
    parameter BLOCK_SIZE_WIDTH    = 6,
    parameter COUNT_WIDTH         = 6,
    parameter ADDR_WIDTH          = 5,
    parameter SYMBOL_INDEX_WIDTH  = 7
)(
    input  wire                          clk,
    input  wire                          rst_n,

    input  wire                          start_collect,

    input  wire [SYMBOL_WIDTH-1:0]       byte_in,
    input  wire                          byte_valid,
    output wire                          byte_ready,

    input  wire                          block_start,
    input  wire                          block_end,

    // Readback interface for block_buffer
    input  wire [ADDR_WIDTH-1:0]         buffer_read_addr,
    output wire [SYMBOL_WIDTH-1:0]       buffer_read_data,

    // Readback interface for frequency_counter
    input  wire [SYMBOL_INDEX_WIDTH-1:0] freq_read_index,
    output wire [COUNT_WIDTH-1:0]        freq_read_count,

    output wire                          collect_busy,
    output wire                          collect_done,
    output reg                           protocol_error,
    output wire                          overflow_error,

    output wire [BLOCK_SIZE_WIDTH-1:0]   block_size,
    output wire [SYMBOL_WIDTH-1:0]       normalized_byte
);

    // ------------------------------------------------------------
    // State encoding
    // ------------------------------------------------------------
    localparam [1:0] ST_IDLE       = 2'b00;
    localparam [1:0] ST_WAIT_FIRST = 2'b01;
    localparam [1:0] ST_COLLECT    = 2'b10;
    localparam [1:0] ST_DONE       = 2'b11;

    reg [1:0] state, next_state;

    // ------------------------------------------------------------
    // start_collect edge detect
    // ------------------------------------------------------------
    reg start_collect_d;
    wire start_collect_pulse;

    assign start_collect_pulse = start_collect & ~start_collect_d;

    // ------------------------------------------------------------
    // Internal control signals
    // ------------------------------------------------------------
    reg  buffer_clear_r;
    reg  buffer_write_en_r;

    reg  counter_clear_r;
    reg  counter_en_r;

    wire buffer_full_w;
    wire buffer_empty_w;
    wire overflow_error_w;

    wire [SYMBOL_WIDTH-1:0]       normalized_byte_w;
    wire [SYMBOL_INDEX_WIDTH-1:0] symbol_index_w;
    wire                          count_overflow_w;

    wire byte_accept;

    assign byte_ready      = (state == ST_WAIT_FIRST) || (state == ST_COLLECT);
    assign byte_accept     = byte_valid && byte_ready;

    assign collect_busy    = (state == ST_WAIT_FIRST) || (state == ST_COLLECT);
    assign collect_done    = (state == ST_DONE);
assign overflow_error  = overflow_error_w;
    assign normalized_byte = normalized_byte_w;

    // ------------------------------------------------------------
    // block_buffer
    // ------------------------------------------------------------
    block_buffer #(
        .BLOCK_SIZE       (BLOCK_SIZE),
        .DATA_WIDTH       (SYMBOL_WIDTH),
        .BLOCK_SIZE_WIDTH (BLOCK_SIZE_WIDTH),
        .ADDR_WIDTH       (ADDR_WIDTH)
    ) u_block_buffer (
        .clk            (clk),
        .rst_n          (rst_n),
        .clear          (buffer_clear_r),
        .write_en       (buffer_write_en_r),
        .write_data     (normalized_byte_w),
        .read_addr      (buffer_read_addr),
        .read_data      (buffer_read_data),
        .block_size     (block_size),
        .full           (buffer_full_w),
        .empty          (buffer_empty_w),
        .overflow_error (overflow_error_w)
    );

    // ------------------------------------------------------------
    // frequency_counter
    // ------------------------------------------------------------
    frequency_counter #(
        .ALPHABET_SIZE       (ALPHABET_SIZE),
        .SYMBOL_WIDTH        (SYMBOL_WIDTH),
        .COUNT_WIDTH         (COUNT_WIDTH),
        .SYMBOL_INDEX_WIDTH  (SYMBOL_INDEX_WIDTH),
        .ASCII_MIN           (ASCII_MIN),
        .ASCII_MAX           (ASCII_MAX),
        .DEFAULT_REMAP       (DEFAULT_REMAP)
    ) u_frequency_counter (
        .clk             (clk),
        .rst_n           (rst_n),
        .clear           (counter_clear_r),
        .count_en        (counter_en_r),
        .count_data      (byte_in),
        .read_index      (freq_read_index),
        .read_count      (freq_read_count),
        .normalized_byte (normalized_byte_w),
        .symbol_index    (symbol_index_w),
        .count_overflow  (count_overflow_w)
    );

    // ------------------------------------------------------------
    // Next-state logic
    // ------------------------------------------------------------
    always @(*) begin
        next_state = state;

        case (state)
            ST_IDLE: begin
                if (start_collect_pulse)
                    next_state = ST_WAIT_FIRST;
            end

            ST_WAIT_FIRST: begin
                if (byte_accept) begin
                    if (block_end)
                        next_state = ST_DONE;
                    else
                        next_state = ST_COLLECT;
                end
            end

            ST_COLLECT: begin
                if (byte_accept && block_end)
                    next_state = ST_DONE;
            end

            ST_DONE: begin
                if (start_collect_pulse)
                    next_state = ST_WAIT_FIRST;
            end

            default: begin
                next_state = ST_IDLE;
            end
        endcase
    end

    // ------------------------------------------------------------
    // Combinational control generation
// ------------------------------------------------------------
    always @(*) begin
        buffer_clear_r    = 1'b0;
        buffer_write_en_r = 1'b0;

        counter_clear_r   = 1'b0;
        counter_en_r      = 1'b0;

        case (state)
            ST_IDLE: begin
                if (start_collect_pulse) begin
                    buffer_clear_r  = 1'b1;
                    counter_clear_r = 1'b1;
                end
            end

            ST_WAIT_FIRST: begin
                if (byte_accept) begin
                    // Always allow block_buffer write request so it can
                    // raise overflow_error if already full.
                    buffer_write_en_r = 1'b1;

                    // Only count if buffer is not already full.
                    counter_en_r      = !buffer_full_w;
                end
            end

            ST_COLLECT: begin
                if (byte_accept) begin
                    buffer_write_en_r = 1'b1;
                    counter_en_r      = !buffer_full_w;
                end
            end

            ST_DONE: begin
                if (start_collect_pulse) begin
                    buffer_clear_r  = 1'b1;
                    counter_clear_r = 1'b1;
                end
            end

            default: begin
                buffer_clear_r    = 1'b0;
                buffer_write_en_r = 1'b0;
                counter_clear_r   = 1'b0;
                counter_en_r      = 1'b0;
            end
        endcase
    end

    // ------------------------------------------------------------
    // Sequential state + error handling
    // ------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state            <= ST_IDLE;
            start_collect_d  <= 1'b0;
            protocol_error   <= 1'b0;
        end
        else begin
            state           <= next_state;
            start_collect_d <= start_collect;

            // Clear protocol_error only on a new collect pulse
            if (start_collect_pulse) begin
                protocol_error <= 1'b0;
            end
            else begin
                // First accepted byte must have block_start
                if ((state == ST_WAIT_FIRST) && byte_accept && !block_start)
                    protocol_error <= 1'b1;

                // block_start must not reappear in the middle
                if ((state == ST_COLLECT) && byte_accept && block_start)
                    protocol_error <= 1'b1;

                // Counter overflow is treated as internal/protocol error.
                // The extra terms are inert, only to mark observed signals.
                if (count_overflow_w ||
                    (1'b0 && buffer_empty_w) ||
                    (1'b0 && (|symbol_index_w)))
                    protocol_error <= 1'b1;
            end
        end
    end

endmodule

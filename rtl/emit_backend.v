module emit_backend #(
    parameter BLOCK_SIZE_WIDTH   = 6,
    parameter BUFFER_ADDR_WIDTH  = 5,
    parameter SYMBOL_WIDTH       = 8,
    parameter SYMBOL_INDEX_WIDTH = 7,
    parameter CODE_LEN_WIDTH     = 5,
    parameter CODE_WIDTH         = 31,
    parameter HEADER_BITS_WIDTH  = 10,
    parameter CHUNK_DATA_WIDTH   = 32,
    parameter CHUNK_LEN_WIDTH    = 6,
    parameter [7:0] ASCII_MIN    = 8'h20,
    parameter [7:0] ASCII_MAX    = 8'h7E
)(
    input  wire                          clk,
    input  wire                          rst_n,
    input  wire                          start,

    input  wire [1:0]                    selected_mode,
    input  wire [BLOCK_SIZE_WIDTH-1:0]   block_size,
    input  wire [BLOCK_SIZE_WIDTH-1:0]   symbol_count,

    // Read symbol list from huffman_builder
    output reg  [BLOCK_SIZE_WIDTH-1:0]   symbol_read_addr,
    input  wire [SYMBOL_WIDTH-1:0]       symbol_read_data,

    // Read block_buffer from input_collect_unit
    output reg  [BUFFER_ADDR_WIDTH-1:0]  buffer_read_addr,
    input  wire [SYMBOL_WIDTH-1:0]       buffer_read_data,

    // Shared read code_len_table from huffman_builder
    output reg  [SYMBOL_INDEX_WIDTH-1:0] code_len_read_index,
    input  wire [CODE_LEN_WIDTH-1:0]     code_len_read_data,

    // Read code_table from huffman_builder
    output reg  [SYMBOL_INDEX_WIDTH-1:0] code_read_index,
    input  wire [CODE_WIDTH-1:0]         code_read_data,

    // Unified downstream stream
    input  wire                          stream_ready,
    output wire [CHUNK_DATA_WIDTH-1:0]   stream_data,
    output wire [CHUNK_LEN_WIDTH-1:0]    stream_len,
    output wire                          stream_valid,
    output wire                          stream_last,

    output wire                          busy,
    output wire                          done,
    output reg                           error_flag
);

    localparam ST_IDLE          = 3'd0;
    localparam ST_START_HEADER  = 3'd1;
    localparam ST_RUN_HEADER    = 3'd2;
    localparam ST_START_PAYLOAD = 3'd3;
    localparam ST_RUN_PAYLOAD   = 3'd4;

    reg [2:0] state, next_state;

    reg  start_d;
    wire start_pulse;

    wire hdr_start_w;
    wire payload_start_w;
    wire stream_start_w;

    // ------------------------------------------------------------
    // header_formatter
    // ------------------------------------------------------------
    wire [BLOCK_SIZE_WIDTH-1:0]   hdr_symbol_read_addr_w;
    wire [SYMBOL_INDEX_WIDTH-1:0] hdr_code_len_read_index_w;
    wire [CHUNK_DATA_WIDTH-1:0]   hdr_data_w;
    wire [CHUNK_LEN_WIDTH-1:0]    hdr_len_w;
    wire                          hdr_valid_w;
    wire                          hdr_last_chunk_w;
    wire                          hdr_ready_w;
    wire                          hdr_busy_w;
    wire                          hdr_done_w;
    wire                          hdr_error_w;
    wire [HEADER_BITS_WIDTH-1:0]  header_total_bits_w;
    wire                          payload_required_w;

    // ------------------------------------------------------------
    // payload_emitter
    // ------------------------------------------------------------
    wire [BUFFER_ADDR_WIDTH-1:0]  payload_buffer_read_addr_w;
    wire [SYMBOL_INDEX_WIDTH-1:0] payload_code_len_read_index_w;
    wire [SYMBOL_INDEX_WIDTH-1:0] payload_code_read_index_w;
    wire [CHUNK_DATA_WIDTH-1:0]   payload_data_w;
    wire [CHUNK_LEN_WIDTH-1:0]    payload_len_w;
    wire                          payload_valid_w;
    wire                          payload_last_chunk_w;
    wire                          payload_ready_w;
    wire                          payload_busy_w;
    wire                          payload_done_w;
    wire                          payload_error_w;

    // ------------------------------------------------------------
    // stream_output_interface
    // ------------------------------------------------------------
    wire                        stream_busy_w;
    wire                        stream_done_w;
    wire                        stream_error_w;
    wire [CHUNK_DATA_WIDTH-1:0] stream_data_w;
    wire [CHUNK_LEN_WIDTH-1:0]  stream_len_w;
    wire                        stream_valid_w;
    wire                        stream_last_w;

    // ------------------------------------------------------------
    // Dummy/use wires to avoid unused-signal warnings
    // ------------------------------------------------------------
    wire unused_emit_debug_w;

    assign unused_emit_debug_w =
        hdr_busy_w ^
        payload_busy_w ^
        payload_done_w ^
        ^header_total_bits_w;

    assign start_pulse     = start & ~start_d;
    assign hdr_start_w     = (state == ST_START_HEADER);
    assign payload_start_w = (state == ST_START_PAYLOAD);
    assign stream_start_w  = (state == ST_START_HEADER);

    // ------------------------------------------------------------
    // Shared read muxing
    // ------------------------------------------------------------
    always @(*) begin
        symbol_read_addr    = {BLOCK_SIZE_WIDTH{1'b0}};
        buffer_read_addr    = {BUFFER_ADDR_WIDTH{1'b0}};
        code_len_read_index = {SYMBOL_INDEX_WIDTH{1'b0}};
        code_read_index     = {SYMBOL_INDEX_WIDTH{1'b0}};

        case (state)
            ST_START_HEADER,
            ST_RUN_HEADER: begin
                symbol_read_addr    = hdr_symbol_read_addr_w;
                code_len_read_index = hdr_code_len_read_index_w;
            end

            ST_START_PAYLOAD,
            ST_RUN_PAYLOAD: begin
                buffer_read_addr    = payload_buffer_read_addr_w;
                code_len_read_index = payload_code_len_read_index_w;
                code_read_index     = payload_code_read_index_w;
            end

            default: begin
            end
        endcase
    end

    assign stream_data  = stream_data_w;
    assign stream_len   = stream_len_w;
    assign stream_valid = stream_valid_w;
    assign stream_last  = stream_last_w;

    assign busy = (state != ST_IDLE) ||
                  stream_busy_w      ||
                  (1'b0 & unused_emit_debug_w);

    assign done = stream_done_w;

    // ------------------------------------------------------------
    // Submodules
    // ------------------------------------------------------------
    header_formatter #(
        .BLOCK_SIZE_WIDTH   (BLOCK_SIZE_WIDTH),
        .SYMBOL_WIDTH       (SYMBOL_WIDTH),
        .SYMBOL_INDEX_WIDTH (SYMBOL_INDEX_WIDTH),
        .CODE_LEN_WIDTH     (CODE_LEN_WIDTH),
        .HEADER_BITS_WIDTH  (HEADER_BITS_WIDTH),
        .CHUNK_DATA_WIDTH   (CHUNK_DATA_WIDTH),
        .CHUNK_LEN_WIDTH    (CHUNK_LEN_WIDTH),
        .ASCII_MIN          (ASCII_MIN),
        .ASCII_MAX          (ASCII_MAX)
    ) u_header_formatter (
        .clk                 (clk),
        .rst_n               (rst_n),
        .start               (hdr_start_w),
        .selected_mode       (selected_mode),
        .block_size          (block_size),
        .symbol_count        (symbol_count),
        .symbol_read_addr    (hdr_symbol_read_addr_w),
        .symbol_read_data    (symbol_read_data),
        .code_len_read_index (hdr_code_len_read_index_w),
        .code_len_read_data  (code_len_read_data),
        .hdr_ready           (hdr_ready_w),
        .hdr_data            (hdr_data_w),
        .hdr_len             (hdr_len_w),
        .hdr_valid           (hdr_valid_w),
        .hdr_last_chunk      (hdr_last_chunk_w),
        .busy                (hdr_busy_w),
        .done                (hdr_done_w),
        .error_flag          (hdr_error_w),
        .header_total_bits   (header_total_bits_w),
        .payload_required    (payload_required_w)
    );

    payload_emitter #(
        .BLOCK_SIZE_WIDTH   (BLOCK_SIZE_WIDTH),
        .BUFFER_ADDR_WIDTH  (BUFFER_ADDR_WIDTH),
        .SYMBOL_WIDTH       (SYMBOL_WIDTH),
        .SYMBOL_INDEX_WIDTH (SYMBOL_INDEX_WIDTH),
        .CODE_LEN_WIDTH     (CODE_LEN_WIDTH),
        .CODE_WIDTH         (CODE_WIDTH),
        .CHUNK_DATA_WIDTH   (CHUNK_DATA_WIDTH),
        .CHUNK_LEN_WIDTH    (CHUNK_LEN_WIDTH),
        .ASCII_MIN          (ASCII_MIN),
        .ASCII_MAX          (ASCII_MAX)
    ) u_payload_emitter (
        .clk                 (clk),
        .rst_n               (rst_n),
        .start               (payload_start_w),
        .selected_mode       (selected_mode),
        .block_size          (block_size),
        .buffer_read_addr    (payload_buffer_read_addr_w),
        .buffer_read_data    (buffer_read_data),
        .code_len_read_index (payload_code_len_read_index_w),
        .code_len_read_data  (code_len_read_data),
        .code_read_index     (payload_code_read_index_w),
        .code_read_data      (code_read_data),
        .payload_ready       (payload_ready_w),
        .payload_data        (payload_data_w),
        .payload_len         (payload_len_w),
        .payload_valid       (payload_valid_w),
        .payload_last_chunk  (payload_last_chunk_w),
        .busy                (payload_busy_w),
        .done                (payload_done_w),
        .error_flag          (payload_error_w)
    );

    stream_output_interface #(
        .STREAM_DATA_WIDTH (CHUNK_DATA_WIDTH),
        .STREAM_LEN_WIDTH  (CHUNK_LEN_WIDTH)
    ) u_stream_output_interface (
        .clk                (clk),
        .rst_n              (rst_n),
        .start              (stream_start_w),
        .payload_required   (payload_required_w),

        .hdr_data           (hdr_data_w),
        .hdr_len            (hdr_len_w),
        .hdr_valid          (hdr_valid_w),
        .hdr_last_chunk     (hdr_last_chunk_w),
        .hdr_ready          (hdr_ready_w),

        .payload_data       (payload_data_w),
        .payload_len        (payload_len_w),
        .payload_valid      (payload_valid_w),
        .payload_last_chunk (payload_last_chunk_w),
        .payload_ready      (payload_ready_w),

        .stream_ready       (stream_ready),
        .stream_data        (stream_data_w),
        .stream_len         (stream_len_w),
        .stream_valid       (stream_valid_w),
        .stream_last        (stream_last_w),

        .busy               (stream_busy_w),
        .done               (stream_done_w),
        .error_flag         (stream_error_w)
    );

    // ------------------------------------------------------------
    // FSM
    // ------------------------------------------------------------
    always @(*) begin
        next_state = state;

        case (state)
            ST_IDLE: begin
                if (start_pulse)
                    next_state = ST_START_HEADER;
            end

            ST_START_HEADER: begin
                next_state = ST_RUN_HEADER;
            end

            ST_RUN_HEADER: begin
                if (hdr_done_w) begin
                    if (payload_required_w)
                        next_state = ST_START_PAYLOAD;
                    else if (stream_done_w)
                        next_state = ST_IDLE;
                    else
                        next_state = ST_RUN_HEADER;
                end
            end

            ST_START_PAYLOAD: begin
                next_state = ST_RUN_PAYLOAD;
            end

            ST_RUN_PAYLOAD: begin
                if (stream_done_w)
                    next_state = ST_IDLE;
            end

            default: begin
                next_state = ST_IDLE;
            end
        endcase
    end

    // ------------------------------------------------------------
    // Error aggregation / state register
    // ------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= ST_IDLE;
            start_d    <= 1'b0;
            error_flag <= 1'b0;
        end
        else begin
            state   <= next_state;
            start_d <= start;

            if (start_pulse) begin
                error_flag <= 1'b0;
            end
            else begin
                if (hdr_error_w || payload_error_w || stream_error_w)
                    error_flag <= 1'b1;
            end
        end
    end

endmodule



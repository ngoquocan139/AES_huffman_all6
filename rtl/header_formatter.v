module header_formatter #(
    parameter BLOCK_SIZE_WIDTH   = 6,
    parameter SYMBOL_WIDTH       = 8,
    parameter SYMBOL_INDEX_WIDTH = 7,
    parameter CODE_LEN_WIDTH     = 5,
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

    // Read symbol list
    output reg  [BLOCK_SIZE_WIDTH-1:0]   symbol_read_addr,
    input  wire [SYMBOL_WIDTH-1:0]       symbol_read_data,

    // Read code length
    output reg  [SYMBOL_INDEX_WIDTH-1:0] code_len_read_index,
    input  wire [CODE_LEN_WIDTH-1:0]     code_len_read_data,

    // Header chunk handshake
    input  wire                          hdr_ready,

    output reg  [CHUNK_DATA_WIDTH-1:0]   hdr_data,
    output reg  [CHUNK_LEN_WIDTH-1:0]    hdr_len,
    output reg                           hdr_valid,
    output reg                           hdr_last_chunk,

    output wire                          busy,
    output wire                          done,
    output reg                           error_flag,

    output reg  [HEADER_BITS_WIDTH-1:0]  header_total_bits,
    output reg                           payload_required
);

    localparam ST_IDLE         = 4'd0;
    localparam ST_INIT         = 4'd1;
    localparam ST_READ_SYMBOL  = 4'd2;
    localparam ST_READ_CODE    = 4'd3;
    localparam ST_LOAD_ENTRY   = 4'd4;
    localparam ST_EMIT_FIELD   = 4'd5;
    localparam ST_SEND_CHUNK   = 4'd6;
    localparam ST_DONE         = 4'd7;
    localparam ST_READ_ONE     = 4'd8;
    localparam ST_LOAD_ONE     = 4'd9;
    localparam ST_FLUSH_LAST   = 4'd10;

    localparam [1:0] MODE_RAW_FULL       = 2'b00;
    localparam [1:0] MODE_RAW_PARTIAL    = 2'b01;
    localparam [1:0] MODE_COMPRESSED     = 2'b10;
    localparam [1:0] MODE_ONE_SYMBOL     = 2'b11;

    localparam [HEADER_BITS_WIDTH-1:0] RAW_FULL_HEADER_BITS    = 10'd2;
    localparam [HEADER_BITS_WIDTH-1:0] RAW_PARTIAL_HEADER_BITS = 10'd8;
    localparam [HEADER_BITS_WIDTH-1:0] COMP_BASE_BITS          = 10'd14;
    localparam [HEADER_BITS_WIDTH-1:0] ONE_SYMBOL_HEADER_BITS  = 10'd16;

    localparam AFTER_DONE      = 2'd0;
    localparam AFTER_COMP_BASE = 2'd1;
    localparam AFTER_ENTRY     = 2'd2;

    reg [3:0] state;
    reg [3:0] post_send_state_r;

    reg  start_d;
    wire start_pulse;

    reg [BLOCK_SIZE_WIDTH-1:0]  sym_idx;
    reg [SYMBOL_WIDTH-1:0]      symbol_data_r;
    reg [CODE_LEN_WIDTH-1:0]    code_len_data_r;

    reg [15:0]                  field_data_r;
    reg [4:0]                   field_len_r;
    reg [4:0]                   field_pos_r;
    reg [1:0]                   after_field_r;

    reg [CHUNK_DATA_WIDTH-1:0]  chunk_data_r;
    reg [CHUNK_LEN_WIDTH-1:0]   chunk_len_r;

`ifndef SYNTHESIS
    localparam [HEADER_BITS_WIDTH-1:0] MAX_HEADER_BITS = 10'd833;
    reg [HEADER_BITS_WIDTH-1:0] bit_ptr;
    reg [HEADER_BITS_WIDTH-1:0] send_ptr;
    reg [MAX_HEADER_BITS-1:0] header_bits;
    wire debug_unused_w;
`endif

    wire [BLOCK_SIZE_WIDTH-1:0] safe_symbol_count_w;
    wire                        mode_is_raw_full_w;
    wire                        mode_is_raw_partial_w;
    wire                        mode_is_compressed_w;
    wire                        mode_is_one_symbol_w;
    wire                        field_bit_w;
    wire                        field_last_bit_w;
    wire                        chunk_full_after_bit_w;
    wire [CHUNK_DATA_WIDTH-1:0] chunk_data_with_bit_w;

`include "huffman_symbol_map.vh"

    assign start_pulse = start & ~start_d;

    assign mode_is_raw_full_w    = (selected_mode == MODE_RAW_FULL);
    assign mode_is_raw_partial_w = (selected_mode == MODE_RAW_PARTIAL);
    assign mode_is_compressed_w  = (selected_mode == MODE_COMPRESSED);
    assign mode_is_one_symbol_w  = (selected_mode == MODE_ONE_SYMBOL);

    assign safe_symbol_count_w = symbol_count;
    assign field_bit_w = field_data_r[field_pos_r[3:0]];
    assign field_last_bit_w = (field_pos_r == (field_len_r - 5'd1));
    assign chunk_full_after_bit_w = (chunk_len_r == (CHUNK_DATA_WIDTH - 1));
    assign chunk_data_with_bit_w =
        chunk_data_r |
        ({{(CHUNK_DATA_WIDTH-1){1'b0}}, field_bit_w} << chunk_len_r[4:0]);
`ifndef SYNTHESIS
    assign debug_unused_w = (^header_bits) ^ (^bit_ptr) ^ (^send_ptr);
`endif

    assign busy = (state == ST_INIT)        ||
                  (state == ST_READ_ONE)    ||
                  (state == ST_LOAD_ONE)    ||
                  (state == ST_READ_SYMBOL) ||
                  (state == ST_READ_CODE)   ||
                  (state == ST_LOAD_ENTRY)  ||
                  (state == ST_EMIT_FIELD)  ||
                  (state == ST_FLUSH_LAST)  ||
                  (state == ST_SEND_CHUNK)
`ifndef SYNTHESIS
                  || (1'b0 & debug_unused_w)
`endif
                  ;

    assign done = (state == ST_DONE);

    // ------------------------------------------------------------
    // Read interfaces
    // ------------------------------------------------------------
    always @(*) begin
        if (state == ST_READ_SYMBOL)
            symbol_read_addr = sym_idx;
        else
            symbol_read_addr = {BLOCK_SIZE_WIDTH{1'b0}};
    end

    always @(*) begin
        if ((state == ST_READ_CODE) && huffman_symbol_valid(symbol_data_r))
            code_len_read_index = huffman_symbol_to_index(symbol_data_r);
        else
            code_len_read_index = {SYMBOL_INDEX_WIDTH{1'b0}};
    end

    // ------------------------------------------------------------
    // Main FSM
    // ------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state             <= ST_IDLE;
            post_send_state_r <= ST_IDLE;
            start_d           <= 1'b0;

            sym_idx           <= {BLOCK_SIZE_WIDTH{1'b0}};
            symbol_data_r     <= {SYMBOL_WIDTH{1'b0}};
            code_len_data_r   <= {CODE_LEN_WIDTH{1'b0}};

            field_data_r      <= 16'b0;
            field_len_r       <= 5'b0;
            field_pos_r       <= 5'b0;
            after_field_r     <= AFTER_DONE;

            chunk_data_r      <= {CHUNK_DATA_WIDTH{1'b0}};
            chunk_len_r       <= {CHUNK_LEN_WIDTH{1'b0}};

`ifndef SYNTHESIS
            bit_ptr           <= {HEADER_BITS_WIDTH{1'b0}};
            send_ptr          <= {HEADER_BITS_WIDTH{1'b0}};
            header_bits       <= {MAX_HEADER_BITS{1'b0}};
`endif

            hdr_data          <= {CHUNK_DATA_WIDTH{1'b0}};
            hdr_len           <= {CHUNK_LEN_WIDTH{1'b0}};
            hdr_valid         <= 1'b0;
            hdr_last_chunk    <= 1'b0;

            error_flag        <= 1'b0;
            header_total_bits <= {HEADER_BITS_WIDTH{1'b0}};
            payload_required  <= 1'b0;
        end
        else begin
            start_d <= start;

            case (state)
                ST_IDLE: begin
                    hdr_valid      <= 1'b0;
                    hdr_last_chunk <= 1'b0;

                    if (start_pulse)
                        state <= ST_INIT;
                end

                ST_INIT: begin
                    error_flag        <= 1'b0;
                    header_total_bits <= {HEADER_BITS_WIDTH{1'b0}};
                    payload_required  <= 1'b0;

                    sym_idx           <= {BLOCK_SIZE_WIDTH{1'b0}};
                    symbol_data_r     <= {SYMBOL_WIDTH{1'b0}};
                    code_len_data_r   <= {CODE_LEN_WIDTH{1'b0}};

                    field_data_r      <= 16'b0;
                    field_len_r       <= 5'b0;
                    field_pos_r       <= 5'b0;
                    after_field_r     <= AFTER_DONE;

                    chunk_data_r      <= {CHUNK_DATA_WIDTH{1'b0}};
                    chunk_len_r       <= {CHUNK_LEN_WIDTH{1'b0}};
                    post_send_state_r <= ST_IDLE;

`ifndef SYNTHESIS
                    bit_ptr           <= {HEADER_BITS_WIDTH{1'b0}};
                    send_ptr          <= {HEADER_BITS_WIDTH{1'b0}};
                    header_bits       <= {MAX_HEADER_BITS{1'b0}};
`endif

                    hdr_data          <= {CHUNK_DATA_WIDTH{1'b0}};
                    hdr_len           <= {CHUNK_LEN_WIDTH{1'b0}};
                    hdr_valid         <= 1'b0;
                    hdr_last_chunk    <= 1'b0;

                    if (mode_is_one_symbol_w)
                        payload_required <= 1'b0;
                    else if (block_size != {BLOCK_SIZE_WIDTH{1'b0}})
                        payload_required <= 1'b1;

                    if (block_size > 6'd32)
                        error_flag <= 1'b1;

                    if (mode_is_raw_full_w && (block_size != 6'd32))
                        error_flag <= 1'b1;

                    if (mode_is_raw_partial_w && (block_size == 6'd32))
                        error_flag <= 1'b1;

                    if (mode_is_compressed_w &&
                        (block_size == {BLOCK_SIZE_WIDTH{1'b0}}) &&
                        (symbol_count != {BLOCK_SIZE_WIDTH{1'b0}}))
                        error_flag <= 1'b1;

                    if (mode_is_one_symbol_w && (symbol_count != 6'd1))
                        error_flag <= 1'b1;

                    if (mode_is_raw_full_w) begin
                        field_data_r      <= {14'b0, MODE_RAW_FULL};
                        field_len_r       <= 5'd2;
                        field_pos_r       <= 5'd0;
                        after_field_r     <= AFTER_DONE;
                        header_total_bits <= RAW_FULL_HEADER_BITS;
                        state             <= ST_EMIT_FIELD;
                    end
                    else if (mode_is_raw_partial_w) begin
                        field_data_r      <= {8'b0, block_size, MODE_RAW_PARTIAL};
                        field_len_r       <= 5'd8;
                        field_pos_r       <= 5'd0;
                        after_field_r     <= AFTER_DONE;
                        header_total_bits <= RAW_PARTIAL_HEADER_BITS;
                        state             <= ST_EMIT_FIELD;
                    end
                    else if (mode_is_one_symbol_w) begin
                        header_total_bits <= ONE_SYMBOL_HEADER_BITS;
                        state             <= ST_READ_ONE;
                    end
                    else begin
                        field_data_r      <= {2'b0, safe_symbol_count_w, block_size, MODE_COMPRESSED};
                        field_len_r       <= 5'd14;
                        field_pos_r       <= 5'd0;
                        after_field_r     <= AFTER_COMP_BASE;
                        header_total_bits <= COMP_BASE_BITS +
                                             ({{(HEADER_BITS_WIDTH-BLOCK_SIZE_WIDTH){1'b0}}, safe_symbol_count_w} << 3) +
                                             ({{(HEADER_BITS_WIDTH-BLOCK_SIZE_WIDTH){1'b0}}, safe_symbol_count_w} << 2) +
                                             {{(HEADER_BITS_WIDTH-BLOCK_SIZE_WIDTH){1'b0}}, safe_symbol_count_w};
                        state             <= ST_EMIT_FIELD;
                    end
                end

                ST_READ_ONE: begin
                    symbol_data_r <= symbol_read_data;
                    state         <= ST_LOAD_ONE;
                end

                ST_LOAD_ONE: begin
                    if (!huffman_symbol_valid(symbol_data_r))
                        error_flag <= 1'b1;

                    field_data_r  <= {symbol_data_r, block_size, MODE_ONE_SYMBOL};
                    field_len_r   <= 5'd16;
                    field_pos_r   <= 5'd0;
                    after_field_r <= AFTER_DONE;
                    state         <= ST_EMIT_FIELD;
                end

                ST_READ_SYMBOL: begin
                    symbol_data_r <= symbol_read_data;
                    state         <= ST_READ_CODE;
                end

                ST_READ_CODE: begin
                    code_len_data_r <= code_len_read_data;
                    state           <= ST_LOAD_ENTRY;
                end

                ST_LOAD_ENTRY: begin
                    if (!huffman_symbol_valid(symbol_data_r))
                        error_flag <= 1'b1;

                    if (code_len_data_r == {CODE_LEN_WIDTH{1'b0}})
                        error_flag <= 1'b1;

                    field_data_r  <= {3'b0, code_len_data_r, symbol_data_r};
                    field_len_r   <= 5'd13;
                    field_pos_r   <= 5'd0;
                    after_field_r <= AFTER_ENTRY;
                    state         <= ST_EMIT_FIELD;
                end

                ST_EMIT_FIELD: begin
`ifndef SYNTHESIS
                    if (bit_ptr < MAX_HEADER_BITS)
                        header_bits[bit_ptr] <= field_bit_w;
                    bit_ptr <= bit_ptr + {{(HEADER_BITS_WIDTH-1){1'b0}}, 1'b1};
`endif

                    if (chunk_full_after_bit_w) begin
                        hdr_data       <= chunk_data_with_bit_w;
                        hdr_len        <= CHUNK_DATA_WIDTH[CHUNK_LEN_WIDTH-1:0];
                        hdr_valid      <= 1'b1;
                        hdr_last_chunk <= 1'b0;
                        chunk_data_r   <= {CHUNK_DATA_WIDTH{1'b0}};
                        chunk_len_r    <= {CHUNK_LEN_WIDTH{1'b0}};
                        state          <= ST_SEND_CHUNK;

                        if (field_last_bit_w) begin
                            case (after_field_r)
                                AFTER_DONE: begin
                                    hdr_last_chunk    <= 1'b1;
                                    post_send_state_r <= ST_DONE;
                                end
                                AFTER_COMP_BASE: begin
                                    if (safe_symbol_count_w == {BLOCK_SIZE_WIDTH{1'b0}}) begin
                                        hdr_last_chunk    <= 1'b1;
                                        post_send_state_r <= ST_DONE;
                                    end
                                    else begin
                                        post_send_state_r <= ST_READ_SYMBOL;
                                    end
                                end
                                AFTER_ENTRY: begin
                                    if (sym_idx == (safe_symbol_count_w - {{(BLOCK_SIZE_WIDTH-1){1'b0}}, 1'b1})) begin
                                        hdr_last_chunk    <= 1'b1;
                                        post_send_state_r <= ST_DONE;
                                    end
                                    else begin
                                        sym_idx           <= sym_idx + {{(BLOCK_SIZE_WIDTH-1){1'b0}}, 1'b1};
                                        post_send_state_r <= ST_READ_SYMBOL;
                                    end
                                end
                                default: begin
                                    hdr_last_chunk    <= 1'b1;
                                    post_send_state_r <= ST_DONE;
                                end
                            endcase
                        end
                        else begin
                            field_pos_r       <= field_pos_r + 5'd1;
                            post_send_state_r <= ST_EMIT_FIELD;
                        end
                    end
                    else begin
                        chunk_data_r <= chunk_data_with_bit_w;
                        chunk_len_r  <= chunk_len_r + {{(CHUNK_LEN_WIDTH-1){1'b0}}, 1'b1};

                        if (field_last_bit_w) begin
                            case (after_field_r)
                                AFTER_DONE: begin
                                    state <= ST_FLUSH_LAST;
                                end
                                AFTER_COMP_BASE: begin
                                    if (safe_symbol_count_w == {BLOCK_SIZE_WIDTH{1'b0}})
                                        state <= ST_FLUSH_LAST;
                                    else
                                        state <= ST_READ_SYMBOL;
                                end
                                AFTER_ENTRY: begin
                                    if (sym_idx == (safe_symbol_count_w - {{(BLOCK_SIZE_WIDTH-1){1'b0}}, 1'b1})) begin
                                        state <= ST_FLUSH_LAST;
                                    end
                                    else begin
                                        sym_idx <= sym_idx + {{(BLOCK_SIZE_WIDTH-1){1'b0}}, 1'b1};
                                        state   <= ST_READ_SYMBOL;
                                    end
                                end
                                default: begin
                                    state <= ST_FLUSH_LAST;
                                end
                            endcase
                        end
                        else begin
                            field_pos_r <= field_pos_r + 5'd1;
                            state       <= ST_EMIT_FIELD;
                        end
                    end
                end

                ST_FLUSH_LAST: begin
                    hdr_data          <= chunk_data_r;
                    hdr_len           <= chunk_len_r;
                    hdr_valid         <= 1'b1;
                    hdr_last_chunk    <= 1'b1;
                    chunk_data_r      <= {CHUNK_DATA_WIDTH{1'b0}};
                    chunk_len_r       <= {CHUNK_LEN_WIDTH{1'b0}};
                    post_send_state_r <= ST_DONE;
                    state             <= ST_SEND_CHUNK;
                end

                ST_SEND_CHUNK: begin
                    if (hdr_valid && hdr_ready) begin
`ifndef SYNTHESIS
                        send_ptr <= send_ptr + {{(HEADER_BITS_WIDTH-CHUNK_LEN_WIDTH){1'b0}}, hdr_len};
`endif
                        hdr_valid <= 1'b0;

                        if (hdr_last_chunk) begin
                            hdr_last_chunk <= 1'b0;
                            state          <= ST_DONE;
                        end
                        else begin
                            state <= post_send_state_r;
                        end
                    end
                end

                ST_DONE: begin
                    if (start_pulse)
                        state <= ST_INIT;
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule

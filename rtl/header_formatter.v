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
    localparam ST_WRITE_SYMBOL = 4'd4;
    localparam ST_PREP_CHUNK   = 4'd5;
    localparam ST_SEND_CHUNK   = 4'd6;
    localparam ST_DONE         = 4'd7;
    localparam ST_READ_ONE     = 4'd8;
    localparam ST_WRITE_ONE    = 4'd9;

    localparam [1:0] MODE_RAW_FULL       = 2'b00;
    localparam [1:0] MODE_RAW_PARTIAL    = 2'b01;
    localparam [1:0] MODE_COMPRESSED     = 2'b10;
    localparam [1:0] MODE_ONE_SYMBOL     = 2'b11;

    localparam [HEADER_BITS_WIDTH-1:0] RAW_FULL_HEADER_BITS    = 10'd2;
    localparam [HEADER_BITS_WIDTH-1:0] RAW_PARTIAL_HEADER_BITS = 10'd8;   // 2 + 6
    localparam [HEADER_BITS_WIDTH-1:0] COMP_BASE_BITS          = 10'd14;  // 2 + 6 + 6
    localparam [HEADER_BITS_WIDTH-1:0] ONE_SYMBOL_HEADER_BITS  = 10'd16;  // 2 + 6 + 8

    localparam [HEADER_BITS_WIDTH-1:0] MAX_HEADER_BITS  = 10'd833; // 14 + 13*63
    localparam HEADER_INDEX_WIDTH = HEADER_BITS_WIDTH;

    reg [3:0] state;

    reg  start_d;
    wire start_pulse;

    reg [HEADER_BITS_WIDTH-1:0] bit_ptr;
    reg [HEADER_BITS_WIDTH-1:0] send_ptr;
    reg [BLOCK_SIZE_WIDTH-1:0]  sym_idx;

    reg [MAX_HEADER_BITS-1:0] header_bits;
    reg [SYMBOL_WIDTH-1:0]    symbol_data_r;
    reg [CODE_LEN_WIDTH-1:0]  code_len_data_r;

    wire [BLOCK_SIZE_WIDTH-1:0] safe_symbol_count_w;
    wire                        mode_is_raw_full_w;
    wire                        mode_is_raw_partial_w;
    wire                        mode_is_compressed_w;
    wire                        mode_is_one_symbol_w;

    reg  [CHUNK_DATA_WIDTH-1:0] next_chunk_data_r;
    reg  [CHUNK_LEN_WIDTH-1:0]  next_chunk_len_r;
    reg                         next_chunk_last_r;
    reg  [HEADER_BITS_WIDTH-1:0] remaining_bits_r;

    wire [HEADER_INDEX_WIDTH-1:0] send_ptr_idx_w;
    wire [HEADER_INDEX_WIDTH-1:0] bit_ptr_idx_w;

    integer i;
    integer j;
    integer t;

`include "huffman_symbol_map.vh"

    assign start_pulse = start & ~start_d;

    assign mode_is_raw_full_w    = (selected_mode == MODE_RAW_FULL);
    assign mode_is_raw_partial_w = (selected_mode == MODE_RAW_PARTIAL);
    assign mode_is_compressed_w  = (selected_mode == MODE_COMPRESSED);
    assign mode_is_one_symbol_w  = (selected_mode == MODE_ONE_SYMBOL);

    assign safe_symbol_count_w = symbol_count;

    assign send_ptr_idx_w = send_ptr[HEADER_INDEX_WIDTH-1:0];
    assign bit_ptr_idx_w  = bit_ptr[HEADER_INDEX_WIDTH-1:0];

    assign busy = (state == ST_INIT)         ||
                  (state == ST_READ_SYMBOL)  ||
                  (state == ST_READ_CODE)    ||
                  (state == ST_WRITE_SYMBOL) ||
                  (state == ST_READ_ONE)     ||
                  (state == ST_WRITE_ONE)    ||
                  (state == ST_PREP_CHUNK)   ||
                  (state == ST_SEND_CHUNK);

    assign done = (state == ST_DONE);

    // ------------------------------------------------------------
    // Read interfaces
    // ------------------------------------------------------------
    always @(*) begin
        if (state == ST_READ_SYMBOL)
            symbol_read_addr = sym_idx;
        else if (state == ST_READ_ONE)
            symbol_read_addr = {BLOCK_SIZE_WIDTH{1'b0}};
        else
            symbol_read_addr = {BLOCK_SIZE_WIDTH{1'b0}};
    end

    always @(*) begin
        if ((state == ST_READ_CODE) &&
            huffman_symbol_valid(symbol_data_r))
            code_len_read_index = huffman_symbol_to_index(symbol_data_r);
        else
            code_len_read_index = {SYMBOL_INDEX_WIDTH{1'b0}};
    end

    // ------------------------------------------------------------
    // Next output chunk
    // ------------------------------------------------------------
    always @(*) begin
        next_chunk_data_r = {CHUNK_DATA_WIDTH{1'b0}};
        next_chunk_len_r  = {CHUNK_LEN_WIDTH{1'b0}};
        next_chunk_last_r = 1'b0;
        remaining_bits_r  = {HEADER_BITS_WIDTH{1'b0}};

        if (header_total_bits > send_ptr) begin
            remaining_bits_r = header_total_bits - send_ptr;

            if (remaining_bits_r > CHUNK_DATA_WIDTH[HEADER_BITS_WIDTH-1:0])
                next_chunk_len_r = CHUNK_DATA_WIDTH[CHUNK_LEN_WIDTH-1:0];
            else
                next_chunk_len_r = remaining_bits_r[CHUNK_LEN_WIDTH-1:0];

            next_chunk_last_r =
                (remaining_bits_r <= CHUNK_DATA_WIDTH[HEADER_BITS_WIDTH-1:0]);

            for (t = 0; t < CHUNK_DATA_WIDTH; t = t + 1) begin
                if ((send_ptr + t[HEADER_BITS_WIDTH-1:0]) < header_total_bits)
                    next_chunk_data_r[t] = header_bits[send_ptr_idx_w + t[HEADER_INDEX_WIDTH-1:0]];
            end
        end
    end

    // ------------------------------------------------------------
    // Main FSM
    // ------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state             <= ST_IDLE;
            start_d           <= 1'b0;

            bit_ptr           <= {HEADER_BITS_WIDTH{1'b0}};
            send_ptr          <= {HEADER_BITS_WIDTH{1'b0}};
            sym_idx           <= {BLOCK_SIZE_WIDTH{1'b0}};

            hdr_data          <= {CHUNK_DATA_WIDTH{1'b0}};
            hdr_len           <= {CHUNK_LEN_WIDTH{1'b0}};
            hdr_valid         <= 1'b0;
            hdr_last_chunk    <= 1'b0;

            error_flag        <= 1'b0;
            header_total_bits <= {HEADER_BITS_WIDTH{1'b0}};
            payload_required  <= 1'b0;

            header_bits       <= {MAX_HEADER_BITS{1'b0}};
            symbol_data_r     <= {SYMBOL_WIDTH{1'b0}};
            code_len_data_r   <= {CODE_LEN_WIDTH{1'b0}};
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
                    bit_ptr           <= {HEADER_BITS_WIDTH{1'b0}};
                    send_ptr          <= {HEADER_BITS_WIDTH{1'b0}};
                    sym_idx           <= {BLOCK_SIZE_WIDTH{1'b0}};

                    hdr_data          <= {CHUNK_DATA_WIDTH{1'b0}};
                    hdr_len           <= {CHUNK_LEN_WIDTH{1'b0}};
                    hdr_valid         <= 1'b0;
                    hdr_last_chunk    <= 1'b0;

                    header_bits       <= {MAX_HEADER_BITS{1'b0}};
                    symbol_data_r     <= {SYMBOL_WIDTH{1'b0}};
                    code_len_data_r   <= {CODE_LEN_WIDTH{1'b0}};

                    // payload requirement by mode
                    if (mode_is_one_symbol_w)
                        payload_required <= 1'b0;
                    else if (block_size != {BLOCK_SIZE_WIDTH{1'b0}})
                        payload_required <= 1'b1;
                    else
                        payload_required <= 1'b0;

                    // integrity checks
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

                    // ------------------------------------------------
                    // RAW_FULL: 00
                    // ------------------------------------------------
                    if (mode_is_raw_full_w) begin
                        header_bits[0]    <= MODE_RAW_FULL[0];
                        header_bits[1]    <= MODE_RAW_FULL[1];
                        header_total_bits <= RAW_FULL_HEADER_BITS;
                        bit_ptr           <= RAW_FULL_HEADER_BITS;
                        state             <= ST_PREP_CHUNK;
                    end

                    // ------------------------------------------------
                    // RAW_PARTIAL: 01 + block_size[5:0]
                    // ------------------------------------------------
                    else if (mode_is_raw_partial_w) begin
                        header_bits[0] <= MODE_RAW_PARTIAL[0];
                        header_bits[1] <= MODE_RAW_PARTIAL[1];

                        for (i = 0; i < 6; i = i + 1)
                            header_bits[2 + i] <= block_size[i];

                        header_total_bits <= RAW_PARTIAL_HEADER_BITS;
                        bit_ptr           <= RAW_PARTIAL_HEADER_BITS;
                        state             <= ST_PREP_CHUNK;
                    end

                    // ------------------------------------------------
                    // ONE_SYMBOL_COMPRESSED: 11 + block_size[5:0] + symbol_id[7:0]
                    // ------------------------------------------------
                    else if (mode_is_one_symbol_w) begin
                        header_bits[0] <= MODE_ONE_SYMBOL[0];
                        header_bits[1] <= MODE_ONE_SYMBOL[1];

                        for (i = 0; i < 6; i = i + 1)
                            header_bits[2 + i] <= block_size[i];

                        header_total_bits <= ONE_SYMBOL_HEADER_BITS;
                        bit_ptr           <= ONE_SYMBOL_HEADER_BITS;
                        state             <= ST_READ_ONE;
                    end

                    // ------------------------------------------------
                    // COMPRESSED: 10 + block_size[5:0] + symbol_count[5:0] + entries
                    // ------------------------------------------------
                    else begin
                        header_bits[0] <= MODE_COMPRESSED[0];
                        header_bits[1] <= MODE_COMPRESSED[1];

                        for (i = 0; i < 6; i = i + 1)
                            header_bits[2 + i] <= block_size[i];

                        for (i = 0; i < 6; i = i + 1)
                            header_bits[8 + i] <= symbol_count[i];

                        header_total_bits <= COMP_BASE_BITS +
                                             ({{(HEADER_BITS_WIDTH-BLOCK_SIZE_WIDTH){1'b0}}, safe_symbol_count_w} << 3) +
                                             ({{(HEADER_BITS_WIDTH-BLOCK_SIZE_WIDTH){1'b0}}, safe_symbol_count_w} << 2) +
                                             {{(HEADER_BITS_WIDTH-BLOCK_SIZE_WIDTH){1'b0}}, safe_symbol_count_w};

                        bit_ptr <= COMP_BASE_BITS;

                        if (safe_symbol_count_w == {BLOCK_SIZE_WIDTH{1'b0}})
                            state <= ST_PREP_CHUNK;
                        else
                            state <= ST_READ_SYMBOL;
                    end
                end

                // ----------------------------------------------------
                // Register one-symbol header tail before writing it into
                // the wide header register.
                // ----------------------------------------------------
                ST_READ_ONE: begin
                    symbol_data_r <= symbol_read_data;
                    state         <= ST_WRITE_ONE;
                end

                ST_WRITE_ONE: begin
                    if (!huffman_symbol_valid(symbol_data_r))
                        error_flag <= 1'b1;

                    for (j = 0; j < 8; j = j + 1)
                        header_bits[8 + j] <= symbol_data_r[j];

                    state <= ST_PREP_CHUNK;
                end

                // ----------------------------------------------------
                // Build compressed symbol entries. The symbol list and
                // canonical code length readbacks are pipelined to avoid
                // timing paths directly into the 430-bit header register.
                // ----------------------------------------------------
                ST_READ_SYMBOL: begin
                    symbol_data_r <= symbol_read_data;
                    state         <= ST_READ_CODE;
                end

                ST_READ_CODE: begin
                    code_len_data_r <= code_len_read_data;
                    state           <= ST_WRITE_SYMBOL;
                end

                ST_WRITE_SYMBOL: begin
                    if (sym_idx < safe_symbol_count_w) begin
                        if (!huffman_symbol_valid(symbol_data_r))
                            error_flag <= 1'b1;

                        if (code_len_data_r == {CODE_LEN_WIDTH{1'b0}})
                            error_flag <= 1'b1;

                        // symbol_id[7:0]
                        for (j = 0; j < 8; j = j + 1)
                            header_bits[bit_ptr_idx_w + j[HEADER_INDEX_WIDTH-1:0]] <= symbol_data_r[j];

                        // code_len[4:0]
                        for (j = 0; j < 5; j = j + 1)
                            header_bits[bit_ptr_idx_w + 9'd8 + j[HEADER_INDEX_WIDTH-1:0]] <= code_len_data_r[j];

                        bit_ptr <= bit_ptr + 10'd13;

                        if (sym_idx == safe_symbol_count_w - {{(BLOCK_SIZE_WIDTH-1){1'b0}},1'b1})
                            state <= ST_PREP_CHUNK;
                        else
                            state <= ST_READ_SYMBOL;

                        sym_idx <= sym_idx +
                                   {{(BLOCK_SIZE_WIDTH-1){1'b0}},1'b1};
                    end
                    else begin
                        state <= ST_PREP_CHUNK;
                    end
                end

                ST_PREP_CHUNK: begin
                    hdr_data       <= next_chunk_data_r;
                    hdr_len        <= next_chunk_len_r;
                    hdr_valid      <= 1'b1;
                    hdr_last_chunk <= next_chunk_last_r;
                    state          <= ST_SEND_CHUNK;
                end

                ST_SEND_CHUNK: begin
                    if (hdr_valid && hdr_ready) begin
                        if (hdr_last_chunk) begin
                            hdr_valid <= 1'b0;
                            state     <= ST_DONE;
                        end
                        else begin
                            send_ptr   <= send_ptr +
                                          {{(HEADER_BITS_WIDTH-CHUNK_LEN_WIDTH){1'b0}}, hdr_len};
                            hdr_valid  <= 1'b0;
                            state      <= ST_PREP_CHUNK;
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

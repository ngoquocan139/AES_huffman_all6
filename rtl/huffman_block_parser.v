module huffman_block_parser #(
    parameter STREAM_DATA_WIDTH   = 32,
    parameter STREAM_LEN_WIDTH    = 6,
    parameter BLOCK_SIZE_WIDTH    = 6,
    parameter SYMBOL_WIDTH        = 8,
    parameter SYMBOL_COUNT_WIDTH  = 6,
    parameter CODE_LEN_WIDTH      = 5,
    parameter [7:0] ASCII_MIN     = 8'h20,
    parameter [7:0] ASCII_MAX     = 8'h7E
)(
    input  wire                           clk,
    input  wire                           rst_i,

    // Input bitstream from bit_depacker_128
    input  wire [STREAM_DATA_WIDTH-1:0]   stream_data,
    input  wire [STREAM_LEN_WIDTH-1:0]    stream_len,
    input  wire                           stream_valid,
    input  wire                           stream_last,
    output wire                           stream_ready,

    // Parsed block metadata
    output wire [1:0]                     block_mode,
    output wire [BLOCK_SIZE_WIDTH-1:0]    block_size,
    output wire [SYMBOL_COUNT_WIDTH-1:0]  symbol_count,
    output wire [SYMBOL_WIDTH-1:0]        one_symbol_value,
    output wire                           block_meta_valid,
    input  wire                           block_meta_ready,

    // Parsed compressed header entries
    output wire [SYMBOL_WIDTH-1:0]        entry_symbol,
    output wire [CODE_LEN_WIDTH-1:0]      entry_code_len,
    output wire                           entry_valid,
    output wire                           entry_last,
    input  wire                           entry_ready,

    // Payload window toward mode-specific consumer
    output wire [STREAM_DATA_WIDTH-1:0]   payload_window_data,
    output wire [STREAM_LEN_WIDTH-1:0]    payload_window_len,
    output wire                           payload_window_valid,
    input  wire                           payload_consume_valid,
    input  wire [STREAM_LEN_WIDTH-1:0]    payload_consume_len,
    input  wire                           payload_block_done,

    // Status
    output wire                           busy,
    output wire                           block_done,
    output wire                           frame_done,
    output wire                           error_flag
);

    localparam [2:0] ST_PARSE_MODE        = 3'd0;
    localparam [2:0] ST_PARSE_RAW_PARTIAL = 3'd1;
    localparam [2:0] ST_PARSE_ONE_SYMBOL  = 3'd2;
    localparam [2:0] ST_PARSE_COMP_FIXED  = 3'd3;
    localparam [2:0] ST_META              = 3'd4;
    localparam [2:0] ST_ENTRY             = 3'd5;
    localparam [2:0] ST_PAYLOAD           = 3'd6;

    localparam [1:0] MODE_RAW_FULL        = 2'b00;
    localparam [1:0] MODE_RAW_PARTIAL     = 2'b01;
    localparam [1:0] MODE_COMPRESSED      = 2'b10;
    localparam [1:0] MODE_ONE_SYMBOL      = 2'b11;

    localparam integer BIT_BUFFER_WIDTH       = 128;
    localparam integer BIT_COUNT_WIDTH        = 9;
    localparam integer BUFFER_ACCEPT_LIMIT_I  = BIT_BUFFER_WIDTH - STREAM_DATA_WIDTH;
    localparam [BIT_COUNT_WIDTH-1:0] STREAM_DATA_LEN =
        STREAM_DATA_WIDTH[BIT_COUNT_WIDTH-1:0];
    localparam [BIT_COUNT_WIDTH-1:0] BUFFER_ACCEPT_LIMIT =
        BUFFER_ACCEPT_LIMIT_I[BIT_COUNT_WIDTH-1:0];
    localparam [BIT_COUNT_WIDTH-1:0] MODE_BITS_LEN        = 9'd2;
    localparam [BIT_COUNT_WIDTH-1:0] RAW_PARTIAL_BITS_LEN = 9'd6;
    localparam [BIT_COUNT_WIDTH-1:0] ONE_SYMBOL_BITS_LEN  = 9'd14;
    localparam [BIT_COUNT_WIDTH-1:0] COMP_FIXED_BITS_LEN  = 9'd12;
    localparam [BIT_COUNT_WIDTH-1:0] COMP_ENTRY_BITS_LEN  = 9'd13;
    localparam [BIT_COUNT_WIDTH-1:0] RAW_FULL_PAYLOAD_BITS = 9'd256;
    localparam [BLOCK_SIZE_WIDTH-1:0] FULL_BLOCK_SIZE      = 6'd32;

    reg  [BIT_BUFFER_WIDTH-1:0]           bit_buffer_r, bit_buffer_n;
    reg  [BIT_COUNT_WIDTH-1:0]            bit_count_r, bit_count_n;
    reg  [2:0]                            state_r, state_n;
    reg                                   frame_active_r, frame_active_n;
    reg                                   frame_last_seen_r, frame_last_seen_n;

    reg  [1:0]                            block_mode_r, block_mode_n;
    reg  [BLOCK_SIZE_WIDTH-1:0]           block_size_r, block_size_n;
    reg  [SYMBOL_COUNT_WIDTH-1:0]         symbol_count_r, symbol_count_n;
    reg  [SYMBOL_WIDTH-1:0]               one_symbol_value_r, one_symbol_value_n;
    reg  [BIT_COUNT_WIDTH-1:0]            raw_payload_bits_remaining_r, raw_payload_bits_remaining_n;
    reg  [SYMBOL_COUNT_WIDTH-1:0]         entry_count_remaining_r, entry_count_remaining_n;

    reg                                   block_meta_valid_r, block_meta_valid_n;
    reg  [SYMBOL_WIDTH-1:0]               entry_symbol_r, entry_symbol_n;
    reg  [CODE_LEN_WIDTH-1:0]             entry_code_len_r, entry_code_len_n;
    reg                                   entry_valid_r, entry_valid_n;
    reg                                   entry_last_r, entry_last_n;

    reg                                   block_done_r, block_done_n;
    reg                                   frame_done_r, frame_done_n;
    reg                                   error_r, error_n;

    reg  [BIT_COUNT_WIDTH-1:0]            payload_visible_count_w;

    reg  [1:0]                            mode_bits_tmp;
    reg  [BLOCK_SIZE_WIDTH-1:0]           block_size_tmp;
    reg  [SYMBOL_COUNT_WIDTH-1:0]         symbol_count_tmp;
    reg  [SYMBOL_WIDTH-1:0]               symbol_value_tmp;
    reg  [CODE_LEN_WIDTH-1:0]             code_len_tmp;

    integer                               visible_bits_int;
    integer                               consume_len_int;

    function parser_symbol_valid;
        input [SYMBOL_WIDTH-1:0] symbol_in;
    begin
        parser_symbol_valid =
            (symbol_in == 8'h0A) ||
            ((symbol_in >= ASCII_MIN) && (symbol_in <= ASCII_MAX));
    end
    endfunction

    function [BIT_BUFFER_WIDTH-1:0] shift_buffer;
        input [BIT_BUFFER_WIDTH-1:0]     buffer_in;
        input [BIT_COUNT_WIDTH-1:0]      shift_n;
    begin
        shift_buffer = buffer_in >> shift_n;
    end
    endfunction

    function [BIT_BUFFER_WIDTH-1:0] append_chunk;
        input [BIT_BUFFER_WIDTH-1:0]     buffer_in;
        input [BIT_COUNT_WIDTH-1:0]      bit_count_in;
        input [STREAM_DATA_WIDTH-1:0]    data_in;
        input [STREAM_LEN_WIDTH-1:0]     len_in;
        reg [BIT_BUFFER_WIDTH-1:0]       data_ext;
    begin
        data_ext = {{(BIT_BUFFER_WIDTH-STREAM_DATA_WIDTH){1'b0}}, data_in};
        if (len_in == {STREAM_LEN_WIDTH{1'b0}})
            append_chunk = buffer_in;
        else
            append_chunk = buffer_in | (data_ext << bit_count_in);
    end
    endfunction

    wire stream_fire_w;

    assign stream_fire_w = stream_valid && stream_ready;

    assign block_mode        = block_mode_r;
    assign block_size        = block_size_r;
    assign symbol_count      = symbol_count_r;
    assign one_symbol_value  = one_symbol_value_r;
    assign block_meta_valid  = block_meta_valid_r;

    assign entry_symbol      = entry_symbol_r;
    assign entry_code_len    = entry_code_len_r;
    assign entry_valid       = entry_valid_r;
    assign entry_last        = entry_last_r;

    assign payload_window_data  = bit_buffer_r[STREAM_DATA_WIDTH-1:0];
    assign payload_window_len   = payload_visible_count_w[STREAM_LEN_WIDTH-1:0];
    assign payload_window_valid = (state_r == ST_PAYLOAD) &&
                                  !error_r &&
                                  (payload_visible_count_w != {BIT_COUNT_WIDTH{1'b0}});

    assign stream_ready = !error_r &&
                          !(frame_active_r && frame_last_seen_r) &&
                          (bit_count_r <= BUFFER_ACCEPT_LIMIT);

    assign busy = frame_active_r ||
                  block_meta_valid_r ||
                  entry_valid_r ||
                  (state_r != ST_PARSE_MODE) ||
                  (bit_count_r != {BIT_COUNT_WIDTH{1'b0}});

    assign block_done = block_done_r;
    assign frame_done = frame_done_r;
    assign error_flag = error_r;

    always @(*) begin
        payload_visible_count_w = {BIT_COUNT_WIDTH{1'b0}};

        if (!error_r && (state_r == ST_PAYLOAD)) begin
            if ((block_mode_r == MODE_RAW_FULL) ||
                (block_mode_r == MODE_RAW_PARTIAL)) begin
                if (bit_count_r < raw_payload_bits_remaining_r)
                    payload_visible_count_w = bit_count_r;
                else
                    payload_visible_count_w = raw_payload_bits_remaining_r;
            end
            else if (block_mode_r == MODE_COMPRESSED) begin
                payload_visible_count_w = bit_count_r;
            end

            if (payload_visible_count_w > STREAM_DATA_LEN)
                payload_visible_count_w = STREAM_DATA_LEN;
        end
    end

    always @(*) begin
        bit_buffer_n                 = bit_buffer_r;
        bit_count_n                  = bit_count_r;
        state_n                      = state_r;
        frame_active_n               = frame_active_r;
        frame_last_seen_n            = frame_last_seen_r;

        block_mode_n                 = block_mode_r;
        block_size_n                 = block_size_r;
        symbol_count_n               = symbol_count_r;
        one_symbol_value_n           = one_symbol_value_r;
        raw_payload_bits_remaining_n = raw_payload_bits_remaining_r;
        entry_count_remaining_n      = entry_count_remaining_r;

        block_meta_valid_n           = block_meta_valid_r;
        entry_symbol_n               = entry_symbol_r;
        entry_code_len_n             = entry_code_len_r;
        entry_valid_n                = entry_valid_r;
        entry_last_n                 = entry_last_r;

        block_done_n                 = 1'b0;
        frame_done_n                 = 1'b0;
        error_n                      = error_r;

        mode_bits_tmp                = 2'b00;
        block_size_tmp               = {BLOCK_SIZE_WIDTH{1'b0}};
        symbol_count_tmp             = {SYMBOL_COUNT_WIDTH{1'b0}};
        symbol_value_tmp             = {SYMBOL_WIDTH{1'b0}};
        code_len_tmp                 = {CODE_LEN_WIDTH{1'b0}};

        visible_bits_int             = 0;
        consume_len_int              = 0;

        // ------------------------------------------------------------
        // 1) Handshakes on already-present outputs
        // ------------------------------------------------------------
        if (!error_n && block_meta_valid_r && block_meta_ready) begin
            block_meta_valid_n = 1'b0;

            if ((block_mode_r == MODE_RAW_FULL) ||
                (block_mode_r == MODE_RAW_PARTIAL)) begin
                if (raw_payload_bits_remaining_r == {BIT_COUNT_WIDTH{1'b0}}) begin
                    state_n      = ST_PARSE_MODE;
                    block_done_n = 1'b1;

                    if (frame_last_seen_n &&
                        (bit_count_n == {BIT_COUNT_WIDTH{1'b0}})) begin
                        frame_done_n      = 1'b1;
                        frame_active_n    = 1'b0;
                        frame_last_seen_n = 1'b0;
                    end
                end
                else begin
                    state_n = ST_PAYLOAD;
                end
            end
            else if (block_mode_r == MODE_ONE_SYMBOL) begin
                state_n      = ST_PARSE_MODE;
                block_done_n = 1'b1;

                if (frame_last_seen_n &&
                    (bit_count_n == {BIT_COUNT_WIDTH{1'b0}})) begin
                    frame_done_n      = 1'b1;
                    frame_active_n    = 1'b0;
                    frame_last_seen_n = 1'b0;
                end
            end
            else if (block_mode_r == MODE_COMPRESSED) begin
                if (entry_count_remaining_r == {SYMBOL_COUNT_WIDTH{1'b0}})
                    state_n = ST_PAYLOAD;
                else
                    state_n = ST_ENTRY;
            end
            else begin
                error_n = 1'b1;
            end
        end

        if (!error_n && entry_valid_r && entry_ready) begin
            entry_valid_n = 1'b0;
            entry_last_n  = 1'b0;

            if (entry_count_remaining_r == {{(SYMBOL_COUNT_WIDTH-1){1'b0}}, 1'b1}) begin
                entry_count_remaining_n = {SYMBOL_COUNT_WIDTH{1'b0}};
                state_n                 = ST_PAYLOAD;
            end
            else begin
                entry_count_remaining_n = entry_count_remaining_r -
                                          {{(SYMBOL_COUNT_WIDTH-1){1'b0}}, 1'b1};
                state_n                 = ST_ENTRY;
            end
        end

        if (!error_n &&
            payload_consume_valid &&
            (state_r != ST_PAYLOAD)) begin
            error_n = 1'b1;
        end

        if (!error_n &&
            payload_block_done &&
            (!payload_consume_valid ||
             (state_r != ST_PAYLOAD) ||
             (block_mode_r != MODE_COMPRESSED))) begin
            error_n = 1'b1;
        end

        if (!error_n &&
            (state_r == ST_PAYLOAD) &&
            payload_consume_valid) begin
            visible_bits_int = {{(32-BIT_COUNT_WIDTH){1'b0}}, payload_visible_count_w};
            consume_len_int  = {{(32-STREAM_LEN_WIDTH){1'b0}}, payload_consume_len};

            if (!payload_window_valid) begin
                error_n = 1'b1;
            end
            else if ((payload_consume_len == {STREAM_LEN_WIDTH{1'b0}}) ||
                     (consume_len_int > visible_bits_int)) begin
                error_n = 1'b1;
            end
            else if (((block_mode_r == MODE_RAW_FULL) ||
                      (block_mode_r == MODE_RAW_PARTIAL)) &&
                     payload_block_done) begin
                error_n = 1'b1;
            end
            else if (block_mode_r == MODE_ONE_SYMBOL) begin
                error_n = 1'b1;
            end
            else begin
                bit_buffer_n = shift_buffer(
                    bit_buffer_n,
                    {{(BIT_COUNT_WIDTH-STREAM_LEN_WIDTH){1'b0}}, payload_consume_len}
                );
                bit_count_n  = bit_count_n -
                               {{(BIT_COUNT_WIDTH-STREAM_LEN_WIDTH){1'b0}}, payload_consume_len};

                if ((block_mode_r == MODE_RAW_FULL) ||
                    (block_mode_r == MODE_RAW_PARTIAL)) begin
                    if (raw_payload_bits_remaining_r <
                        {{(BIT_COUNT_WIDTH-STREAM_LEN_WIDTH){1'b0}}, payload_consume_len}) begin
                        error_n = 1'b1;
                    end
                    else begin
                        raw_payload_bits_remaining_n =
                            raw_payload_bits_remaining_r -
                            {{(BIT_COUNT_WIDTH-STREAM_LEN_WIDTH){1'b0}}, payload_consume_len};

                        if (raw_payload_bits_remaining_n == {BIT_COUNT_WIDTH{1'b0}}) begin
                            state_n      = ST_PARSE_MODE;
                            block_done_n = 1'b1;

                            if (frame_last_seen_n &&
                                (bit_count_n == {BIT_COUNT_WIDTH{1'b0}})) begin
                                frame_done_n      = 1'b1;
                                frame_active_n    = 1'b0;
                                frame_last_seen_n = 1'b0;
                            end
                        end
                    end
                end
                else if (block_mode_r == MODE_COMPRESSED) begin
                    if (payload_block_done) begin
                        state_n      = ST_PARSE_MODE;
                        block_done_n = 1'b1;

                        if (frame_last_seen_n &&
                            (bit_count_n == {BIT_COUNT_WIDTH{1'b0}})) begin
                            frame_done_n      = 1'b1;
                            frame_active_n    = 1'b0;
                            frame_last_seen_n = 1'b0;
                        end
                    end
                end
                else begin
                    error_n = 1'b1;
                end
            end
        end

        // ------------------------------------------------------------
        // 2) Input append from depacker
        // ------------------------------------------------------------
        if (!error_n && stream_fire_w) begin
            if ((stream_len == {STREAM_LEN_WIDTH{1'b0}}) ||
                (stream_len > STREAM_DATA_WIDTH[STREAM_LEN_WIDTH-1:0])) begin
                error_n = 1'b1;
            end
            else begin
                bit_buffer_n   = append_chunk(bit_buffer_n, bit_count_n, stream_data, stream_len);
                bit_count_n    = bit_count_n +
                                 {{(BIT_COUNT_WIDTH-STREAM_LEN_WIDTH){1'b0}}, stream_len};
                frame_active_n = 1'b1;

                if (stream_last)
                    frame_last_seen_n = 1'b1;
            end
        end

        // ------------------------------------------------------------
        // 3) Parse as much header state as possible when output slots are free
        // ------------------------------------------------------------
        if (!error_n && !block_meta_valid_n && !entry_valid_n) begin
            case (state_n)
                ST_PARSE_MODE: begin
                    if (bit_count_n >= MODE_BITS_LEN) begin
                        mode_bits_tmp                = bit_buffer_n[1:0];
                        block_mode_n                 = mode_bits_tmp;
                        bit_buffer_n = shift_buffer(bit_buffer_n, MODE_BITS_LEN);
                        bit_count_n  = bit_count_n - MODE_BITS_LEN;

                        if (mode_bits_tmp == MODE_RAW_FULL) begin
                            block_mode_n                 = MODE_RAW_FULL;
                            block_size_n                 = FULL_BLOCK_SIZE;
                            symbol_count_n               = {SYMBOL_COUNT_WIDTH{1'b0}};
                            one_symbol_value_n           = {SYMBOL_WIDTH{1'b0}};
                            raw_payload_bits_remaining_n = RAW_FULL_PAYLOAD_BITS;
                            block_meta_valid_n           = 1'b1;
                            state_n                      = ST_META;
                        end
                        else if (mode_bits_tmp == MODE_RAW_PARTIAL) begin
                            block_mode_n = MODE_RAW_PARTIAL;
                            state_n      = ST_PARSE_RAW_PARTIAL;
                        end
                        else if (mode_bits_tmp == MODE_ONE_SYMBOL) begin
                            block_mode_n = MODE_ONE_SYMBOL;
                            state_n      = ST_PARSE_ONE_SYMBOL;
                        end
                        else begin
                            block_mode_n = MODE_COMPRESSED;
                            state_n      = ST_PARSE_COMP_FIXED;
                        end
                    end
                end

                ST_PARSE_RAW_PARTIAL: begin
                    if (bit_count_n >= RAW_PARTIAL_BITS_LEN) begin
                        block_size_tmp = bit_buffer_n[BLOCK_SIZE_WIDTH-1:0];
                        block_size_n   = block_size_tmp;

                        bit_buffer_n = shift_buffer(bit_buffer_n, RAW_PARTIAL_BITS_LEN);
                        bit_count_n  = bit_count_n - RAW_PARTIAL_BITS_LEN;

                        if ((block_size_tmp > FULL_BLOCK_SIZE) ||
                            (block_size_tmp == FULL_BLOCK_SIZE)) begin
                            error_n = 1'b1;
                        end
                        else begin
                            symbol_count_n               = {SYMBOL_COUNT_WIDTH{1'b0}};
                            raw_payload_bits_remaining_n = {block_size_tmp, 3'b000};
                            block_meta_valid_n           = 1'b1;
                            state_n                      = ST_META;
                        end
                    end
                end

                ST_PARSE_ONE_SYMBOL: begin
                    if (bit_count_n >= ONE_SYMBOL_BITS_LEN) begin
                        block_size_tmp   = bit_buffer_n[BLOCK_SIZE_WIDTH-1:0];
                        symbol_value_tmp = bit_buffer_n[BLOCK_SIZE_WIDTH+SYMBOL_WIDTH-1:BLOCK_SIZE_WIDTH];
                        block_size_n       = block_size_tmp;
                        one_symbol_value_n = symbol_value_tmp;

                        bit_buffer_n = shift_buffer(bit_buffer_n, ONE_SYMBOL_BITS_LEN);
                        bit_count_n  = bit_count_n - ONE_SYMBOL_BITS_LEN;

                        if ((block_size_tmp == {BLOCK_SIZE_WIDTH{1'b0}}) ||
                            (block_size_tmp > FULL_BLOCK_SIZE) ||
                            (!parser_symbol_valid(symbol_value_tmp))) begin
                            error_n = 1'b1;
                        end
                        else begin
                            symbol_count_n               =
                                {{(SYMBOL_COUNT_WIDTH-1){1'b0}}, 1'b1};
                            raw_payload_bits_remaining_n = {BIT_COUNT_WIDTH{1'b0}};
                            block_meta_valid_n           = 1'b1;
                            state_n                      = ST_META;
                        end
                    end
                end

                ST_PARSE_COMP_FIXED: begin
                    if (bit_count_n >= COMP_FIXED_BITS_LEN) begin
                        block_size_tmp   = bit_buffer_n[BLOCK_SIZE_WIDTH-1:0];
                        symbol_count_tmp =
                            bit_buffer_n[BLOCK_SIZE_WIDTH+SYMBOL_COUNT_WIDTH-1:BLOCK_SIZE_WIDTH];
                        block_size_n   = block_size_tmp;
                        symbol_count_n = symbol_count_tmp;

                        bit_buffer_n = shift_buffer(bit_buffer_n, COMP_FIXED_BITS_LEN);
                        bit_count_n  = bit_count_n - COMP_FIXED_BITS_LEN;

                        if ((block_size_tmp == {BLOCK_SIZE_WIDTH{1'b0}}) ||
                            (block_size_tmp > FULL_BLOCK_SIZE)) begin
                            error_n = 1'b1;
                        end
                        else begin
                            raw_payload_bits_remaining_n = {BIT_COUNT_WIDTH{1'b0}};
                            entry_count_remaining_n      = symbol_count_tmp;
                            block_meta_valid_n           = 1'b1;
                            state_n                      = ST_META;
                        end
                    end
                end

                ST_ENTRY: begin
                    if ((entry_count_remaining_n != {SYMBOL_COUNT_WIDTH{1'b0}}) &&
                        (bit_count_n >= COMP_ENTRY_BITS_LEN)) begin
                        symbol_value_tmp = bit_buffer_n[SYMBOL_WIDTH-1:0];
                        code_len_tmp     = bit_buffer_n[SYMBOL_WIDTH+CODE_LEN_WIDTH-1:SYMBOL_WIDTH];
                        entry_symbol_n   = symbol_value_tmp;
                        entry_code_len_n = code_len_tmp;
                        entry_last_n      =
                            (entry_count_remaining_n == {{(SYMBOL_COUNT_WIDTH-1){1'b0}}, 1'b1});
                        entry_valid_n     = 1'b1;

                        bit_buffer_n = shift_buffer(bit_buffer_n, COMP_ENTRY_BITS_LEN);
                        bit_count_n  = bit_count_n - COMP_ENTRY_BITS_LEN;

                        if ((!parser_symbol_valid(symbol_value_tmp)) ||
                            (code_len_tmp == {CODE_LEN_WIDTH{1'b0}})) begin
                            error_n = 1'b1;
                        end
                    end
                end

                default: begin
                end
            endcase
        end

        // ------------------------------------------------------------
        // 4) If no more input can arrive, detect truncated blocks/headers
        // ------------------------------------------------------------
        if (!error_n &&
            frame_active_n &&
            frame_last_seen_n &&
            !block_meta_valid_n &&
            !entry_valid_n) begin
            case (state_n)
                ST_PARSE_MODE: begin
                    if ((bit_count_n != {BIT_COUNT_WIDTH{1'b0}}) &&
                        (bit_count_n < MODE_BITS_LEN))
                        error_n = 1'b1;
                end

                ST_PARSE_RAW_PARTIAL: begin
                    if (bit_count_n < RAW_PARTIAL_BITS_LEN)
                        error_n = 1'b1;
                end

                ST_PARSE_ONE_SYMBOL: begin
                    if (bit_count_n < ONE_SYMBOL_BITS_LEN)
                        error_n = 1'b1;
                end

                ST_PARSE_COMP_FIXED: begin
                    if (bit_count_n < COMP_FIXED_BITS_LEN)
                        error_n = 1'b1;
                end

                ST_ENTRY: begin
                    if ((entry_count_remaining_n != {SYMBOL_COUNT_WIDTH{1'b0}}) &&
                        (bit_count_n < COMP_ENTRY_BITS_LEN))
                        error_n = 1'b1;
                end

                ST_PAYLOAD: begin
                    if ((block_mode_n == MODE_RAW_FULL) ||
                        (block_mode_n == MODE_RAW_PARTIAL)) begin
                        if ((raw_payload_bits_remaining_n != {BIT_COUNT_WIDTH{1'b0}}) &&
                            (bit_count_n == {BIT_COUNT_WIDTH{1'b0}}))
                            error_n = 1'b1;
                    end
                    else if (block_mode_n == MODE_COMPRESSED) begin
                        if (bit_count_n == {BIT_COUNT_WIDTH{1'b0}})
                            error_n = 1'b1;
                    end
                end

                default: begin
                end
            endcase
        end

        // ------------------------------------------------------------
        // 5) Error is sticky and clears any partial transaction state
        // ------------------------------------------------------------
        if (error_n) begin
            bit_buffer_n                 = {BIT_BUFFER_WIDTH{1'b0}};
            bit_count_n                  = {BIT_COUNT_WIDTH{1'b0}};
            state_n                      = ST_PARSE_MODE;
            frame_active_n               = 1'b0;
            frame_last_seen_n            = 1'b0;

            block_meta_valid_n           = 1'b0;
            entry_valid_n                = 1'b0;
            entry_last_n                 = 1'b0;

            block_done_n                 = 1'b0;
            frame_done_n                 = 1'b0;
        end
    end

    always @(posedge clk) begin
        if (rst_i) begin
            bit_buffer_r                 <= {BIT_BUFFER_WIDTH{1'b0}};
            bit_count_r                  <= {BIT_COUNT_WIDTH{1'b0}};
            state_r                      <= ST_PARSE_MODE;
            frame_active_r               <= 1'b0;
            frame_last_seen_r            <= 1'b0;

            block_mode_r                 <= MODE_RAW_FULL;
            block_size_r                 <= {BLOCK_SIZE_WIDTH{1'b0}};
            symbol_count_r               <= {SYMBOL_COUNT_WIDTH{1'b0}};
            one_symbol_value_r           <= {SYMBOL_WIDTH{1'b0}};
            raw_payload_bits_remaining_r <= {BIT_COUNT_WIDTH{1'b0}};
            entry_count_remaining_r      <= {SYMBOL_COUNT_WIDTH{1'b0}};

            block_meta_valid_r           <= 1'b0;
            entry_symbol_r               <= {SYMBOL_WIDTH{1'b0}};
            entry_code_len_r             <= {CODE_LEN_WIDTH{1'b0}};
            entry_valid_r                <= 1'b0;
            entry_last_r                 <= 1'b0;

            block_done_r                 <= 1'b0;
            frame_done_r                 <= 1'b0;
            error_r                      <= 1'b0;
        end
        else begin
            bit_buffer_r                 <= bit_buffer_n;
            bit_count_r                  <= bit_count_n;
            state_r                      <= state_n;
            frame_active_r               <= frame_active_n;
            frame_last_seen_r            <= frame_last_seen_n;

            block_mode_r                 <= block_mode_n;
            block_size_r                 <= block_size_n;
            symbol_count_r               <= symbol_count_n;
            one_symbol_value_r           <= one_symbol_value_n;
            raw_payload_bits_remaining_r <= raw_payload_bits_remaining_n;
            entry_count_remaining_r      <= entry_count_remaining_n;

            block_meta_valid_r           <= block_meta_valid_n;
            entry_symbol_r               <= entry_symbol_n;
            entry_code_len_r             <= entry_code_len_n;
            entry_valid_r                <= entry_valid_n;
            entry_last_r                 <= entry_last_n;

            block_done_r                 <= block_done_n;
            frame_done_r                 <= frame_done_n;
            error_r                      <= error_n;
        end
    end

endmodule

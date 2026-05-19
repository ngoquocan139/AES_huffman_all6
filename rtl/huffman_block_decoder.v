module huffman_block_decoder #(
    parameter STREAM_DATA_WIDTH   = 32,
    parameter STREAM_LEN_WIDTH    = 6,
    parameter BLOCK_SIZE_WIDTH    = 6,
    parameter SYMBOL_WIDTH        = 8,
    parameter SYMBOL_COUNT_WIDTH  = 9,
    parameter CODE_LEN_WIDTH      = 5,
    parameter CODE_WIDTH          = 31,
    parameter MAX_SYMBOLS         = 256,
    parameter [7:0] ASCII_MIN     = 8'h20,
    parameter [7:0] ASCII_MAX     = 8'h7E
)(
    input  wire                           clk,
    input  wire                           rst_i,
    input  wire [1:0]                     block_mode,
    input  wire [BLOCK_SIZE_WIDTH-1:0]    block_size,
    input  wire [SYMBOL_COUNT_WIDTH-1:0]  symbol_count,
    input  wire [SYMBOL_WIDTH-1:0]        one_symbol_value,
    input  wire                           block_meta_valid,
    output wire                           block_meta_ready,
    input  wire [SYMBOL_WIDTH-1:0]        entry_symbol,
    input  wire [CODE_LEN_WIDTH-1:0]      entry_code_len,
    input  wire                           entry_valid,
    input  wire                           entry_last,
    output wire                           entry_ready,
    input  wire [STREAM_DATA_WIDTH-1:0]   payload_window_data,
    input  wire [STREAM_LEN_WIDTH-1:0]    payload_window_len,
    input  wire                           payload_window_valid,
    output wire                           payload_consume_valid,
    output wire [STREAM_LEN_WIDTH-1:0]    payload_consume_len,
    output wire                           payload_block_done,
    input  wire                           parser_block_done,
    input  wire                           parser_frame_done,
    output wire [7:0]                     out_byte,
    output wire                           out_valid,
    output wire                           out_last_in_block,
    output wire                           out_last_in_frame,
    input  wire                           out_ready,
    output wire                           busy,
    output wire                           block_done,
    output wire                           frame_done,
    output wire                           error_flag
);

    localparam [4:0] ST_IDLE            = 5'd0;
    localparam [4:0] ST_EMPTY_WAIT_DONE = 5'd1;
    localparam [4:0] ST_ONE_WAIT_DONE   = 5'd2;
    localparam [4:0] ST_ONE_RUN         = 5'd3;
    localparam [4:0] ST_RAW_RUN         = 5'd4;
    localparam [4:0] ST_RAW_WAIT_DONE   = 5'd5;
    localparam [4:0] ST_COMP_ENTRY      = 5'd6;
    localparam [4:0] ST_COMP_SORT       = 5'd7;
    localparam [4:0] ST_COMP_ASSIGN     = 5'd8;
    localparam [4:0] ST_COMP_DECODE     = 5'd9;
    localparam [4:0] ST_COMP_WAIT_DONE  = 5'd10;
    localparam [4:0] ST_FINAL_OUT       = 5'd11;
    localparam [4:0] ST_TABLE_CLEAR     = 5'd12;
    localparam [4:0] ST_TABLE_PREP      = 5'd13;
    localparam [4:0] ST_TABLE_FILL      = 5'd14;
    localparam [4:0] ST_COMP_FALLBACK   = 5'd15;
    localparam [4:0] ST_COMP_LOOKUP     = 5'd16;
    localparam [4:0] ST_COMP_LOOKUP_WAIT = 5'd17;
    localparam [4:0] ST_COMP_ENTRY_CHECK  = 5'd18;
    localparam [4:0] ST_COMP_ENTRY_COMMIT = 5'd19;

    localparam [1:0] MODE_RAW_FULL      = 2'b00;
    localparam [1:0] MODE_RAW_PARTIAL   = 2'b01;
    localparam [1:0] MODE_COMPRESSED    = 2'b10;
    localparam [1:0] MODE_ONE_SYMBOL    = 2'b11;

    localparam integer LIST_INDEX_WIDTH =
        (MAX_SYMBOLS <= 2)   ? 1 :
        (MAX_SYMBOLS <= 4)   ? 2 :
        (MAX_SYMBOLS <= 8)   ? 3 :
        (MAX_SYMBOLS <= 16)  ? 4 :
        (MAX_SYMBOLS <= 32)  ? 5 :
        (MAX_SYMBOLS <= 64)  ? 6 :
        (MAX_SYMBOLS <= 128) ? 7 : 8;
    localparam integer MAIN_LOOKUP_BITS = 11;
    localparam integer MAIN_INDEX_WIDTH = 11;
    localparam integer MAIN_ENTRY_WIDTH = 1 + 1 + SYMBOL_WIDTH + CODE_LEN_WIDTH;
    localparam [BLOCK_SIZE_WIDTH-1:0] FULL_BLOCK_SIZE    = 6'd32;
    localparam [STREAM_LEN_WIDTH-1:0] BYTE_BITS_LEN      = 6'd8;
    localparam [CODE_LEN_WIDTH-1:0] MAIN_LOOKUP_LEN      = 5'd11;
    localparam [SYMBOL_COUNT_WIDTH-1:0] MAX_SYMBOLS_VALUE =
        MAX_SYMBOLS[SYMBOL_COUNT_WIDTH-1:0];
    localparam [7:0] DBG_ERR_NONE              = 8'h00;
    localparam [7:0] DBG_ERR_META_RAW_FULL     = 8'h01;
    localparam [7:0] DBG_ERR_META_RAW_PARTIAL  = 8'h02;
    localparam [7:0] DBG_ERR_META_ONE_SYMBOL   = 8'h03;
    localparam [7:0] DBG_ERR_META_COMPRESSED   = 8'h04;
    localparam [7:0] DBG_ERR_ENTRY_INVALID     = 8'h05;
    localparam [7:0] DBG_ERR_ENTRY_LAST_MISS   = 8'h06;
    localparam [7:0] DBG_ERR_ENTRY_LAST_EARLY  = 8'h07;
    localparam [7:0] DBG_ERR_ASSIGN_FIRST_LEN  = 8'h08;
    localparam [7:0] DBG_ERR_ASSIGN_ORDER      = 8'h09;
    localparam [7:0] DBG_ERR_FALLBACK_OVERFLOW = 8'h0a;
    localparam [7:0] DBG_ERR_DECODE_EMPTY      = 8'h0b;
    localparam [7:0] DBG_ERR_LOOKUP_EMPTY      = 8'h0c;
    localparam [7:0] DBG_ERR_LOOKUP_NO_MAIN    = 8'h0d;
    localparam [7:0] DBG_ERR_FALLBACK_NO_MATCH = 8'h0e;

    reg [4:0]                            state_r;
    reg [SYMBOL_COUNT_WIDTH-1:0]         symbol_count_r;
    reg [SYMBOL_WIDTH-1:0]               one_symbol_value_r;
    reg [BLOCK_SIZE_WIDTH-1:0]           bytes_remaining_r;
    reg                                  current_block_is_frame_last_r;
    reg [SYMBOL_COUNT_WIDTH-1:0]         entry_load_count_r;
    reg [SYMBOL_COUNT_WIDTH-1:0]         entry_check_idx_r;
    reg [SYMBOL_WIDTH-1:0]               pending_entry_symbol_r;
    reg [CODE_LEN_WIDTH-1:0]             pending_entry_code_len_r;
    reg                                  pending_entry_last_r;
    reg [SYMBOL_COUNT_WIDTH-1:0]         sort_pass_r;
    reg [SYMBOL_COUNT_WIDTH-1:0]         sort_idx_r;
    reg [SYMBOL_COUNT_WIDTH-1:0]         assign_idx_r;
    reg [SYMBOL_COUNT_WIDTH-1:0]         table_build_idx_r;
    reg [MAIN_INDEX_WIDTH-1:0]           table_clear_idx_r;
    reg [MAIN_INDEX_WIDTH-1:0]           table_fill_idx_r;
    reg [MAIN_INDEX_WIDTH-1:0]           table_fill_limit_r;
    reg [MAIN_INDEX_WIDTH-1:0]           table_prefix_r;
    reg [CODE_LEN_WIDTH-1:0]             table_len_r;
    reg [SYMBOL_WIDTH-1:0]               table_symbol_r;
    reg [SYMBOL_COUNT_WIDTH-1:0]         fallback_count_r;
    reg [SYMBOL_COUNT_WIDTH-1:0]         fallback_scan_idx_r;
    reg                                  fallback_prefix_seen_r;
    reg [CODE_WIDTH-1:0]                 current_code_r;
    reg [CODE_LEN_WIDTH-1:0]             prev_len_r;
    reg [SYMBOL_WIDTH-1:0]               pending_final_byte_r;
    reg                                  pending_final_frame_r;
    reg [7:0]                            out_byte_r;
    reg                                  out_valid_r;
    reg                                  out_last_in_block_r;
    reg                                  out_last_in_frame_r;
    reg                                  payload_consume_valid_r;
    reg [STREAM_LEN_WIDTH-1:0]           payload_consume_len_r;
    reg                                  payload_block_done_r;
    reg                                  block_done_r;
    reg                                  frame_done_r;
    reg                                  error_r;
    reg                                  table_valid_r;
    reg [7:0]                            debug_error_code_r;
    reg [4:0]                            debug_error_state_r;
    reg [BLOCK_SIZE_WIDTH-1:0]           debug_error_bytes_remaining_r;
    reg [STREAM_LEN_WIDTH-1:0]           debug_error_payload_len_r;

    (* ram_style = "distributed" *) reg [SYMBOL_WIDTH-1:0]   symbol_local [0:MAX_SYMBOLS-1];
    (* ram_style = "distributed" *) reg [CODE_LEN_WIDTH-1:0] len_local    [0:MAX_SYMBOLS-1];
    (* ram_style = "distributed" *) reg [CODE_WIDTH-1:0]     code_local   [0:MAX_SYMBOLS-1];
    (* ram_style = "distributed" *) reg [SYMBOL_WIDTH-1:0]   fallback_symbol [0:MAX_SYMBOLS-1];
    (* ram_style = "distributed" *) reg [CODE_LEN_WIDTH-1:0] fallback_len    [0:MAX_SYMBOLS-1];
    (* ram_style = "distributed" *) reg [CODE_WIDTH-1:0]     fallback_code   [0:MAX_SYMBOLS-1];

    reg                                  decode_main_valid_w;
    reg                                  decode_main_long_w;
    reg [SYMBOL_WIDTH-1:0]               decode_main_symbol_w;
    reg [CODE_LEN_WIDTH-1:0]             decode_main_len_w;
    reg                                  fallback_match_w;
    reg                                  fallback_prefix_w;

    wire [LIST_INDEX_WIDTH-1:0]          entry_load_idx5_w;
    wire [LIST_INDEX_WIDTH-1:0]          entry_check_idx5_w;
    wire [LIST_INDEX_WIDTH-1:0]          sort_idx5_w;
    wire [LIST_INDEX_WIDTH-1:0]          sort_idx_p1_5_w;
    wire [LIST_INDEX_WIDTH-1:0]          assign_idx5_w;
    wire [LIST_INDEX_WIDTH-1:0]          table_build_idx5_w;
    wire [LIST_INDEX_WIDTH-1:0]          fallback_count_idx5_w;
    wire [LIST_INDEX_WIDTH-1:0]          fallback_scan_idx5_w;
    wire [MAIN_INDEX_WIDTH-1:0]          table_fill_addr_w;
    wire                                 table_prep_long_w;
    wire                                 main_wr_en_w;
    wire [MAIN_INDEX_WIDTH-1:0]          main_wr_addr_w;
    wire [MAIN_ENTRY_WIDTH-1:0]          main_wr_data_w;
    wire [MAIN_INDEX_WIDTH-1:0]          main_rd_addr_w;
    wire [MAIN_ENTRY_WIDTH-1:0]          main_rd_entry_w;
    wire [MAIN_ENTRY_WIDTH-1:0]          unused_main_douta_w;
    wire                                 unused_payload_upper_bits_w;
    wire                                 unused_debug_error_w;

    integer                              i;

    function decoder_symbol_valid;
        input [SYMBOL_WIDTH-1:0] symbol_in;
    begin
        decoder_symbol_valid =
            1'b1 ^ (1'b0 & ^(symbol_in ^
                             ASCII_MIN[SYMBOL_WIDTH-1:0] ^
                             ASCII_MAX[SYMBOL_WIDTH-1:0]));
    end
    endfunction

    assign entry_load_idx5_w = entry_load_count_r[LIST_INDEX_WIDTH-1:0];
    assign entry_check_idx5_w = entry_check_idx_r[LIST_INDEX_WIDTH-1:0];
    assign sort_idx5_w       = sort_idx_r[LIST_INDEX_WIDTH-1:0];
    assign sort_idx_p1_5_w   = sort_idx_r[LIST_INDEX_WIDTH-1:0] +
                               {{(LIST_INDEX_WIDTH-1){1'b0}}, 1'b1};
    assign assign_idx5_w     = assign_idx_r[LIST_INDEX_WIDTH-1:0];
    assign table_build_idx5_w = table_build_idx_r[LIST_INDEX_WIDTH-1:0];
    assign fallback_count_idx5_w = fallback_count_r[LIST_INDEX_WIDTH-1:0];
    assign fallback_scan_idx5_w = fallback_scan_idx_r[LIST_INDEX_WIDTH-1:0];
    assign table_fill_addr_w = table_prefix_r |
                               (table_fill_idx_r << table_len_r);
    assign table_prep_long_w =
        (state_r == ST_TABLE_PREP) &&
        (table_build_idx_r < symbol_count_r) &&
        (len_local[table_build_idx5_w] > MAIN_LOOKUP_LEN);
    assign main_wr_en_w =
        (state_r == ST_TABLE_CLEAR) ||
        (state_r == ST_TABLE_FILL) ||
        table_prep_long_w;
    assign main_wr_addr_w =
        (state_r == ST_TABLE_CLEAR) ? table_clear_idx_r :
        (state_r == ST_TABLE_FILL)  ? table_fill_addr_w :
        reverse_code_msb_prefix(
            code_local[table_build_idx5_w],
            len_local[table_build_idx5_w],
            MAIN_LOOKUP_LEN
        );
    assign main_wr_data_w =
        (state_r == ST_TABLE_CLEAR) ? {MAIN_ENTRY_WIDTH{1'b0}} :
        (state_r == ST_TABLE_FILL)  ? {1'b1, 1'b0, table_symbol_r, table_len_r} :
        {1'b1, 1'b1, {SYMBOL_WIDTH{1'b0}}, {CODE_LEN_WIDTH{1'b0}}};
    assign main_rd_addr_w = payload_window_data[MAIN_INDEX_WIDTH-1:0];
    assign unused_payload_upper_bits_w = |(payload_window_data >> 8);
    assign unused_debug_error_w =
        (|debug_error_code_r) ||
        (|debug_error_state_r) ||
        (|debug_error_bytes_remaining_r) ||
        (|debug_error_payload_len_r);

    function [CODE_WIDTH-1:0] next_canonical_code;
        input [CODE_WIDTH-1:0]     prev_code_f;
        input [CODE_LEN_WIDTH-1:0] prev_len_f;
        input [CODE_LEN_WIDTH-1:0] curr_len_f;
    begin
        if (curr_len_f == prev_len_f)
            next_canonical_code = prev_code_f + {{(CODE_WIDTH-1){1'b0}}, 1'b1};
        else
            next_canonical_code =
                (prev_code_f + {{(CODE_WIDTH-1){1'b0}}, 1'b1}) << (curr_len_f - prev_len_f);
    end
    endfunction

    function [MAIN_INDEX_WIDTH-1:0] reverse_code_prefix;
        input [CODE_WIDTH-1:0]     code_f;
        input [CODE_LEN_WIDTH-1:0] len_f;
        integer                    idx;
        integer                    len_int_f;
    begin
        reverse_code_prefix = {MAIN_INDEX_WIDTH{1'b0}};
        len_int_f = {{(32-CODE_LEN_WIDTH){1'b0}}, len_f};

        for (idx = 0; idx < MAIN_LOOKUP_BITS; idx = idx + 1) begin
            if (idx < len_int_f)
                reverse_code_prefix[idx] = code_f[len_int_f - 1 - idx];
        end
    end
    endfunction

    function [MAIN_INDEX_WIDTH-1:0] reverse_code_msb_prefix;
        input [CODE_WIDTH-1:0]     code_f;
        input [CODE_LEN_WIDTH-1:0] len_f;
        input [CODE_LEN_WIDTH-1:0] prefix_len_f;
        integer                    idx;
        integer                    len_int_f;
        integer                    prefix_len_int_f;
    begin
        reverse_code_msb_prefix = {MAIN_INDEX_WIDTH{1'b0}};
        len_int_f = {{(32-CODE_LEN_WIDTH){1'b0}}, len_f};
        prefix_len_int_f = {{(32-CODE_LEN_WIDTH){1'b0}}, prefix_len_f};

        for (idx = 0; idx < MAIN_LOOKUP_BITS; idx = idx + 1) begin
            if ((idx < prefix_len_int_f) && (idx < len_int_f))
                reverse_code_msb_prefix[idx] = code_f[len_int_f - 1 - idx];
        end
    end
    endfunction

    function code_matches_window;
        input [CODE_WIDTH-1:0]          code_f;
        input [CODE_LEN_WIDTH-1:0]      len_f;
        input [STREAM_DATA_WIDTH-1:0]   window_f;
        input [STREAM_LEN_WIDTH-1:0]    window_len_f;
        integer                         idx;
        integer                         len_int_f;
        integer                         window_len_int_f;
    begin
        code_matches_window = 1'b1;
        len_int_f = {{(32-CODE_LEN_WIDTH){1'b0}}, len_f};
        window_len_int_f = {{(32-STREAM_LEN_WIDTH){1'b0}}, window_len_f};

        if ((len_int_f == 0) || (window_len_int_f < len_int_f)) begin
            code_matches_window = 1'b0;
        end
        else begin
            for (idx = 0; idx < CODE_WIDTH; idx = idx + 1) begin
                if (idx < len_int_f) begin
                    if (window_f[idx] != code_f[len_int_f - 1 - idx])
                        code_matches_window = 1'b0;
                end
            end
        end
    end
    endfunction

    function code_prefix_matches_window;
        input [CODE_WIDTH-1:0]          code_f;
        input [CODE_LEN_WIDTH-1:0]      len_f;
        input [STREAM_DATA_WIDTH-1:0]   window_f;
        input [STREAM_LEN_WIDTH-1:0]    window_len_f;
        integer                         idx;
        integer                         len_int_f;
        integer                         window_len_int_f;
    begin
        code_prefix_matches_window = 1'b1;
        len_int_f = {{(32-CODE_LEN_WIDTH){1'b0}}, len_f};
        window_len_int_f = {{(32-STREAM_LEN_WIDTH){1'b0}}, window_len_f};

        if ((len_int_f == 0) || (window_len_int_f >= len_int_f)) begin
            code_prefix_matches_window = 1'b0;
        end
        else begin
            for (idx = 0; idx < CODE_WIDTH; idx = idx + 1) begin
                if (idx < window_len_int_f) begin
                    if (window_f[idx] != code_f[len_int_f - 1 - idx])
                        code_prefix_matches_window = 1'b0;
                end
            end
        end
    end
    endfunction

    assign block_meta_ready      = !error_r && (state_r == ST_IDLE);
    assign entry_ready           = !error_r && (state_r == ST_COMP_ENTRY);
    assign payload_consume_valid = payload_consume_valid_r;
    assign payload_consume_len   = payload_consume_len_r;
    assign payload_block_done    = payload_block_done_r;
    assign out_byte              = out_byte_r;
    assign out_valid             = out_valid_r;
    assign out_last_in_block     = out_last_in_block_r;
    assign out_last_in_frame     = out_last_in_frame_r;
    assign busy                  = (state_r != ST_IDLE) ||
                                   out_valid_r ||
                                   (1'b0 && (unused_payload_upper_bits_w || unused_debug_error_w));
    assign block_done            = block_done_r;
    assign frame_done            = frame_done_r;
    assign error_flag            = error_r;

    HUFFMAN_DECODE_TABLE_IP u_main_decode_table (
        .clka  (clk),
        .ena   (1'b1),
        .wea   ({main_wr_en_w}),
        .addra (main_wr_addr_w),
        .dina  (main_wr_data_w),
        .douta (unused_main_douta_w),

        .clkb  (clk),
        .enb   (1'b1),
        .web   (1'b0),
        .addrb (main_rd_addr_w),
        .dinb  ({MAIN_ENTRY_WIDTH{1'b0}}),
        .doutb (main_rd_entry_w)
    );

    always @(*) begin
        decode_main_valid_w  = main_rd_entry_w[MAIN_ENTRY_WIDTH-1];
        decode_main_long_w   = main_rd_entry_w[MAIN_ENTRY_WIDTH-2];
        decode_main_symbol_w =
            main_rd_entry_w[CODE_LEN_WIDTH + SYMBOL_WIDTH - 1:CODE_LEN_WIDTH];
        decode_main_len_w    = main_rd_entry_w[CODE_LEN_WIDTH-1:0];

        fallback_match_w  = 1'b0;
        fallback_prefix_w = 1'b0;
        if (fallback_scan_idx_r < fallback_count_r) begin
            fallback_match_w = code_matches_window(
                                   fallback_code[fallback_scan_idx5_w],
                                   fallback_len[fallback_scan_idx5_w],
                                   payload_window_data,
                                   payload_window_len
                               );
            fallback_prefix_w = code_prefix_matches_window(
                                    fallback_code[fallback_scan_idx5_w],
                                    fallback_len[fallback_scan_idx5_w],
                                    payload_window_data,
                                    payload_window_len
                                );
        end

    end

    always @(posedge clk) begin
        if (rst_i) begin
            state_r                       <= ST_IDLE;
            symbol_count_r                <= {SYMBOL_COUNT_WIDTH{1'b0}};
            one_symbol_value_r            <= {SYMBOL_WIDTH{1'b0}};
            bytes_remaining_r             <= {BLOCK_SIZE_WIDTH{1'b0}};
            current_block_is_frame_last_r <= 1'b0;
            entry_load_count_r            <= {SYMBOL_COUNT_WIDTH{1'b0}};
            entry_check_idx_r             <= {SYMBOL_COUNT_WIDTH{1'b0}};
            pending_entry_symbol_r        <= {SYMBOL_WIDTH{1'b0}};
            pending_entry_code_len_r      <= {CODE_LEN_WIDTH{1'b0}};
            pending_entry_last_r          <= 1'b0;
            sort_pass_r                   <= {SYMBOL_COUNT_WIDTH{1'b0}};
            sort_idx_r                    <= {SYMBOL_COUNT_WIDTH{1'b0}};
            assign_idx_r                  <= {SYMBOL_COUNT_WIDTH{1'b0}};
            table_build_idx_r             <= {SYMBOL_COUNT_WIDTH{1'b0}};
            table_clear_idx_r             <= {MAIN_INDEX_WIDTH{1'b0}};
            table_fill_idx_r              <= {MAIN_INDEX_WIDTH{1'b0}};
            table_fill_limit_r            <= {MAIN_INDEX_WIDTH{1'b0}};
            table_prefix_r                <= {MAIN_INDEX_WIDTH{1'b0}};
            table_len_r                   <= {CODE_LEN_WIDTH{1'b0}};
            table_symbol_r                <= {SYMBOL_WIDTH{1'b0}};
            fallback_count_r              <= {SYMBOL_COUNT_WIDTH{1'b0}};
            fallback_scan_idx_r           <= {SYMBOL_COUNT_WIDTH{1'b0}};
            fallback_prefix_seen_r        <= 1'b0;
            current_code_r                <= {CODE_WIDTH{1'b0}};
            prev_len_r                    <= {CODE_LEN_WIDTH{1'b0}};
            pending_final_byte_r          <= {SYMBOL_WIDTH{1'b0}};
            pending_final_frame_r         <= 1'b0;
            out_byte_r                    <= 8'h00;
            out_valid_r                   <= 1'b0;
            out_last_in_block_r           <= 1'b0;
            out_last_in_frame_r           <= 1'b0;
            payload_consume_valid_r       <= 1'b0;
            payload_consume_len_r         <= {STREAM_LEN_WIDTH{1'b0}};
            payload_block_done_r          <= 1'b0;
            block_done_r                  <= 1'b0;
            frame_done_r                  <= 1'b0;
            error_r                       <= 1'b0;
            table_valid_r                 <= 1'b0;
            debug_error_code_r            <= DBG_ERR_NONE;
            debug_error_state_r           <= ST_IDLE;
            debug_error_bytes_remaining_r <= {BLOCK_SIZE_WIDTH{1'b0}};
            debug_error_payload_len_r     <= {STREAM_LEN_WIDTH{1'b0}};

`ifndef SYNTHESIS
            for (i = 0; i < MAX_SYMBOLS; i = i + 1) begin
                symbol_local[i] <= {SYMBOL_WIDTH{1'b0}};
                len_local[i]    <= {CODE_LEN_WIDTH{1'b0}};
                code_local[i]   <= {CODE_WIDTH{1'b0}};
                fallback_symbol[i] <= {SYMBOL_WIDTH{1'b0}};
                fallback_len[i]    <= {CODE_LEN_WIDTH{1'b0}};
                fallback_code[i]   <= {CODE_WIDTH{1'b0}};
            end
`endif
        end
        else begin
            block_done_r            <= 1'b0;
            frame_done_r            <= 1'b0;
            payload_consume_valid_r <= 1'b0;
            payload_consume_len_r   <= {STREAM_LEN_WIDTH{1'b0}};
            payload_block_done_r    <= 1'b0;

            if (out_valid_r && out_ready) begin
                out_valid_r         <= 1'b0;
                out_last_in_block_r <= 1'b0;
                out_last_in_frame_r <= 1'b0;
            end

            if (!error_r) begin
                case (state_r)
                    ST_IDLE: begin
                        current_block_is_frame_last_r <= 1'b0;
                        pending_final_frame_r         <= 1'b0;

                        if (block_meta_valid) begin
                            debug_error_code_r <= DBG_ERR_NONE;
                            symbol_count_r     <= symbol_count;
                            one_symbol_value_r <= one_symbol_value;
                            bytes_remaining_r  <= block_size;
                            entry_load_count_r <= {SYMBOL_COUNT_WIDTH{1'b0}};
                            entry_check_idx_r  <= {SYMBOL_COUNT_WIDTH{1'b0}};
                            pending_entry_symbol_r   <= {SYMBOL_WIDTH{1'b0}};
                            pending_entry_code_len_r <= {CODE_LEN_WIDTH{1'b0}};
                            pending_entry_last_r     <= 1'b0;
                            sort_pass_r        <= {SYMBOL_COUNT_WIDTH{1'b0}};
                            sort_idx_r         <= {SYMBOL_COUNT_WIDTH{1'b0}};
                            assign_idx_r       <= {SYMBOL_COUNT_WIDTH{1'b0}};
                            table_build_idx_r  <= {SYMBOL_COUNT_WIDTH{1'b0}};
                            table_clear_idx_r  <= {MAIN_INDEX_WIDTH{1'b0}};
                            table_fill_idx_r   <= {MAIN_INDEX_WIDTH{1'b0}};
                            table_fill_limit_r <= {MAIN_INDEX_WIDTH{1'b0}};
                            table_prefix_r     <= {MAIN_INDEX_WIDTH{1'b0}};
                            table_len_r        <= {CODE_LEN_WIDTH{1'b0}};
                            table_symbol_r     <= {SYMBOL_WIDTH{1'b0}};
                            fallback_count_r   <= {SYMBOL_COUNT_WIDTH{1'b0}};
                            fallback_scan_idx_r <= {SYMBOL_COUNT_WIDTH{1'b0}};
                            fallback_prefix_seen_r <= 1'b0;
                            current_code_r     <= {CODE_WIDTH{1'b0}};
                            prev_len_r         <= {CODE_LEN_WIDTH{1'b0}};

                            if ((block_mode == MODE_COMPRESSED) &&
                                (symbol_count == {SYMBOL_COUNT_WIDTH{1'b0}})) begin
                                symbol_count_r   <= symbol_count_r;
                                table_clear_idx_r <= table_clear_idx_r;
                                table_fill_idx_r  <= table_fill_idx_r;
                                table_fill_limit_r <= table_fill_limit_r;
                                table_prefix_r    <= table_prefix_r;
                                table_len_r       <= table_len_r;
                                table_symbol_r    <= table_symbol_r;
                                fallback_count_r  <= fallback_count_r;
                                current_code_r    <= current_code_r;
                                prev_len_r        <= prev_len_r;
                            end

                            if ((block_mode == MODE_RAW_FULL) &&
                                ((block_size != FULL_BLOCK_SIZE) ||
                                 (symbol_count != {SYMBOL_COUNT_WIDTH{1'b0}}))) begin
	                                error_r <= 1'b1;
	                                debug_error_code_r            <= DBG_ERR_META_RAW_FULL;
	                                debug_error_state_r           <= state_r;
	                                debug_error_bytes_remaining_r <= bytes_remaining_r;
	                                debug_error_payload_len_r     <= payload_window_len;
	                            end
                            else if ((block_mode == MODE_RAW_PARTIAL) &&
                                     ((block_size > (FULL_BLOCK_SIZE -
                                                     {{(BLOCK_SIZE_WIDTH-1){1'b0}}, 1'b1})) ||
                                      (symbol_count != {SYMBOL_COUNT_WIDTH{1'b0}}))) begin
	                                error_r <= 1'b1;
	                                debug_error_code_r            <= DBG_ERR_META_RAW_PARTIAL;
	                                debug_error_state_r           <= state_r;
	                                debug_error_bytes_remaining_r <= bytes_remaining_r;
	                                debug_error_payload_len_r     <= payload_window_len;
	                            end
                            else if ((block_mode == MODE_ONE_SYMBOL) &&
                                     ((block_size == {BLOCK_SIZE_WIDTH{1'b0}}) ||
                                      (block_size > FULL_BLOCK_SIZE) ||
                                     (symbol_count != {{(SYMBOL_COUNT_WIDTH-1){1'b0}}, 1'b1}) ||
                                       (!decoder_symbol_valid(one_symbol_value)))) begin
	                                error_r <= 1'b1;
	                                debug_error_code_r            <= DBG_ERR_META_ONE_SYMBOL;
	                                debug_error_state_r           <= state_r;
	                                debug_error_bytes_remaining_r <= bytes_remaining_r;
	                                debug_error_payload_len_r     <= payload_window_len;
	                            end
	                            else if ((block_mode == MODE_COMPRESSED) &&
	                                     ((block_size == {BLOCK_SIZE_WIDTH{1'b0}}) ||
	                                      (block_size > FULL_BLOCK_SIZE) ||
                                          ((symbol_count == {SYMBOL_COUNT_WIDTH{1'b0}}) &&
                                           (!table_valid_r)))) begin
		                                error_r <= 1'b1;
		                                debug_error_code_r            <= DBG_ERR_META_COMPRESSED;
	                                debug_error_state_r           <= state_r;
	                                debug_error_bytes_remaining_r <= bytes_remaining_r;
	                                debug_error_payload_len_r     <= payload_window_len;
	                            end
                            else begin
                                if ((block_mode == MODE_RAW_PARTIAL) &&
                                    (block_size == {BLOCK_SIZE_WIDTH{1'b0}}))
                                    state_r <= ST_EMPTY_WAIT_DONE;
                                else if (block_mode == MODE_ONE_SYMBOL)
                                    state_r <= ST_ONE_WAIT_DONE;
                                else if ((block_mode == MODE_RAW_FULL) ||
                                         (block_mode == MODE_RAW_PARTIAL))
                                    state_r <= ST_RAW_RUN;
	                                else if (block_mode == MODE_COMPRESSED) begin
                                        if (symbol_count == {SYMBOL_COUNT_WIDTH{1'b0}})
                                            state_r <= ST_COMP_DECODE;
                                        else
                                            state_r <= ST_COMP_ENTRY;
                                    end
                                    else
                                        state_r <= ST_COMP_ENTRY;
	                            end
	                        end
                    end

	                    ST_EMPTY_WAIT_DONE: begin
	                        if (parser_block_done) begin
	                            block_done_r <= 1'b1;
	                            if (parser_frame_done) begin
	                                frame_done_r <= 1'b1;
                                    table_valid_r <= 1'b0;
                                end
	                            state_r <= ST_IDLE;
	                        end
	                    end

                    ST_ONE_WAIT_DONE: begin
                        if (parser_block_done) begin
                            current_block_is_frame_last_r <= parser_frame_done;
                            state_r                       <= ST_ONE_RUN;
                        end
                    end

                    ST_ONE_RUN: begin
                        if (!out_valid_r &&
                            (bytes_remaining_r != {BLOCK_SIZE_WIDTH{1'b0}})) begin
                            out_byte_r  <= one_symbol_value_r;
                            out_valid_r <= 1'b1;

                            if (bytes_remaining_r ==
                                {{(BLOCK_SIZE_WIDTH-1){1'b0}}, 1'b1}) begin
                                bytes_remaining_r     <= {BLOCK_SIZE_WIDTH{1'b0}};
                                out_last_in_block_r   <= 1'b1;
                                out_last_in_frame_r   <= current_block_is_frame_last_r;
                                pending_final_frame_r <= current_block_is_frame_last_r;
                                state_r               <= ST_FINAL_OUT;
                            end
                            else begin
                                bytes_remaining_r   <= bytes_remaining_r -
                                                       {{(BLOCK_SIZE_WIDTH-1){1'b0}}, 1'b1};
                                out_last_in_block_r <= 1'b0;
                                out_last_in_frame_r <= 1'b0;
                            end
                        end
                    end

                    ST_RAW_RUN: begin
                        if (!out_valid_r) begin
                            if (payload_window_valid &&
                                (payload_window_len >= BYTE_BITS_LEN)) begin
                                if (bytes_remaining_r ==
                                    {{(BLOCK_SIZE_WIDTH-1){1'b0}}, 1'b1}) begin
                                    pending_final_byte_r    <= payload_window_data[7:0];
                                    payload_consume_valid_r <= 1'b1;
                                    payload_consume_len_r   <= BYTE_BITS_LEN;
                                    bytes_remaining_r       <= {BLOCK_SIZE_WIDTH{1'b0}};
                                    state_r                 <= ST_RAW_WAIT_DONE;
                                end
                                else begin
                                    out_byte_r              <= payload_window_data[7:0];
                                    out_valid_r             <= 1'b1;
                                    out_last_in_block_r     <= 1'b0;
                                    out_last_in_frame_r     <= 1'b0;
                                    payload_consume_valid_r <= 1'b1;
                                    payload_consume_len_r   <= BYTE_BITS_LEN;
                                    bytes_remaining_r       <= bytes_remaining_r -
                                                               {{(BLOCK_SIZE_WIDTH-1){1'b0}}, 1'b1};
                                end
                            end
                        end
                    end

                    ST_RAW_WAIT_DONE: begin
                        if (parser_block_done) begin
                            out_byte_r              <= pending_final_byte_r;
                            out_valid_r             <= 1'b1;
                            out_last_in_block_r     <= 1'b1;
                            out_last_in_frame_r     <= parser_frame_done;
                            pending_final_frame_r   <= parser_frame_done;
                            state_r                 <= ST_FINAL_OUT;
                        end
                    end

                    ST_COMP_ENTRY: begin
                        if (entry_valid) begin
                            if ((!decoder_symbol_valid(entry_symbol)) ||
                                (entry_code_len == {CODE_LEN_WIDTH{1'b0}})) begin
		                                error_r <= 1'b1;
		                                debug_error_code_r            <= DBG_ERR_ENTRY_INVALID;
		                                debug_error_state_r           <= state_r;
		                                debug_error_bytes_remaining_r <= bytes_remaining_r;
		                                debug_error_payload_len_r     <= payload_window_len;
		                            end
                            else begin
                                pending_entry_symbol_r   <= entry_symbol;
                                pending_entry_code_len_r <= entry_code_len;
                                pending_entry_last_r     <= entry_last;
                                entry_check_idx_r        <= {SYMBOL_COUNT_WIDTH{1'b0}};

                                if (entry_load_count_r == {SYMBOL_COUNT_WIDTH{1'b0}})
                                    state_r <= ST_COMP_ENTRY_COMMIT;
                                else
                                    state_r <= ST_COMP_ENTRY_CHECK;
                            end
                        end
                    end

                    ST_COMP_ENTRY_CHECK: begin
                        if (symbol_local[entry_check_idx5_w] ==
                            pending_entry_symbol_r) begin
                            error_r <= 1'b1;
                            debug_error_code_r            <= DBG_ERR_ENTRY_INVALID;
                            debug_error_state_r           <= state_r;
                            debug_error_bytes_remaining_r <= bytes_remaining_r;
                            debug_error_payload_len_r     <= payload_window_len;
                        end
                        else if (entry_check_idx_r ==
                                 (entry_load_count_r -
                                  {{(SYMBOL_COUNT_WIDTH-1){1'b0}}, 1'b1})) begin
                            state_r <= ST_COMP_ENTRY_COMMIT;
                        end
                        else begin
                            entry_check_idx_r <= entry_check_idx_r +
                                                 {{(SYMBOL_COUNT_WIDTH-1){1'b0}}, 1'b1};
                        end
                    end

                    ST_COMP_ENTRY_COMMIT: begin
                        symbol_local[entry_load_idx5_w] <= pending_entry_symbol_r;
                        len_local[entry_load_idx5_w]    <= pending_entry_code_len_r;
                        code_local[entry_load_idx5_w]   <= {CODE_WIDTH{1'b0}};

                        if (entry_load_count_r ==
                            (symbol_count_r -
                             {{(SYMBOL_COUNT_WIDTH-1){1'b0}}, 1'b1})) begin
                            if (!pending_entry_last_r) begin
                                error_r <= 1'b1;
                                debug_error_code_r            <= DBG_ERR_ENTRY_LAST_MISS;
                                debug_error_state_r           <= state_r;
                                debug_error_bytes_remaining_r <= bytes_remaining_r;
                                debug_error_payload_len_r     <= payload_window_len;
                            end
                            else begin
                                sort_pass_r <= {SYMBOL_COUNT_WIDTH{1'b0}};
                                sort_idx_r  <= {SYMBOL_COUNT_WIDTH{1'b0}};
                                state_r     <= ST_COMP_SORT;
                            end
                        end
                        else begin
                            if (pending_entry_last_r) begin
                                error_r <= 1'b1;
                                debug_error_code_r            <= DBG_ERR_ENTRY_LAST_EARLY;
                                debug_error_state_r           <= state_r;
                                debug_error_bytes_remaining_r <= bytes_remaining_r;
                                debug_error_payload_len_r     <= payload_window_len;
                            end
                            else begin
                                entry_load_count_r <= entry_load_count_r +
                                                      {{(SYMBOL_COUNT_WIDTH-1){1'b0}}, 1'b1};
                                state_r <= ST_COMP_ENTRY;
                            end
                        end
                    end

                    ST_COMP_SORT: begin
                        if (sort_pass_r <
                            (symbol_count_r -
                             {{(SYMBOL_COUNT_WIDTH-1){1'b0}}, 1'b1})) begin
                            if (sort_idx_r <
                                (symbol_count_r -
                                 {{(SYMBOL_COUNT_WIDTH-1){1'b0}}, 1'b1} -
                                 sort_pass_r)) begin
                                if ((len_local[sort_idx5_w] > len_local[sort_idx_p1_5_w]) ||
                                    ((len_local[sort_idx5_w] == len_local[sort_idx_p1_5_w]) &&
                                     (symbol_local[sort_idx5_w] > symbol_local[sort_idx_p1_5_w]))) begin
                                    {symbol_local[sort_idx5_w],
                                     symbol_local[sort_idx_p1_5_w]} <=
                                    {symbol_local[sort_idx_p1_5_w],
                                     symbol_local[sort_idx5_w]};

                                    {len_local[sort_idx5_w],
                                     len_local[sort_idx_p1_5_w]} <=
                                    {len_local[sort_idx_p1_5_w],
                                     len_local[sort_idx5_w]};
                                end

                                sort_idx_r <= sort_idx_r +
                                              {{(SYMBOL_COUNT_WIDTH-1){1'b0}}, 1'b1};
                            end
                            else begin
                                sort_idx_r  <= {SYMBOL_COUNT_WIDTH{1'b0}};
                                sort_pass_r <= sort_pass_r +
                                               {{(SYMBOL_COUNT_WIDTH-1){1'b0}}, 1'b1};
                            end
                        end
                        else begin
                            assign_idx_r   <= {SYMBOL_COUNT_WIDTH{1'b0}};
                            current_code_r <= {CODE_WIDTH{1'b0}};
                            prev_len_r     <= {CODE_LEN_WIDTH{1'b0}};
                            state_r        <= ST_COMP_ASSIGN;
                        end
                    end

                    ST_COMP_ASSIGN: begin
                        if (assign_idx_r < symbol_count_r) begin
                            if (assign_idx_r == {SYMBOL_COUNT_WIDTH{1'b0}}) begin
	                                if (len_local[0] == {CODE_LEN_WIDTH{1'b0}}) begin
	                                    error_r <= 1'b1;
	                                    debug_error_code_r            <= DBG_ERR_ASSIGN_FIRST_LEN;
	                                    debug_error_state_r           <= state_r;
	                                    debug_error_bytes_remaining_r <= bytes_remaining_r;
	                                    debug_error_payload_len_r     <= payload_window_len;
	                                end
	                                else begin
                                    code_local[0]  <= {CODE_WIDTH{1'b0}};
                                    current_code_r <= {CODE_WIDTH{1'b0}};
                                    prev_len_r     <= len_local[0];
                                    assign_idx_r   <= assign_idx_r +
                                                      {{(SYMBOL_COUNT_WIDTH-1){1'b0}}, 1'b1};

                                    if (symbol_count_r ==
                                        {{(SYMBOL_COUNT_WIDTH-1){1'b0}}, 1'b1}) begin
                                        state_r       <= ST_TABLE_CLEAR;
                                    end
                                end
                            end
                            else begin
	                                if ((len_local[assign_idx5_w] == {CODE_LEN_WIDTH{1'b0}}) ||
	                                    (len_local[assign_idx5_w] < prev_len_r)) begin
	                                    error_r <= 1'b1;
	                                    debug_error_code_r            <= DBG_ERR_ASSIGN_ORDER;
	                                    debug_error_state_r           <= state_r;
	                                    debug_error_bytes_remaining_r <= bytes_remaining_r;
	                                    debug_error_payload_len_r     <= payload_window_len;
	                                end
	                                else begin
                                    current_code_r <= next_canonical_code(
                                                          current_code_r,
                                                          prev_len_r,
                                                          len_local[assign_idx5_w]
                                                      );

                                    code_local[assign_idx5_w] <=
                                        next_canonical_code(
                                            current_code_r,
                                            prev_len_r,
                                            len_local[assign_idx5_w]
                                        );

                                    prev_len_r   <= len_local[assign_idx5_w];
                                    assign_idx_r <= assign_idx_r +
                                                    {{(SYMBOL_COUNT_WIDTH-1){1'b0}}, 1'b1};

                                    if (assign_idx_r ==
                                        (symbol_count_r -
                                         {{(SYMBOL_COUNT_WIDTH-1){1'b0}}, 1'b1})) begin
                                        state_r       <= ST_TABLE_CLEAR;
                                    end
                                end
                            end
                        end
                        else begin
                            state_r       <= ST_TABLE_CLEAR;
                        end
                    end

                    ST_TABLE_CLEAR: begin
                        if (table_clear_idx_r == {MAIN_INDEX_WIDTH{1'b1}}) begin
                            table_build_idx_r <= {SYMBOL_COUNT_WIDTH{1'b0}};
                            fallback_count_r  <= {SYMBOL_COUNT_WIDTH{1'b0}};
                            state_r           <= ST_TABLE_PREP;
                        end
                        else begin
                            table_clear_idx_r <= table_clear_idx_r +
                                                 {{(MAIN_INDEX_WIDTH-1){1'b0}}, 1'b1};
                        end
                    end

                    ST_TABLE_PREP: begin
                        if (table_build_idx_r < symbol_count_r) begin
                            if (len_local[table_build_idx5_w] <= MAIN_LOOKUP_LEN) begin
                                table_prefix_r <= reverse_code_prefix(
                                                      code_local[table_build_idx5_w],
                                                      len_local[table_build_idx5_w]
                                                  );
                                table_len_r    <= len_local[table_build_idx5_w];
                                table_symbol_r <= symbol_local[table_build_idx5_w];
                                table_fill_idx_r <= {MAIN_INDEX_WIDTH{1'b0}};
                                table_fill_limit_r <=
                                    {{(MAIN_INDEX_WIDTH-1){1'b0}}, 1'b1} <<
                                    (MAIN_LOOKUP_LEN - len_local[table_build_idx5_w]);
                                state_r <= ST_TABLE_FILL;
                            end
                            else begin
                                if (fallback_count_r >= MAX_SYMBOLS_VALUE) begin
	                                    error_r <= 1'b1;
	                                    debug_error_code_r            <= DBG_ERR_FALLBACK_OVERFLOW;
	                                    debug_error_state_r           <= state_r;
	                                    debug_error_bytes_remaining_r <= bytes_remaining_r;
	                                    debug_error_payload_len_r     <= payload_window_len;
	                                end
                                else begin
                                    fallback_symbol[fallback_count_idx5_w] <=
                                        symbol_local[table_build_idx5_w];
                                    fallback_len[fallback_count_idx5_w] <=
                                        len_local[table_build_idx5_w];
                                    fallback_code[fallback_count_idx5_w] <=
                                        code_local[table_build_idx5_w];
                                    fallback_count_r <= fallback_count_r +
                                                        {{(SYMBOL_COUNT_WIDTH-1){1'b0}}, 1'b1};
                                    table_build_idx_r <= table_build_idx_r +
                                                         {{(SYMBOL_COUNT_WIDTH-1){1'b0}}, 1'b1};
                                end
                            end
                        end
	                        else begin
                                table_valid_r <= 1'b1;
	                            state_r <= ST_COMP_DECODE;
	                        end
                    end

                    ST_TABLE_FILL: begin
                        if (table_fill_idx_r ==
                            (table_fill_limit_r -
                             {{(MAIN_INDEX_WIDTH-1){1'b0}}, 1'b1})) begin
                            table_build_idx_r <= table_build_idx_r +
                                                 {{(SYMBOL_COUNT_WIDTH-1){1'b0}}, 1'b1};
                            state_r <= ST_TABLE_PREP;
                        end
                        else begin
                            table_fill_idx_r <= table_fill_idx_r +
                                                {{(MAIN_INDEX_WIDTH-1){1'b0}}, 1'b1};
                        end
                    end

                    ST_COMP_DECODE: begin
                        if (!out_valid_r) begin
	                            if (bytes_remaining_r == {BLOCK_SIZE_WIDTH{1'b0}}) begin
	                                error_r <= 1'b1;
	                                debug_error_code_r            <= DBG_ERR_DECODE_EMPTY;
	                                debug_error_state_r           <= state_r;
	                                debug_error_bytes_remaining_r <= bytes_remaining_r;
	                                debug_error_payload_len_r     <= payload_window_len;
	                            end
	                            else if (payload_window_valid &&
                                     (payload_window_len != {STREAM_LEN_WIDTH{1'b0}})) begin
                                // The parser may have just consumed bits on this
                                // clock edge. Wait one cycle so the BRAM lookup
                                // address is sampled from the updated window.
                                state_r <= ST_COMP_LOOKUP_WAIT;
                            end
                        end
                    end

                    ST_COMP_LOOKUP_WAIT: begin
                        if (!out_valid_r) begin
                            if (bytes_remaining_r == {BLOCK_SIZE_WIDTH{1'b0}}) begin
                                error_r <= 1'b1;
                                debug_error_code_r            <= DBG_ERR_LOOKUP_EMPTY;
                                debug_error_state_r           <= state_r;
                                debug_error_bytes_remaining_r <= bytes_remaining_r;
                                debug_error_payload_len_r     <= payload_window_len;
                            end
                            else if (payload_window_valid &&
                                     (payload_window_len != {STREAM_LEN_WIDTH{1'b0}})) begin
                                state_r <= ST_COMP_LOOKUP;
                            end
                            else begin
                                state_r <= ST_COMP_DECODE;
                            end
                        end
                    end

                    ST_COMP_LOOKUP: begin
                        if (!out_valid_r) begin
	                            if (bytes_remaining_r == {BLOCK_SIZE_WIDTH{1'b0}}) begin
	                                error_r <= 1'b1;
	                                debug_error_code_r            <= DBG_ERR_LOOKUP_EMPTY;
	                                debug_error_state_r           <= state_r;
	                                debug_error_bytes_remaining_r <= bytes_remaining_r;
	                                debug_error_payload_len_r     <= payload_window_len;
	                            end
	                            else if (payload_window_valid &&
                                     (payload_window_len != {STREAM_LEN_WIDTH{1'b0}})) begin
                                if (decode_main_valid_w && !decode_main_long_w) begin
                                    if (payload_window_len >=
                                        {{(STREAM_LEN_WIDTH-CODE_LEN_WIDTH){1'b0}},
                                         decode_main_len_w}) begin
                                        payload_consume_valid_r <= 1'b1;
                                        payload_consume_len_r   <=
                                            {{(STREAM_LEN_WIDTH-CODE_LEN_WIDTH){1'b0}},
                                             decode_main_len_w};

                                        if (bytes_remaining_r ==
                                            {{(BLOCK_SIZE_WIDTH-1){1'b0}}, 1'b1}) begin
                                            pending_final_byte_r <= decode_main_symbol_w;
                                            payload_block_done_r <= 1'b1;
                                            bytes_remaining_r    <= {BLOCK_SIZE_WIDTH{1'b0}};
                                            state_r              <= ST_COMP_WAIT_DONE;
                                        end
                                        else begin
                                            out_byte_r          <= decode_main_symbol_w;
                                            out_valid_r         <= 1'b1;
                                            out_last_in_block_r <= 1'b0;
                                            out_last_in_frame_r <= 1'b0;
                                            bytes_remaining_r   <= bytes_remaining_r -
                                                                   {{(BLOCK_SIZE_WIDTH-1){1'b0}}, 1'b1};
                                            state_r             <= ST_COMP_DECODE;
                                        end
                                    end
                                    else begin
                                        state_r <= ST_COMP_DECODE;
                                    end
                                end
                                else if (decode_main_valid_w && decode_main_long_w) begin
                                    if (payload_window_len >=
                                        {{(STREAM_LEN_WIDTH-CODE_LEN_WIDTH){1'b0}},
                                         MAIN_LOOKUP_LEN}) begin
                                        fallback_scan_idx_r    <= {SYMBOL_COUNT_WIDTH{1'b0}};
                                        fallback_prefix_seen_r <= 1'b0;
                                        state_r                <= ST_COMP_FALLBACK;
                                    end
                                    else begin
                                        state_r <= ST_COMP_DECODE;
                                    end
                                end
                                else if (payload_window_len >=
                                         {{(STREAM_LEN_WIDTH-CODE_LEN_WIDTH){1'b0}},
                                          MAIN_LOOKUP_LEN}) begin
	                                    error_r <= 1'b1;
	                                    debug_error_code_r            <= DBG_ERR_LOOKUP_NO_MAIN;
	                                    debug_error_state_r           <= state_r;
	                                    debug_error_bytes_remaining_r <= bytes_remaining_r;
	                                    debug_error_payload_len_r     <= payload_window_len;
	                                end
                                else begin
                                    state_r <= ST_COMP_DECODE;
                                end
                            end
                            else begin
                                state_r <= ST_COMP_DECODE;
                            end
                        end
                    end

                    ST_COMP_FALLBACK: begin
                        if (fallback_scan_idx_r < fallback_count_r) begin
                            if (fallback_match_w) begin
                                payload_consume_valid_r <= 1'b1;
                                payload_consume_len_r   <=
                                    {{(STREAM_LEN_WIDTH-CODE_LEN_WIDTH){1'b0}},
                                     fallback_len[fallback_scan_idx5_w]};

                                if (bytes_remaining_r ==
                                    {{(BLOCK_SIZE_WIDTH-1){1'b0}}, 1'b1}) begin
                                    pending_final_byte_r <=
                                        fallback_symbol[fallback_scan_idx5_w];
                                    payload_block_done_r <= 1'b1;
                                    bytes_remaining_r    <= {BLOCK_SIZE_WIDTH{1'b0}};
                                    state_r              <= ST_COMP_WAIT_DONE;
                                end
                                else begin
                                    out_byte_r          <= fallback_symbol[fallback_scan_idx5_w];
                                    out_valid_r         <= 1'b1;
                                    out_last_in_block_r <= 1'b0;
                                    out_last_in_frame_r <= 1'b0;
                                    bytes_remaining_r   <= bytes_remaining_r -
                                                           {{(BLOCK_SIZE_WIDTH-1){1'b0}}, 1'b1};
                                    state_r             <= ST_COMP_DECODE;
                                end
                            end
                            else begin
                                if (fallback_prefix_w)
                                    fallback_prefix_seen_r <= 1'b1;

                                fallback_scan_idx_r <= fallback_scan_idx_r +
                                                       {{(SYMBOL_COUNT_WIDTH-1){1'b0}}, 1'b1};
                            end
                        end
                        else begin
	                            if (fallback_prefix_seen_r)
	                                state_r <= ST_COMP_DECODE;
	                            else begin
	                                error_r <= 1'b1;
	                                debug_error_code_r            <= DBG_ERR_FALLBACK_NO_MATCH;
	                                debug_error_state_r           <= state_r;
	                                debug_error_bytes_remaining_r <= bytes_remaining_r;
	                                debug_error_payload_len_r     <= payload_window_len;
	                            end
	                        end
                    end

                    ST_COMP_WAIT_DONE: begin
                        if (parser_block_done) begin
                            out_byte_r            <= pending_final_byte_r;
                            out_valid_r           <= 1'b1;
                            out_last_in_block_r   <= 1'b1;
                            out_last_in_frame_r   <= parser_frame_done;
                            pending_final_frame_r <= parser_frame_done;
                            state_r               <= ST_FINAL_OUT;
                        end
                    end

	                    ST_FINAL_OUT: begin
	                        if (out_valid_r && out_ready) begin
	                            block_done_r <= 1'b1;
	                            if (pending_final_frame_r) begin
	                                frame_done_r <= 1'b1;
                                    table_valid_r <= 1'b0;
                                end
	                            pending_final_frame_r <= 1'b0;
	                            state_r <= ST_IDLE;
	                        end
                    end

                    default: begin
                        state_r <= ST_IDLE;
                    end
                endcase
            end
            else begin
	                state_r                 <= ST_IDLE;
                    table_valid_r           <= 1'b0;
	                out_valid_r             <= 1'b0;
                out_last_in_block_r     <= 1'b0;
                out_last_in_frame_r     <= 1'b0;
                payload_consume_valid_r <= 1'b0;
                payload_consume_len_r   <= {STREAM_LEN_WIDTH{1'b0}};
                payload_block_done_r    <= 1'b0;
            end
        end
    end

endmodule

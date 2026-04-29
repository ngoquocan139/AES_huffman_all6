module mode_decision_logic #(
    parameter BLOCK_SIZE_WIDTH   = 6,
    parameter BUFFER_ADDR_WIDTH  = 5,
    parameter SYMBOL_WIDTH       = 8,
    parameter SYMBOL_INDEX_WIDTH = 7,
    parameter CODE_LEN_WIDTH     = 5,
    parameter TOTAL_BITS_WIDTH   = 11,
    parameter [7:0] ASCII_MIN    = 8'h20,
    parameter [7:0] ASCII_MAX    = 8'h7E
)(
    input  wire                          clk,
    input  wire                          rst_n,
    input  wire                          start,

    input  wire [BLOCK_SIZE_WIDTH-1:0]   block_size,
    input  wire [BLOCK_SIZE_WIDTH-1:0]   symbol_count,

    // Read block_buffer
    output reg  [BUFFER_ADDR_WIDTH-1:0]  buffer_read_addr,
    input  wire [SYMBOL_WIDTH-1:0]       buffer_read_data,

    // Read code_len_table
    output reg  [SYMBOL_INDEX_WIDTH-1:0] code_len_read_index,
    input  wire [CODE_LEN_WIDTH-1:0]     code_len_read_data,

    output wire                          busy,
    output wire                          done,
    output reg                           error_flag,

    output reg  [1:0]                    selected_mode,

    output reg  [TOTAL_BITS_WIDTH-1:0]   raw_total_bits,
    output reg  [TOTAL_BITS_WIDTH-1:0]   compressed_header_bits,
    output reg  [TOTAL_BITS_WIDTH-1:0]   compressed_payload_bits,
    output reg  [TOTAL_BITS_WIDTH-1:0]   compressed_total_bits,
    output reg  [TOTAL_BITS_WIDTH-1:0]   one_symbol_total_bits
);

    localparam ST_IDLE    = 3'd0;
    localparam ST_INIT    = 3'd1;
    localparam ST_SCAN    = 3'd2;
    localparam ST_COMPARE = 3'd3;
    localparam ST_DONE    = 3'd4;

    localparam [1:0] MODE_RAW_FULL          = 2'b00;
    localparam [1:0] MODE_RAW_PARTIAL       = 2'b01;
    localparam [1:0] MODE_COMPRESSED        = 2'b10;
    localparam [1:0] MODE_ONE_SYMBOL_COMP   = 2'b11;

    // RAW_FULL       : 2 bits
    // RAW_PARTIAL    : 2 + 6 = 8 bits
    // COMPRESSED     : 2 + 6 + 6 = 14 bits + 13*K
    // ONE_SYMBOL_COMP: 2 + 6 + 8 = 16 bits, no payload
    localparam [TOTAL_BITS_WIDTH-1:0] RAW_FULL_BASE_BITS     = 11'd2;
    localparam [TOTAL_BITS_WIDTH-1:0] RAW_PARTIAL_BASE_BITS  = 11'd8;
    localparam [TOTAL_BITS_WIDTH-1:0] COMP_BASE_BITS         = 11'd14;
    localparam [TOTAL_BITS_WIDTH-1:0] ONE_SYMBOL_BASE_BITS   = 11'd16;
    localparam [TOTAL_BITS_WIDTH-1:0] TRANSPORT_PAYLOAD_BITS = 11'd120;
    localparam [TOTAL_BITS_WIDTH-1:0] TRANSPORT_WORD_BYTES   = 11'd16;
    localparam [TOTAL_BITS_WIDTH-1:0] MIN_COMP_MARGIN_BITS   = 11'd16;

    reg [2:0] state, next_state;

    reg start_d;
    wire start_pulse;

    reg [BLOCK_SIZE_WIDTH-1:0] scan_idx;

`include "huffman_symbol_map.vh"

    wire [TOTAL_BITS_WIDTH-1:0] raw_data_bits_w;
    wire [TOTAL_BITS_WIDTH-1:0] symbol_list_bits_w;
    wire [TOTAL_BITS_WIDTH-1:0] current_code_len_ext_w;
    wire [TOTAL_BITS_WIDTH-1:0] block_size_ext_w;
    wire [TOTAL_BITS_WIDTH-1:0] compressed_total_bits_w;
    wire [TOTAL_BITS_WIDTH-1:0] raw_transport_words_w;
    wire [TOTAL_BITS_WIDTH-1:0] compressed_transport_words_w;
    wire [TOTAL_BITS_WIDTH-1:0] one_symbol_transport_words_w;
    wire [TOTAL_BITS_WIDTH-1:0] raw_storage_bytes_w;
    wire [TOTAL_BITS_WIDTH-1:0] compressed_storage_bytes_w;
    wire [TOTAL_BITS_WIDTH-1:0] one_symbol_storage_bytes_w;
    wire [TOTAL_BITS_WIDTH-1:0] comp_margin_bits_w;
    wire [TOTAL_BITS_WIDTH-1:0] one_symbol_margin_bits_w;
    wire                        comp_margin_ok_w;
    wire                        one_symbol_margin_ok_w;

    wire                          current_byte_valid_w;
    wire [SYMBOL_INDEX_WIDTH-1:0] current_symbol_index_w;

    function [TOTAL_BITS_WIDTH-1:0] transport_words_for_bits;
        input [TOTAL_BITS_WIDTH-1:0] total_bits;
        begin
            if (total_bits == {TOTAL_BITS_WIDTH{1'b0}})
                transport_words_for_bits = {TOTAL_BITS_WIDTH{1'b0}};
            else if (total_bits <= (TRANSPORT_PAYLOAD_BITS * 1))
                transport_words_for_bits = {{(TOTAL_BITS_WIDTH-1){1'b0}}, 1'b1};
            else if (total_bits <= (TRANSPORT_PAYLOAD_BITS * 2))
                transport_words_for_bits = {{(TOTAL_BITS_WIDTH-2){1'b0}}, 2'b10};
            else if (total_bits <= (TRANSPORT_PAYLOAD_BITS * 3))
                transport_words_for_bits = {{(TOTAL_BITS_WIDTH-2){1'b0}}, 2'b11};
            else if (total_bits <= (TRANSPORT_PAYLOAD_BITS * 4))
                transport_words_for_bits = {{(TOTAL_BITS_WIDTH-3){1'b0}}, 3'b100};
            else
                transport_words_for_bits = {{(TOTAL_BITS_WIDTH-3){1'b0}}, 3'b101};
        end
    endfunction

    assign start_pulse = start & ~start_d;

    assign raw_data_bits_w =
        {{(TOTAL_BITS_WIDTH-BLOCK_SIZE_WIDTH){1'b0}}, block_size} << 3;

    assign block_size_ext_w =
        {{(TOTAL_BITS_WIDTH-BLOCK_SIZE_WIDTH){1'b0}}, block_size};

    assign compressed_total_bits_w =
        compressed_header_bits + compressed_payload_bits;

    assign raw_transport_words_w =
        transport_words_for_bits(raw_total_bits);

    assign compressed_transport_words_w =
        transport_words_for_bits(compressed_total_bits_w);

    assign one_symbol_transport_words_w =
        transport_words_for_bits(one_symbol_total_bits);

    assign raw_storage_bytes_w =
        raw_transport_words_w * TRANSPORT_WORD_BYTES;

    assign compressed_storage_bytes_w =
        compressed_transport_words_w * TRANSPORT_WORD_BYTES;

    assign one_symbol_storage_bytes_w =
        one_symbol_transport_words_w * TRANSPORT_WORD_BYTES;

    assign comp_margin_bits_w =
        (raw_total_bits > compressed_total_bits_w) ?
        (raw_total_bits - compressed_total_bits_w) :
        {TOTAL_BITS_WIDTH{1'b0}};

    assign one_symbol_margin_bits_w =
        (raw_total_bits > one_symbol_total_bits) ?
        (raw_total_bits - one_symbol_total_bits) :
        {TOTAL_BITS_WIDTH{1'b0}};

    assign comp_margin_ok_w =
        (comp_margin_bits_w >= MIN_COMP_MARGIN_BITS);

    assign one_symbol_margin_ok_w =
        (one_symbol_margin_bits_w >= MIN_COMP_MARGIN_BITS);

    // 13 bits / symbol = 8(symbol_id) + 5(code_len)
    assign symbol_list_bits_w =
        ({{(TOTAL_BITS_WIDTH-BLOCK_SIZE_WIDTH){1'b0}}, symbol_count} << 3) +
        ({{(TOTAL_BITS_WIDTH-BLOCK_SIZE_WIDTH){1'b0}}, symbol_count} << 2) +
        {{(TOTAL_BITS_WIDTH-BLOCK_SIZE_WIDTH){1'b0}}, symbol_count};

    assign current_code_len_ext_w =
        {{(TOTAL_BITS_WIDTH-CODE_LEN_WIDTH){1'b0}}, code_len_read_data};

    assign current_byte_valid_w =
        huffman_symbol_valid(buffer_read_data);

    assign current_symbol_index_w =
        huffman_symbol_to_index(buffer_read_data);

    assign busy = (state == ST_INIT) ||
                  (state == ST_SCAN) ||
                  (state == ST_COMPARE);

    assign done = (state == ST_DONE);

    // ------------------------------------------------------------
    // Read interfaces
    // ------------------------------------------------------------
    always @(*) begin
        if (state == ST_SCAN && (scan_idx < block_size))
            buffer_read_addr = scan_idx[BUFFER_ADDR_WIDTH-1:0];
        else
            buffer_read_addr = {BUFFER_ADDR_WIDTH{1'b0}};
    end

    always @(*) begin
        if (state == ST_SCAN && (scan_idx < block_size) && current_byte_valid_w)
            code_len_read_index = current_symbol_index_w;
        else
            code_len_read_index = {SYMBOL_INDEX_WIDTH{1'b0}};
    end

    // ------------------------------------------------------------
    // Next-state logic
    // ------------------------------------------------------------
    always @(*) begin
        next_state = state;

        case (state)
            ST_IDLE: begin
                if (start_pulse)
                    next_state = ST_INIT;
            end

            ST_INIT: begin
                // no need to scan if:
                // - empty block
                // - one-symbol block (can decide directly)
                if (block_size == {BLOCK_SIZE_WIDTH{1'b0}})
                    next_state = ST_COMPARE;
                else if (symbol_count == {{(BLOCK_SIZE_WIDTH-1){1'b0}},1'b1})
                    next_state = ST_COMPARE;
                else
                    next_state = ST_SCAN;
            end

            ST_SCAN: begin
                if (scan_idx == block_size)
                    next_state = ST_COMPARE;
            end

            ST_COMPARE: begin
                next_state = ST_DONE;
            end

            ST_DONE: begin
                if (start_pulse)
                    next_state = ST_INIT;
            end

            default: begin
                next_state = ST_IDLE;
            end
        endcase
    end

    // ------------------------------------------------------------
    // Sequential logic
    // ------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state                    <= ST_IDLE;
            start_d                  <= 1'b0;
            scan_idx                 <= {BLOCK_SIZE_WIDTH{1'b0}};
            error_flag               <= 1'b0;
            selected_mode            <= MODE_RAW_PARTIAL;

            raw_total_bits           <= {TOTAL_BITS_WIDTH{1'b0}};
            compressed_header_bits   <= {TOTAL_BITS_WIDTH{1'b0}};
            compressed_payload_bits  <= {TOTAL_BITS_WIDTH{1'b0}};
            compressed_total_bits    <= {TOTAL_BITS_WIDTH{1'b0}};
            one_symbol_total_bits    <= {TOTAL_BITS_WIDTH{1'b0}};
        end
        else begin
            state   <= next_state;
            start_d <= start;

            case (state)
                ST_IDLE: begin
                end

                ST_INIT: begin
                    scan_idx                 <= {BLOCK_SIZE_WIDTH{1'b0}};
                    error_flag               <= 1'b0;
                    selected_mode            <= MODE_RAW_PARTIAL;
                    compressed_payload_bits  <= {TOTAL_BITS_WIDTH{1'b0}};
                    compressed_total_bits    <= {TOTAL_BITS_WIDTH{1'b0}};
                    one_symbol_total_bits    <= {TOTAL_BITS_WIDTH{1'b0}};

                    // integrity checks
                    if (block_size > 6'd32)
                        error_flag <= 1'b1;

                    if (symbol_count > 6'd32)
                        error_flag <= 1'b1;

                    if ((block_size == {BLOCK_SIZE_WIDTH{1'b0}}) &&
                        (symbol_count != {BLOCK_SIZE_WIDTH{1'b0}}))
                        error_flag <= 1'b1;

                    // raw candidate
                    if (block_size == 6'd32)
                        raw_total_bits <= RAW_FULL_BASE_BITS + raw_data_bits_w;
                    else
                        raw_total_bits <= RAW_PARTIAL_BASE_BITS + raw_data_bits_w;

                    // standard compressed
                    compressed_header_bits <= COMP_BASE_BITS + symbol_list_bits_w;

                    // one-symbol compressed
                    if (symbol_count == {{(BLOCK_SIZE_WIDTH-1){1'b0}},1'b1})
                        one_symbol_total_bits <= ONE_SYMBOL_BASE_BITS;
                    else
                        one_symbol_total_bits <= {TOTAL_BITS_WIDTH{1'b0}};

                    // if only one symbol, standard compressed payload would be 1 bit/byte
                    if (symbol_count == {{(BLOCK_SIZE_WIDTH-1){1'b0}},1'b1})
                        compressed_payload_bits <= block_size_ext_w;
                end

                ST_SCAN: begin
                    if (scan_idx < block_size) begin
                        if (!current_byte_valid_w) begin
                            error_flag <= 1'b1;
                        end
                        else begin
                            if (code_len_read_data == {CODE_LEN_WIDTH{1'b0}})
                                error_flag <= 1'b1;

                            compressed_payload_bits <=
                                compressed_payload_bits + current_code_len_ext_w;
                        end

                        scan_idx <= scan_idx +
                                    {{(BLOCK_SIZE_WIDTH-1){1'b0}},1'b1};
                    end
                end

                ST_COMPARE: begin
                    // always compute for debug visibility
                    compressed_total_bits <= compressed_total_bits_w;

                    // empty block -> RAW_PARTIAL (8-bit header, 0 payload)
                    if (block_size == {BLOCK_SIZE_WIDTH{1'b0}}) begin
                        selected_mode <= MODE_RAW_PARTIAL;
                    end

                    // one-symbol block:
                    // 1) compare final transport storage cost
                    // 2) if tied, require a bit-margin before keeping compressed
                    else if (symbol_count == {{(BLOCK_SIZE_WIDTH-1){1'b0}},1'b1}) begin
                        if (one_symbol_storage_bytes_w < raw_storage_bytes_w)
                            selected_mode <= MODE_ONE_SYMBOL_COMP;
                        else if ((one_symbol_storage_bytes_w == raw_storage_bytes_w) &&
                                 one_symbol_margin_ok_w)
                            selected_mode <= MODE_ONE_SYMBOL_COMP;
                        else if (block_size == 6'd32)
                            selected_mode <= MODE_RAW_FULL;
                        else
                            selected_mode <= MODE_RAW_PARTIAL;
                    end

                    // normal case:
                    // 1) compare final transport storage cost
                    // 2) if tied, require a bit-margin before keeping compressed
                    else begin
                        if (compressed_storage_bytes_w < raw_storage_bytes_w)
                            selected_mode <= MODE_COMPRESSED;
                        else if ((compressed_storage_bytes_w == raw_storage_bytes_w) &&
                                 comp_margin_ok_w)
                            selected_mode <= MODE_COMPRESSED;
                        else if (block_size == 6'd32)
                            selected_mode <= MODE_RAW_FULL;
                        else
                            selected_mode <= MODE_RAW_PARTIAL;
                    end
                end

                ST_DONE: begin
                    if (start_pulse) begin
                        // ST_INIT next cycle overwrites registers
                    end
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule

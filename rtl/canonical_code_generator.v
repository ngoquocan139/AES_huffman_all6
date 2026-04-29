module canonical_code_generator #(
    parameter ALPHABET_SIZE         = 96,
    parameter SYMBOL_WIDTH          = 8,
    parameter SYMBOL_COUNT_WIDTH    = 6,
    parameter SYMBOL_INDEX_WIDTH    = 7,
    parameter CODE_LEN_WIDTH        = 5,
    parameter CODE_WIDTH            = 31,
    parameter MAX_SYMBOLS_PER_BLOCK = 32,
    parameter [7:0] ASCII_MIN       = 8'h20
)(
    input  wire                           clk,
    input  wire                           rst_n,
    input  wire                           start,
    input  wire [SYMBOL_COUNT_WIDTH-1:0]  symbol_count,

    // Read symbol_list from symbol_list_builder
    output reg  [SYMBOL_COUNT_WIDTH-1:0]  symbol_read_addr,
    input  wire [SYMBOL_WIDTH-1:0]        symbol_read_data,

    // Read code_len_table from code_length_builder
    output reg  [SYMBOL_INDEX_WIDTH-1:0]  code_len_src_read_index,
    input  wire [CODE_LEN_WIDTH-1:0]      code_len_src_read_data,

    output wire                           busy,
    output wire                           done,
    output reg                            error_flag,

    // Readback interface of final code_len_table
    input  wire [SYMBOL_INDEX_WIDTH-1:0]  code_len_read_index,
    output reg  [CODE_LEN_WIDTH-1:0]      code_len_read_data,

    // Readback interface of code_table
    input  wire [SYMBOL_INDEX_WIDTH-1:0]  code_read_index,
    output reg  [CODE_WIDTH-1:0]          code_read_data
);

    localparam [2:0] ST_IDLE   = 3'd0;
    localparam [2:0] ST_INIT   = 3'd1;
    localparam [2:0] ST_LOAD   = 3'd2;
    localparam [2:0] ST_SORT   = 3'd3;
    localparam [2:0] ST_ASSIGN = 3'd4;
    localparam [2:0] ST_DONE   = 3'd5;

    localparam LIST_INDEX_WIDTH = (MAX_SYMBOLS_PER_BLOCK <= 32) ? 5 : 6;
    reg [2:0] state;

    // start pulse detect
    reg  start_d;
    wire start_pulse;

    assign start_pulse = start & ~start_d;

    // local storage
    reg [SYMBOL_WIDTH-1:0]   symbol_local [0:MAX_SYMBOLS_PER_BLOCK-1];
    reg [CODE_LEN_WIDTH-1:0] len_local    [0:MAX_SYMBOLS_PER_BLOCK-1];

    reg [CODE_LEN_WIDTH-1:0] code_len_mem [0:ALPHABET_SIZE-1];
    reg [CODE_WIDTH-1:0]     code_mem     [0:ALPHABET_SIZE-1];

    reg [SYMBOL_COUNT_WIDTH-1:0] load_index;
    reg [SYMBOL_COUNT_WIDTH-1:0] sort_pass;
    reg [SYMBOL_COUNT_WIDTH-1:0] sort_idx;
    reg [SYMBOL_COUNT_WIDTH-1:0] assign_index;

    reg [CODE_WIDTH-1:0]     current_code;
    reg [CODE_LEN_WIDTH-1:0] prev_len;

    integer i;
    localparam [7:0] ASCII_MAX = 8'h7E;

`include "huffman_symbol_map.vh"

    // 5-bit views for arrays sized [0:31]
    wire [LIST_INDEX_WIDTH-1:0] load_idx5;
    wire [LIST_INDEX_WIDTH-1:0] sort_idx5;
    wire [LIST_INDEX_WIDTH-1:0] sort_idx_p1_5;
    wire [LIST_INDEX_WIDTH-1:0] assign_idx5;

    assign load_idx5     = load_index[LIST_INDEX_WIDTH-1:0];
    assign sort_idx5     = sort_idx[LIST_INDEX_WIDTH-1:0];
    assign sort_idx_p1_5 = sort_idx[LIST_INDEX_WIDTH-1:0] + 5'd1;
    assign assign_idx5   = assign_index[LIST_INDEX_WIDTH-1:0];

    function [CODE_WIDTH-1:0] next_canonical_code;
        input [CODE_WIDTH-1:0]     prev_code_f;
        input [CODE_LEN_WIDTH-1:0] prev_len_f;
        input [CODE_LEN_WIDTH-1:0] curr_len_f;
    begin
        if (curr_len_f == prev_len_f)
            next_canonical_code = prev_code_f + {{(CODE_WIDTH-1){1'b0}},1'b1};
        else
            next_canonical_code =
                (prev_code_f + {{(CODE_WIDTH-1){1'b0}},1'b1}) << (curr_len_f - prev_len_f);
    end
    endfunction

    // ------------------------------------------------------------
    // Read interfaces
    // ------------------------------------------------------------
    always @(*) begin
        if (state == ST_LOAD)
            symbol_read_addr = load_index;
        else
            symbol_read_addr = {SYMBOL_COUNT_WIDTH{1'b0}};
    end

    always @(*) begin
        if (state == ST_LOAD)
            code_len_src_read_index = huffman_symbol_to_index(symbol_read_data);
        else
            code_len_src_read_index = {SYMBOL_INDEX_WIDTH{1'b0}};
    end

    always @(*) begin
        if (code_len_read_index < ALPHABET_SIZE[SYMBOL_INDEX_WIDTH-1:0])
            code_len_read_data = code_len_mem[code_len_read_index];
        else
            code_len_read_data = {CODE_LEN_WIDTH{1'b0}};
    end

    always @(*) begin
        if (code_read_index < ALPHABET_SIZE[SYMBOL_INDEX_WIDTH-1:0])
            code_read_data = code_mem[code_read_index];
        else
            code_read_data = {CODE_WIDTH{1'b0}};
    end

    assign busy = (state == ST_INIT) ||
                  (state == ST_LOAD) ||
                  (state == ST_SORT) ||
                  (state == ST_ASSIGN);

    assign done = (state == ST_DONE);

    // ------------------------------------------------------------
    // FSM
    // ------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= ST_IDLE;
            start_d      <= 1'b0;
            error_flag   <= 1'b0;

            load_index   <= {SYMBOL_COUNT_WIDTH{1'b0}};
            sort_pass    <= {SYMBOL_COUNT_WIDTH{1'b0}};
            sort_idx     <= {SYMBOL_COUNT_WIDTH{1'b0}};
            assign_index <= {SYMBOL_COUNT_WIDTH{1'b0}};
            current_code <= {CODE_WIDTH{1'b0}};
            prev_len     <= {CODE_LEN_WIDTH{1'b0}};

            for (i = 0; i < MAX_SYMBOLS_PER_BLOCK; i = i + 1) begin
                symbol_local[i] <= {SYMBOL_WIDTH{1'b0}};
                len_local[i]    <= {CODE_LEN_WIDTH{1'b0}};
            end

            for (i = 0; i < ALPHABET_SIZE; i = i + 1) begin
                code_len_mem[i] <= {CODE_LEN_WIDTH{1'b0}};
                code_mem[i]     <= {CODE_WIDTH{1'b0}};
            end
        end
        else begin
            start_d <= start;

            case (state)
                ST_IDLE: begin
                    if (start_pulse)
                        state <= ST_INIT;
                end

                ST_INIT: begin
                    error_flag   <= 1'b0;
                    load_index   <= {SYMBOL_COUNT_WIDTH{1'b0}};
                    sort_pass    <= {SYMBOL_COUNT_WIDTH{1'b0}};
                    sort_idx     <= {SYMBOL_COUNT_WIDTH{1'b0}};
                    assign_index <= {SYMBOL_COUNT_WIDTH{1'b0}};
                    current_code <= {CODE_WIDTH{1'b0}};
                    prev_len     <= {CODE_LEN_WIDTH{1'b0}};

                    for (i = 0; i < MAX_SYMBOLS_PER_BLOCK; i = i + 1) begin
                        symbol_local[i] <= {SYMBOL_WIDTH{1'b0}};
                        len_local[i]    <= {CODE_LEN_WIDTH{1'b0}};
                    end

                    for (i = 0; i < ALPHABET_SIZE; i = i + 1) begin
                        code_len_mem[i] <= {CODE_LEN_WIDTH{1'b0}};
                        code_mem[i]     <= {CODE_WIDTH{1'b0}};
                    end

                    if (symbol_count == {SYMBOL_COUNT_WIDTH{1'b0}}) begin
                        state <= ST_DONE;
                    end
                    else begin
                        state <= ST_LOAD;
                    end
                end

                ST_LOAD: begin
                    if (load_index < symbol_count) begin
                        symbol_local[load_idx5] <= symbol_read_data;
                        len_local[load_idx5]    <= code_len_src_read_data;

                        if (code_len_src_read_data == {CODE_LEN_WIDTH{1'b0}})
                            error_flag <= 1'b1;

                        load_index <= load_index +
                                      {{(SYMBOL_COUNT_WIDTH-1){1'b0}},1'b1};

                        if (load_index == symbol_count - {{(SYMBOL_COUNT_WIDTH-1){1'b0}},1'b1}) begin
                            if (symbol_count == {{(SYMBOL_COUNT_WIDTH-1){1'b0}},1'b1}) begin
                                assign_index <= {SYMBOL_COUNT_WIDTH{1'b0}};
                                current_code <= {CODE_WIDTH{1'b0}};
                                prev_len     <= {CODE_LEN_WIDTH{1'b0}};
                                state        <= ST_ASSIGN;
                            end
                            else begin
                                sort_pass <= {SYMBOL_COUNT_WIDTH{1'b0}};
                                sort_idx  <= {SYMBOL_COUNT_WIDTH{1'b0}};
                                state     <= ST_SORT;
                            end
                        end
                    end
                end

                ST_SORT: begin
                    if (sort_pass < (symbol_count - {{(SYMBOL_COUNT_WIDTH-1){1'b0}},1'b1})) begin
                        if (sort_idx < (symbol_count - {{(SYMBOL_COUNT_WIDTH-1){1'b0}},1'b1} - sort_pass)) begin
                            if ((len_local[sort_idx5] > len_local[sort_idx_p1_5]) ||
                                ((len_local[sort_idx5] == len_local[sort_idx_p1_5]) &&
                                 (symbol_local[sort_idx5] > symbol_local[sort_idx_p1_5]))) begin

                                {symbol_local[sort_idx5], symbol_local[sort_idx_p1_5]} <=
                                {symbol_local[sort_idx_p1_5], symbol_local[sort_idx5]};

                                {len_local[sort_idx5], len_local[sort_idx_p1_5]} <=
                                {len_local[sort_idx_p1_5], len_local[sort_idx5]};
                            end

                            sort_idx <= sort_idx +
                                        {{(SYMBOL_COUNT_WIDTH-1){1'b0}},1'b1};
                        end
                        else begin
                            sort_idx  <= {SYMBOL_COUNT_WIDTH{1'b0}};
                            sort_pass <= sort_pass +
                                         {{(SYMBOL_COUNT_WIDTH-1){1'b0}},1'b1};
                        end
                    end
                    else begin
                        assign_index <= {SYMBOL_COUNT_WIDTH{1'b0}};
                        current_code <= {CODE_WIDTH{1'b0}};
                        prev_len     <= {CODE_LEN_WIDTH{1'b0}};
                        state        <= ST_ASSIGN;
                    end
                end

                ST_ASSIGN: begin
                    if (assign_index < symbol_count) begin
                        if (assign_index == {SYMBOL_COUNT_WIDTH{1'b0}}) begin
                            if (len_local[0] == {CODE_LEN_WIDTH{1'b0}})
                                error_flag <= 1'b1;

                            if ((symbol_count == {{(SYMBOL_COUNT_WIDTH-1){1'b0}},1'b1}) &&
                                (len_local[0] != {{(CODE_LEN_WIDTH-1){1'b0}},1'b1}))
                                error_flag <= 1'b1;

                            code_mem[
                                huffman_symbol_to_index(symbol_local[0])
                            ] <= {CODE_WIDTH{1'b0}};

                            code_len_mem[
                                huffman_symbol_to_index(symbol_local[0])
                            ] <= len_local[0];

                            current_code <= {CODE_WIDTH{1'b0}};
                            prev_len     <= len_local[0];
                            assign_index <= assign_index +
                                            {{(SYMBOL_COUNT_WIDTH-1){1'b0}},1'b1};

                            if (symbol_count == {{(SYMBOL_COUNT_WIDTH-1){1'b0}},1'b1})
                                state <= ST_DONE;
                        end
                        else begin
                            if (len_local[assign_idx5] == {CODE_LEN_WIDTH{1'b0}})
                                error_flag <= 1'b1;

                            if (len_local[assign_idx5] < prev_len)
                                error_flag <= 1'b1;

                            current_code <= next_canonical_code(
                                                current_code,
                                                prev_len,
                                                len_local[assign_idx5]
                                            );

                            code_mem[
                                huffman_symbol_to_index(symbol_local[assign_idx5])
                            ] <= next_canonical_code(
                                    current_code,
                                    prev_len,
                                    len_local[assign_idx5]
                                  );

                            code_len_mem[
                                huffman_symbol_to_index(symbol_local[assign_idx5])
                            ] <= len_local[assign_idx5];

                            prev_len <= len_local[assign_idx5];
                            assign_index <= assign_index +
                                            {{(SYMBOL_COUNT_WIDTH-1){1'b0}},1'b1};

                            if (assign_index == symbol_count - {{(SYMBOL_COUNT_WIDTH-1){1'b0}},1'b1})
                                state <= ST_DONE;
                        end
                    end
                    else begin
                        state <= ST_DONE;
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

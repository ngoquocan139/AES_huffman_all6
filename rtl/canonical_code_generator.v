module canonical_code_generator #(
    parameter ALPHABET_SIZE         = 256,
    parameter SYMBOL_WIDTH          = 8,
    parameter SYMBOL_COUNT_WIDTH    = 9,
    parameter SYMBOL_INDEX_WIDTH    = 8,
    parameter CODE_LEN_WIDTH        = 5,
    parameter CODE_WIDTH            = 13,
    parameter MAX_SYMBOLS_PER_BLOCK = 32,
    parameter [7:0] ASCII_MIN       = 8'h20
)(
    input  wire                           clk,
    input  wire                           rst_n,
    input  wire                           start,
    input  wire [SYMBOL_COUNT_WIDTH-1:0]  symbol_count,

    // Kept for the huffman_builder interface. The current implementation
    // generates canonical codes by scanning the full code-length table.
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

    localparam [31:0] ALPHABET_LAST_I = ALPHABET_SIZE - 1;
    localparam [SYMBOL_INDEX_WIDTH-1:0] ALPHABET_LAST =
        ALPHABET_LAST_I[SYMBOL_INDEX_WIDTH-1:0];
    localparam [CODE_LEN_WIDTH-1:0] CODE_WIDTH_LIMIT =
        CODE_WIDTH[CODE_LEN_WIDTH-1:0];

    reg [2:0] state;

    reg  start_d;
    wire start_pulse;

    assign start_pulse = start & ~start_d;

    // load_index scans the source length table and also clears stale entries.
    // assign_index scans symbols for each canonical length.
    reg [SYMBOL_COUNT_WIDTH-1:0] load_index;
    reg [SYMBOL_COUNT_WIDTH-1:0] sort_pass;    // non-zero length count
    reg [SYMBOL_COUNT_WIDTH-1:0] sort_idx;     // assigned code count
    reg [SYMBOL_COUNT_WIDTH-1:0] assign_index;

    reg [CODE_WIDTH-1:0]     current_code;
    reg [CODE_LEN_WIDTH-1:0] prev_len;         // current canonical length

    (* ram_style = "distributed" *) reg [CODE_LEN_WIDTH-1:0] code_len_mem [0:ALPHABET_SIZE-1];
    (* ram_style = "distributed" *) reg [CODE_WIDTH-1:0]     code_mem     [0:ALPHABET_SIZE-1];

    reg                          code_len_we;
    reg [SYMBOL_INDEX_WIDTH-1:0] code_len_wr_addr;
    reg [CODE_LEN_WIDTH-1:0]     code_len_wr_data;
    reg                          code_we;
    reg [SYMBOL_INDEX_WIDTH-1:0] code_wr_addr;
    reg [CODE_WIDTH-1:0]         code_wr_data;

    wire [SYMBOL_INDEX_WIDTH-1:0] load_symbol_index_w;
    wire [SYMBOL_INDEX_WIDTH-1:0] assign_symbol_index_w;
    wire [CODE_LEN_WIDTH-1:0]     assign_code_len_w;
    wire                          load_is_last_w;
    wire                          assign_is_last_w;
    wire                          assign_match_w;
    wire [SYMBOL_COUNT_WIDTH-1:0] sort_idx_next_w;
    wire                          unused_iface_w;

    assign load_symbol_index_w   = load_index[SYMBOL_INDEX_WIDTH-1:0];
    assign assign_symbol_index_w = assign_index[SYMBOL_INDEX_WIDTH-1:0];
    assign assign_code_len_w     = code_len_mem[assign_symbol_index_w];
    assign load_is_last_w        = (load_symbol_index_w == ALPHABET_LAST);
    assign assign_is_last_w      = (assign_symbol_index_w == ALPHABET_LAST);
    assign assign_match_w        = (assign_code_len_w == prev_len);
    assign sort_idx_next_w       = sort_idx + {{(SYMBOL_COUNT_WIDTH-1){1'b0}}, assign_match_w};
    assign unused_iface_w        = ^{ASCII_MIN, symbol_read_data};

`ifndef SYNTHESIS
    // Simulation-only compatibility with older coverage tests that force these
    // hierarchical names. They are not used by the synthesized implementation.
/* verilator lint_off UNUSEDSIGNAL */
    reg [SYMBOL_WIDTH-1:0]   symbol_local [0:MAX_SYMBOLS_PER_BLOCK-1];
    reg [CODE_LEN_WIDTH-1:0] len_local    [0:MAX_SYMBOLS_PER_BLOCK-1];
/* verilator lint_on UNUSEDSIGNAL */
    integer i;
`endif

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

    always @(*) begin
        if (state == ST_IDLE)
            symbol_read_addr = {SYMBOL_COUNT_WIDTH{unused_iface_w & 1'b0}};
        else
            symbol_read_addr = {SYMBOL_COUNT_WIDTH{1'b0}};
    end

    always @(*) begin
        if (state == ST_LOAD)
            code_len_src_read_index = load_symbol_index_w;
        else
            code_len_src_read_index = {SYMBOL_INDEX_WIDTH{1'b0}};
    end

    always @(*) begin
        code_len_read_data = code_len_mem[code_len_read_index];
    end

    always @(*) begin
        code_read_data = code_mem[code_read_index];
    end

    always @(*) begin
        code_len_we      = 1'b0;
        code_len_wr_addr = {SYMBOL_INDEX_WIDTH{1'b0}};
        code_len_wr_data = {CODE_LEN_WIDTH{1'b0}};
        code_we          = 1'b0;
        code_wr_addr     = {SYMBOL_INDEX_WIDTH{1'b0}};
        code_wr_data     = {CODE_WIDTH{1'b0}};

        if (state == ST_LOAD) begin
            code_len_we      = 1'b1;
            code_len_wr_addr = load_symbol_index_w;
            code_len_wr_data = (code_len_src_read_data <= CODE_WIDTH_LIMIT) ?
                               code_len_src_read_data : {CODE_LEN_WIDTH{1'b0}};

            // Clear stale code values from a previous file without using a
            // reset on the RAM array.
            code_we      = 1'b1;
            code_wr_addr = load_symbol_index_w;
            code_wr_data = {CODE_WIDTH{1'b0}};
        end
        else if ((state == ST_ASSIGN) && assign_match_w) begin
            code_we      = 1'b1;
            code_wr_addr = assign_symbol_index_w;
            code_wr_data = current_code;
        end
    end

    always @(posedge clk) begin
        if (code_len_we)
            code_len_mem[code_len_wr_addr] <= code_len_wr_data;
        if (code_we)
            code_mem[code_wr_addr] <= code_wr_data;
    end

    assign busy = (state == ST_INIT) ||
                  (state == ST_LOAD) ||
                  (state == ST_SORT) ||
                  (state == ST_ASSIGN);

    assign done = (state == ST_DONE);

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

`ifndef SYNTHESIS
            for (i = 0; i < MAX_SYMBOLS_PER_BLOCK; i = i + 1) begin
                symbol_local[i] <= {SYMBOL_WIDTH{1'b0}};
                len_local[i]    <= {CODE_LEN_WIDTH{1'b0}};
            end
`endif
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
                    prev_len     <= {{(CODE_LEN_WIDTH-1){1'b0}}, 1'b1};
                    state        <= ST_LOAD;
                end

                ST_LOAD: begin
                    if (code_len_src_read_data > CODE_WIDTH_LIMIT)
                        error_flag <= 1'b1;
                    else if (code_len_src_read_data != {CODE_LEN_WIDTH{1'b0}})
                        sort_pass <= sort_pass +
                                     {{(SYMBOL_COUNT_WIDTH-1){1'b0}}, 1'b1};

                    if (load_is_last_w) begin
                        assign_index <= {SYMBOL_COUNT_WIDTH{1'b0}};
                        current_code <= {CODE_WIDTH{1'b0}};
                        prev_len     <= {{(CODE_LEN_WIDTH-1){1'b0}}, 1'b1};
                        state        <= ST_ASSIGN;
                    end
                    else begin
                        load_index <= load_index +
                                      {{(SYMBOL_COUNT_WIDTH-1){1'b0}}, 1'b1};
                    end
                end

                // ST_SORT is intentionally retained for coverage compatibility;
                // canonical ordering is now produced by length/symbol scans.
                ST_SORT: begin
                    state <= ST_ASSIGN;
                end

                ST_ASSIGN: begin
                    if (assign_match_w) begin
                        current_code <= current_code +
                                        {{(CODE_WIDTH-1){1'b0}}, 1'b1};
                        sort_idx <= sort_idx_next_w;
                    end

                    if (assign_is_last_w) begin
                        if (prev_len == CODE_WIDTH_LIMIT) begin
                            if ((sort_idx_next_w != sort_pass) ||
                                (sort_pass != symbol_count))
                                error_flag <= 1'b1;
                            state <= ST_DONE;
                        end
                        else begin
                            assign_index <= {SYMBOL_COUNT_WIDTH{1'b0}};
                            current_code <= (assign_match_w ?
                                             (current_code + {{(CODE_WIDTH-1){1'b0}}, 1'b1}) :
                                             current_code) << 1;
                            prev_len <= prev_len +
                                        {{(CODE_LEN_WIDTH-1){1'b0}}, 1'b1};
                        end
                    end
                    else begin
                        assign_index <= assign_index +
                                        {{(SYMBOL_COUNT_WIDTH-1){1'b0}}, 1'b1};
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

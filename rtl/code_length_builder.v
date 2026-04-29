module code_length_builder #(
    parameter ALPHABET_SIZE         = 96,
    parameter SYMBOL_WIDTH          = 8,
    parameter SYMBOL_COUNT_WIDTH    = 6,
    parameter COUNT_WIDTH           = 6,
    parameter SYMBOL_INDEX_WIDTH    = 7,
    parameter CODE_LEN_WIDTH        = 5,
    parameter MAX_SYMBOLS_PER_BLOCK = 32,
    parameter MAX_TREE_NODES        = 63,
    parameter [7:0] ASCII_MIN       = 8'h20
)(
    input  wire                           clk,
    input  wire                           rst_n,
    input  wire                           start,
    input  wire [SYMBOL_COUNT_WIDTH-1:0]  symbol_count,

    output reg  [SYMBOL_COUNT_WIDTH-1:0]  symbol_read_addr,
    input  wire [SYMBOL_WIDTH-1:0]        symbol_read_data,

    output reg  [SYMBOL_INDEX_WIDTH-1:0]  freq_read_index,
    input  wire [COUNT_WIDTH-1:0]         freq_read_count,

    output wire                           busy,
    output wire                           done,
    output reg                            error_flag,

    input  wire [SYMBOL_INDEX_WIDTH-1:0]  code_len_read_index,
    output reg  [CODE_LEN_WIDTH-1:0]      code_len_read_data
);

    localparam [3:0] ST_IDLE        = 4'd0;
    localparam [3:0] ST_INIT        = 4'd1;
    localparam [3:0] ST_LOAD_SYMBOL = 4'd2;
    localparam [3:0] ST_LOAD_COUNT  = 4'd3;
    localparam [3:0] ST_LOAD_NODE   = 4'd4;
    localparam [3:0] ST_FIND_INIT   = 4'd5;
    localparam [3:0] ST_FIND_SCAN   = 4'd6;
    localparam [3:0] ST_BUILD_MERGE = 4'd7;
    localparam [3:0] ST_MAP_TABLE   = 4'd8;
    localparam [3:0] ST_DONE        = 4'd9;

    localparam LIST_INDEX_WIDTH = (MAX_SYMBOLS_PER_BLOCK <= 32) ? 5 : 6;
    localparam NODE_INDEX_WIDTH = (MAX_TREE_NODES <= 63) ? 6 : 7;

    reg [3:0] state, next_state;

    reg  start_d;
    wire start_pulse;

    assign start_pulse = start & ~start_d;

    reg [SYMBOL_WIDTH-1:0]   leaf_symbol   [0:MAX_SYMBOLS_PER_BLOCK-1];
    reg [CODE_LEN_WIDTH-1:0] leaf_code_len [0:MAX_SYMBOLS_PER_BLOCK-1];

    reg [COUNT_WIDTH-1:0]                node_weight [0:MAX_TREE_NODES-1];
    reg [MAX_SYMBOLS_PER_BLOCK-1:0]      node_mask   [0:MAX_TREE_NODES-1];
    reg                                  node_active [0:MAX_TREE_NODES-1];
    reg                                  node_is_leaf[0:MAX_TREE_NODES-1];
    reg [SYMBOL_WIDTH-1:0]               node_symbol [0:MAX_TREE_NODES-1];
    reg [NODE_INDEX_WIDTH-1:0]           node_order  [0:MAX_TREE_NODES-1];

    reg [CODE_LEN_WIDTH-1:0] code_len_mem [0:ALPHABET_SIZE-1];

    reg [SYMBOL_COUNT_WIDTH-1:0] load_index;
    reg [SYMBOL_COUNT_WIDTH-1:0] map_index;
    reg [SYMBOL_COUNT_WIDTH-1:0] active_nodes;
    reg [NODE_INDEX_WIDTH-1:0]   next_free_index;
    reg [NODE_INDEX_WIDTH-1:0]   order_counter;
    reg [NODE_INDEX_WIDTH-1:0]   scan_node_idx;
    reg [NODE_INDEX_WIDTH-1:0]   min1_idx_r;
    reg [NODE_INDEX_WIDTH-1:0]   min2_idx_r;
    reg                          found1_r;
    reg                          found2_r;
    reg [SYMBOL_WIDTH-1:0]       load_symbol_r;
    reg [COUNT_WIDTH-1:0]        load_freq_count_r;
    wire [NODE_INDEX_WIDTH-1:0]  load_node_idx_w;

    integer i;
    localparam [7:0] ASCII_MAX = 8'h7E;

`include "huffman_symbol_map.vh"

    function [NODE_INDEX_WIDTH-1:0] widen_symbol_index;
        input [SYMBOL_COUNT_WIDTH-1:0] idx;
    begin
        widen_symbol_index = {NODE_INDEX_WIDTH{1'b0}};
        widen_symbol_index[SYMBOL_COUNT_WIDTH-1:0] = idx;
    end
    endfunction

    assign load_node_idx_w = widen_symbol_index(load_index);

    function better_node;
        input [COUNT_WIDTH-1:0] aw;
        input                   al;
        input [SYMBOL_WIDTH-1:0] as;
        input [NODE_INDEX_WIDTH-1:0]   ao;
        input [COUNT_WIDTH-1:0] bw;
        input                   bl;
        input [SYMBOL_WIDTH-1:0] bs;
        input [NODE_INDEX_WIDTH-1:0]   bo;
    begin
        if (aw < bw)
            better_node = 1'b1;
        else if (aw > bw)
            better_node = 1'b0;
        else if (al && !bl)
            better_node = 1'b1;
        else if (!al && bl)
            better_node = 1'b0;
        else if (al && bl)
            better_node = (as < bs);
        else
            better_node = (ao < bo);
    end
    endfunction

    always @(*) begin
        if (state == ST_LOAD_SYMBOL)
            symbol_read_addr = load_index;
        else
            symbol_read_addr = {SYMBOL_COUNT_WIDTH{1'b0}};
    end

    always @(*) begin
        if (state == ST_LOAD_COUNT)
            freq_read_index = huffman_symbol_to_index(load_symbol_r);
        else
            freq_read_index = {SYMBOL_INDEX_WIDTH{1'b0}};
    end

    always @(*) begin
        if (code_len_read_index < ALPHABET_SIZE[SYMBOL_INDEX_WIDTH-1:0])
            code_len_read_data = code_len_mem[code_len_read_index];
        else
            code_len_read_data = {CODE_LEN_WIDTH{1'b0}};
    end

    assign busy = (state == ST_INIT) ||
                  (state == ST_LOAD_SYMBOL) ||
                  (state == ST_LOAD_COUNT) ||
                  (state == ST_LOAD_NODE) ||
                  (state == ST_FIND_INIT) ||
                  (state == ST_FIND_SCAN) ||
                  (state == ST_BUILD_MERGE) ||
                  (state == ST_MAP_TABLE);

    assign done = (state == ST_DONE);

    always @(*) begin
        next_state = state;

        case (state)
            ST_IDLE: begin
                if (start_pulse)
                    next_state = ST_INIT;
            end

            ST_INIT: begin
                next_state = ST_LOAD_SYMBOL;
            end

            ST_LOAD_SYMBOL: begin
                if (load_index == symbol_count) begin
                    if (symbol_count == {SYMBOL_COUNT_WIDTH{1'b0}})
                        next_state = ST_DONE;
                    else if (symbol_count == {{(SYMBOL_COUNT_WIDTH-1){1'b0}},1'b1})
                        next_state = ST_MAP_TABLE;
                    else
                        next_state = ST_FIND_INIT;
                end
                else begin
                    next_state = ST_LOAD_COUNT;
                end
            end

            ST_LOAD_COUNT: begin
                next_state = ST_LOAD_NODE;
            end

            ST_LOAD_NODE: begin
                next_state = ST_LOAD_SYMBOL;
            end

            ST_FIND_INIT: begin
                if (active_nodes <= {{(SYMBOL_COUNT_WIDTH-1){1'b0}},1'b1})
                    next_state = ST_MAP_TABLE;
                else
                    next_state = ST_FIND_SCAN;
            end

            ST_FIND_SCAN: begin
                if (scan_node_idx == (MAX_TREE_NODES-1))
                    next_state = ST_BUILD_MERGE;
            end

            ST_BUILD_MERGE: begin
                if (!found1_r || !found2_r)
                    next_state = ST_DONE;
                else if (active_nodes <= {{(SYMBOL_COUNT_WIDTH-2){1'b0}},2'd2})
                    next_state = ST_MAP_TABLE;
                else
                    next_state = ST_FIND_INIT;
            end

            ST_MAP_TABLE: begin
                if (map_index == symbol_count)
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

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= ST_IDLE;
            start_d         <= 1'b0;
            error_flag      <= 1'b0;
            load_index      <= {SYMBOL_COUNT_WIDTH{1'b0}};
            map_index       <= {SYMBOL_COUNT_WIDTH{1'b0}};
            active_nodes    <= {SYMBOL_COUNT_WIDTH{1'b0}};
            next_free_index <= {NODE_INDEX_WIDTH{1'b0}};
            order_counter   <= {NODE_INDEX_WIDTH{1'b0}};
            scan_node_idx   <= {NODE_INDEX_WIDTH{1'b0}};
            min1_idx_r      <= {NODE_INDEX_WIDTH{1'b0}};
            min2_idx_r      <= {NODE_INDEX_WIDTH{1'b0}};
            found1_r        <= 1'b0;
            found2_r        <= 1'b0;
            load_symbol_r   <= {SYMBOL_WIDTH{1'b0}};
            load_freq_count_r <= {COUNT_WIDTH{1'b0}};

            for (i = 0; i < MAX_SYMBOLS_PER_BLOCK; i = i + 1) begin
                leaf_symbol[i]   <= {SYMBOL_WIDTH{1'b0}};
                leaf_code_len[i] <= {CODE_LEN_WIDTH{1'b0}};
            end

            for (i = 0; i < MAX_TREE_NODES; i = i + 1) begin
                node_weight[i]  <= {COUNT_WIDTH{1'b0}};
                node_mask[i]    <= {MAX_SYMBOLS_PER_BLOCK{1'b0}};
                node_active[i]  <= 1'b0;
                node_is_leaf[i] <= 1'b0;
                node_symbol[i]  <= {SYMBOL_WIDTH{1'b0}};
                node_order[i]   <= {NODE_INDEX_WIDTH{1'b0}};
            end

            for (i = 0; i < ALPHABET_SIZE; i = i + 1)
                code_len_mem[i] <= {CODE_LEN_WIDTH{1'b0}};
        end
        else begin
            state   <= next_state;
            start_d <= start;

            case (state)
                ST_IDLE: begin
                end

                ST_INIT: begin
                    error_flag      <= 1'b0;
                    load_index      <= {SYMBOL_COUNT_WIDTH{1'b0}};
                    map_index       <= {SYMBOL_COUNT_WIDTH{1'b0}};
                    active_nodes    <= {SYMBOL_COUNT_WIDTH{1'b0}};
                    next_free_index <= widen_symbol_index(symbol_count);
                    order_counter   <= widen_symbol_index(symbol_count);
                    scan_node_idx   <= {NODE_INDEX_WIDTH{1'b0}};
                    min1_idx_r      <= {NODE_INDEX_WIDTH{1'b0}};
                    min2_idx_r      <= {NODE_INDEX_WIDTH{1'b0}};
                    found1_r        <= 1'b0;
                    found2_r        <= 1'b0;
                    load_symbol_r   <= {SYMBOL_WIDTH{1'b0}};
                    load_freq_count_r <= {COUNT_WIDTH{1'b0}};

                    for (i = 0; i < MAX_SYMBOLS_PER_BLOCK; i = i + 1) begin
                        leaf_symbol[i]   <= {SYMBOL_WIDTH{1'b0}};
                        leaf_code_len[i] <= {CODE_LEN_WIDTH{1'b0}};
                    end

                    for (i = 0; i < MAX_TREE_NODES; i = i + 1) begin
                        node_weight[i]  <= {COUNT_WIDTH{1'b0}};
                        node_mask[i]    <= {MAX_SYMBOLS_PER_BLOCK{1'b0}};
                        node_active[i]  <= 1'b0;
                        node_is_leaf[i] <= 1'b0;
                        node_symbol[i]  <= {SYMBOL_WIDTH{1'b0}};
                        node_order[i]   <= {NODE_INDEX_WIDTH{1'b0}};
                    end

                    for (i = 0; i < ALPHABET_SIZE; i = i + 1)
                        code_len_mem[i] <= {CODE_LEN_WIDTH{1'b0}};

                end

                ST_LOAD_SYMBOL: begin
                    if (load_index < symbol_count)
                        load_symbol_r <= symbol_read_data;
                end

                ST_LOAD_COUNT: begin
                    load_freq_count_r <= freq_read_count;
                end

                ST_LOAD_NODE: begin
                    if (load_index < symbol_count) begin
                        leaf_symbol[load_index[LIST_INDEX_WIDTH-1:0]] <= load_symbol_r;

                        if (symbol_count == {{(SYMBOL_COUNT_WIDTH-1){1'b0}},1'b1})
                            leaf_code_len[load_index[LIST_INDEX_WIDTH-1:0]] <= {{(CODE_LEN_WIDTH-1){1'b0}},1'b1};
                        else
                            leaf_code_len[load_index[LIST_INDEX_WIDTH-1:0]] <= {CODE_LEN_WIDTH{1'b0}};

                        if (load_freq_count_r == {COUNT_WIDTH{1'b0}}) begin
                            error_flag <= 1'b1;
                        end
                        else begin
                            node_weight[load_node_idx_w]  <= load_freq_count_r;
                            node_mask[load_node_idx_w]    <= ({MAX_SYMBOLS_PER_BLOCK{1'b0}} |
                                                         ({{(MAX_SYMBOLS_PER_BLOCK-1){1'b0}},1'b1} << load_index));
                            node_active[load_node_idx_w]  <= 1'b1;
                            node_is_leaf[load_node_idx_w] <= 1'b1;
                            node_symbol[load_node_idx_w]  <= load_symbol_r;
                            node_order[load_node_idx_w]   <= load_node_idx_w;
                            active_nodes             <= active_nodes +
                                                        {{(SYMBOL_COUNT_WIDTH-1){1'b0}},1'b1};
                        end

                        load_index <= load_index +
                                      {{(SYMBOL_COUNT_WIDTH-1){1'b0}},1'b1};
                    end
                end

                ST_FIND_INIT: begin
                    scan_node_idx <= {NODE_INDEX_WIDTH{1'b0}};
                    min1_idx_r    <= {NODE_INDEX_WIDTH{1'b0}};
                    min2_idx_r    <= {NODE_INDEX_WIDTH{1'b0}};
                    found1_r      <= 1'b0;
                    found2_r      <= 1'b0;
                end

                ST_FIND_SCAN: begin
                    if (node_active[scan_node_idx]) begin
                        if (!found1_r) begin
                            found1_r   <= 1'b1;
                            min1_idx_r <= scan_node_idx;
                        end
                        else if (better_node(
                                    node_weight[scan_node_idx],
                                    node_is_leaf[scan_node_idx],
                                    node_symbol[scan_node_idx],
                                    node_order[scan_node_idx],
                                    node_weight[min1_idx_r],
                                    node_is_leaf[min1_idx_r],
                                    node_symbol[min1_idx_r],
                                    node_order[min1_idx_r]
                                 )) begin
                            found2_r   <= found1_r;
                            min2_idx_r <= min1_idx_r;
                            found1_r   <= 1'b1;
                            min1_idx_r <= scan_node_idx;
                        end
                        else if (!found2_r) begin
                            found2_r   <= 1'b1;
                            min2_idx_r <= scan_node_idx;
                        end
                        else if (better_node(
                                    node_weight[scan_node_idx],
                                    node_is_leaf[scan_node_idx],
                                    node_symbol[scan_node_idx],
                                    node_order[scan_node_idx],
                                    node_weight[min2_idx_r],
                                    node_is_leaf[min2_idx_r],
                                    node_symbol[min2_idx_r],
                                    node_order[min2_idx_r]
                                 )) begin
                            min2_idx_r <= scan_node_idx;
                        end
                    end

                    if (scan_node_idx != (MAX_TREE_NODES-1))
                        scan_node_idx <= scan_node_idx +
                                         {{(NODE_INDEX_WIDTH-1){1'b0}},1'b1};
                end

                ST_BUILD_MERGE: begin
                    if (active_nodes > {{(SYMBOL_COUNT_WIDTH-1){1'b0}},1'b1}) begin
                        if (!found1_r || !found2_r) begin
                            error_flag <= 1'b1;
                        end
                        else begin
                            for (i = 0; i < MAX_SYMBOLS_PER_BLOCK; i = i + 1) begin
                                if (node_mask[min1_idx_r][i] || node_mask[min2_idx_r][i])
                                    leaf_code_len[i] <= leaf_code_len[i] +
                                                        {{(CODE_LEN_WIDTH-1){1'b0}},1'b1};
                            end

                            node_active[min1_idx_r] <= 1'b0;
                            node_active[min2_idx_r] <= 1'b0;

                            node_weight[next_free_index]  <= node_weight[min1_idx_r] + node_weight[min2_idx_r];
                            node_mask[next_free_index]    <= node_mask[min1_idx_r] | node_mask[min2_idx_r];
                            node_active[next_free_index]  <= 1'b1;
                            node_is_leaf[next_free_index] <= 1'b0;
                            node_symbol[next_free_index]  <= {SYMBOL_WIDTH{1'b0}};
                            node_order[next_free_index]   <= order_counter;

                            next_free_index <= next_free_index +
                                               {{(NODE_INDEX_WIDTH-1){1'b0}},1'b1};
                            order_counter   <= order_counter +
                                               {{(NODE_INDEX_WIDTH-1){1'b0}},1'b1};

                            active_nodes <= active_nodes -
                                            {{(SYMBOL_COUNT_WIDTH-1){1'b0}},1'b1};
                        end
                    end
                end

                ST_MAP_TABLE: begin
                    if (map_index < symbol_count) begin
                        if (leaf_code_len[map_index[LIST_INDEX_WIDTH-1:0]] == {CODE_LEN_WIDTH{1'b0}})
                            error_flag <= 1'b1;

                        code_len_mem[
                            huffman_symbol_to_index(
                                leaf_symbol[map_index[LIST_INDEX_WIDTH-1:0]]
                            )
                        ] <= leaf_code_len[map_index[LIST_INDEX_WIDTH-1:0]];

                        map_index <= map_index +
                                     {{(SYMBOL_COUNT_WIDTH-1){1'b0}},1'b1};
                    end
                end

                ST_DONE: begin
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule

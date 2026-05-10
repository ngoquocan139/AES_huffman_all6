module code_length_builder #(
    parameter ALPHABET_SIZE         = 256,
    parameter SYMBOL_WIDTH          = 8,
    parameter SYMBOL_COUNT_WIDTH    = 9,
    parameter COUNT_WIDTH           = 6,
    parameter SYMBOL_INDEX_WIDTH    = 8,
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
    localparam [3:0] ST_DEPTH_INIT  = 4'd8;
    localparam [3:0] ST_DEPTH_WALK  = 4'd9;
    localparam [3:0] ST_MAP_TABLE   = 4'd10;
    localparam [3:0] ST_DONE        = 4'd11;
    localparam [3:0] ST_CLEAR_LEN   = 4'd12;

    localparam LIST_INDEX_WIDTH =
        (MAX_SYMBOLS_PER_BLOCK <= 2)   ? 1 :
        (MAX_SYMBOLS_PER_BLOCK <= 4)   ? 2 :
        (MAX_SYMBOLS_PER_BLOCK <= 8)   ? 3 :
        (MAX_SYMBOLS_PER_BLOCK <= 16)  ? 4 :
        (MAX_SYMBOLS_PER_BLOCK <= 32)  ? 5 :
        (MAX_SYMBOLS_PER_BLOCK <= 64)  ? 6 :
        (MAX_SYMBOLS_PER_BLOCK <= 128) ? 7 : 8;

    localparam NODE_INDEX_WIDTH =
        (MAX_TREE_NODES <= 2)   ? 1 :
        (MAX_TREE_NODES <= 4)   ? 2 :
        (MAX_TREE_NODES <= 8)   ? 3 :
        (MAX_TREE_NODES <= 16)  ? 4 :
        (MAX_TREE_NODES <= 32)  ? 5 :
        (MAX_TREE_NODES <= 64)  ? 6 :
        (MAX_TREE_NODES <= 128) ? 7 :
        (MAX_TREE_NODES <= 256) ? 8 : 9;

    reg [3:0] state, next_state;

    reg  start_d;
    wire start_pulse;

    assign start_pulse = start & ~start_d;

    reg [SYMBOL_WIDTH-1:0]         leaf_symbol     [0:MAX_SYMBOLS_PER_BLOCK-1];
    reg [NODE_INDEX_WIDTH-1:0]     leaf_node_index [0:MAX_SYMBOLS_PER_BLOCK-1];
`ifndef SYNTHESIS
    // Simulation-only compatibility signals for targeted coverage tasks.
    reg [CODE_LEN_WIDTH-1:0]       leaf_code_len   [0:MAX_SYMBOLS_PER_BLOCK-1];
    reg [MAX_SYMBOLS_PER_BLOCK-1:0] node_mask      [0:MAX_TREE_NODES-1];
`endif

    reg [COUNT_WIDTH-1:0]          node_weight  [0:MAX_TREE_NODES-1];
    reg                            node_active  [0:MAX_TREE_NODES-1];
    reg                            node_is_leaf [0:MAX_TREE_NODES-1];
    reg [SYMBOL_WIDTH-1:0]         node_symbol  [0:MAX_TREE_NODES-1];
    reg [NODE_INDEX_WIDTH-1:0]     node_order   [0:MAX_TREE_NODES-1];
    reg [NODE_INDEX_WIDTH-1:0]     node_parent  [0:MAX_TREE_NODES-1];

    (* ram_style = "distributed" *) reg [CODE_LEN_WIDTH-1:0] code_len_mem [0:ALPHABET_SIZE-1];

    reg [SYMBOL_COUNT_WIDTH-1:0]   load_index;
    reg [SYMBOL_COUNT_WIDTH-1:0]   map_index;
    reg [SYMBOL_INDEX_WIDTH-1:0]   clear_index;
    reg [SYMBOL_COUNT_WIDTH-1:0]   active_nodes;
    reg [NODE_INDEX_WIDTH-1:0]     next_free_index;
    reg [NODE_INDEX_WIDTH-1:0]     order_counter;
    reg [NODE_INDEX_WIDTH-1:0]     scan_node_idx;
    reg [NODE_INDEX_WIDTH-1:0]     min1_idx_r;
    reg [NODE_INDEX_WIDTH-1:0]     min2_idx_r;
    reg                            found1_r;
    reg                            found2_r;
    reg [COUNT_WIDTH-1:0]          min1_weight_r;
    reg [COUNT_WIDTH-1:0]          min2_weight_r;
    reg                            min1_is_leaf_r;
    reg                            min2_is_leaf_r;
    reg [SYMBOL_WIDTH-1:0]         min1_symbol_r;
    reg [SYMBOL_WIDTH-1:0]         min2_symbol_r;
    reg [NODE_INDEX_WIDTH-1:0]     min1_order_r;
    reg [NODE_INDEX_WIDTH-1:0]     min2_order_r;
    reg [SYMBOL_WIDTH-1:0]         load_symbol_r;
    reg [COUNT_WIDTH-1:0]          load_freq_count_r;
    reg [NODE_INDEX_WIDTH-1:0]     depth_node_idx_r;
    reg [CODE_LEN_WIDTH-1:0]       depth_len_r;
    reg [CODE_LEN_WIDTH-1:0]       depth_code_len_r;

    wire [NODE_INDEX_WIDTH-1:0]    load_node_idx_w;
    wire                           scan_active_w;
    wire [COUNT_WIDTH-1:0]         scan_weight_w;
    wire                           scan_is_leaf_w;
    wire [SYMBOL_WIDTH-1:0]        scan_symbol_w;
    wire [NODE_INDEX_WIDTH-1:0]    scan_order_w;
    wire [NODE_INDEX_WIDTH-1:0]    depth_parent_w;
    reg                            code_len_we;
    reg [SYMBOL_INDEX_WIDTH-1:0]   code_len_wr_addr;
    reg [CODE_LEN_WIDTH-1:0]       code_len_wr_data;

    integer i;
    localparam [7:0] ASCII_MAX = 8'h7E;
    localparam [31:0] ALPHABET_LAST_I = ALPHABET_SIZE - 1;
    localparam [SYMBOL_INDEX_WIDTH-1:0] ALPHABET_LAST =
        ALPHABET_LAST_I[SYMBOL_INDEX_WIDTH-1:0];

`include "huffman_symbol_map.vh"

    function [NODE_INDEX_WIDTH-1:0] widen_symbol_index;
        input [SYMBOL_COUNT_WIDTH-1:0] idx;
    begin
        widen_symbol_index =
            idx[NODE_INDEX_WIDTH-1:0] ^
            ({NODE_INDEX_WIDTH{1'b0}} & {NODE_INDEX_WIDTH{^idx}});
    end
    endfunction

    assign load_node_idx_w = widen_symbol_index(load_index);

    assign scan_active_w  = node_active[scan_node_idx];
    assign scan_weight_w  = node_weight[scan_node_idx];
    assign scan_is_leaf_w = node_is_leaf[scan_node_idx];
    assign scan_symbol_w  = node_symbol[scan_node_idx];
    assign scan_order_w   = node_order[scan_node_idx];
    assign depth_parent_w = node_parent[depth_node_idx_r];

    function better_node;
        input [COUNT_WIDTH-1:0]      aw;
        input                        al;
        input [SYMBOL_WIDTH-1:0]     as;
        input [NODE_INDEX_WIDTH-1:0] ao;
        input [COUNT_WIDTH-1:0]      bw;
        input                        bl;
        input [SYMBOL_WIDTH-1:0]     bs;
        input [NODE_INDEX_WIDTH-1:0] bo;
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
        code_len_read_data = code_len_mem[code_len_read_index];
    end

    assign busy = (state == ST_INIT) ||
                  (state == ST_LOAD_SYMBOL) ||
                  (state == ST_LOAD_COUNT) ||
                  (state == ST_LOAD_NODE) ||
                  (state == ST_FIND_INIT) ||
                  (state == ST_FIND_SCAN) ||
                  (state == ST_BUILD_MERGE) ||
                  (state == ST_DEPTH_INIT) ||
                  (state == ST_DEPTH_WALK) ||
                  (state == ST_MAP_TABLE) ||
                  (state == ST_CLEAR_LEN);

    assign done = (state == ST_DONE);

    always @(*) begin
        code_len_we      = 1'b0;
        code_len_wr_addr = {SYMBOL_INDEX_WIDTH{1'b0}};
        code_len_wr_data = {CODE_LEN_WIDTH{1'b0}};

        if (state == ST_CLEAR_LEN) begin
            code_len_we      = 1'b1;
            code_len_wr_addr = clear_index;
            code_len_wr_data = {CODE_LEN_WIDTH{1'b0}};
        end
        else if ((state == ST_MAP_TABLE) && (map_index < symbol_count)) begin
            code_len_we      = 1'b1;
            code_len_wr_addr = huffman_symbol_to_index(
                                   leaf_symbol[map_index[LIST_INDEX_WIDTH-1:0]]
                               );
            code_len_wr_data = depth_code_len_r;
        end
    end

    always @(posedge clk) begin
        if (code_len_we)
            code_len_mem[code_len_wr_addr] <= code_len_wr_data;
    end

    always @(*) begin
        next_state = state;

        case (state)
            ST_IDLE: begin
                if (start_pulse)
                    next_state = ST_INIT;
            end

            ST_INIT: begin
                next_state = ST_CLEAR_LEN;
            end

            ST_CLEAR_LEN: begin
                if (clear_index == ALPHABET_LAST)
                    next_state = ST_LOAD_SYMBOL;
            end

            ST_LOAD_SYMBOL: begin
                if (load_index == symbol_count) begin
                    if (symbol_count == {SYMBOL_COUNT_WIDTH{1'b0}})
                        next_state = ST_DONE;
                    else if (symbol_count == {{(SYMBOL_COUNT_WIDTH-1){1'b0}},1'b1})
                        next_state = ST_DEPTH_INIT;
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
                    next_state = ST_DEPTH_INIT;
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
                    next_state = ST_DEPTH_INIT;
                else
                    next_state = ST_FIND_INIT;
            end

            ST_DEPTH_INIT: begin
                if (map_index == symbol_count)
                    next_state = ST_DONE;
                else if (symbol_count == {{(SYMBOL_COUNT_WIDTH-1){1'b0}},1'b1})
                    next_state = ST_MAP_TABLE;
                else
                    next_state = ST_DEPTH_WALK;
            end

            ST_DEPTH_WALK: begin
                if (depth_parent_w == depth_node_idx_r)
                    next_state = ST_MAP_TABLE;
            end

            ST_MAP_TABLE: begin
                next_state = ST_DEPTH_INIT;
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
            state             <= ST_IDLE;
            start_d           <= 1'b0;
            error_flag        <= 1'b0;
            load_index        <= {SYMBOL_COUNT_WIDTH{1'b0}};
            map_index         <= {SYMBOL_COUNT_WIDTH{1'b0}};
            clear_index       <= {SYMBOL_INDEX_WIDTH{1'b0}};
            active_nodes      <= {SYMBOL_COUNT_WIDTH{1'b0}};
            next_free_index   <= {NODE_INDEX_WIDTH{1'b0}};
            order_counter     <= {NODE_INDEX_WIDTH{1'b0}};
            scan_node_idx     <= {NODE_INDEX_WIDTH{1'b0}};
            min1_idx_r        <= {NODE_INDEX_WIDTH{1'b0}};
            min2_idx_r        <= {NODE_INDEX_WIDTH{1'b0}};
            found1_r          <= 1'b0;
            found2_r          <= 1'b0;
            min1_weight_r     <= {COUNT_WIDTH{1'b0}};
            min2_weight_r     <= {COUNT_WIDTH{1'b0}};
            min1_is_leaf_r    <= 1'b0;
            min2_is_leaf_r    <= 1'b0;
            min1_symbol_r     <= {SYMBOL_WIDTH{1'b0}};
            min2_symbol_r     <= {SYMBOL_WIDTH{1'b0}};
            min1_order_r      <= {NODE_INDEX_WIDTH{1'b0}};
            min2_order_r      <= {NODE_INDEX_WIDTH{1'b0}};
            load_symbol_r     <= {SYMBOL_WIDTH{1'b0}};
            load_freq_count_r <= {COUNT_WIDTH{1'b0}};
            depth_node_idx_r  <= {NODE_INDEX_WIDTH{1'b0}};
            depth_len_r       <= {CODE_LEN_WIDTH{1'b0}};
            depth_code_len_r  <= {CODE_LEN_WIDTH{1'b0}};

            for (i = 0; i < MAX_SYMBOLS_PER_BLOCK; i = i + 1) begin
`ifndef SYNTHESIS
                leaf_symbol[i]     <= {SYMBOL_WIDTH{1'b0}};
                leaf_node_index[i] <= {NODE_INDEX_WIDTH{1'b0}};
                leaf_code_len[i]   <= {CODE_LEN_WIDTH{1'b0}};
`endif
            end

            for (i = 0; i < MAX_TREE_NODES; i = i + 1) begin
`ifndef SYNTHESIS
                node_weight[i]  <= {COUNT_WIDTH{1'b0}};
`endif
                node_active[i]  <= 1'b0;
`ifndef SYNTHESIS
                node_is_leaf[i] <= 1'b0;
                node_symbol[i]  <= {SYMBOL_WIDTH{1'b0}};
                node_order[i]   <= {NODE_INDEX_WIDTH{1'b0}};
                node_parent[i]  <= {NODE_INDEX_WIDTH{1'b0}};
                node_mask[i]    <= {MAX_SYMBOLS_PER_BLOCK{1'b0}};
`endif
            end

        end
        else begin
            state   <= next_state;
            start_d <= start;

            case (state)
                ST_IDLE: begin
                end

                ST_INIT: begin
                    error_flag        <= 1'b0;
                    load_index        <= {SYMBOL_COUNT_WIDTH{1'b0}};
                    map_index         <= {SYMBOL_COUNT_WIDTH{1'b0}};
                    clear_index       <= {SYMBOL_INDEX_WIDTH{1'b0}};
                    active_nodes      <= {SYMBOL_COUNT_WIDTH{1'b0}};
                    next_free_index   <= widen_symbol_index(symbol_count);
                    order_counter     <= widen_symbol_index(symbol_count);
                    scan_node_idx     <= {NODE_INDEX_WIDTH{1'b0}};
                    min1_idx_r        <= {NODE_INDEX_WIDTH{1'b0}};
                    min2_idx_r        <= {NODE_INDEX_WIDTH{1'b0}};
                    found1_r          <= 1'b0;
                    found2_r          <= 1'b0;
                    min1_weight_r     <= {COUNT_WIDTH{1'b0}};
                    min2_weight_r     <= {COUNT_WIDTH{1'b0}};
                    min1_is_leaf_r    <= 1'b0;
                    min2_is_leaf_r    <= 1'b0;
                    min1_symbol_r     <= {SYMBOL_WIDTH{1'b0}};
                    min2_symbol_r     <= {SYMBOL_WIDTH{1'b0}};
                    min1_order_r      <= {NODE_INDEX_WIDTH{1'b0}};
                    min2_order_r      <= {NODE_INDEX_WIDTH{1'b0}};
                    load_symbol_r     <= {SYMBOL_WIDTH{1'b0}};
                    load_freq_count_r <= {COUNT_WIDTH{1'b0}};
                    depth_node_idx_r  <= {NODE_INDEX_WIDTH{1'b0}};
                    depth_len_r       <= {CODE_LEN_WIDTH{1'b0}};
                    depth_code_len_r  <= {CODE_LEN_WIDTH{1'b0}};

                    for (i = 0; i < MAX_SYMBOLS_PER_BLOCK; i = i + 1) begin
`ifndef SYNTHESIS
                        leaf_symbol[i]     <= {SYMBOL_WIDTH{1'b0}};
                        leaf_node_index[i] <= {NODE_INDEX_WIDTH{1'b0}};
                        leaf_code_len[i]   <= {CODE_LEN_WIDTH{1'b0}};
`endif
                    end

                    for (i = 0; i < MAX_TREE_NODES; i = i + 1) begin
`ifndef SYNTHESIS
                        node_weight[i]  <= {COUNT_WIDTH{1'b0}};
`endif
                        node_active[i]  <= 1'b0;
`ifndef SYNTHESIS
                        node_is_leaf[i] <= 1'b0;
                        node_symbol[i]  <= {SYMBOL_WIDTH{1'b0}};
                        node_order[i]   <= {NODE_INDEX_WIDTH{1'b0}};
                        node_parent[i]  <= {NODE_INDEX_WIDTH{1'b0}};
                        node_mask[i]    <= {MAX_SYMBOLS_PER_BLOCK{1'b0}};
`endif
                    end

                end

                ST_CLEAR_LEN: begin
                    if (clear_index != ALPHABET_LAST)
                        clear_index <= clear_index +
                                       {{(SYMBOL_INDEX_WIDTH-1){1'b0}}, 1'b1};
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
                        leaf_symbol[load_index[LIST_INDEX_WIDTH-1:0]]     <= load_symbol_r;
                        leaf_node_index[load_index[LIST_INDEX_WIDTH-1:0]] <= load_node_idx_w;
`ifndef SYNTHESIS
                        if (symbol_count == {{(SYMBOL_COUNT_WIDTH-1){1'b0}},1'b1})
                            leaf_code_len[load_index[LIST_INDEX_WIDTH-1:0]] <=
                                {{(CODE_LEN_WIDTH-1){1'b0}},1'b1};
                        else
                            leaf_code_len[load_index[LIST_INDEX_WIDTH-1:0]] <=
                                {CODE_LEN_WIDTH{1'b0}};
`endif

                        if (load_freq_count_r == {COUNT_WIDTH{1'b0}}) begin
                            error_flag <= 1'b1;
                        end
                        else begin
                            node_weight[load_node_idx_w]  <= load_freq_count_r;
                            node_active[load_node_idx_w]  <= 1'b1;
                            node_is_leaf[load_node_idx_w] <= 1'b1;
                            node_symbol[load_node_idx_w]  <= load_symbol_r;
                            node_order[load_node_idx_w]   <= load_node_idx_w;
                            node_parent[load_node_idx_w]  <= load_node_idx_w;
`ifndef SYNTHESIS
                            node_mask[load_node_idx_w]    <=
                                ({MAX_SYMBOLS_PER_BLOCK{1'b0}} |
                                 ({{(MAX_SYMBOLS_PER_BLOCK-1){1'b0}},1'b1} << load_index));
`endif
                            active_nodes <= active_nodes +
                                            {{(SYMBOL_COUNT_WIDTH-1){1'b0}},1'b1};
                        end

                        load_index <= load_index +
                                      {{(SYMBOL_COUNT_WIDTH-1){1'b0}},1'b1};
                    end
                end

                ST_FIND_INIT: begin
                    scan_node_idx  <= {NODE_INDEX_WIDTH{1'b0}};
                    min1_idx_r     <= {NODE_INDEX_WIDTH{1'b0}};
                    min2_idx_r     <= {NODE_INDEX_WIDTH{1'b0}};
                    found1_r       <= 1'b0;
                    found2_r       <= 1'b0;
                    min1_weight_r  <= {COUNT_WIDTH{1'b0}};
                    min2_weight_r  <= {COUNT_WIDTH{1'b0}};
                    min1_is_leaf_r <= 1'b0;
                    min2_is_leaf_r <= 1'b0;
                    min1_symbol_r  <= {SYMBOL_WIDTH{1'b0}};
                    min2_symbol_r  <= {SYMBOL_WIDTH{1'b0}};
                    min1_order_r   <= {NODE_INDEX_WIDTH{1'b0}};
                    min2_order_r   <= {NODE_INDEX_WIDTH{1'b0}};
                end

                ST_FIND_SCAN: begin
                    if (scan_active_w) begin
                        if (!found1_r) begin
                            found1_r       <= 1'b1;
                            min1_idx_r     <= scan_node_idx;
                            min1_weight_r  <= scan_weight_w;
                            min1_is_leaf_r <= scan_is_leaf_w;
                            min1_symbol_r  <= scan_symbol_w;
                            min1_order_r   <= scan_order_w;
                        end
                        else if (better_node(
                                    scan_weight_w,
                                    scan_is_leaf_w,
                                    scan_symbol_w,
                                    scan_order_w,
                                    min1_weight_r,
                                    min1_is_leaf_r,
                                    min1_symbol_r,
                                    min1_order_r
                                 )) begin
                            found2_r       <= found1_r;
                            min2_idx_r     <= min1_idx_r;
                            min2_weight_r  <= min1_weight_r;
                            min2_is_leaf_r <= min1_is_leaf_r;
                            min2_symbol_r  <= min1_symbol_r;
                            min2_order_r   <= min1_order_r;
                            found1_r       <= 1'b1;
                            min1_idx_r     <= scan_node_idx;
                            min1_weight_r  <= scan_weight_w;
                            min1_is_leaf_r <= scan_is_leaf_w;
                            min1_symbol_r  <= scan_symbol_w;
                            min1_order_r   <= scan_order_w;
                        end
                        else if (!found2_r) begin
                            found2_r       <= 1'b1;
                            min2_idx_r     <= scan_node_idx;
                            min2_weight_r  <= scan_weight_w;
                            min2_is_leaf_r <= scan_is_leaf_w;
                            min2_symbol_r  <= scan_symbol_w;
                            min2_order_r   <= scan_order_w;
                        end
                        else if (better_node(
                                    scan_weight_w,
                                    scan_is_leaf_w,
                                    scan_symbol_w,
                                    scan_order_w,
                                    min2_weight_r,
                                    min2_is_leaf_r,
                                    min2_symbol_r,
                                    min2_order_r
                                 )) begin
                            min2_idx_r     <= scan_node_idx;
                            min2_weight_r  <= scan_weight_w;
                            min2_is_leaf_r <= scan_is_leaf_w;
                            min2_symbol_r  <= scan_symbol_w;
                            min2_order_r   <= scan_order_w;
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
                            node_active[min1_idx_r] <= 1'b0;
                            node_active[min2_idx_r] <= 1'b0;
                            node_parent[min1_idx_r] <= next_free_index;
                            node_parent[min2_idx_r] <= next_free_index;
`ifndef SYNTHESIS
                            for (i = 0; i < MAX_SYMBOLS_PER_BLOCK; i = i + 1) begin
                                if (node_mask[min1_idx_r][i] || node_mask[min2_idx_r][i])
                                    leaf_code_len[i] <= leaf_code_len[i] +
                                                        {{(CODE_LEN_WIDTH-1){1'b0}},1'b1};
                            end
`endif

                            node_weight[next_free_index]  <= min1_weight_r + min2_weight_r;
                            node_active[next_free_index]  <= 1'b1;
                            node_is_leaf[next_free_index] <= 1'b0;
                            node_symbol[next_free_index]  <= {SYMBOL_WIDTH{1'b0}};
                            node_order[next_free_index]   <= order_counter;
                            node_parent[next_free_index]  <= next_free_index;
`ifndef SYNTHESIS
                            node_mask[next_free_index]    <=
                                node_mask[min1_idx_r] | node_mask[min2_idx_r];
`endif

                            next_free_index <= next_free_index +
                                               {{(NODE_INDEX_WIDTH-1){1'b0}},1'b1};
                            order_counter   <= order_counter +
                                               {{(NODE_INDEX_WIDTH-1){1'b0}},1'b1};

                            active_nodes <= active_nodes -
                                            {{(SYMBOL_COUNT_WIDTH-1){1'b0}},1'b1};
                        end
                    end
                end

                ST_DEPTH_INIT: begin
                    if (map_index < symbol_count) begin
                        depth_node_idx_r <= leaf_node_index[map_index[LIST_INDEX_WIDTH-1:0]];
                        depth_len_r      <= {CODE_LEN_WIDTH{1'b0}};
                        if (symbol_count == {{(SYMBOL_COUNT_WIDTH-1){1'b0}},1'b1})
                            depth_code_len_r <= {{(CODE_LEN_WIDTH-1){1'b0}},1'b1};
                        else
                            depth_code_len_r <= {CODE_LEN_WIDTH{1'b0}};
                    end
                end

                ST_DEPTH_WALK: begin
                    if (depth_parent_w == depth_node_idx_r) begin
                        depth_code_len_r <= depth_len_r;
                        if (depth_len_r == {CODE_LEN_WIDTH{1'b0}})
                            error_flag <= 1'b1;
                    end
                    else begin
                        depth_node_idx_r <= depth_parent_w;
                        if (depth_len_r == {CODE_LEN_WIDTH{1'b1}}) begin
                            error_flag <= 1'b1;
                            depth_code_len_r <= depth_len_r;
                        end
                        else begin
                            depth_len_r <= depth_len_r +
                                           {{(CODE_LEN_WIDTH-1){1'b0}},1'b1};
                        end
                    end
                end

                ST_MAP_TABLE: begin
                    if (map_index < symbol_count) begin
                        if (depth_code_len_r == {CODE_LEN_WIDTH{1'b0}})
                            error_flag <= 1'b1;

`ifndef SYNTHESIS
                        leaf_code_len[map_index[LIST_INDEX_WIDTH-1:0]] <= depth_code_len_r;
`endif

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

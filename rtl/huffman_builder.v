module huffman_builder #(
    parameter ALPHABET_SIZE         = 256,
    parameter SYMBOL_WIDTH          = 8,
    parameter SYMBOL_COUNT_WIDTH    = 9,
    parameter COUNT_WIDTH           = 6,
    parameter SYMBOL_INDEX_WIDTH    = 8,
    parameter CODE_LEN_WIDTH        = 5,
    parameter CODE_WIDTH            = 13,
    parameter MAX_SYMBOLS_PER_BLOCK = 32,
    parameter MAX_TREE_NODES        = 63,
    parameter [7:0] ASCII_MIN       = 8'h20
)(
    input  wire                           clk,
    input  wire                           rst_n,
    input  wire                           start,
    input  wire [SYMBOL_COUNT_WIDTH-1:0]  block_size,

    output reg  [SYMBOL_INDEX_WIDTH-1:0]  freq_read_index,
    input  wire [COUNT_WIDTH-1:0]         freq_read_count,

    output wire                           busy,
    output wire                           done,
    output reg                            error_flag,

    output wire [SYMBOL_COUNT_WIDTH-1:0]  symbol_count,

    input  wire [SYMBOL_COUNT_WIDTH-1:0]  symbol_read_addr,
    output wire [SYMBOL_WIDTH-1:0]        symbol_read_data,

    input  wire [SYMBOL_INDEX_WIDTH-1:0]  code_len_read_index,
    output wire [CODE_LEN_WIDTH-1:0]      code_len_read_data,

    input  wire [SYMBOL_INDEX_WIDTH-1:0]  code_read_index,
    output wire [CODE_WIDTH-1:0]          code_read_data
);

    localparam [3:0] ST_IDLE      = 4'd0;
    localparam [3:0] ST_START_SLB = 4'd1;
    localparam [3:0] ST_RUN_SLB   = 4'd2;
    localparam [3:0] ST_START_CLB = 4'd3;
    localparam [3:0] ST_RUN_CLB   = 4'd4;
    localparam [3:0] ST_START_CGG = 4'd5;
    localparam [3:0] ST_RUN_CGG   = 4'd6;
    localparam [3:0] ST_DONE      = 4'd7;

    reg [3:0] state, next_state;

    reg  start_d;
    wire start_pulse;

    assign start_pulse = start & ~start_d;

    wire slb_start;
    wire clb_start;
    wire cgg_start;

    assign slb_start = (state == ST_START_SLB);
    assign clb_start = (state == ST_START_CLB);
    assign cgg_start = (state == ST_START_CGG);

    wire                          slb_busy;
    wire                          slb_done;
    wire                          slb_error;
    wire [SYMBOL_COUNT_WIDTH-1:0] slb_symbol_count;

    reg  [SYMBOL_COUNT_WIDTH-1:0] slb_symbol_read_addr_mux;
    wire [SYMBOL_WIDTH-1:0]       slb_symbol_read_data;
    wire [SYMBOL_INDEX_WIDTH-1:0] slb_freq_read_index;

    wire                          clb_busy;
    wire                          clb_done;
    wire                          clb_error;
    wire [SYMBOL_COUNT_WIDTH-1:0] clb_symbol_read_addr;
    wire [SYMBOL_INDEX_WIDTH-1:0] clb_freq_read_index;
    wire [SYMBOL_INDEX_WIDTH-1:0] clb_code_len_read_index;
    wire [CODE_LEN_WIDTH-1:0]     clb_code_len_read_data;
    wire                          clb_active_w;
    wire [SYMBOL_WIDTH-1:0]       clb_symbol_read_data_w;
    wire [COUNT_WIDTH-1:0]        clb_freq_read_count_w;

    wire                          cgg_busy;
    wire                          cgg_done;
    wire                          cgg_error;
    wire [SYMBOL_COUNT_WIDTH-1:0] cgg_symbol_read_addr;
    wire [SYMBOL_INDEX_WIDTH-1:0] cgg_code_len_src_read_index;
    wire [CODE_LEN_WIDTH-1:0]     cgg_code_len_read_data;
    wire [CODE_WIDTH-1:0]         cgg_code_read_data;

    assign clb_active_w = (state == ST_START_CLB) || (state == ST_RUN_CLB);
    assign clb_symbol_read_data_w =
        clb_active_w ? slb_symbol_read_data : {SYMBOL_WIDTH{1'b0}};
    assign clb_freq_read_count_w =
        clb_active_w ? freq_read_count : {COUNT_WIDTH{1'b0}};

    always @(*) begin
        if ((state == ST_START_SLB) || (state == ST_RUN_SLB))
            freq_read_index = slb_freq_read_index;
        else if ((state == ST_START_CLB) || (state == ST_RUN_CLB))
            freq_read_index = clb_freq_read_index;
        else
            freq_read_index = {SYMBOL_INDEX_WIDTH{1'b0}};
    end

    always @(*) begin
        if ((state == ST_START_CLB) || (state == ST_RUN_CLB))
            slb_symbol_read_addr_mux = clb_symbol_read_addr;
        else if ((state == ST_START_CGG) || (state == ST_RUN_CGG))
            slb_symbol_read_addr_mux = cgg_symbol_read_addr;
        else
            slb_symbol_read_addr_mux = symbol_read_addr;
    end

    assign symbol_read_data   = slb_symbol_read_data;
    assign code_len_read_data = cgg_code_len_read_data;
    assign code_read_data     = cgg_code_read_data;
    assign symbol_count       = slb_symbol_count;

    assign busy = (state == ST_START_SLB) ||
                  (state == ST_RUN_SLB)   ||
                  (state == ST_START_CLB) ||
                  (state == ST_RUN_CLB)   ||
                  (state == ST_START_CGG) ||
                  (state == ST_RUN_CGG)   ||
                  (1'b0 && slb_busy)      ||
                  (1'b0 && clb_busy)      ||
                  (1'b0 && cgg_busy);

    assign done = (state == ST_DONE);

    symbol_list_builder #(
        .ALPHABET_SIZE         (ALPHABET_SIZE),
        .SYMBOL_WIDTH          (SYMBOL_WIDTH),
        .SYMBOL_COUNT_WIDTH    (SYMBOL_COUNT_WIDTH),
        .COUNT_WIDTH           (COUNT_WIDTH),
        .SYMBOL_INDEX_WIDTH    (SYMBOL_INDEX_WIDTH),
        .MAX_SYMBOLS_PER_BLOCK (MAX_SYMBOLS_PER_BLOCK),
        .ASCII_MIN             (ASCII_MIN)
    ) u_symbol_list_builder (
        .clk              (clk),
        .rst_n            (rst_n),
        .start            (slb_start),
        .block_size       (block_size),
        .freq_read_index  (slb_freq_read_index),
        .freq_read_count  (freq_read_count),
        .busy             (slb_busy),
        .done             (slb_done),
        .error_flag       (slb_error),
        .symbol_count     (slb_symbol_count),
        .symbol_read_addr (slb_symbol_read_addr_mux),
        .symbol_read_data (slb_symbol_read_data)
    );

    code_length_builder #(
        .ALPHABET_SIZE         (ALPHABET_SIZE),
        .SYMBOL_WIDTH          (SYMBOL_WIDTH),
        .SYMBOL_COUNT_WIDTH    (SYMBOL_COUNT_WIDTH),
        .COUNT_WIDTH           (COUNT_WIDTH),
        .SYMBOL_INDEX_WIDTH    (SYMBOL_INDEX_WIDTH),
        .CODE_LEN_WIDTH        (CODE_LEN_WIDTH),
        .MAX_SYMBOLS_PER_BLOCK (MAX_SYMBOLS_PER_BLOCK),
        .MAX_TREE_NODES        (MAX_TREE_NODES),
        .ASCII_MIN             (ASCII_MIN)
    ) u_code_length_builder (
        .clk                 (clk),
        .rst_n               (rst_n),
        .start               (clb_start),
        .symbol_count        (slb_symbol_count),
        .symbol_read_addr    (clb_symbol_read_addr),
        .symbol_read_data    (clb_symbol_read_data_w),
        .freq_read_index     (clb_freq_read_index),
        .freq_read_count     (clb_freq_read_count_w),
        .busy                (clb_busy),
        .done                (clb_done),
        .error_flag          (clb_error),
        .code_len_read_index (clb_code_len_read_index),
        .code_len_read_data  (clb_code_len_read_data)
    );

    canonical_code_generator #(
        .ALPHABET_SIZE         (ALPHABET_SIZE),
        .SYMBOL_WIDTH          (SYMBOL_WIDTH),
        .SYMBOL_COUNT_WIDTH    (SYMBOL_COUNT_WIDTH),
        .SYMBOL_INDEX_WIDTH    (SYMBOL_INDEX_WIDTH),
        .CODE_LEN_WIDTH        (CODE_LEN_WIDTH),
        .CODE_WIDTH            (CODE_WIDTH),
        .MAX_SYMBOLS_PER_BLOCK (MAX_SYMBOLS_PER_BLOCK),
        .ASCII_MIN             (ASCII_MIN)
    ) u_canonical_code_generator (
        .clk                     (clk),
        .rst_n                   (rst_n),
        .start                   (cgg_start),
        .symbol_count            (slb_symbol_count),
        .symbol_read_addr        (cgg_symbol_read_addr),
        .symbol_read_data        (slb_symbol_read_data),
        .code_len_src_read_index (cgg_code_len_src_read_index),
        .code_len_src_read_data  (clb_code_len_read_data),
        .busy                    (cgg_busy),
        .done                    (cgg_done),
        .error_flag              (cgg_error),
        .code_len_read_index     (code_len_read_index),
        .code_len_read_data      (cgg_code_len_read_data),
        .code_read_index         (code_read_index),
        .code_read_data          (cgg_code_read_data)
    );

    assign clb_code_len_read_index = cgg_code_len_src_read_index;

    always @(*) begin
        next_state = state;

        case (state)
            ST_IDLE: begin
                if (start_pulse)
                    next_state = ST_START_SLB;
            end

            ST_START_SLB: begin
                next_state = ST_RUN_SLB;
            end

            ST_RUN_SLB: begin
                if (slb_done)
                    next_state = ST_START_CLB;
            end

            ST_START_CLB: begin
                next_state = ST_RUN_CLB;
            end

            ST_RUN_CLB: begin
                if (clb_done)
                    next_state = ST_START_CGG;
            end

            ST_START_CGG: begin
                next_state = ST_RUN_CGG;
            end

            ST_RUN_CGG: begin
                if (cgg_done)
                    next_state = ST_DONE;
            end

            ST_DONE: begin
                if (start_pulse)
                    next_state = ST_START_SLB;
            end

            default: begin
                next_state = ST_IDLE;
            end
        endcase
    end

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
                if (slb_error || clb_error || cgg_error)
                    error_flag <= 1'b1;
            end
        end
    end

endmodule

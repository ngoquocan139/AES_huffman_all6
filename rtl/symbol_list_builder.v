module symbol_list_builder #(
    parameter ALPHABET_SIZE         = 96,
    parameter SYMBOL_WIDTH          = 8,
    parameter SYMBOL_COUNT_WIDTH    = 6,
    parameter COUNT_WIDTH           = 6,
    parameter SYMBOL_INDEX_WIDTH    = 7,
    parameter MAX_SYMBOLS_PER_BLOCK = 32,
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

    output reg  [SYMBOL_COUNT_WIDTH-1:0]  symbol_count,

    input  wire [SYMBOL_COUNT_WIDTH-1:0]  symbol_read_addr,
    output reg  [SYMBOL_WIDTH-1:0]        symbol_read_data
);

    localparam [1:0] ST_IDLE = 2'b00;
    localparam [1:0] ST_INIT = 2'b01;
    localparam [1:0] ST_SCAN = 2'b10;
    localparam [1:0] ST_DONE = 2'b11;

    localparam LIST_INDEX_WIDTH = (MAX_SYMBOLS_PER_BLOCK <= 32) ? 5 : 6;

    reg [1:0] state, next_state;

    reg  start_d;
    wire start_pulse;

    assign start_pulse = start & ~start_d;

    reg [SYMBOL_WIDTH-1:0] symbol_list_mem [0:MAX_SYMBOLS_PER_BLOCK-1];
    reg [SYMBOL_INDEX_WIDTH-1:0] scan_index;

    integer i;
    localparam [7:0] ASCII_MAX = 8'h7E;

`include "huffman_symbol_map.vh"

    localparam [SYMBOL_INDEX_WIDTH-1:0] ALPHABET_LAST =
        ALPHABET_SIZE - 1;

    localparam [SYMBOL_COUNT_WIDTH-1:0] MAX_SYMBOLS_VALUE =
        MAX_SYMBOLS_PER_BLOCK[SYMBOL_COUNT_WIDTH-1:0];

    wire has_symbol;
    wire [SYMBOL_WIDTH-1:0] current_symbol_id;

    assign has_symbol = (freq_read_count != {COUNT_WIDTH{1'b0}});

    assign current_symbol_id = huffman_index_to_symbol(scan_index);

    assign busy = (state == ST_INIT) || (state == ST_SCAN);
    assign done = (state == ST_DONE);

    always @(*) begin
        if (symbol_read_addr < symbol_count)
            symbol_read_data = symbol_list_mem[symbol_read_addr[LIST_INDEX_WIDTH-1:0]];
        else
            symbol_read_data = {SYMBOL_WIDTH{1'b0}};
    end

    always @(*) begin
        if (state == ST_SCAN)
            freq_read_index = scan_index;
        else
            freq_read_index = {SYMBOL_INDEX_WIDTH{1'b0}};
    end

    always @(*) begin
        next_state = state;

        case (state)
            ST_IDLE: begin
                if (start_pulse)
                    next_state = ST_INIT;
            end

            ST_INIT: begin
                next_state = ST_SCAN;
            end

            ST_SCAN: begin
                if (scan_index == ALPHABET_LAST)
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
            state        <= ST_IDLE;
            start_d      <= 1'b0;
            scan_index   <= {SYMBOL_INDEX_WIDTH{1'b0}};
            symbol_count <= {SYMBOL_COUNT_WIDTH{1'b0}};
            error_flag   <= 1'b0;

            for (i = 0; i < MAX_SYMBOLS_PER_BLOCK; i = i + 1)
                symbol_list_mem[i] <= {SYMBOL_WIDTH{1'b0}};
        end
        else begin
            state   <= next_state;
            start_d <= start;

            case (state)
                ST_IDLE: begin
                end

                ST_INIT: begin
                    scan_index   <= {SYMBOL_INDEX_WIDTH{1'b0}};
                    symbol_count <= {SYMBOL_COUNT_WIDTH{1'b0}};
                    error_flag   <= 1'b0;

                    for (i = 0; i < MAX_SYMBOLS_PER_BLOCK; i = i + 1)
                        symbol_list_mem[i] <= {SYMBOL_WIDTH{1'b0}};
                end

                ST_SCAN: begin
                    if (has_symbol) begin
                        if (symbol_count < MAX_SYMBOLS_VALUE) begin
                            symbol_list_mem[symbol_count[LIST_INDEX_WIDTH-1:0]] <= current_symbol_id;
                            symbol_count <= symbol_count +
                                            {{(SYMBOL_COUNT_WIDTH-1){1'b0}}, 1'b1};
                        end
                        else begin
                            error_flag <= 1'b1;
                        end
                    end

                    if (scan_index != ALPHABET_LAST) begin
                        scan_index <= scan_index +
                                      {{(SYMBOL_INDEX_WIDTH-1){1'b0}}, 1'b1};
                    end
                    else begin
                        if ((block_size != {SYMBOL_COUNT_WIDTH{1'b0}}) &&
                            (symbol_count == {SYMBOL_COUNT_WIDTH{1'b0}}) &&
                            !has_symbol) begin
                            error_flag <= 1'b1;
                        end
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

module frequency_counter #(
    parameter ALPHABET_SIZE       = 256,
    parameter SYMBOL_WIDTH        = 8,
    parameter COUNT_WIDTH         = 6,
    parameter SYMBOL_INDEX_WIDTH  = 8,
    parameter [7:0] ASCII_MIN     = 8'h20,
    parameter [7:0] ASCII_MAX     = 8'h7E,
    parameter [7:0] DEFAULT_REMAP = 8'h20
)(
    input  wire                          clk,
    input  wire                          rst_n,

    input  wire                          clear,
    input  wire                          count_en,
    input  wire [SYMBOL_WIDTH-1:0]       count_data,

    input  wire [SYMBOL_INDEX_WIDTH-1:0] read_index,
    output reg  [COUNT_WIDTH-1:0]        read_count,

    output reg  [SYMBOL_WIDTH-1:0]       normalized_byte,
    output reg  [SYMBOL_INDEX_WIDTH-1:0] symbol_index,
    output reg                           count_overflow
);

    (* ram_style = "distributed" *) reg [COUNT_WIDTH-1:0] freq_table [0:ALPHABET_SIZE-1];
    reg [ALPHABET_SIZE-1:0] freq_valid;

    reg [SYMBOL_WIDTH-1:0]       norm_byte_w;
    reg [SYMBOL_INDEX_WIDTH-1:0] symbol_index_w;

`include "huffman_symbol_map.vh"

    always @(*) begin
        norm_byte_w    = huffman_normalize_symbol(count_data, DEFAULT_REMAP);
        symbol_index_w = huffman_symbol_to_index(norm_byte_w);

        normalized_byte = norm_byte_w;
        symbol_index    = symbol_index_w;
    end

    always @(*) begin
        if (freq_valid[read_index])
            read_count = freq_table[read_index];
        else
            read_count = {COUNT_WIDTH{1'b0}};
    end

    always @(posedge clk) begin
        if (!clear && count_en) begin
            if (!freq_valid[symbol_index_w])
                freq_table[symbol_index_w] <=
                    {{(COUNT_WIDTH-1){1'b0}}, 1'b1};
            else if (freq_table[symbol_index_w] != {COUNT_WIDTH{1'b1}})
                freq_table[symbol_index_w] <=
                    freq_table[symbol_index_w] +
                    {{(COUNT_WIDTH-1){1'b0}}, 1'b1};
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            count_overflow <= 1'b0;
            freq_valid     <= {ALPHABET_SIZE{1'b0}};
        end
        else begin
            if (clear) begin
                count_overflow <= 1'b0;
                freq_valid     <= {ALPHABET_SIZE{1'b0}};
            end
            else if (count_en) begin
                if (!freq_valid[symbol_index_w]) begin
                    freq_valid[symbol_index_w] <= 1'b1;
                end
                else if (freq_table[symbol_index_w] == {COUNT_WIDTH{1'b1}})
                    count_overflow <= 1'b1;
            end
        end
    end

endmodule

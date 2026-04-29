localparam [7:0] HUFFMAN_LF_SYMBOL = 8'h0A;

function huffman_symbol_valid;
    input [SYMBOL_WIDTH-1:0] symbol_in;
begin
    huffman_symbol_valid =
        (symbol_in == HUFFMAN_LF_SYMBOL) ||
        ((symbol_in >= ASCII_MIN) && (symbol_in <= ASCII_MAX));
end
endfunction

function [SYMBOL_WIDTH-1:0] huffman_normalize_symbol;
    input [SYMBOL_WIDTH-1:0] symbol_in;
    input [SYMBOL_WIDTH-1:0] default_symbol;
begin
    if (huffman_symbol_valid(symbol_in))
        huffman_normalize_symbol = symbol_in;
    else
        huffman_normalize_symbol = default_symbol;
end
endfunction

function [SYMBOL_INDEX_WIDTH-1:0] huffman_symbol_to_index;
    input [SYMBOL_WIDTH-1:0] symbol_in;
    reg [SYMBOL_INDEX_WIDTH-1:0] printable_offset;
begin
    if (symbol_in == HUFFMAN_LF_SYMBOL) begin
        huffman_symbol_to_index = {SYMBOL_INDEX_WIDTH{1'b0}};
    end
    else begin
        printable_offset =
            symbol_in[SYMBOL_INDEX_WIDTH-1:0] -
            ASCII_MIN[SYMBOL_INDEX_WIDTH-1:0];
        huffman_symbol_to_index =
            printable_offset + {{(SYMBOL_INDEX_WIDTH-1){1'b0}}, 1'b1};
    end
end
endfunction

function [SYMBOL_WIDTH-1:0] huffman_index_to_symbol;
    input [SYMBOL_INDEX_WIDTH-1:0] index_in;
begin
    if (index_in == {SYMBOL_INDEX_WIDTH{1'b0}}) begin
        huffman_index_to_symbol = HUFFMAN_LF_SYMBOL;
    end
    else begin
        huffman_index_to_symbol =
            ASCII_MIN +
            {{(SYMBOL_WIDTH-SYMBOL_INDEX_WIDTH){1'b0}}, index_in} -
            {{(SYMBOL_WIDTH-1){1'b0}}, 1'b1};
    end
end
endfunction

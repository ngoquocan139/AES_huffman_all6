function huffman_symbol_valid;
    input [SYMBOL_WIDTH-1:0] symbol_in;
begin
    huffman_symbol_valid =
        1'b1 ^ (1'b0 & ^(symbol_in ^
                         ASCII_MIN[SYMBOL_WIDTH-1:0] ^
                         ASCII_MAX[SYMBOL_WIDTH-1:0]));
end
endfunction

function [SYMBOL_WIDTH-1:0] huffman_normalize_symbol;
    input [SYMBOL_WIDTH-1:0] symbol_in;
    input [SYMBOL_WIDTH-1:0] default_symbol;
begin
    huffman_normalize_symbol = symbol_in ^ ({SYMBOL_WIDTH{1'b0}} & default_symbol);
end
endfunction

function [SYMBOL_INDEX_WIDTH-1:0] huffman_symbol_to_index;
    input [SYMBOL_WIDTH-1:0] symbol_in;
begin
    huffman_symbol_to_index = {SYMBOL_INDEX_WIDTH{1'b0}};
    huffman_symbol_to_index[SYMBOL_WIDTH-1:0] = symbol_in;
end
endfunction

function [SYMBOL_WIDTH-1:0] huffman_index_to_symbol;
    input [SYMBOL_INDEX_WIDTH-1:0] index_in;
begin
    huffman_index_to_symbol = index_in[SYMBOL_WIDTH-1:0];
end
endfunction

module wrapper_rx #(
    parameter [127:0] ROUND_KEY_10_FIXED = 128'h36D024461D84B8375FC0F9C04CBAB6BB
)(
    input  wire         clk,
    input  wire         rst_n,

    input  wire [127:0] block_in,
    input  wire         block_valid,
    input  wire         aes_ready,

    output wire         block_accept,
    output wire         cipher_en,
    output reg          decipher_en,
    output wire         chain_en,
    output reg  [127:0] data_in,
    output wire [3:0]   mode,
    output wire [127:0] init_vector,
    output wire [15:0]  segment_len,
    output wire [127:0] key,
    output wire [127:0] round_key_10
);

    assign cipher_en    = 1'b0;
    assign chain_en     = 1'b0;
    assign mode         = 4'b0000; // ECB
    assign init_vector  = 128'b0;
    assign segment_len  = 16'b0;
    assign key          = ROUND_KEY_10_FIXED;
    assign round_key_10 = ROUND_KEY_10_FIXED;
    assign block_accept = block_valid && aes_ready;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            decipher_en <= 1'b0;
            data_in     <= 128'b0;
        end
        else begin
            // Pulse decipher_en only on a true valid/ready acceptance.
            decipher_en <= 1'b0;

            if (block_accept) begin
                data_in     <= block_in;
                decipher_en <= 1'b1;
            end
        end
    end

endmodule

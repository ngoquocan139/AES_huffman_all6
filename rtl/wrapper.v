module wrapper #(
    parameter [127:0] AES_KEY_FIXED = 128'h00112233445566778899AABBCCDDEEFF
)(
    input  wire         clk,
    input  wire         rst_n,

    input  wire [127:0] block_in,
    input  wire         block_valid,
    input  wire         aes_ready,

    output wire         block_accept,
    output reg          cipher_en,
    output wire         decipher_en,
    output wire         chain_en,
    output reg  [127:0] data_in,
    output wire [3:0]   mode,
    output wire [127:0] init_vector,
    output wire [15:0]  segment_len,
    output wire [127:0] key
);

    assign decipher_en = 1'b0;
    assign chain_en    = 1'b0;
    assign mode        = 4'b0000; // ECB
    assign init_vector = 128'b0;
    assign segment_len = 16'b0;
    assign key         = AES_KEY_FIXED;
    assign block_accept = block_valid && aes_ready;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cipher_en    <= 1'b0;
            data_in      <= 128'b0;
        end
        else begin
            // Pulse cipher_en only on a true valid/ready acceptance.
            cipher_en    <= 1'b0;

            if (block_accept) begin
                data_in      <= block_in;
                cipher_en    <= 1'b1;
            end
        end
    end

endmodule

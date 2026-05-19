module block_buffer #(
    parameter BLOCK_SIZE       = 32,
    parameter DATA_WIDTH       = 8,
    parameter BLOCK_SIZE_WIDTH = 6,
    parameter ADDR_WIDTH       = 5
)(
    input  wire                         clk,
    input  wire                         rst_n,

    input  wire                         clear,
    input  wire                         write_en,
    input  wire [DATA_WIDTH-1:0]        write_data,

    input  wire [ADDR_WIDTH-1:0]        read_addr,
    output reg  [DATA_WIDTH-1:0]        read_data,

    output reg  [BLOCK_SIZE_WIDTH-1:0]  block_size,
    output wire                         full,
    output wire                         empty,
    output reg                          overflow_error
);

    (* ram_style = "distributed" *) reg [DATA_WIDTH-1:0] block_mem [0:BLOCK_SIZE-1];

    localparam [BLOCK_SIZE_WIDTH-1:0] BLOCK_SIZE_VALUE = BLOCK_SIZE;

    wire [BLOCK_SIZE_WIDTH-1:0] read_addr_ext;
    assign read_addr_ext = {{(BLOCK_SIZE_WIDTH-ADDR_WIDTH){1'b0}}, read_addr};

    assign empty = (block_size == {BLOCK_SIZE_WIDTH{1'b0}});
    assign full  = (block_size == BLOCK_SIZE_VALUE);

    always @(*) begin
        if (read_addr_ext < block_size)
            read_data = block_mem[read_addr];
        else
            read_data = {DATA_WIDTH{1'b0}};
    end

    always @(posedge clk) begin
        if (!clear && write_en && (block_size < BLOCK_SIZE_VALUE))
            block_mem[block_size[ADDR_WIDTH-1:0]] <= write_data;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            block_size     <= {BLOCK_SIZE_WIDTH{1'b0}};
            overflow_error <= 1'b0;
        end
        else begin
            if (clear) begin
                block_size     <= {BLOCK_SIZE_WIDTH{1'b0}};
                overflow_error <= 1'b0;
            end
            else if (write_en) begin
                if (block_size < BLOCK_SIZE_VALUE) begin
                    block_size <= block_size + {{(BLOCK_SIZE_WIDTH-1){1'b0}}, 1'b1};
                end
                else begin
                    overflow_error <= 1'b1;
                end
            end
        end
    end

endmodule

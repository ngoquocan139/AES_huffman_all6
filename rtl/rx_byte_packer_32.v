module rx_byte_packer_32 (
    input  wire         clk,
    input  wire         rst_n,

    input  wire [7:0]   in_byte,
    input  wire         in_valid,
    input  wire         in_last_in_block,
    input  wire         in_last_in_frame,
    output wire         in_ready,

    output wire [31:0]  word_data,
    output wire [2:0]   word_valid_bytes,
    output wire         word_last_in_block,
    output wire         word_last_in_frame,
    output wire         word_valid,
    input  wire         word_ready,

    output wire         busy,
    output wire         block_done,
    output wire         frame_done,
    output wire         error_flag
);

    localparam [2:0] BYTE_COUNT_ZERO = 3'd0;
    localparam [2:0] BYTE_COUNT_FOUR = 3'd4;

    reg [31:0] accum_data_r;
    reg [2:0]  accum_count_r;

    reg [31:0] word_data_r;
    reg [2:0]  word_valid_bytes_r;
    reg        word_last_in_block_r;
    reg        word_last_in_frame_r;
    reg        word_valid_r;

    reg        block_done_r;
    reg        frame_done_r;
    reg        error_r;

    reg [31:0] assembled_word_w;
    reg [2:0]  next_count_w;
    reg        flush_now_w;
    reg        sanitized_last_block_w;
    reg        sanitized_last_frame_w;
    reg        illegal_frame_flag_w;

    wire can_accept_input_w;
    wire in_fire_w;
    wire out_fire_w;

    assign can_accept_input_w = !word_valid_r || word_ready;
    assign in_fire_w          = in_valid && can_accept_input_w;
    assign out_fire_w         = word_valid_r && word_ready;

    assign in_ready           = can_accept_input_w;
    assign word_data          = word_data_r;
    assign word_valid_bytes   = word_valid_bytes_r;
    assign word_last_in_block = word_last_in_block_r;
    assign word_last_in_frame = word_last_in_frame_r;
    assign word_valid         = word_valid_r;
    assign busy               = (accum_count_r != BYTE_COUNT_ZERO) || word_valid_r;
    assign block_done         = block_done_r;
    assign frame_done         = frame_done_r;
    assign error_flag         = error_r;

    always @(*) begin
        // Build the word as {byte3, byte2, byte1, byte0} while the first
        // byte accepted always lands in bits [7:0] for RV32I little-endian reads.
        assembled_word_w       = accum_data_r;
        next_count_w           = accum_count_r + 3'd1;
        sanitized_last_frame_w = in_last_in_frame;
        sanitized_last_block_w = in_last_in_block || in_last_in_frame;
        illegal_frame_flag_w   = in_last_in_frame && !in_last_in_block;

        case (accum_count_r)
            3'd0: assembled_word_w = {24'h000000, in_byte};
            3'd1: assembled_word_w = {16'h0000, in_byte, accum_data_r[7:0]};
            3'd2: assembled_word_w = {8'h00, in_byte, accum_data_r[15:0]};
            3'd3: assembled_word_w = {in_byte, accum_data_r[23:0]};
            default: assembled_word_w = {24'h000000, in_byte};
        endcase

        flush_now_w = (next_count_w == BYTE_COUNT_FOUR) || sanitized_last_block_w;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            accum_data_r          <= 32'h00000000;
            accum_count_r         <= BYTE_COUNT_ZERO;
            word_data_r           <= 32'h00000000;
            word_valid_bytes_r    <= BYTE_COUNT_ZERO;
            word_last_in_block_r  <= 1'b0;
            word_last_in_frame_r  <= 1'b0;
            word_valid_r          <= 1'b0;
            block_done_r          <= 1'b0;
            frame_done_r          <= 1'b0;
            error_r               <= 1'b0;
        end
        else begin
            block_done_r <= 1'b0;
            frame_done_r <= 1'b0;

            if (out_fire_w) begin
                if (word_last_in_block_r)
                    block_done_r <= 1'b1;

                if (word_last_in_frame_r)
                    frame_done_r <= 1'b1;

                word_valid_r         <= 1'b0;
                word_last_in_block_r <= 1'b0;
                word_last_in_frame_r <= 1'b0;
                word_valid_bytes_r   <= BYTE_COUNT_ZERO;
            end

            if (accum_count_r > 3'd3)
                error_r <= 1'b1;

            if (in_fire_w) begin
                if (illegal_frame_flag_w)
                    error_r <= 1'b1;

                if (flush_now_w) begin
                    word_data_r          <= assembled_word_w;
                    word_valid_bytes_r   <= next_count_w;
                    word_last_in_block_r <= sanitized_last_block_w;
                    word_last_in_frame_r <= sanitized_last_frame_w;
                    word_valid_r         <= 1'b1;

                    accum_data_r         <= 32'h00000000;
                    accum_count_r        <= BYTE_COUNT_ZERO;

                    if (next_count_w == BYTE_COUNT_ZERO)
                        error_r <= 1'b1;
                end
                else begin
                    accum_data_r  <= assembled_word_w;
                    accum_count_r <= next_count_w;
                end
            end
        end
    end

endmodule

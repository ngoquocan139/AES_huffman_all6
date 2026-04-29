module payload_emitter #(
    parameter BLOCK_SIZE_WIDTH   = 6,
    parameter BUFFER_ADDR_WIDTH  = 5,
    parameter SYMBOL_WIDTH       = 8,
    parameter SYMBOL_INDEX_WIDTH = 7,
    parameter CODE_LEN_WIDTH     = 5,
    parameter CODE_WIDTH         = 31,
    parameter CHUNK_DATA_WIDTH   = 32,
    parameter CHUNK_LEN_WIDTH    = 6,
    parameter [7:0] ASCII_MIN    = 8'h20,
    parameter [7:0] ASCII_MAX    = 8'h7E
)(
    input  wire                          clk,
    input  wire                          rst_n,
    input  wire                          start,

    input  wire [1:0]                    selected_mode,
    input  wire [BLOCK_SIZE_WIDTH-1:0]   block_size,

    // Read block_buffer
    output reg  [BUFFER_ADDR_WIDTH-1:0]  buffer_read_addr,
    input  wire [SYMBOL_WIDTH-1:0]       buffer_read_data,

    // Read code_len_table
    output reg  [SYMBOL_INDEX_WIDTH-1:0] code_len_read_index,
    input  wire [CODE_LEN_WIDTH-1:0]     code_len_read_data,

    // Read code_table
    output reg  [SYMBOL_INDEX_WIDTH-1:0] code_read_index,
    input  wire [CODE_WIDTH-1:0]         code_read_data,

    // Payload chunk handshake
    input  wire                          payload_ready,

    output reg  [CHUNK_DATA_WIDTH-1:0]   payload_data,
    output reg  [CHUNK_LEN_WIDTH-1:0]    payload_len,
    output reg                           payload_valid,
    output reg                           payload_last_chunk,

    output wire                          busy,
    output wire                          done,
    output reg                           error_flag
);

    localparam ST_IDLE      = 3'd0;
    localparam ST_INIT      = 3'd1;
    localparam ST_READ_BYTE = 3'd2;
    localparam ST_READ_CODE = 3'd3;
    localparam ST_PREP      = 3'd4;
    localparam ST_SEND      = 3'd5;
    localparam ST_DONE      = 3'd6;

    localparam [1:0] MODE_RAW_FULL       = 2'b00;
    localparam [1:0] MODE_RAW_PARTIAL    = 2'b01;
    localparam [1:0] MODE_COMPRESSED     = 2'b10;
    localparam [1:0] MODE_ONE_SYMBOL     = 2'b11;

    reg [2:0] state;

    reg start_d;
    wire start_pulse;

    reg [BLOCK_SIZE_WIDTH-1:0] byte_idx;

`include "huffman_symbol_map.vh"

    wire mode_is_raw_full_w;
    wire mode_is_raw_partial_w;
    wire mode_is_compressed_w;
    wire mode_is_one_symbol_w;

    wire current_byte_valid_w;
    wire [SYMBOL_INDEX_WIDTH-1:0] current_symbol_index_w;
    wire last_byte_w;
    reg  [SYMBOL_WIDTH-1:0]       current_byte_r;
    reg  [SYMBOL_INDEX_WIDTH-1:0] current_symbol_index_r;
    reg                           current_byte_valid_r;
    reg                           last_byte_r;
    reg  [CODE_LEN_WIDTH-1:0]     current_code_len_r;
    reg  [CODE_WIDTH-1:0]         current_code_r;

    assign start_pulse = start & ~start_d;

    assign mode_is_raw_full_w    = (selected_mode == MODE_RAW_FULL);
    assign mode_is_raw_partial_w = (selected_mode == MODE_RAW_PARTIAL);
    assign mode_is_compressed_w  = (selected_mode == MODE_COMPRESSED);
    assign mode_is_one_symbol_w  = (selected_mode == MODE_ONE_SYMBOL);

    assign current_byte_valid_w =
        huffman_symbol_valid(buffer_read_data);

    assign current_symbol_index_w =
        huffman_symbol_to_index(buffer_read_data);

    assign last_byte_w =
        (block_size != {BLOCK_SIZE_WIDTH{1'b0}}) &&
        (byte_idx == (block_size - {{(BLOCK_SIZE_WIDTH-1){1'b0}},1'b1}));

    assign busy = (state == ST_INIT) ||
                  (state == ST_READ_BYTE) ||
                  (state == ST_READ_CODE) ||
                  (state == ST_PREP) ||
                  (state == ST_SEND);

    assign done = (state == ST_DONE);

    // Reverse code bits so that earliest emitted bit goes to lower payload_data index
    function [CHUNK_DATA_WIDTH-1:0] reverse_code_bits;
        input [CODE_WIDTH-1:0]     code_in;
        input [CODE_LEN_WIDTH-1:0] len_in;
        integer m;
        reg [CODE_LEN_WIDTH-1:0] src_idx;
    begin
        reverse_code_bits = {CHUNK_DATA_WIDTH{1'b0}};
        for (m = 0; m < CHUNK_DATA_WIDTH; m = m + 1) begin
            if (m < len_in) begin
                src_idx = len_in
                        - {{(CODE_LEN_WIDTH-1){1'b0}}, 1'b1}
                        - m[CODE_LEN_WIDTH-1:0];
                reverse_code_bits[m] = code_in[src_idx];
            end
        end
    end
    endfunction

    // ------------------------------------------------------------
    // Read interfaces
    // ------------------------------------------------------------
    always @(*) begin
        if (state == ST_READ_BYTE)
            buffer_read_addr = byte_idx[BUFFER_ADDR_WIDTH-1:0];
        else
            buffer_read_addr = {BUFFER_ADDR_WIDTH{1'b0}};
    end

    always @(*) begin
        if ((state == ST_READ_CODE) &&
            mode_is_compressed_w &&
            current_byte_valid_r)
            code_len_read_index = current_symbol_index_r;
        else
            code_len_read_index = {SYMBOL_INDEX_WIDTH{1'b0}};
    end

    always @(*) begin
        if ((state == ST_READ_CODE) &&
            mode_is_compressed_w &&
            current_byte_valid_r)
            code_read_index = current_symbol_index_r;
        else
            code_read_index = {SYMBOL_INDEX_WIDTH{1'b0}};
    end

    // ------------------------------------------------------------
    // Main FSM
    // ------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state              <= ST_IDLE;
            start_d            <= 1'b0;
            byte_idx           <= {BLOCK_SIZE_WIDTH{1'b0}};

            payload_data       <= {CHUNK_DATA_WIDTH{1'b0}};
            payload_len        <= {CHUNK_LEN_WIDTH{1'b0}};
            payload_valid      <= 1'b0;
            payload_last_chunk <= 1'b0;

            error_flag         <= 1'b0;
            current_byte_r     <= {SYMBOL_WIDTH{1'b0}};
            current_symbol_index_r <= {SYMBOL_INDEX_WIDTH{1'b0}};
            current_byte_valid_r <= 1'b0;
            last_byte_r        <= 1'b0;
            current_code_len_r <= {CODE_LEN_WIDTH{1'b0}};
            current_code_r     <= {CODE_WIDTH{1'b0}};
        end
        else begin
            start_d <= start;

            case (state)
                ST_IDLE: begin
                    payload_valid      <= 1'b0;
                    payload_last_chunk <= 1'b0;

                    if (start_pulse)
                        state <= ST_INIT;
                end

                ST_INIT: begin
                    byte_idx           <= {BLOCK_SIZE_WIDTH{1'b0}};
                    payload_data       <= {CHUNK_DATA_WIDTH{1'b0}};
                    payload_len        <= {CHUNK_LEN_WIDTH{1'b0}};
                    payload_valid      <= 1'b0;
                    payload_last_chunk <= 1'b0;
                    error_flag         <= 1'b0;
                    current_byte_r     <= {SYMBOL_WIDTH{1'b0}};
                    current_symbol_index_r <= {SYMBOL_INDEX_WIDTH{1'b0}};
                    current_byte_valid_r <= 1'b0;
                    last_byte_r        <= 1'b0;
                    current_code_len_r <= {CODE_LEN_WIDTH{1'b0}};
                    current_code_r     <= {CODE_WIDTH{1'b0}};

                    if (block_size > 6'd32)
                        error_flag <= 1'b1;

                    // Mode/data consistency checks
                    if (mode_is_raw_full_w && (block_size != 6'd32))
                        error_flag <= 1'b1;

                    if (mode_is_raw_partial_w && (block_size == 6'd32))
                        error_flag <= 1'b1;

                    if (mode_is_one_symbol_w && (block_size == {BLOCK_SIZE_WIDTH{1'b0}}))
                        error_flag <= 1'b1;

                    // No payload for empty block
                    if (block_size == {BLOCK_SIZE_WIDTH{1'b0}})
                        state <= ST_DONE;

                    // No payload for one-symbol compressed
                    else if (mode_is_one_symbol_w)
                        state <= ST_DONE;

                    else
                        state <= ST_READ_BYTE;
                end

                ST_READ_BYTE: begin
                    current_byte_r        <= buffer_read_data;
                    current_symbol_index_r <= current_symbol_index_w;
                    current_byte_valid_r  <= current_byte_valid_w;
                    last_byte_r           <= last_byte_w;

                    if (mode_is_raw_full_w || mode_is_raw_partial_w)
                        state <= ST_PREP;
                    else if (mode_is_compressed_w)
                        state <= ST_READ_CODE;
                    else begin
                        error_flag <= 1'b1;
                        state      <= ST_DONE;
                    end
                end

                ST_READ_CODE: begin
                    current_code_len_r <= code_len_read_data;
                    current_code_r     <= code_read_data;
                    state              <= ST_PREP;
                end

                ST_PREP: begin
                    payload_data       <= {CHUNK_DATA_WIDTH{1'b0}};
                    payload_len        <= {CHUNK_LEN_WIDTH{1'b0}};
                    payload_valid      <= 1'b0;
                    payload_last_chunk <= 1'b0;

                    // RAW_FULL and RAW_PARTIAL both emit raw bytes
                    if (mode_is_raw_full_w || mode_is_raw_partial_w) begin
                        payload_data[7:0] <= current_byte_r;
                        payload_len        <= 6'd8;
                        payload_valid      <= 1'b1;
                        payload_last_chunk <= last_byte_r;
                        state              <= ST_SEND;
                    end

                    // Standard COMPRESSED mode
                    else if (mode_is_compressed_w) begin
                        if (!current_byte_valid_r) begin
                            error_flag <= 1'b1;
                            state      <= ST_DONE;
                        end
                        else if (current_code_len_r == {CODE_LEN_WIDTH{1'b0}}) begin
                            error_flag <= 1'b1;
                            state      <= ST_DONE;
                        end
                        else begin
                            payload_data       <= reverse_code_bits(current_code_r, current_code_len_r);
                            payload_len        <= {{(CHUNK_LEN_WIDTH-CODE_LEN_WIDTH){1'b0}}, current_code_len_r};
                            payload_valid      <= 1'b1;
                            payload_last_chunk <= last_byte_r;
                            state              <= ST_SEND;
                        end
                    end

                    // Undefined mode should not happen
                    else begin
                        error_flag <= 1'b1;
                        state      <= ST_DONE;
                    end
                end

                ST_SEND: begin
                    if (payload_valid && payload_ready) begin
                        if (payload_last_chunk) begin
                            payload_valid <= 1'b0;
                            state         <= ST_DONE;
                        end
                        else begin
                            byte_idx      <= byte_idx +
                                             {{(BLOCK_SIZE_WIDTH-1){1'b0}},1'b1};
                            payload_valid <= 1'b0;
                            state         <= ST_READ_BYTE;
                        end
                    end
                end

                ST_DONE: begin
                    if (start_pulse)
                        state <= ST_INIT;
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule

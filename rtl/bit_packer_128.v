module bit_packer_128 #(
    parameter CHUNK_DATA_WIDTH      = 32,
    parameter CHUNK_LEN_WIDTH       = 6,
    parameter TRANSPORT_WORD_WIDTH  = 128,
    parameter VALID_BITS_WIDTH      = 7
)(
    input  wire                              clk,
    input  wire                              rst_n,

    // Input stream from dynamic_huffman_encoder
    input  wire [CHUNK_DATA_WIDTH-1:0]       stream_data,
    input  wire [CHUNK_LEN_WIDTH-1:0]        stream_len,
    input  wire                              stream_valid,
    input  wire                              stream_last,
    input  wire                              flush_on_last,
    output wire                              stream_ready,

    // 128-bit transport word to AES
    output wire [TRANSPORT_WORD_WIDTH-1:0]   transport_word_out,
    output wire                              transport_word_valid,
    input  wire                              transport_word_ready,

    // Status
    output wire                              busy,
    output wire                              done,
    output wire                              error_flag
);

    localparam TRANSPORT_PAYLOAD_WIDTH = TRANSPORT_WORD_WIDTH - 1 - VALID_BITS_WIDTH; // 120
    localparam PAYLOAD_COUNT_WIDTH     = VALID_BITS_WIDTH;                              // enough for 0..120
    localparam COMBINED_WIDTH          = TRANSPORT_PAYLOAD_WIDTH + CHUNK_DATA_WIDTH;    // 152

    reg  [TRANSPORT_PAYLOAD_WIDTH-1:0] payload_buf_r,   payload_buf_n;
    reg  [PAYLOAD_COUNT_WIDTH-1:0]     payload_count_r, payload_count_n;

    reg  [TRANSPORT_WORD_WIDTH-1:0]    transport_word_r,  transport_word_n;
    reg                                transport_valid_r, transport_valid_n;

    reg  [CHUNK_DATA_WIDTH-1:0]        pending_payload_r, pending_payload_n;
    reg  [VALID_BITS_WIDTH-1:0]        pending_len_r,     pending_len_n;
    reg                                pending_valid_r, pending_valid_n;

    reg                                busy_r,  busy_n;
    reg                                done_r,  done_n;
    reg                                error_r, error_n;

    reg  [COMBINED_WIDTH-1:0]          combined_bits;
    reg  [TRANSPORT_PAYLOAD_WIDTH-1:0] first_payload_bits;
    reg  [CHUNK_DATA_WIDTH-1:0]        rem_payload_bits;

    integer                            i;
    integer                            total_bits;
    integer                            rem_bits;
    integer                            payload_count_int;
    integer                            stream_len_int;

    assign stream_ready         = (!transport_valid_r) && (!pending_valid_r) && (!error_r);
    assign transport_word_out   = transport_word_r;
    assign transport_word_valid = transport_valid_r;
    assign busy                 = busy_r;
    assign done                 = done_r;
    assign error_flag           = error_r;

    always @(*) begin
        // Defaults
        payload_buf_n      = payload_buf_r;
        payload_count_n    = payload_count_r;
        transport_word_n   = transport_word_r;
        transport_valid_n  = transport_valid_r;
        pending_payload_n  = pending_payload_r;
        pending_len_n      = pending_len_r;
        pending_valid_n    = pending_valid_r;
        busy_n             = busy_r;
        done_n             = 1'b0; // pulse
        error_n            = error_r;

        combined_bits      = {COMBINED_WIDTH{1'b0}};
        first_payload_bits = {TRANSPORT_PAYLOAD_WIDTH{1'b0}};
        rem_payload_bits   = {CHUNK_DATA_WIDTH{1'b0}};
        total_bits         = 0;
        rem_bits           = 0;
        payload_count_int  = {{(32-PAYLOAD_COUNT_WIDTH){1'b0}}, payload_count_r};
        stream_len_int     = {{(32-CHUNK_LEN_WIDTH){1'b0}}, stream_len};

        // --------------------------------------------------------------------
        // 1) Output side: current transport word accepted by downstream
        // --------------------------------------------------------------------
        if (transport_valid_r && transport_word_ready) begin
            if (transport_word_r[TRANSPORT_WORD_WIDTH-1]) begin
                // Accepted current final word
                transport_valid_n = 1'b0;
                busy_n            = 1'b0;
                done_n            = 1'b1;
                payload_buf_n     = {TRANSPORT_PAYLOAD_WIDTH{1'b0}};
                payload_count_n   = {PAYLOAD_COUNT_WIDTH{1'b0}};
                pending_payload_n = {CHUNK_DATA_WIDTH{1'b0}};
                pending_len_n     = {VALID_BITS_WIDTH{1'b0}};
                pending_valid_n   = 1'b0;
            end
            else if (pending_valid_r) begin
                // Current word accepted, move pending final word into output
                transport_word_n  = {1'b1,
                                     pending_len_r,
                                     {{(TRANSPORT_PAYLOAD_WIDTH-CHUNK_DATA_WIDTH){1'b0}},
                                      pending_payload_r}};
                transport_valid_n = 1'b1;
                pending_payload_n = {CHUNK_DATA_WIDTH{1'b0}};
                pending_len_n     = {VALID_BITS_WIDTH{1'b0}};
                pending_valid_n   = 1'b0;
            end
            else begin
                // Current non-final word accepted, no pending word
                transport_valid_n = 1'b0;
            end
        end

        // --------------------------------------------------------------------
        // 2) Input side: accept a new encoder chunk
        // --------------------------------------------------------------------
        else if (stream_valid && stream_ready) begin
            busy_n = 1'b1;

            // Basic protocol checks
            if ((stream_len == {CHUNK_LEN_WIDTH{1'b0}}) ||
                (stream_len > CHUNK_DATA_WIDTH[CHUNK_LEN_WIDTH-1:0])) begin
                error_n = 1'b1;
                busy_n  = 1'b0;
            end
            else begin
                // Build combined bit vector:
                // existing buffered bits first, then new chunk bits
                for (i = 0; i < TRANSPORT_PAYLOAD_WIDTH; i = i + 1) begin
                    if (i < payload_count_int)
                        combined_bits[i] = payload_buf_r[i];
                end

                for (i = 0; i < CHUNK_DATA_WIDTH; i = i + 1) begin
                    if (i < stream_len_int)
                        combined_bits[payload_count_int + i] = stream_data[i];
                end

                total_bits = payload_count_int + stream_len_int;

                if (stream_last && flush_on_last) begin
                    // ---------------------------------------------------------
                    // Final chunk of current packet
                    // ---------------------------------------------------------
                    if (total_bits <= TRANSPORT_PAYLOAD_WIDTH) begin
                        for (i = 0; i < TRANSPORT_PAYLOAD_WIDTH; i = i + 1) begin
                            if (i < total_bits)
                                first_payload_bits[i] = combined_bits[i];
                            else
                                first_payload_bits[i] = 1'b0;
                        end

                        transport_word_n  = {1'b1, total_bits[VALID_BITS_WIDTH-1:0], first_payload_bits};
                        transport_valid_n = 1'b1;

                        payload_buf_n     = {TRANSPORT_PAYLOAD_WIDTH{1'b0}};
                        payload_count_n   = {PAYLOAD_COUNT_WIDTH{1'b0}};
                        pending_payload_n = {CHUNK_DATA_WIDTH{1'b0}};
                        pending_len_n     = {VALID_BITS_WIDTH{1'b0}};
                        pending_valid_n   = 1'b0;
                    end
                    else begin
                        // Need two transport words:
                        // first = full non-final word
                        // second = final partial word
                        rem_bits = total_bits - TRANSPORT_PAYLOAD_WIDTH;

                        for (i = 0; i < TRANSPORT_PAYLOAD_WIDTH; i = i + 1)
                            first_payload_bits[i] = combined_bits[i];

                        for (i = 0; i < CHUNK_DATA_WIDTH; i = i + 1) begin
                            if (i < rem_bits)
                                rem_payload_bits[i] = combined_bits[TRANSPORT_PAYLOAD_WIDTH + i];
                            else
                                rem_payload_bits[i] = 1'b0;
                        end

                        transport_word_n  = {1'b0, TRANSPORT_PAYLOAD_WIDTH[VALID_BITS_WIDTH-1:0], first_payload_bits};
                        transport_valid_n = 1'b1;

                        pending_payload_n = rem_payload_bits;
                        pending_len_n     = rem_bits[VALID_BITS_WIDTH-1:0];
                        pending_valid_n   = 1'b1;

                        payload_buf_n     = {TRANSPORT_PAYLOAD_WIDTH{1'b0}};
                        payload_count_n   = {PAYLOAD_COUNT_WIDTH{1'b0}};
                    end
                end
                else begin
                    // ---------------------------------------------------------
                    // Non-final chunk
                    // ---------------------------------------------------------
                    if (total_bits < TRANSPORT_PAYLOAD_WIDTH) begin
                        payload_buf_n = {TRANSPORT_PAYLOAD_WIDTH{1'b0}};
                        for (i = 0; i < TRANSPORT_PAYLOAD_WIDTH; i = i + 1) begin
                            if (i < total_bits)
                                payload_buf_n[i] = combined_bits[i];
                        end
                        payload_count_n = total_bits[PAYLOAD_COUNT_WIDTH-1:0];
                    end
                    else if (total_bits == TRANSPORT_PAYLOAD_WIDTH) begin
                        for (i = 0; i < TRANSPORT_PAYLOAD_WIDTH; i = i + 1)
                            first_payload_bits[i] = combined_bits[i];

                        transport_word_n  = {1'b0, TRANSPORT_PAYLOAD_WIDTH[VALID_BITS_WIDTH-1:0], first_payload_bits};
                        transport_valid_n = 1'b1;

                        payload_buf_n     = {TRANSPORT_PAYLOAD_WIDTH{1'b0}};
                        payload_count_n   = {PAYLOAD_COUNT_WIDTH{1'b0}};
                    end
                    else begin
                        rem_bits = total_bits - TRANSPORT_PAYLOAD_WIDTH;

                        for (i = 0; i < TRANSPORT_PAYLOAD_WIDTH; i = i + 1)
                            first_payload_bits[i] = combined_bits[i];

                        payload_buf_n = {TRANSPORT_PAYLOAD_WIDTH{1'b0}};
                        for (i = 0; i < CHUNK_DATA_WIDTH; i = i + 1) begin
                            if (i < rem_bits)
                                payload_buf_n[i] = combined_bits[TRANSPORT_PAYLOAD_WIDTH + i];
                        end

                        transport_word_n  = {1'b0, TRANSPORT_PAYLOAD_WIDTH[VALID_BITS_WIDTH-1:0], first_payload_bits};
                        transport_valid_n = 1'b1;
                        payload_count_n   = rem_bits[PAYLOAD_COUNT_WIDTH-1:0];
                    end
                end
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            payload_buf_r     <= {TRANSPORT_PAYLOAD_WIDTH{1'b0}};
            payload_count_r   <= {PAYLOAD_COUNT_WIDTH{1'b0}};
            transport_word_r  <= {TRANSPORT_WORD_WIDTH{1'b0}};
            transport_valid_r <= 1'b0;
            pending_payload_r <= {CHUNK_DATA_WIDTH{1'b0}};
            pending_len_r     <= {VALID_BITS_WIDTH{1'b0}};
            pending_valid_r   <= 1'b0;
            busy_r            <= 1'b0;
            done_r            <= 1'b0;
            error_r           <= 1'b0;
        end
        else begin
            payload_buf_r     <= payload_buf_n;
            payload_count_r   <= payload_count_n;
            transport_word_r  <= transport_word_n;
            transport_valid_r <= transport_valid_n;
            pending_payload_r <= pending_payload_n;
            pending_len_r     <= pending_len_n;
            pending_valid_r   <= pending_valid_n;
            busy_r            <= busy_n;
            done_r            <= done_n;
            error_r           <= error_n;
        end
    end

endmodule

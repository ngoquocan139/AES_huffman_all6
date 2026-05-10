module bit_depacker_128 #(
    parameter CHUNK_DATA_WIDTH      = 32,
    parameter CHUNK_LEN_WIDTH       = 6,
    parameter TRANSPORT_WORD_WIDTH  = 128,
    parameter VALID_BITS_WIDTH      = 7
)(
    input  wire                              clk,
    input  wire                              rst_n,

    // 128-bit transport word input
    input  wire [TRANSPORT_WORD_WIDTH-1:0]   transport_word_in,
    input  wire                              transport_word_valid,
    output wire                              transport_word_ready,

    // Recovered bitstream output
    output wire [CHUNK_DATA_WIDTH-1:0]       stream_data,
    output wire [CHUNK_LEN_WIDTH-1:0]        stream_len,
    output wire                              stream_valid,
    output wire                              stream_last,
    input  wire                              stream_ready,

    // Status
    output wire                              busy,
    output wire                              done,
    output wire                              error_flag
);

    localparam integer TRANSPORT_PAYLOAD_WIDTH = TRANSPORT_WORD_WIDTH - 1 - VALID_BITS_WIDTH;
    localparam integer BUFFER_WIDTH            = TRANSPORT_PAYLOAD_WIDTH + CHUNK_DATA_WIDTH;
    localparam integer BUFFER_COUNT_WIDTH      = VALID_BITS_WIDTH + CHUNK_LEN_WIDTH;
    localparam [VALID_BITS_WIDTH-1:0] TRANSPORT_PAYLOAD_LEN = TRANSPORT_PAYLOAD_WIDTH[VALID_BITS_WIDTH-1:0];
    localparam [CHUNK_LEN_WIDTH-1:0]  CHUNK_DATA_LEN        = CHUNK_DATA_WIDTH[CHUNK_LEN_WIDTH-1:0];

    reg  [BUFFER_WIDTH-1:0]           bit_buffer_r, bit_buffer_n;
    reg  [BUFFER_COUNT_WIDTH-1:0]     bit_count_r, bit_count_n;
    reg                               frame_active_r, frame_active_n;
    reg                               frame_last_pending_r, frame_last_pending_n;

    reg  [CHUNK_DATA_WIDTH-1:0]       stream_data_r, stream_data_n;
    reg  [CHUNK_LEN_WIDTH-1:0]        stream_len_r, stream_len_n;
    reg                               stream_valid_r, stream_valid_n;
    reg                               stream_last_r, stream_last_n;

    reg                               done_r, done_n;
    reg                               error_r, error_n;

    wire                              frame_last_w;
    wire [VALID_BITS_WIDTH-1:0]       valid_bits_w;
    wire [TRANSPORT_PAYLOAD_WIDTH-1:0] payload_w;

    wire                              can_emit_full_w;
    wire                              can_emit_tail_w;
    wire                              transport_word_fire_w;
    wire [BUFFER_COUNT_WIDTH-1:0]     valid_bits_ext_w;
    wire [BUFFER_WIDTH-1:0]           payload_ext_w;

    integer                           bit_count_int;
    integer                           valid_bits_int;

    assign frame_last_w          = transport_word_in[TRANSPORT_WORD_WIDTH-1];
    assign valid_bits_w          = transport_word_in[TRANSPORT_WORD_WIDTH-2:TRANSPORT_PAYLOAD_WIDTH];
    assign payload_w             = transport_word_in[TRANSPORT_PAYLOAD_WIDTH-1:0];

    assign can_emit_full_w       = (bit_count_r >= CHUNK_DATA_WIDTH);
    assign can_emit_tail_w       = frame_last_pending_r &&
                                   (bit_count_r != {BUFFER_COUNT_WIDTH{1'b0}}) &&
                                   (bit_count_r < CHUNK_DATA_WIDTH);
    assign valid_bits_ext_w      = {{(BUFFER_COUNT_WIDTH-VALID_BITS_WIDTH){1'b0}}, valid_bits_w};
    assign payload_ext_w         =
        {{(BUFFER_WIDTH-TRANSPORT_PAYLOAD_WIDTH){1'b0}}, payload_w};

    assign transport_word_ready  = (!stream_valid_r) &&
                                   (!error_r) &&
                                   (!can_emit_full_w) &&
                                   (!can_emit_tail_w);

    assign transport_word_fire_w = transport_word_valid && transport_word_ready;

    assign stream_data           = stream_data_r;
    assign stream_len            = stream_len_r;
    assign stream_valid          = stream_valid_r;
    assign stream_last           = stream_last_r;

    assign busy                  = frame_active_r ||
                                   stream_valid_r ||
                                   (bit_count_r != {BUFFER_COUNT_WIDTH{1'b0}});
    assign done                  = done_r;
    assign error_flag            = error_r;

    always @(*) begin
        bit_buffer_n         = bit_buffer_r;
        bit_count_n          = bit_count_r;
        frame_active_n       = frame_active_r;
        frame_last_pending_n = frame_last_pending_r;

        stream_data_n        = stream_data_r;
        stream_len_n         = stream_len_r;
        stream_valid_n       = stream_valid_r;
        stream_last_n        = stream_last_r;

        done_n               = 1'b0;
        error_n              = error_r;

        bit_count_int        = {{(32-BUFFER_COUNT_WIDTH){1'b0}}, bit_count_r};
        valid_bits_int       = {{(32-VALID_BITS_WIDTH){1'b0}}, valid_bits_w};
        // ------------------------------------------------------------
        // 1) Output side: current chunk accepted by downstream
        // ------------------------------------------------------------
        if (stream_valid_r && stream_ready) begin
            stream_data_n  = {CHUNK_DATA_WIDTH{1'b0}};
            stream_len_n   = {CHUNK_LEN_WIDTH{1'b0}};
            stream_valid_n = 1'b0;
            stream_last_n  = 1'b0;

            if (stream_last_r) begin
                bit_buffer_n         = {BUFFER_WIDTH{1'b0}};
                bit_count_n          = {BUFFER_COUNT_WIDTH{1'b0}};
                frame_active_n       = 1'b0;
                frame_last_pending_n = 1'b0;
                done_n               = 1'b1;
            end
        end

        // ------------------------------------------------------------
        // 2) Create a new output chunk when no pending chunk exists
        // ------------------------------------------------------------
        if (!stream_valid_n && !error_n) begin
            if (bit_count_n >= CHUNK_DATA_WIDTH) begin
                stream_data_n = bit_buffer_n[CHUNK_DATA_WIDTH-1:0];

                stream_len_n   = CHUNK_DATA_LEN;
                stream_valid_n = 1'b1;
                stream_last_n  = frame_last_pending_n &&
                                 (bit_count_n == CHUNK_DATA_WIDTH);

                bit_buffer_n = bit_buffer_n >> CHUNK_DATA_WIDTH;
                bit_count_n = bit_count_n - CHUNK_DATA_WIDTH;
            end
            else if (frame_last_pending_n &&
                     (bit_count_n != {BUFFER_COUNT_WIDTH{1'b0}})) begin
                stream_data_n = bit_buffer_n[CHUNK_DATA_WIDTH-1:0];

                stream_len_n          = bit_count_n[CHUNK_LEN_WIDTH-1:0];
                stream_valid_n        = 1'b1;
                stream_last_n         = 1'b1;
                bit_buffer_n          = {BUFFER_WIDTH{1'b0}};
                bit_count_n           = {BUFFER_COUNT_WIDTH{1'b0}};
            end
            else if (transport_word_fire_w) begin
                if ((valid_bits_w == {VALID_BITS_WIDTH{1'b0}}) ||
                    ((!frame_last_w) && (valid_bits_w != TRANSPORT_PAYLOAD_LEN)) ||
                    (frame_last_w && (valid_bits_w > TRANSPORT_PAYLOAD_LEN)) ||
                    ((bit_count_int + valid_bits_int) > BUFFER_WIDTH)) begin
                    bit_buffer_n         = {BUFFER_WIDTH{1'b0}};
                    bit_count_n          = {BUFFER_COUNT_WIDTH{1'b0}};
                    frame_active_n       = 1'b0;
                    frame_last_pending_n = 1'b0;
                    stream_data_n        = {CHUNK_DATA_WIDTH{1'b0}};
                    stream_len_n         = {CHUNK_LEN_WIDTH{1'b0}};
                    stream_valid_n       = 1'b0;
                    stream_last_n        = 1'b0;
                    error_n              = 1'b1;
                end
                else begin
                    bit_buffer_n = bit_buffer_r |
                                   (payload_ext_w << bit_count_r);
                    bit_count_n    = bit_count_r + valid_bits_ext_w;
                    frame_active_n = 1'b1;

                    if (frame_last_w)
                        frame_last_pending_n = 1'b1;
                end
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bit_buffer_r         <= {BUFFER_WIDTH{1'b0}};
            bit_count_r          <= {BUFFER_COUNT_WIDTH{1'b0}};
            frame_active_r       <= 1'b0;
            frame_last_pending_r <= 1'b0;

            stream_data_r        <= {CHUNK_DATA_WIDTH{1'b0}};
            stream_len_r         <= {CHUNK_LEN_WIDTH{1'b0}};
            stream_valid_r       <= 1'b0;
            stream_last_r        <= 1'b0;

            done_r               <= 1'b0;
            error_r              <= 1'b0;
        end
        else begin
            bit_buffer_r         <= bit_buffer_n;
            bit_count_r          <= bit_count_n;
            frame_active_r       <= frame_active_n;
            frame_last_pending_r <= frame_last_pending_n;

            stream_data_r        <= stream_data_n;
            stream_len_r         <= stream_len_n;
            stream_valid_r       <= stream_valid_n;
            stream_last_r        <= stream_last_n;

            done_r               <= done_n;
            error_r              <= error_n;
        end
    end

endmodule

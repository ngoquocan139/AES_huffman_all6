module stream_output_interface #(
    parameter STREAM_DATA_WIDTH = 32,
    parameter STREAM_LEN_WIDTH  = 6
)(
    input  wire                          clk,
    input  wire                          rst_n,
    input  wire                          start,
    input  wire                          payload_required,

    // Header side
    input  wire [STREAM_DATA_WIDTH-1:0]  hdr_data,
    input  wire [STREAM_LEN_WIDTH-1:0]   hdr_len,
    input  wire                          hdr_valid,
    input  wire                          hdr_last_chunk,
    output reg                           hdr_ready,

    // Payload side
    input  wire [STREAM_DATA_WIDTH-1:0]  payload_data,
    input  wire [STREAM_LEN_WIDTH-1:0]   payload_len,
    input  wire                          payload_valid,
    input  wire                          payload_last_chunk,
    output reg                           payload_ready,

    // Downstream unified stream
    input  wire                          stream_ready,

    output reg  [STREAM_DATA_WIDTH-1:0]  stream_data,
    output reg  [STREAM_LEN_WIDTH-1:0]   stream_len,
    output reg                           stream_valid,
    output reg                           stream_last,

    output wire                          busy,
    output reg                           done,
    output reg                           error_flag
);

    localparam ST_IDLE   = 2'd0;
    localparam ST_HEADER = 2'd1;
    localparam ST_PAYLOAD= 2'd2;
    localparam ST_DONE   = 2'd3;

    reg [1:0] state, next_state;

    reg  start_d;
    wire start_pulse;

    wire header_accept;
    wire payload_accept;

    assign start_pulse   = start & ~start_d;
    assign header_accept = (state == ST_HEADER)  && hdr_valid     && stream_ready;
    assign payload_accept= (state == ST_PAYLOAD) && payload_valid && stream_ready;

    assign busy = (state == ST_HEADER) || (state == ST_PAYLOAD);

    // ------------------------------------------------------------
    // Next-state logic
    // ------------------------------------------------------------
    always @(*) begin
        next_state = state;

        case (state)
            ST_IDLE: begin
                if (start_pulse)
                    next_state = ST_HEADER;
            end

            ST_HEADER: begin
                if (header_accept && hdr_last_chunk) begin
                    if (payload_required)
                        next_state = ST_PAYLOAD;
                    else
                        next_state = ST_DONE;
                end
            end

            ST_PAYLOAD: begin
                if (payload_accept && payload_last_chunk)
                    next_state = ST_DONE;
            end

            ST_DONE: begin
                if (start_pulse)
                    next_state = ST_HEADER;
            end

            default: begin
                next_state = ST_IDLE;
            end
        endcase
    end

    // ------------------------------------------------------------
    // Combinational routing
    // ------------------------------------------------------------
    always @(*) begin
        // defaults
        hdr_ready      = 1'b0;
        payload_ready  = 1'b0;

        stream_data    = {STREAM_DATA_WIDTH{1'b0}};
        stream_len     = {STREAM_LEN_WIDTH{1'b0}};
        stream_valid   = 1'b0;
        stream_last    = 1'b0;

        case (state)
            ST_HEADER: begin
                // Pass header through directly
                hdr_ready    = stream_ready;
                stream_data  = hdr_data;
                stream_len   = hdr_len;
                stream_valid = hdr_valid;

                // Header chunk becomes stream_last only if no payload follows
                if (!payload_required)
                    stream_last = hdr_last_chunk;
                else
                    stream_last = 1'b0;
            end

            ST_PAYLOAD: begin
                // Pass payload through directly
                payload_ready = stream_ready;
                stream_data   = payload_data;
                stream_len    = payload_len;
                stream_valid  = payload_valid;
                stream_last   = payload_last_chunk;
            end

            default: begin
                // keep defaults
            end
        endcase
    end

    // ------------------------------------------------------------
    // Sequential state / status
    // ------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= ST_IDLE;
            start_d    <= 1'b0;
            done       <= 1'b0;
            error_flag <= 1'b0;
        end
        else begin
            state   <= next_state;
            start_d <= start;

            // default done pulse = 0, raise for one cycle on final accept
            done <= 1'b0;

            if (start_pulse) begin
                error_flag <= 1'b0;
            end
            else begin
                // simple consistency checks
                if ((state == ST_HEADER) && header_accept && (hdr_len == {STREAM_LEN_WIDTH{1'b0}}))
                    error_flag <= 1'b1;

                if ((state == ST_PAYLOAD) && payload_accept && (payload_len == {STREAM_LEN_WIDTH{1'b0}}))
                    error_flag <= 1'b1;

                // final accept => done pulse
                if ((state == ST_HEADER) && header_accept && hdr_last_chunk && !payload_required)
                    done <= 1'b1;

                if ((state == ST_PAYLOAD) && payload_accept && payload_last_chunk)
                    done <= 1'b1;
            end
        end
    end

endmodule

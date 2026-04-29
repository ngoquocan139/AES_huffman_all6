module control_fsm (
    input  wire       clk,
    input  wire       rst_n,

    // top-level request
    input  wire       start_block,
    input  wire       whole_file_enable,
    input  wire       whole_file_table_valid,

    // status from input_collect_unit
    input  wire       collect_done,
    input  wire       collect_busy,
    input  wire       collect_protocol_error,
    input  wire       collect_overflow_error,

    // status from huffman_builder
    input  wire       build_done,
    input  wire       build_busy,
    input  wire       build_error,

    // status from mode_decision_logic
    input  wire       mode_done,
    input  wire       mode_busy,
    input  wire       mode_error,
    input  wire [1:0] selected_mode,

    // status from emit_backend
    input  wire       emit_done,
    input  wire       emit_busy,
    input  wire       emit_error,

    // one-cycle start pulses
    output reg        start_collect,
    output reg        start_build,
    output reg        start_mode_decision,
    output reg        start_emit,

    // latched decision for current block
    output reg [1:0]  mode_selected_latched,

    // top-level status
    output reg        busy,
    output reg        done,
    output reg        error_flag,

    // debug/state
    output reg [3:0]  state
);

    localparam ST_IDLE          = 4'd0;
    localparam ST_START_COLLECT = 4'd1;
    localparam ST_WAIT_COLLECT  = 4'd2;
    localparam ST_START_BUILD   = 4'd3;
    localparam ST_WAIT_BUILD    = 4'd4;
    localparam ST_START_MODE    = 4'd5;
    localparam ST_WAIT_MODE     = 4'd6;
    localparam ST_START_EMIT    = 4'd7;
    localparam ST_WAIT_EMIT     = 4'd8;
    localparam ST_DONE          = 4'd9;
    localparam ST_ERROR         = 4'd10;

    localparam [1:0] MODE_COMPRESSED = 2'b10;

    reg [3:0] next_state;

    wire collect_error_w;
    wire any_sub_busy_w;

    assign collect_error_w = collect_protocol_error | collect_overflow_error;
    assign any_sub_busy_w  = collect_busy | build_busy | mode_busy | emit_busy;

    // ------------------------------------------------------------
    // Next-state logic
    // ------------------------------------------------------------
    always @(*) begin
        next_state = state;

        case (state)
            ST_IDLE: begin
                if (start_block)
                    next_state = ST_START_COLLECT;
            end

            ST_START_COLLECT: begin
                next_state = ST_WAIT_COLLECT;
            end

            ST_WAIT_COLLECT: begin
                if (collect_error_w)
                    next_state = ST_ERROR;
                else if (collect_done && whole_file_enable && whole_file_table_valid)
                    next_state = ST_START_EMIT;
                else if (collect_done && whole_file_enable && !whole_file_table_valid)
                    next_state = ST_ERROR;
                else if (collect_done)
                    next_state = ST_START_BUILD;
            end

            ST_START_BUILD: begin
                next_state = ST_WAIT_BUILD;
            end

            ST_WAIT_BUILD: begin
                if (build_error)
                    next_state = ST_ERROR;
                else if (build_done)
                    next_state = ST_START_MODE;
            end

            ST_START_MODE: begin
                next_state = ST_WAIT_MODE;
            end

            ST_WAIT_MODE: begin
                if (mode_error)
                    next_state = ST_ERROR;
                else if (mode_done)
                    next_state = ST_START_EMIT;
            end

            ST_START_EMIT: begin
                next_state = ST_WAIT_EMIT;
            end

            ST_WAIT_EMIT: begin
                if (emit_error)
                    next_state = ST_ERROR;
                else if (emit_done)
                    next_state = ST_DONE;
            end

            ST_DONE: begin
                next_state = ST_IDLE;
            end

            ST_ERROR: begin
                next_state = ST_IDLE;
            end

            default: begin
                next_state = ST_IDLE;
            end
        endcase
    end

    // ------------------------------------------------------------
    // Output decode
    // ------------------------------------------------------------
    always @(*) begin
        start_collect       = 1'b0;
        start_build         = 1'b0;
        start_mode_decision = 1'b0;
        start_emit          = 1'b0;

        done = 1'b0;
        busy = 1'b0;

        case (state)
            ST_START_COLLECT: begin
                start_collect = 1'b1;
                busy          = 1'b1;
            end

            ST_WAIT_COLLECT: begin
                busy = 1'b1;
            end

            ST_START_BUILD: begin
                start_build = 1'b1;
                busy        = 1'b1;
            end

            ST_WAIT_BUILD: begin
                busy = 1'b1;
            end

            ST_START_MODE: begin
                start_mode_decision = 1'b1;
                busy                = 1'b1;
            end

            ST_WAIT_MODE: begin
                busy = 1'b1;
            end

            ST_START_EMIT: begin
                start_emit = 1'b1;
                busy       = 1'b1;
            end

            ST_WAIT_EMIT: begin
                busy = 1'b1;
            end

            ST_DONE: begin
                done = 1'b1;
                busy = 1'b0;
            end

            ST_ERROR: begin
                busy = 1'b0;
            end

            default: begin
                busy = 1'b0;
            end
        endcase

        // optional safety: if a submodule still says busy, keep top busy high
        if (any_sub_busy_w)
            busy = 1'b1;
    end

    // ------------------------------------------------------------
    // Sequential state / flags / latched mode
    // ------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state                 <= ST_IDLE;
            error_flag            <= 1'b0;
            mode_selected_latched <= 2'b00;
        end
        else begin
            state <= next_state;

            // clear error at new block request from IDLE
            if ((state == ST_IDLE) && start_block)
                error_flag <= 1'b0;
            else if ((state == ST_WAIT_COLLECT) && collect_error_w)
                error_flag <= 1'b1;
            else if ((state == ST_WAIT_BUILD) && build_error)
                error_flag <= 1'b1;
            else if ((state == ST_WAIT_MODE) && mode_error)
                error_flag <= 1'b1;
            else if ((state == ST_WAIT_EMIT) && emit_error)
                error_flag <= 1'b1;

            // latch mode once mode_decision_logic completes successfully
            if ((state == ST_WAIT_MODE) && mode_done && !mode_error)
                mode_selected_latched <= selected_mode;
            else if ((state == ST_WAIT_COLLECT) && collect_done &&
                     whole_file_enable && whole_file_table_valid)
                mode_selected_latched <= MODE_COMPRESSED;
        end
    end

endmodule

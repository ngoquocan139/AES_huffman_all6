`timescale 1ns/1ps

module test_bench;

    parameter CHUNK_DATA_WIDTH      = 32;
    parameter CHUNK_LEN_WIDTH       = 6;
    parameter TRANSPORT_WORD_WIDTH  = 128;
    parameter VALID_BITS_WIDTH      = 7;

    localparam integer TRANSPORT_PAYLOAD_WIDTH = TRANSPORT_WORD_WIDTH - 1 - VALID_BITS_WIDTH;
    localparam integer MAX_FRAME_BITS          = 512;
    localparam integer MAX_CAPTURE_CHUNKS      = 64;
    localparam integer TB_DLY                  = 2;

    reg                               clk;
    reg                               rst_n;

    reg  [TRANSPORT_WORD_WIDTH-1:0]   transport_word_in;
    reg                               transport_word_valid;
    wire                              transport_word_ready;

    wire [CHUNK_DATA_WIDTH-1:0]       stream_data;
    wire [CHUNK_LEN_WIDTH-1:0]        stream_len;
    wire                              stream_valid;
    wire                              stream_last;
    reg                               stream_ready;

    wire                              busy;
    wire                              done;
    wire                              error_flag;

    reg  [CHUNK_DATA_WIDTH-1:0]       expected_data [0:MAX_CAPTURE_CHUNKS-1];
    reg  [CHUNK_LEN_WIDTH-1:0]        expected_len  [0:MAX_CAPTURE_CHUNKS-1];
    reg                               expected_last [0:MAX_CAPTURE_CHUNKS-1];

    reg  [CHUNK_DATA_WIDTH-1:0]       actual_data [0:MAX_CAPTURE_CHUNKS-1];
    reg  [CHUNK_LEN_WIDTH-1:0]        actual_len  [0:MAX_CAPTURE_CHUNKS-1];
    reg                               actual_last [0:MAX_CAPTURE_CHUNKS-1];

    reg  [MAX_FRAME_BITS-1:0]         frame_bits_a;
    reg  [MAX_FRAME_BITS-1:0]         frame_bits_b;

    integer                           expected_count;
    integer                           actual_count;
    integer                           pass_count;
    integer                           fail_count;
    integer                           done_pulse_count;
    integer                           transport_fire_count;
    integer                           expected_word_count;

    integer                           ready_mode_r;
    integer                           ready_stall_cycles_r;
    integer                           ready_stall_count_r;
    reg                               chunk_fire_r;

    integer                           i;
    integer                           bit_idx;
    integer                           base_idx;
    integer                           chunk_len_i;
    integer                           word_len_i;
    integer                           timeout_i;
    reg                               frame_last_v;
    reg  [VALID_BITS_WIDTH-1:0]       valid_bits_v;
    reg  [TRANSPORT_PAYLOAD_WIDTH-1:0] payload_v;
    reg  [TRANSPORT_WORD_WIDTH-1:0]   transport_word_v;

    bit_depacker_128 #(
        .CHUNK_DATA_WIDTH     (CHUNK_DATA_WIDTH),
        .CHUNK_LEN_WIDTH      (CHUNK_LEN_WIDTH),
        .TRANSPORT_WORD_WIDTH (TRANSPORT_WORD_WIDTH),
        .VALID_BITS_WIDTH     (VALID_BITS_WIDTH)
    ) dut (
        .clk                  (clk),
        .rst_n                (rst_n),
        .transport_word_in    (transport_word_in),
        .transport_word_valid (transport_word_valid),
        .transport_word_ready (transport_word_ready),
        .stream_data          (stream_data),
        .stream_len           (stream_len),
        .stream_valid         (stream_valid),
        .stream_last          (stream_last),
        .stream_ready         (stream_ready),
        .busy                 (busy),
        .done                 (done),
        .error_flag           (error_flag)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // Capture handshakes exactly at the active clock edge seen by the DUT.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            actual_count         <= 0;
            done_pulse_count     <= 0;
            transport_fire_count <= 0;
            chunk_fire_r         <= 1'b0;
        end
        else begin
            chunk_fire_r <= stream_valid && stream_ready;

            if (transport_word_valid && transport_word_ready)
                transport_fire_count <= transport_fire_count + 1;

            if (done)
                done_pulse_count <= done_pulse_count + 1;

            if (stream_valid && stream_ready) begin
                if (actual_count < MAX_CAPTURE_CHUNKS) begin
                    actual_data[actual_count] <= stream_data;
                    actual_len [actual_count] <= stream_len;
                    actual_last[actual_count] <= stream_last;
                    actual_count              <= actual_count + 1;
                end
                else begin
                    $display("[FAIL] actual capture overflow");
                    fail_count <= fail_count + 1;
                end
            end
        end
    end

    // Ready generator:
    // mode 0: always ready
    // mode 1: stall each chunk for N cycles before allowing one handshake
    always @(negedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stream_ready         <= 1'b0;
            ready_stall_count_r  <= 0;
        end
        else begin
            case (ready_mode_r)
                0: begin
                    stream_ready        <= 1'b1;
                    ready_stall_count_r <= ready_stall_cycles_r;
                end

                default: begin
                    if (chunk_fire_r) begin
                        stream_ready        <= 1'b0;
                        ready_stall_count_r <= ready_stall_cycles_r;
                    end
                    else if (stream_valid) begin
                        if (ready_stall_count_r > 0) begin
                            stream_ready        <= 1'b0;
                            ready_stall_count_r <= ready_stall_count_r - 1;
                        end
                        else begin
                            stream_ready <= 1'b1;
                        end
                    end
                    else begin
                        stream_ready        <= 1'b0;
                        ready_stall_count_r <= ready_stall_cycles_r;
                    end
                end
            endcase
        end
    end

    task clear_inputs;
    begin
        transport_word_in    = {TRANSPORT_WORD_WIDTH{1'b0}};
        transport_word_valid = 1'b0;
        ready_mode_r         = 0;
        ready_stall_cycles_r = 0;
        ready_stall_count_r  = 0;
    end
    endtask

    task clear_scoreboard;
    begin
        expected_count       = 0;
        expected_word_count  = 0;
        actual_count         = 0;
        done_pulse_count     = 0;
        transport_fire_count = 0;
        chunk_fire_r         = 1'b0;

        for (i = 0; i < MAX_CAPTURE_CHUNKS; i = i + 1) begin
            expected_data[i] = {CHUNK_DATA_WIDTH{1'b0}};
            expected_len[i]  = {CHUNK_LEN_WIDTH{1'b0}};
            expected_last[i] = 1'b0;

            actual_data[i]   = {CHUNK_DATA_WIDTH{1'b0}};
            actual_len[i]    = {CHUNK_LEN_WIDTH{1'b0}};
            actual_last[i]   = 1'b0;
        end
    end
    endtask

    task reset_dut;
    begin
        clear_inputs;
        clear_scoreboard;
        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        #TB_DLY;
        rst_n = 1'b1;
        repeat (4) @(posedge clk);
        #TB_DLY;
    end
    endtask

    task check1;
        input actual;
        input expected;
        input [8*96-1:0] name;
    begin
        if (actual === expected) begin
            $display("[PASS] %0s | actual=%0d expected=%0d", name, actual, expected);
            pass_count = pass_count + 1;
        end
        else begin
            $display("[FAIL] %0s | actual=%0d expected=%0d", name, actual, expected);
            fail_count = fail_count + 1;
        end
    end
    endtask

    task check_int;
        input integer actual;
        input integer expected;
        input [8*96-1:0] name;
    begin
        if (actual == expected) begin
            $display("[PASS] %0s | actual=%0d expected=%0d", name, actual, expected);
            pass_count = pass_count + 1;
        end
        else begin
            $display("[FAIL] %0s | actual=%0d expected=%0d", name, actual, expected);
            fail_count = fail_count + 1;
        end
    end
    endtask

    task gen_frame_pattern;
        output [MAX_FRAME_BITS-1:0] bits;
        input integer num_bits;
        input integer seed;
        integer idx;
        integer mix_v;
    begin
        bits = {MAX_FRAME_BITS{1'b0}};
        for (idx = 0; idx < num_bits; idx = idx + 1) begin
            mix_v = ((idx + seed) ^ (idx >> 1) ^ (idx << 1));
            bits[idx] = mix_v[0];
        end
    end
    endtask

    task build_expected_chunks;
        input [MAX_FRAME_BITS-1:0] bits;
        input integer num_bits;
    begin
        expected_count      = 0;
        expected_word_count = (num_bits + TRANSPORT_PAYLOAD_WIDTH - 1) / TRANSPORT_PAYLOAD_WIDTH;

        base_idx = 0;
        while (base_idx < num_bits) begin
            if ((num_bits - base_idx) >= CHUNK_DATA_WIDTH)
                chunk_len_i = CHUNK_DATA_WIDTH;
            else
                chunk_len_i = num_bits - base_idx;

            expected_data[expected_count] = {CHUNK_DATA_WIDTH{1'b0}};
            for (bit_idx = 0; bit_idx < chunk_len_i; bit_idx = bit_idx + 1)
                expected_data[expected_count][bit_idx] = bits[base_idx + bit_idx];

            expected_len [expected_count] = chunk_len_i[CHUNK_LEN_WIDTH-1:0];
            expected_last[expected_count] = ((base_idx + chunk_len_i) == num_bits);
            expected_count                = expected_count + 1;
            base_idx                     = base_idx + chunk_len_i;
        end
    end
    endtask

    task send_transport_word;
        input frame_last_i;
        input [VALID_BITS_WIDTH-1:0] valid_bits_i;
        input [TRANSPORT_PAYLOAD_WIDTH-1:0] payload_i;
    begin : send_transport_word_blk
        transport_word_v = {frame_last_i, valid_bits_i, payload_i};

        @(negedge clk);
        #TB_DLY;
        transport_word_in    = transport_word_v;
        transport_word_valid = 1'b1;

        timeout_i = 0;
        while (!(transport_word_valid && transport_word_ready)) begin
            @(posedge clk);
            @(negedge clk);
            #TB_DLY;
            timeout_i = timeout_i + 1;
            if (timeout_i > 5000) begin
                $display("[FAIL] send_transport_word timeout");
                fail_count = fail_count + 1;
                transport_word_in    = {TRANSPORT_WORD_WIDTH{1'b0}};
                transport_word_valid = 1'b0;
                disable send_transport_word_blk;
            end
        end

        @(posedge clk);
        @(negedge clk);
        #TB_DLY;
        transport_word_in    = {TRANSPORT_WORD_WIDTH{1'b0}};
        transport_word_valid = 1'b0;
    end
    endtask

    task send_frame;
        input [MAX_FRAME_BITS-1:0] bits;
        input integer num_bits;
    begin
        base_idx = 0;
        while (base_idx < num_bits) begin
            if ((num_bits - base_idx) >= TRANSPORT_PAYLOAD_WIDTH)
                word_len_i = TRANSPORT_PAYLOAD_WIDTH;
            else
                word_len_i = num_bits - base_idx;

            payload_v = {TRANSPORT_PAYLOAD_WIDTH{1'b0}};
            for (bit_idx = 0; bit_idx < word_len_i; bit_idx = bit_idx + 1)
                payload_v[bit_idx] = bits[base_idx + bit_idx];

            frame_last_v = ((base_idx + word_len_i) == num_bits);
            valid_bits_v = word_len_i[VALID_BITS_WIDTH-1:0];

            send_transport_word(frame_last_v, valid_bits_v, payload_v);
            base_idx = base_idx + word_len_i;
        end
    end
    endtask

    task wait_done_or_error;
        output integer got_done;
        output integer got_error;
        input integer max_cycles;
        integer polls;
    begin
        got_done  = 0;
        got_error = 0;
        polls     = 0;

        while ((polls < max_cycles) && (got_done == 0) && (got_error == 0)) begin
            @(posedge clk);
            #TB_DLY;
            if (done_pulse_count > 0)
                got_done = 1;
            if (error_flag)
                got_error = 1;
            polls = polls + 1;
        end

        if ((got_done == 0) && (got_error == 0)) begin
            $display("[FAIL] wait_done_or_error timeout");
            fail_count = fail_count + 1;
        end
    end
    endtask

    task wait_error_only;
        output integer got_error;
        input integer max_cycles;
        integer polls;
    begin
        got_error = 0;
        polls     = 0;

        while ((polls < max_cycles) && (got_error == 0)) begin
            @(posedge clk);
            #TB_DLY;
            if (error_flag)
                got_error = 1;
            polls = polls + 1;
        end

        if (got_error == 0) begin
            $display("[FAIL] wait_error_only timeout");
            fail_count = fail_count + 1;
        end
    end
    endtask

    task compare_captured_chunks;
        input [8*96-1:0] test_name;
    begin
        check_int(actual_count, expected_count, test_name);

        for (i = 0; i < expected_count; i = i + 1) begin
            if (actual_data[i] === expected_data[i]) begin
                $display("[PASS] %0s chunk[%0d] data match", test_name, i);
                pass_count = pass_count + 1;
            end
            else begin
                $display("[FAIL] %0s chunk[%0d] data mismatch", test_name, i);
                $display("       actual   = 0x%08x", actual_data[i]);
                $display("       expected = 0x%08x", expected_data[i]);
                fail_count = fail_count + 1;
            end

            if (actual_len[i] === expected_len[i]) begin
                $display("[PASS] %0s chunk[%0d] len match", test_name, i);
                pass_count = pass_count + 1;
            end
            else begin
                $display("[FAIL] %0s chunk[%0d] len mismatch | actual=%0d expected=%0d",
                         test_name, i, actual_len[i], expected_len[i]);
                fail_count = fail_count + 1;
            end

            if (actual_last[i] === expected_last[i]) begin
                $display("[PASS] %0s chunk[%0d] last match", test_name, i);
                pass_count = pass_count + 1;
            end
            else begin
                $display("[FAIL] %0s chunk[%0d] last mismatch | actual=%0d expected=%0d",
                         test_name, i, actual_last[i], expected_last[i]);
                fail_count = fail_count + 1;
            end
        end
    end
    endtask

    task run_valid_frame_case;
        input [8*96-1:0] test_name;
        input [MAX_FRAME_BITS-1:0] bits;
        input integer num_bits;
        input integer ready_mode_i;
        input integer ready_stall_i;
        integer got_done;
        integer got_error;
    begin
        $display("\n===== %0s =====", test_name);
        reset_dut;
        build_expected_chunks(bits, num_bits);
        ready_mode_r         = ready_mode_i;
        ready_stall_cycles_r = ready_stall_i;
        ready_stall_count_r  = ready_stall_i;

        send_frame(bits, num_bits);
        wait_done_or_error(got_done, got_error, 20000);

        check_int(got_done, 1, "frame_should_complete");
        check_int(got_error, 0, "frame_should_not_error");
        check1(error_flag, 1'b0, "error_flag_should_be_0");
        check_int(done_pulse_count, 1, "done_pulse_count_should_be_1");
        check_int(transport_fire_count, expected_word_count, "transport_word_count_should_match");
        compare_captured_chunks(test_name);

        @(posedge clk);
        #TB_DLY;
        check1(busy, 1'b0, "busy_should_return_0_after_done");
        check1(stream_valid, 1'b0, "stream_valid_should_return_0_after_done");
    end
    endtask

    task run_invalid_case_zero_valid_bits;
        integer got_error;
    begin
        $display("\n===== invalid_zero_valid_bits =====");
        reset_dut;
        ready_mode_r         = 0;
        ready_stall_cycles_r = 0;
        ready_stall_count_r  = 0;

        send_transport_word(1'b1,
                            {VALID_BITS_WIDTH{1'b0}},
                            {TRANSPORT_PAYLOAD_WIDTH{1'b0}});
        wait_error_only(got_error, 2000);

        check_int(got_error, 1, "zero_valid_bits_should_error");
        check1(error_flag, 1'b1, "error_flag_should_be_1");
        check_int(done_pulse_count, 0, "done_pulse_count_should_be_0");
        check_int(actual_count, 0, "no_chunk_should_be_emitted");
    end
    endtask

    task run_invalid_case_non_last_short_word;
        integer got_error;
    begin
        $display("\n===== invalid_non_last_short_word =====");
        reset_dut;
        ready_mode_r         = 0;
        ready_stall_cycles_r = 0;
        ready_stall_count_r  = 0;

        payload_v = {TRANSPORT_PAYLOAD_WIDTH{1'b0}};
        for (bit_idx = 0; bit_idx < 11; bit_idx = bit_idx + 1)
            payload_v[bit_idx] = bit_idx[0];

        send_transport_word(1'b0,
                            7'd11,
                            payload_v);
        wait_error_only(got_error, 2000);

        check_int(got_error, 1, "non_last_short_word_should_error");
        check1(error_flag, 1'b1, "error_flag_should_be_1");
        check_int(done_pulse_count, 0, "done_pulse_count_should_be_0");
        check_int(actual_count, 0, "no_chunk_should_be_emitted");
    end
    endtask

    task run_two_frame_sequence_case;
        integer got_done;
        integer got_error;
    begin
        $display("\n===== two_frame_sequence =====");
        reset_dut;
        ready_mode_r         = 0;
        ready_stall_cycles_r = 0;
        ready_stall_count_r  = 0;

        gen_frame_pattern(frame_bits_a, 17, 3);
        build_expected_chunks(frame_bits_a, 17);
        send_frame(frame_bits_a, 17);
        wait_done_or_error(got_done, got_error, 20000);
        check_int(got_done, 1, "first_frame_should_complete");
        check_int(got_error, 0, "first_frame_should_not_error");
        compare_captured_chunks("two_frame_sequence_first");
        check_int(done_pulse_count, 1, "first_frame_done_pulse");
        check_int(transport_fire_count, expected_word_count, "first_frame_word_count");

        clear_scoreboard;
        gen_frame_pattern(frame_bits_b, 63, 9);
        build_expected_chunks(frame_bits_b, 63);
        send_frame(frame_bits_b, 63);
        wait_done_or_error(got_done, got_error, 20000);
        check_int(got_done, 1, "second_frame_should_complete");
        check_int(got_error, 0, "second_frame_should_not_error");
        compare_captured_chunks("two_frame_sequence_second");
        check_int(done_pulse_count, 1, "second_frame_done_pulse");
        check_int(transport_fire_count, expected_word_count, "second_frame_word_count");

        @(posedge clk);
        #TB_DLY;
        check1(busy, 1'b0, "busy_should_be_0_after_two_frames");
    end
    endtask

    initial begin
        pass_count = 0;
        fail_count = 0;
        rst_n      = 1'b0;
        stream_ready = 1'b0;
        clear_inputs;
        clear_scoreboard;

        gen_frame_pattern(frame_bits_a, 13, 1);
        run_valid_frame_case("single_short_frame", frame_bits_a, 13, 0, 0);

        gen_frame_pattern(frame_bits_a, 32, 5);
        run_valid_frame_case("single_exact_chunk", frame_bits_a, 32, 0, 0);

        gen_frame_pattern(frame_bits_a, 145, 7);
        run_valid_frame_case("multiword_multichunk_frame", frame_bits_a, 145, 0, 0);

        gen_frame_pattern(frame_bits_a, 145, 11);
        run_valid_frame_case("backpressure_frame", frame_bits_a, 145, 1, 3);

        run_two_frame_sequence_case;

        run_invalid_case_zero_valid_bits;
        run_invalid_case_non_last_short_word;

        $display("\n========================================");
        $display("BIT_DEPACKER_128 TEST SUMMARY: PASS=%0d FAIL=%0d", pass_count, fail_count);
        $display("========================================");

        #20;
        $finish;
    end

endmodule


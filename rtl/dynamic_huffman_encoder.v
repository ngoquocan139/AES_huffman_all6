module dynamic_huffman_encoder #(
    parameter BLOCK_SIZE_WIDTH      = 6,
    parameter BUFFER_ADDR_WIDTH     = 5,
    parameter SYMBOL_WIDTH          = 8,
    parameter SYMBOL_COUNT_WIDTH    = 9,
    parameter COUNT_WIDTH           = 6,
    parameter SYMBOL_INDEX_WIDTH    = 8,
    parameter CODE_LEN_WIDTH        = 5,
    parameter CODE_WIDTH            = 13,
    parameter HEADER_BITS_WIDTH     = 12,
    parameter TOTAL_BITS_WIDTH      = 16,
    parameter CHUNK_DATA_WIDTH      = 32,
    parameter CHUNK_LEN_WIDTH       = 6,
    parameter MAX_SYMBOLS_PER_BLOCK = 32,
    parameter MAX_TREE_NODES        = 63,
    parameter [7:0] ASCII_MIN       = 8'h20,
    parameter [7:0] ASCII_MAX       = 8'h7E
)(
    input  wire                          clk,
    input  wire                          rst_n,

    // top-level block control
    input  wire                          start_block,
    input  wire                          whole_file_enable,
    input  wire                          whole_file_emit_table,
    input  wire                          whole_file_table_valid,

    // external codebook for whole-file dynamic mode
    input  wire [SYMBOL_COUNT_WIDTH-1:0] external_symbol_count,
    output wire [SYMBOL_COUNT_WIDTH-1:0] external_symbol_read_addr,
    input  wire [SYMBOL_WIDTH-1:0]       external_symbol_read_data,
    output wire [SYMBOL_INDEX_WIDTH-1:0] external_code_len_read_index,
    input  wire [CODE_LEN_WIDTH-1:0]     external_code_len_read_data,
    output wire [SYMBOL_INDEX_WIDTH-1:0] external_code_read_index,
    input  wire [CODE_WIDTH-1:0]         external_code_read_data,

    // byte-stream input
    input  wire [SYMBOL_WIDTH-1:0]       byte_in,
    input  wire                          byte_valid,
    output wire                          byte_ready,
    input  wire                          block_start,
    input  wire                          block_end,

    // downstream unified stream
    input  wire                          stream_ready,
    output wire [CHUNK_DATA_WIDTH-1:0]   stream_data,
    output wire [CHUNK_LEN_WIDTH-1:0]    stream_len,
    output wire                          stream_valid,
    output wire                          stream_last,

    // top-level status
    output wire                          busy,
    output wire                          done,
    output wire                          error_flag,

    // optional debug
    output wire [1:0]                    selected_mode_out,
    output wire [3:0]                    fsm_state
);

    // ------------------------------------------------------------
    // control_fsm wires
    // ------------------------------------------------------------
    localparam integer HUFFMAN_ALPHABET_SIZE = 256;

    wire        ctrl_start_collect_w;
    wire        ctrl_start_build_w;
    wire        ctrl_start_mode_w;
    wire        ctrl_start_emit_w;
    wire [1:0]  ctrl_mode_selected_latched_w;
    wire        ctrl_busy_w;
    wire        ctrl_done_w;
    wire        ctrl_error_flag_w;
    wire [3:0]  ctrl_state_w;
    wire        whole_file_mode_w;

    // ------------------------------------------------------------
    // input_collect_unit wires
    // ------------------------------------------------------------
    wire [BUFFER_ADDR_WIDTH-1:0]  icu_buffer_read_addr_mux_w;
    wire [SYMBOL_WIDTH-1:0]       icu_buffer_read_data_w;

    wire [SYMBOL_INDEX_WIDTH-1:0] hb_freq_read_index_w;
    wire [COUNT_WIDTH-1:0]        icu_freq_read_count_w;

    wire                          collect_busy_w;
    wire                          collect_done_w;
    wire                          collect_protocol_error_w;
    wire                          collect_overflow_error_w;
    wire [BLOCK_SIZE_WIDTH-1:0]   collect_block_size_w;
    wire [SYMBOL_WIDTH-1:0]       normalized_byte_w;

    // ------------------------------------------------------------
    // huffman_builder wires
    // ------------------------------------------------------------
    reg  [SYMBOL_COUNT_WIDTH-1:0] hb_symbol_read_addr_mux_w;
    wire [SYMBOL_WIDTH-1:0]       hb_symbol_read_data_w;

    wire [SYMBOL_COUNT_WIDTH-1:0] hb_symbol_count_w;

    reg  [SYMBOL_INDEX_WIDTH-1:0] hb_code_len_read_index_mux_w;
    wire [CODE_LEN_WIDTH-1:0]     hb_code_len_read_data_w;

    reg  [SYMBOL_INDEX_WIDTH-1:0] hb_code_read_index_mux_w;
    wire [CODE_WIDTH-1:0]         hb_code_read_data_w;

    wire                          build_busy_w;
    wire                          build_done_w;
    wire                          build_error_w;

    // ------------------------------------------------------------
    // Fixed block storage mode
    // ------------------------------------------------------------
    localparam [1:0] MODE_COMPRESSED = 2'b10;
    wire                          mode_busy_w;
    wire                          mode_done_w;
    wire                          mode_error_w;
    wire [1:0]                    mode_selected_w;

    // ------------------------------------------------------------
    // emit_backend wires
    // ------------------------------------------------------------
    wire [SYMBOL_COUNT_WIDTH-1:0] emit_symbol_read_addr_w;
    wire [BUFFER_ADDR_WIDTH-1:0]  emit_buffer_read_addr_w;
    wire [SYMBOL_INDEX_WIDTH-1:0] emit_code_len_read_index_w;
    wire [SYMBOL_INDEX_WIDTH-1:0] emit_code_read_index_w;
    wire [SYMBOL_COUNT_WIDTH-1:0] emit_symbol_count_w;
    wire [SYMBOL_WIDTH-1:0]       emit_symbol_read_data_w;
    wire [CODE_LEN_WIDTH-1:0]     emit_code_len_read_data_w;
    wire [CODE_WIDTH-1:0]         emit_code_read_data_w;

    wire                          emit_busy_w;
    wire                          emit_done_w;
    wire                          emit_error_w;

    // ------------------------------------------------------------
    // Dummy/use wires to avoid unused-signal warnings
    // ------------------------------------------------------------
    wire unused_debug_w;
    wire unused_total_bits_width_w;

    assign unused_total_bits_width_w = ^{TOTAL_BITS_WIDTH{1'b0}};

`ifdef SYNTHESIS
    assign whole_file_mode_w = 1'b1;
`else
    assign whole_file_mode_w = whole_file_enable;
`endif

    assign unused_debug_w =
        ^normalized_byte_w ^
        ctrl_start_mode_w ^
        (1'b0 & unused_total_bits_width_w);

    assign busy = ctrl_busy_w | (1'b0 & unused_debug_w);

    assign done              = ctrl_done_w;
    assign error_flag        = ctrl_error_flag_w;
    assign selected_mode_out = ctrl_mode_selected_latched_w;
    assign fsm_state         = ctrl_state_w;

    // ------------------------------------------------------------
    // Mux shared readback interfaces by active phase
    // ------------------------------------------------------------

    // block_buffer read consumer:
    //   emit_backend during EMIT phase
    assign icu_buffer_read_addr_mux_w =
        (ctrl_start_emit_w || emit_busy_w) ? emit_buffer_read_addr_w :
        {BUFFER_ADDR_WIDTH{1'b0}};

    // symbol_list read consumer:
    //   emit_backend only during EMIT phase
    always @(*) begin
        if ((ctrl_start_emit_w || emit_busy_w) && !whole_file_mode_w)
            hb_symbol_read_addr_mux_w = emit_symbol_read_addr_w;
        else
            hb_symbol_read_addr_mux_w = {SYMBOL_COUNT_WIDTH{1'b0}};
    end

    // code_len_table read consumer:
    //   emit_backend during EMIT phase
    always @(*) begin
        if ((ctrl_start_emit_w || emit_busy_w) && !whole_file_mode_w)
            hb_code_len_read_index_mux_w = emit_code_len_read_index_w;
        else
            hb_code_len_read_index_mux_w = {SYMBOL_INDEX_WIDTH{1'b0}};
    end

    // code_table read consumer:
    //   emit_backend only during EMIT phase
    always @(*) begin
        if ((ctrl_start_emit_w || emit_busy_w) && !whole_file_mode_w)
            hb_code_read_index_mux_w = emit_code_read_index_w;
        else
            hb_code_read_index_mux_w = {SYMBOL_INDEX_WIDTH{1'b0}};
    end

    assign external_symbol_read_addr =
        (whole_file_mode_w && (ctrl_start_emit_w || emit_busy_w)) ?
        emit_symbol_read_addr_w : {SYMBOL_COUNT_WIDTH{1'b0}};
    assign external_code_len_read_index =
        (whole_file_mode_w && (ctrl_start_emit_w || emit_busy_w)) ?
        emit_code_len_read_index_w : {SYMBOL_INDEX_WIDTH{1'b0}};
    assign external_code_read_index =
        (whole_file_mode_w && (ctrl_start_emit_w || emit_busy_w)) ?
        emit_code_read_index_w : {SYMBOL_INDEX_WIDTH{1'b0}};

    assign emit_symbol_count_w =
        whole_file_mode_w ? (whole_file_emit_table ? external_symbol_count :
                                                    {SYMBOL_COUNT_WIDTH{1'b0}}) :
                            hb_symbol_count_w;
    assign emit_symbol_read_data_w =
        whole_file_mode_w ? external_symbol_read_data : hb_symbol_read_data_w;
    assign emit_code_len_read_data_w =
        whole_file_mode_w ? external_code_len_read_data : hb_code_len_read_data_w;
    assign emit_code_read_data_w =
        whole_file_mode_w ? external_code_read_data : hb_code_read_data_w;

    // ------------------------------------------------------------
    // input_collect_unit
    // ------------------------------------------------------------
    input_collect_unit #(
        .BLOCK_SIZE         (MAX_SYMBOLS_PER_BLOCK),
        .SYMBOL_WIDTH       (SYMBOL_WIDTH),
        .ALPHABET_SIZE      (HUFFMAN_ALPHABET_SIZE),
        .ASCII_MIN          (ASCII_MIN),
        .ASCII_MAX          (ASCII_MAX),
        .DEFAULT_REMAP      (ASCII_MIN),
        .BLOCK_SIZE_WIDTH   (BLOCK_SIZE_WIDTH),
        .COUNT_WIDTH        (COUNT_WIDTH),
        .ADDR_WIDTH         (BUFFER_ADDR_WIDTH),
        .SYMBOL_INDEX_WIDTH (SYMBOL_INDEX_WIDTH)
    ) u_input_collect_unit (
        .clk              (clk),
        .rst_n            (rst_n),

        .start_collect    (ctrl_start_collect_w),

        .byte_in          (byte_in),
        .byte_valid       (byte_valid),
        .byte_ready       (byte_ready),

        .block_start      (block_start),
        .block_end        (block_end),

        .buffer_read_addr (icu_buffer_read_addr_mux_w),
        .buffer_read_data (icu_buffer_read_data_w),

        .freq_read_index  (hb_freq_read_index_w),
        .freq_read_count  (icu_freq_read_count_w),

        .collect_busy     (collect_busy_w),
        .collect_done     (collect_done_w),
        .protocol_error   (collect_protocol_error_w),
        .overflow_error   (collect_overflow_error_w),

        .block_size       (collect_block_size_w),
        .normalized_byte  (normalized_byte_w)
    );

    // ------------------------------------------------------------
    // huffman_builder
    // ------------------------------------------------------------
`ifdef SYNTHESIS
    assign hb_freq_read_index_w      = {SYMBOL_INDEX_WIDTH{1'b0}};
    assign hb_symbol_read_data_w     = {SYMBOL_WIDTH{1'b0}};
    assign hb_symbol_count_w         = {SYMBOL_COUNT_WIDTH{1'b0}};
    assign hb_code_len_read_data_w   = {CODE_LEN_WIDTH{1'b0}};
    assign hb_code_read_data_w       = {CODE_WIDTH{1'b0}};
    assign build_busy_w              = 1'b0;
    assign build_done_w              = 1'b0;
    assign build_error_w             = 1'b0;
`else
    huffman_builder #(
        .ALPHABET_SIZE         (HUFFMAN_ALPHABET_SIZE),
        .SYMBOL_WIDTH          (SYMBOL_WIDTH),
        .SYMBOL_COUNT_WIDTH    (SYMBOL_COUNT_WIDTH),
        .COUNT_WIDTH           (COUNT_WIDTH),
        .SYMBOL_INDEX_WIDTH    (SYMBOL_INDEX_WIDTH),
        .CODE_LEN_WIDTH        (CODE_LEN_WIDTH),
        .CODE_WIDTH            (CODE_WIDTH),
        .MAX_SYMBOLS_PER_BLOCK (MAX_SYMBOLS_PER_BLOCK),
        .MAX_TREE_NODES        (MAX_TREE_NODES),
        .ASCII_MIN             (ASCII_MIN)
    ) u_huffman_builder (
        .clk                 (clk),
        .rst_n               (rst_n),
        .start               (ctrl_start_build_w),
        .block_size          ({{(SYMBOL_COUNT_WIDTH-BLOCK_SIZE_WIDTH){1'b0}}, collect_block_size_w}),

        .freq_read_index     (hb_freq_read_index_w),
        .freq_read_count     (icu_freq_read_count_w),

        .busy                (build_busy_w),
        .done                (build_done_w),
        .error_flag          (build_error_w),

        .symbol_count        (hb_symbol_count_w),

        .symbol_read_addr    (hb_symbol_read_addr_mux_w),
        .symbol_read_data    (hb_symbol_read_data_w),

        .code_len_read_index (hb_code_len_read_index_mux_w),
        .code_len_read_data  (hb_code_len_read_data_w),

        .code_read_index     (hb_code_read_index_mux_w),
        .code_read_data      (hb_code_read_data_w)
    );
`endif

    // ------------------------------------------------------------
    // Fixed compressed-mode latch
    // ------------------------------------------------------------
    // File-level storage selection is owned by RV32I firmware/metadata. The
    // encoder datapath always emits Huffman compressed blocks when TX is used.
    assign mode_busy_w     = 1'b0;
    assign mode_done_w     = 1'b1;
    assign mode_error_w    = 1'b0;
    assign mode_selected_w = MODE_COMPRESSED;

    // ------------------------------------------------------------
    // emit_backend
    // ------------------------------------------------------------
    emit_backend #(
        .BLOCK_SIZE_WIDTH   (BLOCK_SIZE_WIDTH),
        .BUFFER_ADDR_WIDTH  (BUFFER_ADDR_WIDTH),
        .SYMBOL_WIDTH       (SYMBOL_WIDTH),
        .SYMBOL_COUNT_WIDTH (SYMBOL_COUNT_WIDTH),
        .SYMBOL_INDEX_WIDTH (SYMBOL_INDEX_WIDTH),
        .CODE_LEN_WIDTH     (CODE_LEN_WIDTH),
        .CODE_WIDTH         (CODE_WIDTH),
        .HEADER_BITS_WIDTH  (HEADER_BITS_WIDTH),
        .CHUNK_DATA_WIDTH   (CHUNK_DATA_WIDTH),
        .CHUNK_LEN_WIDTH    (CHUNK_LEN_WIDTH),
        .ASCII_MIN          (ASCII_MIN),
        .ASCII_MAX          (ASCII_MAX)
    ) u_emit_backend (
        .clk                 (clk),
        .rst_n               (rst_n),
        .start               (ctrl_start_emit_w),

        .selected_mode       (ctrl_mode_selected_latched_w),
        .block_size          (collect_block_size_w),
        .symbol_count        (emit_symbol_count_w),

        .symbol_read_addr    (emit_symbol_read_addr_w),
        .symbol_read_data    (emit_symbol_read_data_w),

        .buffer_read_addr    (emit_buffer_read_addr_w),
        .buffer_read_data    (icu_buffer_read_data_w),

        .code_len_read_index (emit_code_len_read_index_w),
        .code_len_read_data  (emit_code_len_read_data_w),

        .code_read_index     (emit_code_read_index_w),
        .code_read_data      (emit_code_read_data_w),

        .stream_ready        (stream_ready),
        .stream_data         (stream_data),
        .stream_len          (stream_len),
        .stream_valid        (stream_valid),
        .stream_last         (stream_last),

        .busy                (emit_busy_w),
        .done                (emit_done_w),
        .error_flag          (emit_error_w)
    );

    // ------------------------------------------------------------
    // control_fsm
    // NOTE:
    // control_fsm must also be updated so that:
    //   .selected_mode          is [1:0]
    //   .mode_selected_latched  is [1:0]
    // ------------------------------------------------------------
    control_fsm u_control_fsm (
        .clk                    (clk),
        .rst_n                  (rst_n),

        .start_block            (start_block),
        .whole_file_enable      (whole_file_mode_w),
        .whole_file_table_valid (whole_file_table_valid),

        .collect_done           (collect_done_w),
        .collect_busy           (collect_busy_w),
        .collect_protocol_error (collect_protocol_error_w),
        .collect_overflow_error (collect_overflow_error_w),

        .build_done             (build_done_w),
        .build_busy             (build_busy_w),
        .build_error            (build_error_w),

        .mode_done              (mode_done_w),
        .mode_busy              (mode_busy_w),
        .mode_error             (mode_error_w),
        .selected_mode          (mode_selected_w),

        .emit_done              (emit_done_w),
        .emit_busy              (emit_busy_w),
        .emit_error             (emit_error_w),

        .start_collect          (ctrl_start_collect_w),
        .start_build            (ctrl_start_build_w),
        .start_mode_decision    (ctrl_start_mode_w),
        .start_emit             (ctrl_start_emit_w),

        .mode_selected_latched  (ctrl_mode_selected_latched_w),

        .busy                   (ctrl_busy_w),
        .done                   (ctrl_done_w),
        .error_flag             (ctrl_error_flag_w),

        .state                  (ctrl_state_w)
    );

endmodule

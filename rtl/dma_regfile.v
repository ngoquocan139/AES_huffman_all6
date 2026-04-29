module dma_regfile #(
    parameter BLOCK_SIZE_WIDTH = 6
)(
    input  wire                         PCLK,
    input  wire                         rst_i,
    input  wire                         PSEL,
    input  wire                         PENABLE,
    input  wire                         PWRITE,
    input  wire [31:0]                  PADDR,
    input  wire [31:0]                  PWDATA,
    output reg  [31:0]                  PRDATA,
    output reg                          PREADY,
    output reg                          PSLVERR,

    output reg  [31:0]                  src_addr_o,
    output reg  [31:0]                  dst_addr_o,
    output reg  [31:0]                  len_bytes_o,
    output reg  [1:0]                   direction_o,
    output reg                          compress_only_o,
    output reg                          whole_file_o,
    output wire [127:0]                 iv_o,
    output reg  [BLOCK_SIZE_WIDTH-1:0]  block_size_o,
    output reg                          start_pulse_o,
    output reg                          soft_reset_pulse_o,
    output reg                          clear_done_pulse_o,
    output reg                          clear_error_pulse_o,

    input  wire                         dma_busy_i,
    input  wire                         dma_done_i,
    input  wire                         dma_error_i,
    input  wire [31:0]                  bytes_done_i,
    input  wire [31:0]                  ciphertext_bytes_produced_i,
    input  wire [7:0]                   last_error_code_i,
    input  wire [3:0]                   engine_state_i
);

    localparam [31:0] ADDR_CONTROL    = 32'h0000_0000;
    localparam [31:0] ADDR_STATUS     = 32'h0000_0004;
    localparam [31:0] ADDR_SRC_ADDR   = 32'h0000_0008;
    localparam [31:0] ADDR_DST_ADDR   = 32'h0000_000C;
    localparam [31:0] ADDR_LEN_BYTES  = 32'h0000_0010;
    localparam [31:0] ADDR_MODE       = 32'h0000_0014;
    localparam [31:0] ADDR_BLOCK_CFG  = 32'h0000_0018;
    localparam [31:0] ADDR_BYTES_DONE = 32'h0000_001C;
    localparam [31:0] ADDR_DEBUG      = 32'h0000_0020;
    localparam [31:0] ADDR_CTXT_BYTES = 32'h0000_0024;
    localparam [31:0] ADDR_IV0        = 32'h0000_0028;
    localparam [31:0] ADDR_IV1        = 32'h0000_002C;
    localparam [31:0] ADDR_IV2        = 32'h0000_0030;
    localparam [31:0] ADDR_IV3        = 32'h0000_0034;

    localparam [BLOCK_SIZE_WIDTH-1:0] DEFAULT_BLOCK_SIZE = 6'd32;

    reg done_sticky_r;
    reg error_sticky_r;
    reg [31:0] iv0_r;
    reg [31:0] iv1_r;
    reg [31:0] iv2_r;
    reg [31:0] iv3_r;

    wire apb_access_w;
    wire apb_write_access_w;
    wire apb_read_access_w;
    wire write_commit_w;
    wire read_commit_w;

    wire control_reserved_bits_set_w;
    wire mode_reserved_bits_set_w;
    wire block_cfg_reserved_bits_set_w;
    wire direction_valid_w;
    wire block_size_valid_w;
    wire cfg_valid_w;
    wire control_start_invalid_w;

    assign apb_access_w               = PSEL && PENABLE;
    assign apb_write_access_w         = apb_access_w && PWRITE;
    assign apb_read_access_w          = apb_access_w && (!PWRITE);
    assign write_commit_w             = apb_write_access_w && PREADY;
    assign read_commit_w              = apb_read_access_w && PREADY;
    assign iv_o                       = {iv3_r, iv2_r, iv1_r, iv0_r};

    assign control_reserved_bits_set_w = |PWDATA[31:4];
    assign mode_reserved_bits_set_w    = |PWDATA[31:4];
    assign block_cfg_reserved_bits_set_w = |PWDATA[31:BLOCK_SIZE_WIDTH];

    assign direction_valid_w = (direction_o == 2'b01) || (direction_o == 2'b10);
    assign block_size_valid_w = (block_size_o != {BLOCK_SIZE_WIDTH{1'b0}}) &&
                                (block_size_o <= 32);
    assign cfg_valid_w = (src_addr_o[1:0] == 2'b00) &&
                         (dst_addr_o[1:0] == 2'b00) &&
                         (len_bytes_o != 32'b0) &&
                         block_size_valid_w &&
                         direction_valid_w;

    assign control_start_invalid_w = PWDATA[0] && ((!cfg_valid_w) || dma_busy_i);

    always @(*) begin
        PRDATA  = 32'b0;
        PREADY  = 1'b1;
        PSLVERR = 1'b0;

        if (apb_read_access_w) begin
            case (PADDR)
                ADDR_CONTROL: begin
                    PRDATA = 32'b0;
                end

                ADDR_STATUS: begin
                    PRDATA[0] = dma_busy_i;
                    PRDATA[1] = done_sticky_r;
                    PRDATA[2] = error_sticky_r;
                    PRDATA[3] = cfg_valid_w;
                    PRDATA[5:4] = direction_o;
                    PRDATA[6] = compress_only_o;
                    PRDATA[7] = whole_file_o;
                end

                ADDR_SRC_ADDR: begin
                    PRDATA = src_addr_o;
                end

                ADDR_DST_ADDR: begin
                    PRDATA = dst_addr_o;
                end

                ADDR_LEN_BYTES: begin
                    PRDATA = len_bytes_o;
                end

                ADDR_MODE: begin
                    PRDATA[1:0] = direction_o;
                    PRDATA[2]   = compress_only_o;
                    PRDATA[3]   = whole_file_o;
                end

                ADDR_BLOCK_CFG: begin
                    PRDATA[BLOCK_SIZE_WIDTH-1:0] = block_size_o;
                end

                ADDR_BYTES_DONE: begin
                    PRDATA = bytes_done_i;
                end

                ADDR_DEBUG: begin
                    PRDATA[3:0]  = engine_state_i;
                    PRDATA[11:4] = last_error_code_i;
                end

                ADDR_CTXT_BYTES: begin
                    PRDATA = ciphertext_bytes_produced_i;
                end

                ADDR_IV0: begin
                    PRDATA = iv0_r;
                end

                ADDR_IV1: begin
                    PRDATA = iv1_r;
                end

                ADDR_IV2: begin
                    PRDATA = iv2_r;
                end

                ADDR_IV3: begin
                    PRDATA = iv3_r;
                end

                default: begin
                    PSLVERR = 1'b1;
                end
            endcase
        end

        if (apb_write_access_w) begin
            case (PADDR)
                ADDR_CONTROL: begin
                    PSLVERR = control_reserved_bits_set_w || control_start_invalid_w;
                end

                ADDR_SRC_ADDR,
                ADDR_DST_ADDR,
                ADDR_LEN_BYTES: begin
                    PSLVERR = dma_busy_i;
                end

                ADDR_MODE: begin
                    PSLVERR = dma_busy_i || mode_reserved_bits_set_w;
                end

                ADDR_BLOCK_CFG: begin
                    PSLVERR = dma_busy_i || block_cfg_reserved_bits_set_w;
                end

                ADDR_IV0,
                ADDR_IV1,
                ADDR_IV2,
                ADDR_IV3: begin
                    PSLVERR = dma_busy_i;
                end

                ADDR_STATUS,
                ADDR_BYTES_DONE,
                ADDR_DEBUG,
                ADDR_CTXT_BYTES: begin
                    PSLVERR = 1'b1;
                end

                default: begin
                    PSLVERR = 1'b1;
                end
            endcase
        end
    end

    always @(posedge PCLK) begin
        if (rst_i) begin
            src_addr_o         <= 32'b0;
            dst_addr_o         <= 32'b0;
            len_bytes_o        <= 32'b0;
            direction_o        <= 2'b00;
            compress_only_o    <= 1'b0;
            whole_file_o       <= 1'b0;
            block_size_o       <= DEFAULT_BLOCK_SIZE;
            start_pulse_o      <= 1'b0;
            soft_reset_pulse_o <= 1'b0;
            clear_done_pulse_o <= 1'b0;
            clear_error_pulse_o<= 1'b0;
            done_sticky_r      <= 1'b0;
            error_sticky_r     <= 1'b0;
            iv0_r              <= 32'b0;
            iv1_r              <= 32'b0;
            iv2_r              <= 32'b0;
            iv3_r              <= 32'b0;
        end
        else begin
            start_pulse_o       <= 1'b0;
            soft_reset_pulse_o  <= 1'b0;
            clear_done_pulse_o  <= 1'b0;
            clear_error_pulse_o <= 1'b0;

            if (dma_done_i)
                done_sticky_r <= 1'b1;

            if (dma_error_i)
                error_sticky_r <= 1'b1;

            if ((write_commit_w || read_commit_w) && PSLVERR)
                error_sticky_r <= 1'b1;

            if (write_commit_w) begin
`ifdef MMIO_DEBUG
                $display("[DMA_REGFILE][WRITE] t=%0t addr=0x%08x data=0x%08x err=%0b",
                         $time, PADDR, PWDATA, PSLVERR);
`endif
                case (PADDR)
                    ADDR_CONTROL: begin
                        if (!PSLVERR) begin
                            if (PWDATA[1]) begin
                                src_addr_o         <= 32'b0;
                                dst_addr_o         <= 32'b0;
                                len_bytes_o        <= 32'b0;
                                direction_o        <= 2'b00;
                                compress_only_o    <= 1'b0;
                                whole_file_o       <= 1'b0;
                                block_size_o       <= DEFAULT_BLOCK_SIZE;
                                iv0_r              <= 32'b0;
                                iv1_r              <= 32'b0;
                                iv2_r              <= 32'b0;
                                iv3_r              <= 32'b0;
                                done_sticky_r      <= 1'b0;
                                error_sticky_r     <= 1'b0;
                                soft_reset_pulse_o <= 1'b1;
                            end
                            else begin
                                if (PWDATA[2]) begin
                                    done_sticky_r      <= 1'b0;
                                    clear_done_pulse_o <= 1'b1;
                                end

                                if (PWDATA[3]) begin
                                    error_sticky_r      <= 1'b0;
                                    clear_error_pulse_o <= 1'b1;
                                end

                                if (PWDATA[0]) begin
                                    done_sticky_r <= 1'b0;
                                    start_pulse_o <= 1'b1;
                                end
                            end
                        end
                    end

                    ADDR_SRC_ADDR: begin
                        if (!PSLVERR)
                            src_addr_o <= PWDATA;
                    end

                    ADDR_DST_ADDR: begin
                        if (!PSLVERR)
                            dst_addr_o <= PWDATA;
                    end

                    ADDR_LEN_BYTES: begin
                        if (!PSLVERR)
                            len_bytes_o <= PWDATA;
                    end

                    ADDR_MODE: begin
                        if (!PSLVERR) begin
                            direction_o <= PWDATA[1:0];
                            compress_only_o <= PWDATA[2];
                            whole_file_o <= PWDATA[3];
                        end
                    end

                    ADDR_BLOCK_CFG: begin
                        if (!PSLVERR)
                            block_size_o <= PWDATA[BLOCK_SIZE_WIDTH-1:0];
                    end

                    ADDR_IV0: begin
                        if (!PSLVERR)
                            iv0_r <= PWDATA;
                    end

                    ADDR_IV1: begin
                        if (!PSLVERR)
                            iv1_r <= PWDATA;
                    end

                    ADDR_IV2: begin
                        if (!PSLVERR)
                            iv2_r <= PWDATA;
                    end

                    ADDR_IV3: begin
                        if (!PSLVERR)
                            iv3_r <= PWDATA;
                    end

                    default: begin
                    end
                endcase
            end
        end
    end

endmodule

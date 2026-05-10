module cpu_mmio_to_apb_bridge (
    input  wire        clk_i,
    input  wire        rst_i,

    input  wire        mmio_req_i,
    input  wire        mmio_write_i,
    input  wire [31:0] mmio_addr_i,
    input  wire [31:0] mmio_wdata_i,
    input  wire [3:0]  mmio_wstrb_i,
    output reg  [31:0] mmio_rdata_o,
    output reg         mmio_done_o,
    output reg         mmio_error_o,
    output wire        mmio_busy_o,
    output wire        cpu_stall_req_o,

    output wire        PSEL_o,
    output wire        PENABLE_o,
    output wire        PWRITE_o,
    output wire [31:0] PADDR_o,
    output wire [31:0] PWDATA_o,
    input  wire [31:0] PRDATA_i,
    input  wire        PREADY_i,
    input  wire        PSLVERR_i
);

    localparam [1:0] STATE_IDLE   = 2'b00;
    localparam [1:0] STATE_ACCESS = 2'b10;

    reg [1:0]  state_r;
    reg        req_write_r;
    reg [31:0] req_addr_r;
    reg [31:0] req_wdata_r;
    reg        last_req_valid_r;
    reg        last_req_write_r;
    reg [31:0] last_req_addr_r;
    reg [31:0] last_req_wdata_r;
    reg [3:0]  last_req_wstrb_r;

    wire can_sample_req_w;
    wire req_aligned_w;
    wire write_strobe_valid_w;
    wire req_valid_w;
    wire accept_req_w;
    wire reject_req_w;
    wire same_as_last_req_w;
    wire setup_phase_w;
    wire access_phase_w;
    wire req_write_mux_w;
    wire [31:0] req_addr_mux_w;
    wire [31:0] req_wdata_mux_w;

    assign can_sample_req_w     = (state_r == STATE_IDLE) && mmio_req_i;
    assign req_aligned_w        = (mmio_addr_i[1:0] == 2'b00);
    assign write_strobe_valid_w = (!mmio_write_i) || (mmio_wstrb_i == 4'b1111);
    assign req_valid_w          = req_aligned_w && write_strobe_valid_w;
    assign same_as_last_req_w   = last_req_valid_r &&
                                  (mmio_write_i == last_req_write_r) &&
                                  (mmio_addr_i == last_req_addr_r) &&
                                  (mmio_wdata_i == last_req_wdata_r) &&
                                  (mmio_wstrb_i == last_req_wstrb_r);
    assign accept_req_w         = can_sample_req_w && req_valid_w && (!same_as_last_req_w);
    assign reject_req_w         = can_sample_req_w && (!req_valid_w);

    assign setup_phase_w    = accept_req_w;
    assign access_phase_w   = (state_r == STATE_ACCESS);

    assign req_write_mux_w  = setup_phase_w ? mmio_write_i : req_write_r;
    assign req_addr_mux_w   = setup_phase_w ? mmio_addr_i  : req_addr_r;
    assign req_wdata_mux_w  = setup_phase_w ? mmio_wdata_i : req_wdata_r;

    assign mmio_busy_o      = setup_phase_w || access_phase_w;
    // The bridge captures the request in SETUP, so the CPU only needs to hold
    // once the transfer reaches ACCESS and waits for completion.
    assign cpu_stall_req_o  = access_phase_w;

    assign PSEL_o           = setup_phase_w || access_phase_w;
    assign PENABLE_o        = access_phase_w;
    assign PWRITE_o         = req_write_mux_w;
    assign PADDR_o          = req_addr_mux_w;
    assign PWDATA_o         = req_wdata_mux_w;

    always @(posedge clk_i) begin
        if (rst_i) begin
            state_r       <= STATE_IDLE;
            req_write_r   <= 1'b0;
            req_addr_r    <= 32'b0;
            req_wdata_r   <= 32'b0;
            last_req_valid_r <= 1'b0;
            last_req_write_r <= 1'b0;
            last_req_addr_r  <= 32'b0;
            last_req_wdata_r <= 32'b0;
            last_req_wstrb_r <= 4'b0;
            mmio_rdata_o  <= 32'b0;
            mmio_done_o   <= 1'b0;
            mmio_error_o  <= 1'b0;
        end
        else begin
            mmio_done_o  <= 1'b0;
            mmio_error_o <= 1'b0;

            if (!mmio_req_i)
                last_req_valid_r <= 1'b0;

            case (state_r)
                STATE_IDLE: begin
                    if (accept_req_w) begin
`ifdef MMIO_DEBUG
                        $display("[MMIO_BRIDGE][ACCEPT] t=%0t write=%0b addr=0x%08x wdata=0x%08x wstrb=0x%x",
                                 $time, mmio_write_i, mmio_addr_i, mmio_wdata_i, mmio_wstrb_i);
`endif
                        req_write_r <= mmio_write_i;
                        req_addr_r  <= mmio_addr_i;
                        req_wdata_r <= mmio_wdata_i;
                        last_req_valid_r <= 1'b1;
                        last_req_write_r <= mmio_write_i;
                        last_req_addr_r  <= mmio_addr_i;
                        last_req_wdata_r <= mmio_wdata_i;
                        last_req_wstrb_r <= mmio_wstrb_i;
                        state_r     <= STATE_ACCESS;
                    end
                    else if (reject_req_w) begin
                        mmio_rdata_o <= 32'b0;
                        mmio_done_o  <= 1'b1;
                        mmio_error_o <= 1'b1;
                    end
                end

                STATE_ACCESS: begin
                    if (PREADY_i) begin
`ifdef MMIO_DEBUG
                        $display("[MMIO_BRIDGE][DONE] t=%0t write=%0b addr=0x%08x rdata=0x%08x err=%0b",
                                 $time, req_write_r, req_addr_r, PRDATA_i, PSLVERR_i);
`endif
                        if (!req_write_r)
                            mmio_rdata_o <= PSLVERR_i ? 32'b0 : PRDATA_i;

                        mmio_done_o  <= 1'b1;
                        mmio_error_o <= PSLVERR_i;
                        state_r      <= STATE_IDLE;
                    end
                end

                default: begin
                    state_r <= STATE_IDLE;
                end
            endcase
        end
    end

endmodule

module forwarding
(
    // EX stage source register addresses + values
    input  wire [4:0]   ex_rs1_addr,
    input  wire [4:0]   ex_rs2_addr,
    input  wire [31:0]  ex_rs1_data,
    input  wire [31:0]  ex_rs2_data,

    // EX/MEM pipeline information
    input  wire         exmem_regwrite,
    input  wire [4:0]   exmem_rd_addr,
    input  wire [1:0]   exmem_wb_se,
    input  wire [31:0]  exmem_alu_result,
    input  wire [31:0]  exmem_pc_plus,
    input  wire [31:0]  mem_data,

    // MEM/WB pipeline information
    input  wire         memwb_regwrite,
    input  wire [4:0]   memwb_rd_addr,
    input  wire [1:0]   memwb_wb_se,
    input  wire [31:0]  memwb_alu_result,
    input  wire [31:0]  memwb_mem_data,
    input  wire [31:0]  memwb_pc_plus,

    // Forwarded sources out
    output wire [31:0]  forward_src_1,
    output wire [31:0]  forward_src_2
);

    // ============================================================
    // 1. Match conditions
    // ============================================================
    wire exmem_match_1 = exmem_regwrite && 
                         (ex_rs1_addr == exmem_rd_addr) && 
                         (ex_rs1_addr != 5'd0);

    wire exmem_match_2 = exmem_regwrite && 
                         (ex_rs2_addr == exmem_rd_addr) && 
                         (ex_rs2_addr != 5'd0);

    wire memwb_match_1 = memwb_regwrite && 
                         (ex_rs1_addr == memwb_rd_addr) && 
                         (ex_rs1_addr != 5'd0);

    wire memwb_match_2 = memwb_regwrite && 
                         (ex_rs2_addr == memwb_rd_addr) && 
                         (ex_rs2_addr != 5'd0);

    // ============================================================
    // 2. Select mux values
    // ============================================================
    wire [3:0] forward_mux_1 =
        (exmem_match_1 && (exmem_wb_se == 2'b00)) ? 4'b0001 :
        (exmem_match_1 && (exmem_wb_se == 2'b10)) ? 4'b0010 :
        (exmem_match_1 && (exmem_wb_se == 2'b01)) ? 4'b1001 :
        (memwb_match_1 && (memwb_wb_se == 2'b00)) ? 4'b0110 :
        (memwb_match_1 && (memwb_wb_se == 2'b01)) ? 4'b0111 :
        (memwb_match_1 && (memwb_wb_se == 2'b10)) ? 4'b1000 : 4'b0000;

    wire [3:0] forward_mux_2 =
        (exmem_match_2 && (exmem_wb_se == 2'b00)) ? 4'b0001 :
        (exmem_match_2 && (exmem_wb_se == 2'b10)) ? 4'b0010 :
        (exmem_match_2 && (exmem_wb_se == 2'b01)) ? 4'b1001 :
        (memwb_match_2 && (memwb_wb_se == 2'b00)) ? 4'b0110 :
        (memwb_match_2 && (memwb_wb_se == 2'b01)) ? 4'b0111 :
        (memwb_match_2 && (memwb_wb_se == 2'b10)) ? 4'b1000 : 4'b0000;

    // ============================================================
    // 3. Final forwarding paths
    // ============================================================
    assign forward_src_1 =
        (forward_mux_1 == 4'b1000) ? memwb_pc_plus    :
        (forward_mux_1 == 4'b0111) ? memwb_mem_data   :
        (forward_mux_1 == 4'b0110) ? memwb_alu_result :
        (forward_mux_1 == 4'b1001) ? mem_data         :
        (forward_mux_1 == 4'b0010) ? exmem_pc_plus    :
        (forward_mux_1 == 4'b0001) ? exmem_alu_result : ex_rs1_data;

    assign forward_src_2 =
        (forward_mux_2 == 4'b1000) ? memwb_pc_plus    :
        (forward_mux_2 == 4'b0111) ? memwb_mem_data   :
        (forward_mux_2 == 4'b0110) ? memwb_alu_result :
        (forward_mux_2 == 4'b1001) ? mem_data         :
        (forward_mux_2 == 4'b0010) ? exmem_pc_plus    :
        (forward_mux_2 == 4'b0001) ? exmem_alu_result : ex_rs2_data;

endmodule

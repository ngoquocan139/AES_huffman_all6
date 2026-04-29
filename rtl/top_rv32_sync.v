`include "defines.vh"
module top_rv32_sync (
  input wire clk_i,
  input wire rst_i,
  // Imem interface
  output wire imem_en_o,
  output wire [31:0] imem_addr_o,
  input wire [31:0] imem_instr_i,
  // Dmem interface
  output wire dmem_en_o,
  output wire [3:0] dmem_we_o,
  output wire [31:0] dmem_addr_o,
  output wire [31:0] dmem_w_data_o,
  input wire [31:0] dmem_r_data_i,
  input wire dmem_is_mmio_i,
  output wire dmem_load_resp_is_mmio_o,
  // Register file interface
  output wire [4:0] rs1_addr,
  output wire [4:0] rs2_addr,
  input wire [31:0] rs1_data,
  input wire [31:0] rs2_data,
  output wire reg_write,
  output wire [4:0] rd_addr,
  output wire [31:0] rd_data,
  input wire if_flush_i,
  input wire stall_i,
  output wire [1:0] mem_err_o
);

  wire if_flush_w;
  wire if_stall_w;

  wire id_flush_w;
  wire id_hold_w;
  wire id_bubble_w;

  wire ex_flush_w;
  wire ex_stall_w;

  wire [4:0] rs1_addr_w;
  wire [4:0] rs2_addr_w;
  wire [31:0] rs1_data_w;
  wire [31:0] rs2_data_w;

  assign rs1_addr = rs1_addr_w;
  assign rs2_addr = rs2_addr_w;

  wire [31:0] ifid_pc_w;
  wire [31:0] ifid_instruction_w;

  wire        rf_reg_write_w;
  wire [4:0]  rf_rd_addr_w;
  wire [31:0] rf_rd_data_w;

  assign reg_write = rf_reg_write_w;
  assign rd_addr = rf_rd_addr_w;
  assign rd_data = rf_rd_data_w;

  wire [31:0] idex_pc_w;
  wire [31:0] idex_imm_w;
  wire [31:0] idex_rs1_data_w;
  wire [31:0] idex_rs2_data_w;

  wire        idex_jal_w;
  wire        idex_jalr_w;
  wire        idex_se_alu_src1_w;
  wire        idex_se_alu_src2_w;
  wire [3:0]  idex_aluop_w;
  wire        idex_mem_we_w;
  wire        idex_mem_en_w;
  wire [2:0]  idex_width_se_w;
  wire [1:0]  idex_wb_se_w;
  wire        idex_regwrite_w;
  wire [4:0]  idex_rd_addr_w;

  wire [31:0] exif_pc_bj_w;
  wire        exif_bj_taken_w;

  assign id_flush_w = exif_bj_taken_w;
  assign ex_flush_w = exif_bj_taken_w;

  wire [4:0] idex_rs1_addr_w;
  wire [4:0] idex_rs2_addr_w;

  assign if_flush_w = if_flush_i;

  wire [2:0] exmem_width_se_w;
  wire       exmem_mem_we_w;
  wire       exmem_mem_en_w;
  wire [1:0] mem_stage_err_w;

  wire load_use_hazard;
  wire external_hold_w;
  wire front_hold_w;
  wire load_use_bubble_w;
  wire is_load_instrucion;
  wire is_load_memwb_instruction;
  wire exmem_load_hazard;
  wire memwb_load_hazard;
  wire mem_load_wait_w;
  wire mem_load_resp_is_mmio_w;

  assign external_hold_w = stall_i;
  assign front_hold_w = external_hold_w || mem_load_wait_w;
  assign load_use_bubble_w = load_use_hazard && (!front_hold_w);

  assign if_stall_w = front_hold_w || load_use_bubble_w;
  assign id_hold_w = front_hold_w;
  assign id_bubble_w = load_use_bubble_w;
  assign ex_stall_w = front_hold_w;

  assign mem_err_o = mem_stage_err_w;
  assign dmem_load_resp_is_mmio_o = mem_load_resp_is_mmio_w;

  wire        exmem_regwrite_w;
  wire [4:0]  exmem_rd_addr_w;
  wire [1:0]  exmem_wb_se_w;
  wire [31:0] exmem_pc_plus_w;
  wire [31:0] exmem_alu_result_w;
  wire [31:0] exmem_rs2_data_w;

  wire        memwb_regwrite_w;
  wire [4:0]  memwb_rd_addr_w;
  wire [1:0]  memwb_wb_se_w;
  wire [31:0] memwb_pc_plus_w;
  wire [31:0] memwb_alu_result_w;
  wire [31:0] memwb_mem_data_w;

  wire [31:0] mem_r_data_w;
  wire [31:0] forward_src_1_w;
  wire [31:0] forward_src_2_w;
  wire [31:0] wb_data_w;
  wire [31:0] mem_data_w;

  if_stage_sync u_if_stage (
    .clk_i              (clk_i),
    .rst_i              (rst_i),
    .flush_i            (if_flush_w),
    .stall_i            (if_stall_w),
    .if_bj_taken_i      (exif_bj_taken_w),
    .if_pc_bj_i         (exif_pc_bj_w),
    .imem_en_o          (imem_en_o),
    .imem_addr_o        (imem_addr_o),
    .imem_instr_i       (imem_instr_i),
    .ifid_pc_o          (ifid_pc_w),
    .ifid_instruction_o (ifid_instruction_w)
  );

  id_stage u_id_stage (
    .clk_i                  (clk_i),
    .rst_i                  (rst_i),
    .ifid_pc_i              (ifid_pc_w),
    .ifid_instruction_i     (ifid_instruction_w),
    .flush_i                (id_flush_w),
    .hold_i                 (id_hold_w),
    .bubble_i               (id_bubble_w),
    .rf_rs1_addr_o          (rs1_addr_w),
    .rf_rs2_addr_o          (rs2_addr_w),
    .rf_rs1_data_i          (rs1_data_w),
    .rf_rs2_data_i          (rs2_data_w),
    .idex_jal_o             (idex_jal_w),
    .idex_jalr_o            (idex_jalr_w),
    .idex_se_alu_src1_o     (idex_se_alu_src1_w),
    .idex_se_alu_src2_o     (idex_se_alu_src2_w),
    .idex_aluop_o           (idex_aluop_w),
    .idex_rs1_data_o        (idex_rs1_data_w),
    .idex_rs2_data_o        (idex_rs2_data_w),
    .idex_imm_o             (idex_imm_w),
    .idex_rs1_addr_o        (idex_rs1_addr_w),
    .idex_rs2_addr_o        (idex_rs2_addr_w),
    .idex_mem_we_o          (idex_mem_we_w),
    .idex_mem_en_o          (idex_mem_en_w),
    .idex_width_se_o        (idex_width_se_w),
    .idex_wb_se_o           (idex_wb_se_w),
    .idex_regwrite_o        (idex_regwrite_w),
    .idex_rd_addr_o         (idex_rd_addr_w),
    .idex_pc_o              (idex_pc_w)
  );

  assign is_load_instrucion = ((exmem_mem_we_w == 0) && (exmem_mem_en_w == 1)) ? 1'b1 : 1'b0;
  assign is_load_memwb_instruction = memwb_regwrite_w && (memwb_wb_se_w == 2'b01);

  assign exmem_load_hazard = is_load_instrucion &&
              ((exmem_rd_addr_w == rs1_addr_w) || (exmem_rd_addr_w == rs2_addr_w)) && (exmem_rd_addr_w != 0);

  assign memwb_load_hazard = is_load_memwb_instruction &&
              ((memwb_rd_addr_w == rs1_addr_w) || (memwb_rd_addr_w == rs2_addr_w)) && (memwb_rd_addr_w != 0);

  assign load_use_hazard = exmem_load_hazard || memwb_load_hazard;

  ex_stage u_ex_stage (
    .clk_i                (clk_i),
    .rst_i                (rst_i),
    .flush_i              (ex_flush_w),
    .stall_i              (ex_stall_w),
    .ex_pc_i              (idex_pc_w),
    .ex_imm_i             (idex_imm_w),
    .ex_rs1_data_i        (forward_src_1_w),
    .ex_rs2_data_i        (forward_src_2_w),
    .ex_jal_i             (idex_jal_w),
    .ex_jalr_i            (idex_jalr_w),
    .ex_alu_src1_i        (idex_se_alu_src1_w),
    .ex_alu_src2_i        (idex_se_alu_src2_w),
    .ex_aluop_i           (idex_aluop_w),
    .ex_mem_we_i          (idex_mem_we_w),
    .ex_mem_en_i          (idex_mem_en_w),
    .ex_width_se_i        (idex_width_se_w),
    .ex_wb_se_i           (idex_wb_se_w),
    .ex_regwrite_i        (idex_regwrite_w),
    .ex_rd_addr_i         (idex_rd_addr_w),
    .exif_pc_bj_o         (exif_pc_bj_w),
    .exif_bj_taken_o      (exif_bj_taken_w),
    .exmem_mem_we_o       (exmem_mem_we_w),
    .exmem_mem_en_o       (exmem_mem_en_w),
    .exmem_width_se_o     (exmem_width_se_w),
    .exmem_wb_se_o        (exmem_wb_se_w),
    .exmem_regwrite_o     (exmem_regwrite_w),
    .exmem_rd_addr_o      (exmem_rd_addr_w),
    .exmem_alu_result_o   (exmem_alu_result_w),
    .exmem_rs2_data_o     (exmem_rs2_data_w),
    .exmem_pc_plus_o      (exmem_pc_plus_w)
  );

  mem_stage_sync u_mem_stage (
    .clk_i               (clk_i),
    .rst_i               (rst_i),
    .hold_i              (external_hold_w),
    .mem_we_i            (exmem_mem_we_w),
    .mem_en_i            (exmem_mem_en_w),
    .mem_is_mmio_i       (dmem_is_mmio_i),
    .mem_width_se_i      (exmem_width_se_w),
    .mem_alu_result_i    (exmem_alu_result_w),
    .mem_data_i          (exmem_rs2_data_w),
    .mem_regwrite_i      (exmem_regwrite_w),
    .mem_rd_addr_i       (exmem_rd_addr_w),
    .mem_wb_se_i         (exmem_wb_se_w),
    .mem_pc_plus_i       (exmem_pc_plus_w),
    .en_o                (dmem_en_o),
    .we_o                (dmem_we_o),
    .addr_o              (dmem_addr_o),
    .data_w_o            (dmem_w_data_o),
    .data_r_i            (mem_r_data_w),
    .memwb_regwrite_o    (memwb_regwrite_w),
    .memwb_rd_addr_o     (memwb_rd_addr_w),
    .memwb_wb_se_o       (memwb_wb_se_w),
    .memwb_pc_plus_o     (memwb_pc_plus_w),
    .memwb_alu_result_o  (memwb_alu_result_w),
    .memwb_mem_data_o    (memwb_mem_data_w),
    .mem_data_w          (mem_data_w),
    .mem_stage_err_o     (mem_stage_err_w),
    .load_wait_o         (mem_load_wait_w),
    .load_resp_is_mmio_o (mem_load_resp_is_mmio_w)
  );

  forwarding u_forwarding (
    .ex_rs1_addr      (idex_rs1_addr_w),
    .ex_rs2_addr      (idex_rs2_addr_w),
    .ex_rs1_data      (idex_rs1_data_w),
    .ex_rs2_data      (idex_rs2_data_w),
    .exmem_regwrite   (exmem_regwrite_w),
    .exmem_rd_addr    (exmem_rd_addr_w),
    .exmem_wb_se      (exmem_wb_se_w),
    .exmem_alu_result (exmem_alu_result_w),
    .exmem_pc_plus    (exmem_pc_plus_w),
    .mem_data         (mem_data_w),
    .memwb_regwrite   (memwb_regwrite_w),
    .memwb_rd_addr    (memwb_rd_addr_w),
    .memwb_wb_se      (memwb_wb_se_w),
    .memwb_alu_result (memwb_alu_result_w),
    .memwb_mem_data   (memwb_mem_data_w),
    .memwb_pc_plus    (memwb_pc_plus_w),
    .forward_src_1    (forward_src_1_w),
    .forward_src_2    (forward_src_2_w)
  );

  assign mem_r_data_w = dmem_r_data_i;

  assign wb_data_w = (memwb_wb_se_w == 2'b00) ? memwb_alu_result_w :
                     (memwb_wb_se_w == 2'b01) ? memwb_mem_data_w   :
                     (memwb_wb_se_w == 2'b10) ? memwb_pc_plus_w    : 32'b0;

  assign rf_reg_write_w = memwb_regwrite_w;
  assign rf_rd_addr_w = memwb_rd_addr_w;
  assign rf_rd_data_w = wb_data_w;

  assign rs1_data_w = (rf_reg_write_w && (rf_rd_addr_w != 5'd0) && (rf_rd_addr_w == rs1_addr_w)) ? rf_rd_data_w : rs1_data;
  assign rs2_data_w = (rf_reg_write_w && (rf_rd_addr_w != 5'd0) && (rf_rd_addr_w == rs2_addr_w)) ? rf_rd_data_w : rs2_data;

`ifdef MMIO_DEBUG
  always @(posedge clk_i) begin
    if (!rst_i) begin
      $display("[CPU_TRACE] t=%0t pc=0x%08x ifid_instr=0x%08x idex_rd=x%0d exmem_addr=0x%08x exmem_mem_en=%0b exmem_mem_we=%0b memwb_rd=x%0d wb_data=0x%08x hold=%0b bubble=%0b",
               $time,
               ifid_pc_w,
               ifid_instruction_w,
               idex_rd_addr_w,
               exmem_alu_result_w,
               exmem_mem_en_w,
               exmem_mem_we_w,
               memwb_rd_addr_w,
               wb_data_w,
               front_hold_w,
               load_use_bubble_w);
    end
  end
`endif
endmodule

/////////////////////////////////////////////////////////////////////
//   ,------.                    ,--.                ,--.          //
//   |  .--. ' ,---.  ,--,--.    |  |    ,---. ,---. `--' ,---.    //
//   |  '--'.'| .-. |' ,-.  |    |  |   | .-. | .-. |,--.| .--'    //
//   |  |\  \ ' '-' '\ '-'  |    |  '--.' '-' ' '-' ||  |\ `--.    //
//   `--' '--' `---'  `--`--'    `-----' `---' `-   /`--' `---'    //
//                                             `---'               //
//    RISC-V                                                       //
//    Instruction Decoder                                          //
//                                                                 //
/////////////////////////////////////////////////////////////////////
//                                                                 //
//             Copyright (C) 2014-2021 ROA Logic BV                //
//             www.roalogic.com                                    //
//                                                                 //
//     Unless specifically agreed in writing, this software is     //
//   licensed under the RoaLogic Non-Commercial License            //
//   version-1.0 (the "License"), a copy of which is included      //
//   with this file or may be found on the RoaLogic website        //
//   http://www.roalogic.com. You may not use the file except      //
//   in compliance with the License.                               //
//                                                                 //
//     THIS SOFTWARE IS PROVIDED "AS IS" AND WITHOUT ANY           //
//   EXPRESS OF IMPLIED WARRANTIES OF ANY KIND.                    //
//   See the License for permissions and limitations under the     //
//   License.                                                      //
//                                                                 //
/////////////////////////////////////////////////////////////////////

/*
  Changelog: 2017-02-28
             2017-03-01: Updates for 1.9.1 priv.spec
             2018-01-20: Updates for 1.10 priv.spec
             2021-10-12: Fixed missing stall
*/

module riscv_id
import riscv_opcodes_pkg::*;
import riscv_state_pkg::*;
#(
  parameter    int                  XLEN           = 32,
  parameter    [XLEN          -1:0] PC_INIT        = 'h200,
  parameter    int                  HAS_HYPER      = 0,
  parameter    int                  HAS_SUPER      = 0,
  parameter    int                  HAS_USER       = 0,
  parameter    int                  HAS_FPU        = 0,
  parameter    int                  HAS_RVA        = 0,
  parameter    int                  HAS_RVM        = 0,
  parameter    int                  HAS_RVC        = 0,
  parameter    int                  MULT_LATENCY   = 0,
  parameter    int                  RF_REGOUT      = 1,
  parameter    int                  BP_GLOBAL_BITS = 2,
  parameter    int                  RSB_DEPTH      = 0,
  parameter    int                  MEM_STAGES     = 1
)
(
  input                             rst_ni,
  input                             clk_i,

  output reg                        id_stall_o,
  input                             ex_stall_i,
                                    du_stall_i,

  input                             bu_flush_i,
                                    st_flush_i,
                                    du_flush_i,

  input        [XLEN          -1:0] bu_nxt_pc_i,
                                    st_nxt_pc_i,


  //Program counter
  input        [XLEN          -1:0] pd_pc_i,
                                    pd_rsb_pc_i,
  input        [XLEN          -1:0] if_nxt_pc_i,
  output logic [XLEN          -1:0] id_pc_o,
                                    id_rsb_pc_o,

  input        [BP_GLOBAL_BITS-1:0] pd_bp_history_i,
  output logic [BP_GLOBAL_BITS-1:0] id_bp_history_o,
  input        [               1:0] pd_bp_predict_i,
  output logic [               1:0] id_bp_predict_o,


  //Instruction
  input  instruction_t              pd_insn_i,
  output instruction_t              id_insn_o,
  input  instruction_t              ex_insn_i,
                                    mem_insn_i [MEM_STAGES],
                                    wb_insn_i,
                                    dwb_insn_i,

  //Exceptions
  input  interrupts_t               st_interrupts_i,
  input                             int_nmi_i,
  input  interrupts_exceptions_t    pd_exceptions_i,
  output interrupts_exceptions_t    id_exceptions_o,
  input  interrupts_exceptions_t    ex_exceptions_i,
                                    mem_exceptions_i,
                                    wb_exceptions_i,


  //From State
  input        [              1:0] st_prv_i,
                                   st_xlen_i,
  input                            st_tvm_i,
                                   st_tw_i,
                                   st_tsr_i,
  input        [XLEN         -1:0] st_mcounteren_i,
                                   st_scounteren_i,


  //To RF
  output rsd_t                     id_rs1_o,
                                   id_rs2_o,

  //To execution units
  output logic [XLEN         -1:0] id_opA_o,
                                   id_opB_o,

  output logic                     id_userf_opA_o,
                                   id_userf_opB_o,
                                   id_bypex_opA_o,
                                   id_bypex_opB_o,

  //from MEM/WB
  input        [XLEN         -1:0] ex_r_i,
                                   mem_r_i [MEM_STAGES],
                                   wb_r_i,
                                   wb_memq_i,
                                   dwb_r_i
);

  //////////////////////////////////////////////////////////////////
  //
  // Functions
  //

  /* Use result from a stage?
   * 'x0' is used as a black hole. It should always be zero, but may contain
   *  other values in the pipeline; therefore we check if rd is non-zero
   */
  function logic use_result;
    input rsd_t rs, rd;
    input logic valid;

    use_result = (rs == rd ) & |rd  & valid;
  endfunction: use_result


  //next operand value, from lowest to highest priority
  function logic [XLEN-1:0] nxt_operand;
    input logic                  use_exr;
    input logic [MEM_STAGES-1:0] use_memr;
    input logic                  use_wbr;
    input logic [XLEN      -1:0] ex_r,
                                 mem_r     [MEM_STAGES],
                                 wb_memq,
                                 wb_r,
                                 dwb_r;
     input opcode_t              mem_opcode[MEM_STAGES];

     //default value (lowest priority)
     nxt_operand = dwb_r;

     //Write Back stage
     if (use_wbr) nxt_operand = wb_r;

     //upper MEM_STAGES
     for (int n=MEM_STAGES-1; n >= 0; n--)
       if (n == MEM_STAGES-1)
       begin
           //last MEM_STAGE; latch results from memory upon LOAD
           if (use_memr[MEM_STAGES-1]) nxt_operand = mem_opcode[MEM_STAGES-1] == OPC_LOAD ? wb_memq : mem_r[MEM_STAGES-1];
       end
       else
       begin
           if (use_memr[n]) nxt_operand = mem_r[n];
       end

     //lastly EX (highest priority)
     if (use_exr) nxt_operand = ex_r;
  endfunction: nxt_operand


  //////////////////////////////////////////////////////////////////
  //
  // Variables
  //
  genvar                  n;

  logic                   has_rvc,
                          has_rsb;

  logic                   id_bubble_r;
  logic                   multi_cycle_instruction;
  logic                   stalls,
                          flushes,
                          exceptions;

  interrupts_exceptions_t my_exceptions;

  //Immediates
  immI_t                  immI;
  immU_t                  immU;
  logic [XLEN       -1:0] ext_immI,
                          ext_immU;

  //Opcodes
  opcR_t                  pd_opcR;

  opcode_t                id_opcode,
                          ex_opcode,
                          mem_opcode  [MEM_STAGES],
                          wb_opcode,
                          dwb_opcode;
	    
  logic                   is_32bit_instruction;

  logic                   xlen64,    //Is the CPU state set to RV64?
                          xlen32,    //Is the CPU state set to RV32?
                          has_fpu,
                          has_muldiv,
                          has_amo,
                          has_u,
                          has_s,
                          has_h;

  rsd_t                   pd_rs1,
                          pd_rs2,
                          id_rd,
                          ex_rd,
                          mem_rd      [MEM_STAGES],
                          wb_rd,
                          dwb_rd;

  logic                   can_bypex,
                          can_use_exr,
                          can_use_memr[MEM_STAGES],
                          can_use_wbr,
		          can_use_dwbr;

  logic                   use_rf_opA,
                          use_rf_opB,
                          use_exr_opA,
                          use_exr_opB;
  logic [MEM_STAGES-1:0]  use_memr_opA,
                          use_memr_opB;
  logic                   use_wbr_opA,
                          use_wbr_opB,
                          use_dwbr_opA,
                          use_dwbr_opB;

  logic                   stall_ld_id,
                          stall_ld_ex;
  logic [MEM_STAGES-1:0]  stall_ld_mem;


  logic [XLEN       -1:0] nxt_opA,
		          nxt_opB;

  logic                   illegal_instr,
                          illegal_alu_instr,
                          illegal_lsu_instr,
                          illegal_muldiv_instr,
                          illegal_csr_rd,
                          illegal_csr_wr;


  //////////////////////////////////////////////////////////////////
  //
  // Module Body
  //
  assign has_rvc = HAS_RVC != 0;
  assign has_rsb = RSB_DEPTH > 0;
  

  /*
   * Program Counter
   */
  always @(posedge clk_i,negedge rst_ni)
    if      (!rst_ni                   ) id_pc_o <= PC_INIT;
    else if ( st_flush_i               ) id_pc_o <= st_nxt_pc_i;
    else if ( bu_flush_i 	       ) id_pc_o <= bu_nxt_pc_i; //Is this required?! 
    else if ( du_flush_i 	       ) id_pc_o <= if_nxt_pc_i;
    else if (!stalls   && !id_stall_o  ) id_pc_o <= pd_pc_i;


  always @(posedge clk_i)
    if (!stalls && !id_stall_o) id_rsb_pc_o <= has_rsb ? pd_rsb_pc_i : {$bits(id_rsb_pc_o){1'b0}};


  /*
   * Instruction
   *
   * TODO: push if-instr upon illegal-instruction
   */
  assign id_insn_o.retired = 1'b0;


  always @(posedge clk_i)
    if (!stalls) id_insn_o.instr <= pd_insn_i.instr;


  always @(posedge clk_i, negedge rst_ni)
    if      (!rst_ni) id_insn_o.dbg <= 1'b0;
    else if (!stalls) id_insn_o.dbg <= pd_insn_i.dbg;


  always @(posedge clk_i,negedge rst_ni)
    if      (!rst_ni                  ) id_bubble_r <= 1'b1;
    else if ( bu_flush_i || st_flush_i) id_bubble_r <= 1'b1;
    else if (!stalls                  ) id_bubble_r <= pd_insn_i.bubble | id_stall_o | my_exceptions.any;


  //local stall
  assign stalls           = ex_stall_i;
  assign flushes          = bu_flush_i | st_flush_i;
  assign exceptions       = ex_exceptions_i.any | mem_exceptions_i.any | wb_exceptions_i.any;
  assign id_insn_o.bubble = stalls | flushes | exceptions | id_bubble_r;


//This is the correct decoder for a 32bit instruction. But we change this in IF
//  assign is_32bit_instruction = ~&pd_insn_i.instr[4:2] & &pd_insn_i.instr[1:0];
  assign is_32bit_instruction = ~&pd_insn_i.instr[4:1] & pd_insn_i.instr[0];

  assign pd_opcR    = decode_opcR(pd_insn_i.instr);

  assign id_opcode  = decode_opcode(id_insn_o.instr );
  assign ex_opcode  = decode_opcode(ex_insn_i.instr );
generate
  for (n=0; n < MEM_STAGES; n++)
    assign mem_opcode[n] = decode_opcode(mem_insn_i[n].instr);
endgenerate
  assign wb_opcode  = decode_opcode(wb_insn_i.instr );
  assign dwb_opcode = decode_opcode(dwb_insn_i.instr);
  assign id_rd      = decode_rd    (id_insn_o.instr );
  assign ex_rd      = decode_rd    (ex_insn_i.instr );
generate
  for (n=0; n < MEM_STAGES; n++)
    assign mem_rd[n] = decode_rd   (mem_insn_i[n].instr);
endgenerate
  assign wb_rd      = decode_rd    (wb_insn_i.instr );
  assign dwb_rd     = decode_rd    (dwb_insn_i.instr);

  assign has_fpu    = (HAS_FPU    !=   0);
  assign has_muldiv = (HAS_RVM    !=   0);
  assign has_amo    = (HAS_RVA    !=   0);
  assign has_u      = (HAS_USER   !=   0);
  assign has_s      = (HAS_SUPER  !=   0);
  assign has_h      = (HAS_HYPER  !=   0);

  assign xlen64     = st_xlen_i == RV64I;
  assign xlen32     = st_xlen_i == RV32I;


  //Branch Predict History
  always @(posedge clk_i)
    if (!stalls && !id_stall_o) id_bp_predict_o <= pd_bp_predict_i;


  /*
   * Exceptions
   */
  always_comb
    begin
        my_exceptions                                =  pd_exceptions_i;

	my_exceptions.interrupts                     =  {$bits(st_interrupts_i){~pd_insn_i.bubble}} & st_interrupts_i;
	my_exceptions.nmi                            = ~pd_insn_i.bubble & int_nmi_i;
	
        my_exceptions.exceptions.illegal_instruction = ~pd_insn_i.bubble & (illegal_instr | pd_exceptions_i.exceptions.illegal_instruction);
        my_exceptions.exceptions.breakpoint          = ~pd_insn_i.bubble & (pd_insn_i.instr == EBREAK);
        my_exceptions.exceptions.umode_ecall         = ~pd_insn_i.bubble & (pd_insn_i.instr == ECALL ) & (st_prv_i == PRV_U) & has_u;
        my_exceptions.exceptions.smode_ecall         = ~pd_insn_i.bubble & (pd_insn_i.instr == ECALL ) & (st_prv_i == PRV_S) & has_s;
        my_exceptions.exceptions.hmode_ecall         = ~pd_insn_i.bubble & (pd_insn_i.instr == ECALL ) & (st_prv_i == PRV_H) & has_h;
        my_exceptions.exceptions.mmode_ecall         = ~pd_insn_i.bubble & (pd_insn_i.instr == ECALL ) & (st_prv_i == PRV_M);

	my_exceptions.any                            = |my_exceptions.exceptions | |my_exceptions.interrupts | int_nmi_i;
    end

  always @(posedge clk_i, negedge rst_ni)
    if      (!rst_ni                  ) id_exceptions_o <= 'h0;
    else if ( bu_flush_i || st_flush_i) id_exceptions_o <= 'h0;
    else if (!stalls                  )
        if ( id_stall_o) id_exceptions_o <= 'h0;
        else             id_exceptions_o <= my_exceptions;


  always @(posedge clk_i)
    if (!stalls && !id_stall_o) id_bp_history_o <= pd_bp_history_i;


  /*
   * To Register File
   */
  //address into register file. Gets registered in memory
  assign id_rs1_o = decode_rs1(pd_insn_i.instr);
  assign id_rs2_o = decode_rs2(pd_insn_i.instr);

  assign pd_rs1   = decode_rs1(pd_insn_i.instr);
  assign pd_rs2   = decode_rs2(pd_insn_i.instr);


  /*
   * Decode Immediates
   */
  assign immI = decode_immI(pd_insn_i.instr);
  assign immU = decode_immU(pd_insn_i.instr);
  assign ext_immI = { {XLEN-$bits(immI){immI[$left(immI,1)]}}, immI};
  assign ext_immU = { {XLEN-$bits(immU){immU[$left(immU,1)]}}, immU};


  /*
   * Create ALU operands
   * Feedback pipeline results here
   */
  assign use_rf_opA = ~(use_dwbr_opA | use_wbr_opA | |use_memr_opA | use_exr_opA);
  assign use_rf_opB = ~(use_dwbr_opB | use_wbr_opB | |use_memr_opB | use_exr_opB);
 

  always @(posedge clk_i)
    if (!stalls)
    casex (pd_opcR.opcode)
      OPC_OP_IMM  : begin
                        id_userf_opA_o <= use_rf_opA;
                        id_userf_opB_o <= 'b0;
                    end
      OPC_AUIPC   : begin
                        id_userf_opA_o <= 'b0;
                        id_userf_opB_o <= 'b0;
                    end
      OPC_OP_IMM32: begin
                        id_userf_opA_o <= use_rf_opA;
                        id_userf_opB_o <= 'b0;
                    end
      OPC_OP      : begin
                        id_userf_opA_o <= use_rf_opA;
                        id_userf_opB_o <= use_rf_opB;
                    end
      OPC_LUI     : begin
                        id_userf_opA_o <= 'b0;
                        id_userf_opB_o <= 'b0;
                    end
      OPC_OP32    : begin
                        id_userf_opA_o <= use_rf_opA;
                        id_userf_opB_o <= use_rf_opB;
                    end
      OPC_BRANCH  : begin
                        id_userf_opA_o <= use_rf_opA;
                        id_userf_opB_o <= use_rf_opB;
                    end
      OPC_JALR    : begin
                        id_userf_opA_o <= use_rf_opA;
                        id_userf_opB_o <= 'b0;
                    end
      OPC_LOAD    : begin
                        id_userf_opA_o <= use_rf_opA;
                        id_userf_opB_o <= 'b0;
                    end
      OPC_STORE   : begin
                        id_userf_opA_o <= use_rf_opA;
                        id_userf_opB_o <= use_rf_opB;
                    end
      OPC_SYSTEM  : begin
                        id_userf_opA_o <= use_rf_opA;
                        id_userf_opB_o <= 'b0;
                    end
      default     : begin
                        id_userf_opA_o <= 'b1;
                        id_userf_opB_o <= 'b1;
                    end
    endcase


  assign nxt_opA = nxt_operand(use_exr_opA, use_memr_opA, use_wbr_opA,
                               ex_r_i, mem_r_i, wb_memq_i, wb_r_i, dwb_r_i,
                               mem_opcode);
  assign nxt_opB = nxt_operand(use_exr_opB, use_memr_opB, use_wbr_opB,
                               ex_r_i, mem_r_i, wb_memq_i, wb_r_i, dwb_r_i,
                               mem_opcode);

  always @(posedge clk_i)
    if (!stalls)
    casex (pd_opcR.opcode)
      OPC_LOAD_FP : ;
      OPC_MISC_MEM: ;
      OPC_OP_IMM  : begin
                        id_opA_o <= nxt_opA;
                        id_opB_o <= ext_immI;
                    end
      OPC_AUIPC   : begin
                        id_opA_o <= pd_pc_i;
                        id_opB_o <= ext_immU;
                    end
      OPC_OP_IMM32: begin
                        id_opA_o <= nxt_opA;
                        id_opB_o <= ext_immI;
                    end
      OPC_LOAD    : begin
                        id_opA_o <= nxt_opA;
                        id_opB_o <= ext_immI;
                    end
      OPC_STORE   : begin
                        id_opA_o <= nxt_opA;
                        id_opB_o <= nxt_opB;
                    end
      OPC_STORE_FP: ;
      OPC_AMO     : ; 
      OPC_OP      : begin
                        id_opA_o <= nxt_opA;
                        id_opB_o <= nxt_opB;
                    end
      OPC_LUI     : begin
                        id_opA_o <= 0;
                        id_opB_o <= ext_immU;
                    end
      OPC_OP32    : begin
                        id_opA_o <= nxt_opA;
                        id_opB_o <= nxt_opB;
                    end
      OPC_MADD    : ;
      OPC_MSUB    : ;
      OPC_NMSUB   : ;
      OPC_NMADD   : ;
      OPC_OP_FP   : ;
      OPC_BRANCH  : begin
                        id_opA_o <= nxt_opA;
                        id_opB_o <= nxt_opB;
                    end
      OPC_JALR    : begin
                        id_opA_o <= nxt_opA;
                        id_opB_o <= ext_immI;
                    end
      OPC_SYSTEM  : begin
                        id_opA_o <= nxt_opA;     //for CSRxx
                        id_opB_o <= { {XLEN-$bits(pd_rs1){1'b0}},pd_rs1 }; //for CSRxxI
                    end
      default     : begin
                        id_opA_o <= 'hx;
                        id_opB_o <= 'hx;
                    end
    endcase



  /*
   * Bypasses
   */
  always @(posedge clk_i,negedge rst_ni)
    if (!rst_ni) multi_cycle_instruction <= 1'b0;
    else if (!stalls)
    casex ( {xlen32,pd_opcR} )
      {1'b?,MUL   } : multi_cycle_instruction <= MULT_LATENCY > 0 ? has_muldiv : 1'b0;
      {1'b?,MULH  } : multi_cycle_instruction <= MULT_LATENCY > 0 ? has_muldiv : 1'b0;
      {1'b0,MULW  } : multi_cycle_instruction <= MULT_LATENCY > 0 ? has_muldiv : 1'b0;
      {1'b?,MULHSU} : multi_cycle_instruction <= MULT_LATENCY > 0 ? has_muldiv : 1'b0;
      {1'b?,MULHU } : multi_cycle_instruction <= MULT_LATENCY > 0 ? has_muldiv : 1'b0;
      {1'b?,DIV   } : multi_cycle_instruction <= has_muldiv;
      {1'b0,DIVW  } : multi_cycle_instruction <= has_muldiv;
      {1'b?,DIVU  } : multi_cycle_instruction <= has_muldiv;
      {1'b0,DIVUW } : multi_cycle_instruction <= has_muldiv;
      {1'b?,REM   } : multi_cycle_instruction <= has_muldiv;
      {1'b0,REMW  } : multi_cycle_instruction <= has_muldiv;
      {1'b?,REMU  } : multi_cycle_instruction <= has_muldiv;
      {1'b0,REMUW } : multi_cycle_instruction <= has_muldiv;
      default       : multi_cycle_instruction <= 1'b0;
    endcase


  //Check for each stage if the result should be used
  always_comb
    casex (id_opcode)
       OPC_LOAD    : can_bypex = ~id_insn_o.bubble;
       OPC_OP_IMM  : can_bypex = ~id_insn_o.bubble;
       OPC_AUIPC   : can_bypex = ~id_insn_o.bubble;
       OPC_OP_IMM32: can_bypex = ~id_insn_o.bubble;
       OPC_AMO     : can_bypex = ~id_insn_o.bubble;
       OPC_OP      : can_bypex = ~id_insn_o.bubble;
       OPC_LUI     : can_bypex = ~id_insn_o.bubble;
       OPC_OP32    : can_bypex = ~id_insn_o.bubble;
       OPC_JALR    : can_bypex = ~id_insn_o.bubble;
       OPC_JAL     : can_bypex = ~id_insn_o.bubble;
       OPC_SYSTEM  : can_bypex = ~id_insn_o.bubble; //TODO not ALL SYSTEM
       default     : can_bypex = 1'b0;
    endcase


  always_comb
    casex (ex_opcode)
       OPC_LOAD    : can_use_exr = ~ex_insn_i.bubble;
       OPC_OP_IMM  : can_use_exr = ~ex_insn_i.bubble;
       OPC_AUIPC   : can_use_exr = ~ex_insn_i.bubble;
       OPC_OP_IMM32: can_use_exr = ~ex_insn_i.bubble;
       OPC_AMO     : can_use_exr = ~ex_insn_i.bubble;
       OPC_OP      : can_use_exr = ~ex_insn_i.bubble;
       OPC_LUI     : can_use_exr = ~ex_insn_i.bubble;
       OPC_OP32    : can_use_exr = ~ex_insn_i.bubble;
       OPC_JALR    : can_use_exr = ~ex_insn_i.bubble;
       OPC_JAL     : can_use_exr = ~ex_insn_i.bubble;
       OPC_SYSTEM  : can_use_exr = ~ex_insn_i.bubble; //TODO not ALL SYSTEM
       default     : can_use_exr = 1'b0;
    endcase


  always_comb
    for (int n=0; n < MEM_STAGES; n++)
        casex (mem_opcode[n])
           OPC_LOAD    : can_use_memr[n] = ~mem_insn_i[n].bubble;
           OPC_OP_IMM  : can_use_memr[n] = ~mem_insn_i[n].bubble;
           OPC_AUIPC   : can_use_memr[n] = ~mem_insn_i[n].bubble;
           OPC_OP_IMM32: can_use_memr[n] = ~mem_insn_i[n].bubble;
           OPC_AMO     : can_use_memr[n] = ~mem_insn_i[n].bubble;
           OPC_OP      : can_use_memr[n] = ~mem_insn_i[n].bubble;
           OPC_LUI     : can_use_memr[n] = ~mem_insn_i[n].bubble;
           OPC_OP32    : can_use_memr[n] = ~mem_insn_i[n].bubble;
           OPC_JALR    : can_use_memr[n] = ~mem_insn_i[n].bubble;
           OPC_JAL     : can_use_memr[n] = ~mem_insn_i[n].bubble;
           OPC_SYSTEM  : can_use_memr[n] = ~mem_insn_i[n].bubble; //TODO not ALL SYSTEM
           default     : can_use_memr[n] = 1'b0;
        endcase


  always_comb
    casex (wb_opcode)
       OPC_LOAD    : can_use_wbr =  ~wb_insn_i.bubble;
       OPC_OP_IMM  : can_use_wbr =  ~wb_insn_i.bubble;
       OPC_AUIPC   : can_use_wbr =  ~wb_insn_i.bubble;
       OPC_OP_IMM32: can_use_wbr =  ~wb_insn_i.bubble;
       OPC_AMO     : can_use_wbr =  ~wb_insn_i.bubble;
       OPC_OP      : can_use_wbr =  ~wb_insn_i.bubble;
       OPC_LUI     : can_use_wbr =  ~wb_insn_i.bubble;
       OPC_OP32    : can_use_wbr =  ~wb_insn_i.bubble;
       OPC_JALR    : can_use_wbr =  ~wb_insn_i.bubble;
       OPC_JAL     : can_use_wbr =  ~wb_insn_i.bubble;
       OPC_SYSTEM  : can_use_wbr =  ~wb_insn_i.bubble; //TODO not ALL SYSTEM
       default     : can_use_wbr = 1'b0;
    endcase

  always_comb
    casex (dwb_opcode)
       OPC_LOAD    : can_use_dwbr =  (RF_REGOUT > 0) ? ~dwb_insn_i.bubble : 1'b0;
       OPC_OP_IMM  : can_use_dwbr =  (RF_REGOUT > 0) ? ~dwb_insn_i.bubble : 1'b0;
       OPC_AUIPC   : can_use_dwbr =  (RF_REGOUT > 0) ? ~dwb_insn_i.bubble : 1'b0;
       OPC_OP_IMM32: can_use_dwbr =  (RF_REGOUT > 0) ? ~dwb_insn_i.bubble : 1'b0;
       OPC_AMO     : can_use_dwbr =  (RF_REGOUT > 0) ? ~dwb_insn_i.bubble : 1'b0;
       OPC_OP      : can_use_dwbr =  (RF_REGOUT > 0) ? ~dwb_insn_i.bubble : 1'b0;
       OPC_LUI     : can_use_dwbr =  (RF_REGOUT > 0) ? ~dwb_insn_i.bubble : 1'b0;
       OPC_OP32    : can_use_dwbr =  (RF_REGOUT > 0) ? ~dwb_insn_i.bubble : 1'b0;
       OPC_JALR    : can_use_dwbr =  (RF_REGOUT > 0) ? ~dwb_insn_i.bubble : 1'b0;
       OPC_JAL     : can_use_dwbr =  (RF_REGOUT > 0) ? ~dwb_insn_i.bubble : 1'b0;
       OPC_SYSTEM  : can_use_dwbr =  (RF_REGOUT > 0) ? ~dwb_insn_i.bubble : 1'b0; //TODO not ALL SYSTEM
       default     : can_use_dwbr = 1'b0;
    endcase


  /*
   set bypass switches
  */
  always_comb
    casex (pd_opcR.opcode)
      OPC_OP_IMM  : begin
                        use_exr_opA  = use_result(pd_rs1, ex_rd, can_use_exr);
                        use_exr_opB  = 1'b0;

                        for (int n=0; n < MEM_STAGES; n++)
                        begin
                            use_memr_opA[n] = use_result(pd_rs1, mem_rd[n], can_use_memr[n]);
                            use_memr_opB[n] = 1'b0;
                        end

                        use_wbr_opA  = use_result(pd_rs1, wb_rd, can_use_wbr);
                        use_wbr_opB  = 1'b0;

                        use_dwbr_opA = use_result(pd_rs1, dwb_rd, can_use_dwbr);
                        use_dwbr_opB = 1'b0;
                    end
      OPC_OP_IMM32: begin
                        use_exr_opA  = use_result(pd_rs1, ex_rd, can_use_exr);
                        use_exr_opB  = 1'b0;

                        for (int n=0; n < MEM_STAGES; n++)
                        begin
                            use_memr_opA[n] = use_result(pd_rs1, mem_rd[n], can_use_memr[n]);
                            use_memr_opB[n] = 1'b0;
                        end

                        use_wbr_opA  = use_result(pd_rs1, wb_rd, can_use_wbr);
                        use_wbr_opB  = 1'b0;

                        use_dwbr_opA = use_result(pd_rs1, dwb_rd, can_use_dwbr);
                        use_dwbr_opB = 1'b0;
                    end
      OPC_OP      : begin
                        use_exr_opA  = use_result(pd_rs1, ex_rd, can_use_exr);
                        use_exr_opB  = use_result(pd_rs2, ex_rd, can_use_exr);

                        for (int n=0; n < MEM_STAGES; n++)
                        begin
                            use_memr_opA[n] = use_result(pd_rs1, mem_rd[n], can_use_memr[n]);
                            use_memr_opB[n] = use_result(pd_rs2, mem_rd[n], can_use_memr[n]);
                        end

                        use_wbr_opA  = use_result(pd_rs1, wb_rd, can_use_wbr);
                        use_wbr_opB  = use_result(pd_rs2, wb_rd, can_use_wbr);

                        use_dwbr_opA = use_result(pd_rs1, dwb_rd, can_use_dwbr);
                        use_dwbr_opB = use_result(pd_rs2, dwb_rd, can_use_dwbr);
                    end
      OPC_OP32    : begin
                        use_exr_opA  = use_result(pd_rs1, ex_rd, can_use_exr);
                        use_exr_opB  = use_result(pd_rs2, ex_rd, can_use_exr);

                        for (int n=0; n < MEM_STAGES; n++)
                        begin
                            use_memr_opA[n] = use_result(pd_rs1, mem_rd[n], can_use_memr[n]);
                            use_memr_opB[n] = use_result(pd_rs2, mem_rd[n], can_use_memr[n]);
                        end

                        use_wbr_opA  = use_result(pd_rs1, wb_rd, can_use_wbr);
                        use_wbr_opB  = use_result(pd_rs2, wb_rd, can_use_wbr);

                        use_dwbr_opA = use_result(pd_rs1, dwb_rd, can_use_dwbr);
                        use_dwbr_opB = use_result(pd_rs2, dwb_rd, can_use_dwbr);
                    end
      OPC_BRANCH  : begin
                        use_exr_opA  = use_result(pd_rs1, ex_rd, can_use_exr);
                        use_exr_opB  = use_result(pd_rs2, ex_rd, can_use_exr);

                        for (int n=0; n < MEM_STAGES; n++)
                        begin
                            use_memr_opA[n] = use_result(pd_rs1, mem_rd[n], can_use_memr[n]);
                            use_memr_opB[n] = use_result(pd_rs2, mem_rd[n], can_use_memr[n]);
                        end

                        use_wbr_opA  = use_result(pd_rs1, wb_rd, can_use_wbr);
                        use_wbr_opB  = use_result(pd_rs2, wb_rd, can_use_wbr);

                        use_dwbr_opA = use_result(pd_rs1, dwb_rd, can_use_dwbr);
                        use_dwbr_opB = use_result(pd_rs2, dwb_rd, can_use_dwbr);
                    end
      OPC_JALR    : begin
                        use_exr_opA  = use_result(pd_rs1, ex_rd, can_use_exr);
                        use_exr_opB  = 1'b0;

                        for (int n=0; n < MEM_STAGES; n++)
                        begin
                            use_memr_opA[n] = use_result(pd_rs1, mem_rd[n], can_use_memr[n]);
                            use_memr_opB[n] = 1'b0;
                        end

                        use_wbr_opA  = use_result(pd_rs1, wb_rd, can_use_wbr);
                        use_wbr_opB  = 1'b0;

                        use_dwbr_opA = use_result(pd_rs1, dwb_rd, can_use_dwbr);
                        use_dwbr_opB = 1'b0;
                    end
     OPC_LOAD     : begin
                        use_exr_opA  = use_result(pd_rs1, ex_rd, can_use_exr);
                        use_exr_opB  = 1'b0;

                        for (int n=0; n < MEM_STAGES; n++)
                        begin
                            use_memr_opA[n] = use_result(pd_rs1, mem_rd[n], can_use_memr[n]);
                            use_memr_opB[n] = 1'b0;
                        end

                        use_wbr_opA  = use_result(pd_rs1, wb_rd, can_use_wbr);
                        use_wbr_opB  = 1'b0;

                        use_dwbr_opA = use_result(pd_rs1, dwb_rd, can_use_dwbr);
                        use_dwbr_opB = 1'b0;
                    end
     OPC_STORE    : begin
                        use_exr_opA  = use_result(pd_rs1, ex_rd, can_use_exr);
                        use_exr_opB  = use_result(pd_rs2, ex_rd, can_use_exr);

                        for (int n=0; n < MEM_STAGES; n++)
                        begin
                            use_memr_opA[n] = use_result(pd_rs1, mem_rd[n], can_use_memr[n]);
                            use_memr_opB[n] = use_result(pd_rs2, mem_rd[n], can_use_memr[n]);
                        end

                        use_wbr_opA  = use_result(pd_rs1, wb_rd, can_use_wbr);
                        use_wbr_opB  = use_result(pd_rs2, wb_rd, can_use_wbr);

                        use_dwbr_opA = use_result(pd_rs1, dwb_rd, can_use_dwbr);
                        use_dwbr_opB = use_result(pd_rs2, dwb_rd, can_use_dwbr);
                    end
     OPC_SYSTEM   : begin
                        use_exr_opA  = use_result(pd_rs1,  ex_rd, can_use_exr);
                        use_exr_opB  = 1'b0;

                        for (int n=0; n < MEM_STAGES; n++)
                        begin
                            use_memr_opA[n] = use_result(pd_rs1, mem_rd[n], can_use_memr[n]);
                            use_memr_opB[n] = 1'b0;
                        end

                        use_wbr_opA  = use_result(pd_rs1, wb_rd, can_use_wbr);
                        use_wbr_opB  = 1'b0;

                        use_dwbr_opA = use_result(pd_rs1, dwb_rd, can_use_dwbr);
                        use_dwbr_opB = 1'b0;
                    end
      default     : begin
                        use_exr_opA  = 1'b0;
                        use_exr_opB  = 1'b0;

                        for (int n=0; n < MEM_STAGES; n++)
                        begin
                            use_memr_opA[n] = 1'b0;
                            use_memr_opB[n] = 1'b0;
                        end

                        use_wbr_opA  = 1'b0;
                        use_wbr_opB  = 1'b0;

                        use_dwbr_opA = 1'b0;
                        use_dwbr_opB = 1'b0;
                    end
    endcase


  /*
  * Bypass EX for obvious reasons (no time to register results)
  */
  always @(posedge clk_i)
    if (!stalls)
    casex (pd_opcR.opcode)
      OPC_OP_IMM  : begin
                        id_bypex_opA_o  <= use_result(pd_rs1, id_rd, can_bypex);
                        id_bypex_opB_o  <= 1'b0;
                    end
      OPC_OP_IMM32: begin
                        id_bypex_opA_o  <= use_result(pd_rs1, id_rd, can_bypex);
                        id_bypex_opB_o  <= 1'b0;
                    end
      OPC_OP      : begin
                        id_bypex_opA_o  <= use_result(pd_rs1, id_rd, can_bypex);
                        id_bypex_opB_o  <= use_result(pd_rs2, id_rd, can_bypex);
                    end
      OPC_OP32    : begin
                        id_bypex_opA_o  <= use_result(pd_rs1, id_rd, can_bypex);
                        id_bypex_opB_o  <= use_result(pd_rs2, id_rd, can_bypex);
                    end
      OPC_BRANCH  : begin
                        id_bypex_opA_o  <= use_result(pd_rs1, id_rd, can_bypex);
                        id_bypex_opB_o  <= use_result(pd_rs2, id_rd, can_bypex);
                    end
      OPC_JALR    : begin
                        id_bypex_opA_o  <= use_result(pd_rs1, id_rd, can_bypex);
                        id_bypex_opB_o  <= 1'b0;
                    end
     OPC_LOAD     : begin
                        id_bypex_opA_o  <= use_result(pd_rs1, id_rd, can_bypex);
                        id_bypex_opB_o  <= 1'b0;
                    end
     OPC_STORE    : begin
                        id_bypex_opA_o  <= use_result(pd_rs1, id_rd, can_bypex);
                        id_bypex_opB_o  <= use_result(pd_rs2, id_rd, can_bypex);
                    end
     OPC_SYSTEM   : begin
                        id_bypex_opA_o  <= use_result(pd_rs1, id_rd, can_bypex);
                        id_bypex_opB_o  <= 1'b0;
                    end
      default     : begin
                        id_bypex_opA_o  <= 1'b0;
                        id_bypex_opB_o  <= 1'b0;
                    end
    endcase


  /*
   * Generate STALL
   */
  always_comb
    if (id_opcode != OPC_LOAD || id_insn_o.bubble) stall_ld_id = 1'b0;
    else
      casex (pd_opcR.opcode)
        OPC_OP_IMM  : stall_ld_id = (pd_rs1 == id_rd);
        OPC_OP_IMM32: stall_ld_id = (pd_rs1 == id_rd);
        OPC_OP      : stall_ld_id = (pd_rs1 == id_rd) | (pd_rs2 == id_rd);
        OPC_OP32    : stall_ld_id = (pd_rs1 == id_rd) | (pd_rs2 == id_rd);
        OPC_BRANCH  : stall_ld_id = (pd_rs1 == id_rd) | (pd_rs2 == id_rd);
        OPC_JALR    : stall_ld_id = (pd_rs1 == id_rd);
        OPC_LOAD    : stall_ld_id = (pd_rs1 == id_rd);
        OPC_STORE   : stall_ld_id = (pd_rs1 == id_rd) | (pd_rs2 == id_rd);
        OPC_SYSTEM  : stall_ld_id = (pd_rs1 == id_rd);
        default     : stall_ld_id = 'b0;
      endcase


  always_comb
    if (ex_opcode != OPC_LOAD || ex_insn_i.bubble) stall_ld_ex = 1'b0;
    else
      casex (pd_opcR.opcode)
        OPC_OP_IMM  : stall_ld_ex = (pd_rs1 == ex_rd);
        OPC_OP_IMM32: stall_ld_ex = (pd_rs1 == ex_rd);
        OPC_OP      : stall_ld_ex = (pd_rs1 == ex_rd) | (pd_rs2 == ex_rd);
        OPC_OP32    : stall_ld_ex = (pd_rs1 == ex_rd) | (pd_rs2 == ex_rd);
        OPC_BRANCH  : stall_ld_ex = (pd_rs1 == ex_rd) | (pd_rs2 == ex_rd);
        OPC_JALR    : stall_ld_ex = (pd_rs1 == ex_rd);
        OPC_LOAD    : stall_ld_ex = (pd_rs1 == ex_rd);
        OPC_STORE   : stall_ld_ex = (pd_rs1 == ex_rd) | (pd_rs2 == ex_rd);
        OPC_SYSTEM  : stall_ld_ex = (pd_rs1 == ex_rd);
        default     : stall_ld_ex = 'b0;
      endcase


  always_comb
    if (MEM_STAGES == 1) stall_ld_mem[0] = 1'b0;
    else
    begin
        for (int n=0; n < MEM_STAGES -1; n++)
          if (mem_opcode[n] != OPC_LOAD || mem_insn_i[n].bubble) stall_ld_mem[n] = 1'b0;
          else
            casex (pd_opcR.opcode)
              OPC_OP_IMM  : stall_ld_mem[n] = (pd_rs1 == mem_rd[n]);
              OPC_OP_IMM32: stall_ld_mem[n] = (pd_rs1 == mem_rd[n]);
              OPC_OP      : stall_ld_mem[n] = (pd_rs1 == mem_rd[n]) | (pd_rs2 == mem_rd[n]);
              OPC_OP32    : stall_ld_mem[n] = (pd_rs1 == mem_rd[n]) | (pd_rs2 == mem_rd[n]);
              OPC_BRANCH  : stall_ld_mem[n] = (pd_rs1 == mem_rd[n]) | (pd_rs2 == mem_rd[n]);
              OPC_JALR    : stall_ld_mem[n] = (pd_rs1 == mem_rd[n]);
              OPC_LOAD    : stall_ld_mem[n] = (pd_rs1 == mem_rd[n]);
              OPC_STORE   : stall_ld_mem[n] = (pd_rs1 == mem_rd[n]) | (pd_rs2 == mem_rd[n]);
              OPC_SYSTEM  : stall_ld_mem[n] = (pd_rs1 == mem_rd[n]);
              default     : stall_ld_mem[n] = 'b0;
            endcase

        stall_ld_mem[MEM_STAGES -1] = 1'b0;
    end


  always_comb
    if      (bu_flush_i || st_flush_i || du_flush_i) id_stall_o = 'b0;        //flush overrules stall
    else if (stalls                                ) id_stall_o =1'b1;// ~pd_insn_i.bubble; //TODO
    else                                             id_stall_o = stall_ld_id | stall_ld_ex | |stall_ld_mem;


  /*
   * Generate Illegal Instruction
   */
  always_comb
    casex (pd_opcR.opcode)
      OPC_LOAD  : illegal_instr = illegal_lsu_instr;
      OPC_STORE : illegal_instr = illegal_lsu_instr;
      default   : illegal_instr = illegal_alu_instr & (has_muldiv ? illegal_muldiv_instr : 1'b1);
    endcase


  //ALU
  always_comb
    casex (pd_insn_i.instr)
       FENCE  : illegal_alu_instr = 1'b0;
       FENCE_I: illegal_alu_instr = 1'b0;
       ECALL  : illegal_alu_instr = 1'b0;
       EBREAK : illegal_alu_instr = 1'b0;
       EBREAKC: illegal_alu_instr = ~has_rvc;
       URET   : illegal_alu_instr = ~has_u;
       SRET   : illegal_alu_instr = ~has_s | (st_prv_i <  PRV_S) | (st_prv_i == PRV_S && st_tsr_i);
       MRET   : illegal_alu_instr =          (st_prv_i != PRV_M);
       default:
            casex ( {xlen32,pd_opcR} )
              {1'b?,LUI   }: illegal_alu_instr = ~is_32bit_instruction & ~has_rvc;
              {1'b?,AUIPC }: illegal_alu_instr = ~is_32bit_instruction;
              {1'b?,JAL   }: illegal_alu_instr = ~is_32bit_instruction & ~has_rvc;
              {1'b?,JALR  }: illegal_alu_instr = ~is_32bit_instruction & ~has_rvc;
              {1'b?,BEQ   }: illegal_alu_instr = ~is_32bit_instruction & ~has_rvc;
              {1'b?,BNE   }: illegal_alu_instr = ~is_32bit_instruction & ~has_rvc;
              {1'b?,BLT   }: illegal_alu_instr = ~is_32bit_instruction;
              {1'b?,BGE   }: illegal_alu_instr = ~is_32bit_instruction;
              {1'b?,BLTU  }: illegal_alu_instr = ~is_32bit_instruction;
              {1'b?,BGEU  }: illegal_alu_instr = ~is_32bit_instruction;
              {1'b?,ADDI  }: illegal_alu_instr = ~is_32bit_instruction & ~has_rvc;
              {1'b?,ADD   }: illegal_alu_instr = ~is_32bit_instruction & ~has_rvc;
              {1'b0,ADDIW }: illegal_alu_instr = ~is_32bit_instruction & ~has_rvc;                       //RV64
              {1'b0,ADDW  }: illegal_alu_instr = ~is_32bit_instruction & ~has_rvc;                       //RV64
              {1'b?,SUB   }: illegal_alu_instr = ~is_32bit_instruction & ~has_rvc;
              {1'b0,SUBW  }: illegal_alu_instr = ~is_32bit_instruction & ~has_rvc;                       //RV64
              {1'b?,XORI  }: illegal_alu_instr = ~is_32bit_instruction;
              {1'b?,XOR   }: illegal_alu_instr = ~is_32bit_instruction & ~has_rvc;
              {1'b?,ORI   }: illegal_alu_instr = ~is_32bit_instruction;
              {1'b?,OR    }: illegal_alu_instr = ~is_32bit_instruction & ~has_rvc;
              {1'b?,ANDI  }: illegal_alu_instr = ~is_32bit_instruction & ~has_rvc;
              {1'b?,AND   }: illegal_alu_instr = ~is_32bit_instruction & ~has_rvc;
              {1'b?,SLLI  }: illegal_alu_instr =(~is_32bit_instruction & ~has_rvc) | (xlen32 & pd_opcR.funct7[0]);   //shamt[5] illegal for RV32
              {1'b?,SLL   }: illegal_alu_instr = ~is_32bit_instruction;
              {1'b0,SLLIW }: illegal_alu_instr = ~is_32bit_instruction;                                  //RV64
              {1'b0,SLLW  }: illegal_alu_instr = ~is_32bit_instruction;                                  //RV64
              {1'b?,SLTI  }: illegal_alu_instr = ~is_32bit_instruction;
              {1'b?,SLT   }: illegal_alu_instr = ~is_32bit_instruction;
              {1'b?,SLTIU }: illegal_alu_instr = ~is_32bit_instruction;
              {1'b?,SLTU  }: illegal_alu_instr = ~is_32bit_instruction;
              {1'b?,SRLI  }: illegal_alu_instr =(~is_32bit_instruction & ~has_rvc) | (xlen32 & pd_opcR.funct7[0]);   //shamt[5] illegal for RV32
              {1'b?,SRL   }: illegal_alu_instr = ~is_32bit_instruction;
              {1'b0,SRLIW }: illegal_alu_instr = ~is_32bit_instruction;                                  //RV64
              {1'b0,SRLW  }: illegal_alu_instr = ~is_32bit_instruction;                                  //RV64
              {1'b?,SRAI  }: illegal_alu_instr =(~is_32bit_instruction & ~has_rvc) | (xlen32 & pd_opcR.funct7[0]);   //shamt[5] illegal for RV32
              {1'b?,SRA   }: illegal_alu_instr = ~is_32bit_instruction;
              {1'b0,SRAIW }: illegal_alu_instr = ~is_32bit_instruction;
              {1'b?,SRAW  }: illegal_alu_instr = ~is_32bit_instruction;
  
              //system
              {1'b?,CSRRW }: illegal_alu_instr = ~is_32bit_instruction | illegal_csr_rd |            illegal_csr_wr;
              {1'b?,CSRRS }: illegal_alu_instr = ~is_32bit_instruction | illegal_csr_rd | (|pd_rs1 & illegal_csr_wr);
              {1'b?,CSRRC }: illegal_alu_instr = ~is_32bit_instruction | illegal_csr_rd | (|pd_rs1 & illegal_csr_wr);
              {1'b?,CSRRWI}: illegal_alu_instr = ~is_32bit_instruction | illegal_csr_rd | (|pd_rs1 & illegal_csr_wr);
              {1'b?,CSRRSI}: illegal_alu_instr = ~is_32bit_instruction | illegal_csr_rd | (|pd_rs1 & illegal_csr_wr);
              {1'b?,CSRRCI}: illegal_alu_instr = ~is_32bit_instruction | illegal_csr_rd | (|pd_rs1 & illegal_csr_wr);

              default: illegal_alu_instr = 1'b1;
            endcase
        endcase

  //LSU
  always_comb
    casex ( {xlen32,has_amo,pd_opcR} )
      {1'b?,1'b?,LB    }: illegal_lsu_instr = ~is_32bit_instruction;
      {1'b?,1'b?,LH    }: illegal_lsu_instr = ~is_32bit_instruction;
      {1'b?,1'b?,LW    }: illegal_lsu_instr = ~is_32bit_instruction & ~has_rvc;
      {1'b0,1'b?,LD    }: illegal_lsu_instr = ~is_32bit_instruction & ~has_rvc;  //RV64
      {1'b?,1'b?,LBU   }: illegal_lsu_instr = ~is_32bit_instruction;
      {1'b?,1'b?,LHU   }: illegal_lsu_instr = ~is_32bit_instruction;
      {1'b0,1'b?,LWU   }: illegal_lsu_instr = ~is_32bit_instruction;  //RV64
      {1'b?,1'b?,SB    }: illegal_lsu_instr = ~is_32bit_instruction;
      {1'b?,1'b?,SH    }: illegal_lsu_instr = ~is_32bit_instruction;
      {1'b?,1'b?,SW    }: illegal_lsu_instr = ~is_32bit_instruction & ~has_rvc;
      {1'b0,1'b?,SD    }: illegal_lsu_instr = ~is_32bit_instruction & ~has_rvc;  //RV64

      //AMO
      default           : illegal_lsu_instr = 1'b1;
    endcase


  //MULDIV
  always_comb
    casex ( {xlen32,pd_opcR} )
      {1'b?,MUL    }: illegal_muldiv_instr = ~is_32bit_instruction;
      {1'b?,MULH   }: illegal_muldiv_instr = ~is_32bit_instruction;
      {1'b0,MULW   }: illegal_muldiv_instr = ~is_32bit_instruction;  //RV64
      {1'b?,MULHSU }: illegal_muldiv_instr = ~is_32bit_instruction;
      {1'b?,MULHU  }: illegal_muldiv_instr = ~is_32bit_instruction;
      {1'b?,DIV    }: illegal_muldiv_instr = ~is_32bit_instruction;
      {1'b0,DIVW   }: illegal_muldiv_instr = ~is_32bit_instruction;  //RV64
      {1'b?,DIVU   }: illegal_muldiv_instr = ~is_32bit_instruction;
      {1'b0,DIVUW  }: illegal_muldiv_instr = ~is_32bit_instruction;  //RV64
      {1'b?,REM    }: illegal_muldiv_instr = ~is_32bit_instruction;
      {1'b0,REMW   }: illegal_muldiv_instr = ~is_32bit_instruction;  //RV64
      {1'b?,REMU   }: illegal_muldiv_instr = ~is_32bit_instruction;
      {1'b0,REMUW  }: illegal_muldiv_instr = ~is_32bit_instruction;
      default       : illegal_muldiv_instr = 1'b1;
    endcase

  /*
   * Check CSR accesses
   */
  always_comb
    case (pd_insn_i.instr[31:20])
      //User
      USTATUS   : illegal_csr_rd = ~has_u;
      UIE       : illegal_csr_rd = ~has_u;
      UTVEC     : illegal_csr_rd = ~has_u;
      USCRATCH  : illegal_csr_rd = ~has_u;
      UEPC      : illegal_csr_rd = ~has_u;
      UCAUSE    : illegal_csr_rd = ~has_u;
      UTVAL     : illegal_csr_rd = ~has_u;
      UIP       : illegal_csr_rd = ~has_u;
      FFLAGS    : illegal_csr_rd = ~has_fpu;
      FRM       : illegal_csr_rd = ~has_fpu;
      FCSR      : illegal_csr_rd = ~has_fpu;
      CYCLE     : illegal_csr_rd = ~has_u                                          |
                                   (~has_s & st_prv_i == PRV_U & ~st_mcounteren_i[CY]) |
                                   ( has_s & st_prv_i == PRV_S & ~st_mcounteren_i[CY]) |
                                   ( has_s & st_prv_i == PRV_U &  st_mcounteren_i[CY] & st_scounteren_i[CY]);
      TIME      : illegal_csr_rd = 1'b1; //trap on reading TIME. Machine mode must access external timer
      INSTRET   : illegal_csr_rd = ~has_u                                         |
                                   (~has_s & st_prv_i == PRV_U & ~st_mcounteren_i[IR]) |
                                   ( has_s & st_prv_i == PRV_S & ~st_mcounteren_i[IR]) |
                                   ( has_s & st_prv_i == PRV_U &  st_mcounteren_i[IR] & st_scounteren_i[IR]);
      CYCLEH    : illegal_csr_rd = ~has_u | ~xlen32                                |
                                   (~has_s & st_prv_i == PRV_U & ~st_mcounteren_i[CY]) |
                                   ( has_s & st_prv_i == PRV_S & ~st_mcounteren_i[CY]) |
                                   ( has_s & st_prv_i == PRV_U &  st_mcounteren_i[CY] & st_scounteren_i[CY]);
      TIMEH     : illegal_csr_rd = 1'b1; //trap on reading TIMEH. Machine mode must access external timer
      INSTRETH  : illegal_csr_rd = ~has_u | ~xlen32                                |
                                   (~has_s & st_prv_i == PRV_U & ~st_mcounteren_i[IR]) |
                                   ( has_s & st_prv_i == PRV_S & ~st_mcounteren_i[IR]) |
                                   ( has_s & st_prv_i == PRV_U &  st_mcounteren_i[IR] & st_scounteren_i[IR]);
      //TODO: hpmcounters

      //Supervisor
      SSTATUS   : illegal_csr_rd = ~has_s               | (st_prv_i < PRV_S);
      SEDELEG   : illegal_csr_rd = ~has_s               | (st_prv_i < PRV_S);
      SIDELEG   : illegal_csr_rd = ~has_s               | (st_prv_i < PRV_S);
      SIE       : illegal_csr_rd = ~has_s               | (st_prv_i < PRV_S);
      STVEC     : illegal_csr_rd = ~has_s               | (st_prv_i < PRV_S);
      SSCRATCH  : illegal_csr_rd = ~has_s               | (st_prv_i < PRV_S);
      SEPC      : illegal_csr_rd = ~has_s               | (st_prv_i < PRV_S);
      SCAUSE    : illegal_csr_rd = ~has_s               | (st_prv_i < PRV_S);
      STVAL     : illegal_csr_rd = ~has_s               | (st_prv_i < PRV_S);
      SIP       : illegal_csr_rd = ~has_s               | (st_prv_i < PRV_S);
      SATP      : illegal_csr_rd = ~has_s               | (st_prv_i < PRV_S) | (st_prv_i == PRV_S && st_tvm_i);

      //Hypervisor
/*
      HSTATUS   : illegal_csr_rd = (HAS_HYPER == 0)               | (st_prv_i < PRV_H);
      HEDELEG   : illegal_csr_rd = (HAS_HYPER == 0)               | (st_prv_i < PRV_H);
      HIDELEG   : illegal_csr_rd = (HAS_HYPER == 0)               | (st_prv_i < PRV_H);
      HIE       : illegal_csr_rd = (HAS_HYPER == 0)               | (st_prv_i < PRV_H);
      HTVEC     : illegal_csr_rd = (HAS_HYPER == 0)               | (st_prv_i < PRV_H);
      HSCRATCH  : illegal_csr_rd = (HAS_HYPER == 0)               | (st_prv_i < PRV_H);
      HEPC      : illegal_csr_rd = (HAS_HYPER == 0)               | (st_prv_i < PRV_H);
      HCAUSE    : illegal_csr_rd = (HAS_HYPER == 0)               | (st_prv_i < PRV_H);
      HTVAL     : illegal_csr_rd = (HAS_HYPER == 0)               | (st_prv_i < PRV_H);
      HIP       : illegal_csr_rd = (HAS_HYPER == 0)               | (st_prv_i < PRV_H);
*/
      //Machine
      MVENDORID : illegal_csr_rd =                        (st_prv_i < PRV_M);
      MARCHID   : illegal_csr_rd =                        (st_prv_i < PRV_M);
      MIMPID    : illegal_csr_rd =                        (st_prv_i < PRV_M);
      MHARTID   : illegal_csr_rd =                        (st_prv_i < PRV_M);
      MSTATUS   : illegal_csr_rd =                        (st_prv_i < PRV_M);
      MISA      : illegal_csr_rd =                        (st_prv_i < PRV_M);
      MEDELEG   : illegal_csr_rd =                        (st_prv_i < PRV_M);
      MIDELEG   : illegal_csr_rd =                        (st_prv_i < PRV_M);
      MIE       : illegal_csr_rd =                        (st_prv_i < PRV_M);
      MTVEC     : illegal_csr_rd =                        (st_prv_i < PRV_M);
      MCOUNTEREN: illegal_csr_rd =                        (st_prv_i < PRV_M);
      MSCRATCH  : illegal_csr_rd =                        (st_prv_i < PRV_M);
      MEPC      : illegal_csr_rd =                        (st_prv_i < PRV_M);
      MCAUSE    : illegal_csr_rd =                        (st_prv_i < PRV_M);
      MTVAL     : illegal_csr_rd =                        (st_prv_i < PRV_M);
      MIP       : illegal_csr_rd =                        (st_prv_i < PRV_M);
      PMPCFG0   : illegal_csr_rd =                        (st_prv_i < PRV_M);
      PMPCFG1   : illegal_csr_rd =          (XLEN > 32) | (st_prv_i < PRV_M);
      PMPCFG2   : illegal_csr_rd =          (XLEN > 64) | (st_prv_i < PRV_M);
      PMPCFG3   : illegal_csr_rd =          (XLEN > 32) | (st_prv_i < PRV_M);
      PMPADDR0  : illegal_csr_rd =                        (st_prv_i < PRV_M);
      PMPADDR1  : illegal_csr_rd =                        (st_prv_i < PRV_M);
      PMPADDR2  : illegal_csr_rd =                        (st_prv_i < PRV_M);
      PMPADDR3  : illegal_csr_rd =                        (st_prv_i < PRV_M);
      PMPADDR4  : illegal_csr_rd =                        (st_prv_i < PRV_M);
      PMPADDR5  : illegal_csr_rd =                        (st_prv_i < PRV_M);
      PMPADDR6  : illegal_csr_rd =                        (st_prv_i < PRV_M);
      PMPADDR7  : illegal_csr_rd =                        (st_prv_i < PRV_M);
      PMPADDR8  : illegal_csr_rd =                        (st_prv_i < PRV_M);
      PMPADDR9  : illegal_csr_rd =                        (st_prv_i < PRV_M);
      PMPADDR10 : illegal_csr_rd =                        (st_prv_i < PRV_M);
      PMPADDR11 : illegal_csr_rd =                        (st_prv_i < PRV_M);
      PMPADDR12 : illegal_csr_rd =                        (st_prv_i < PRV_M);
      PMPADDR13 : illegal_csr_rd =                        (st_prv_i < PRV_M);
      PMPADDR14 : illegal_csr_rd =                        (st_prv_i < PRV_M);
      PMPADDR15 : illegal_csr_rd =                        (st_prv_i < PRV_M);
      MCYCLE    : illegal_csr_rd =                        (st_prv_i < PRV_M); 
      MINSTRET  : illegal_csr_rd =                        (st_prv_i < PRV_M);
     //TODO: performance counters
      MCYCLEH   : illegal_csr_rd =          (XLEN > 32) | (st_prv_i < PRV_M);
      MINSTRETH : illegal_csr_rd =          (XLEN > 32) | (st_prv_i < PRV_M);

      default   : illegal_csr_rd = 1'b1;
    endcase

  always_comb
    case (pd_insn_i.instr[31:20])
      USTATUS   : illegal_csr_wr = ~has_u;
      UIE       : illegal_csr_wr = ~has_u;
      UTVEC     : illegal_csr_wr = ~has_u;
      USCRATCH  : illegal_csr_wr = ~has_u;
      UEPC      : illegal_csr_wr = ~has_u;
      UCAUSE    : illegal_csr_wr = ~has_u;
      UTVAL     : illegal_csr_wr = ~has_u;
      UIP       : illegal_csr_wr = ~has_u;
      FFLAGS    : illegal_csr_wr = ~has_fpu;
      FRM       : illegal_csr_wr = ~has_fpu;
      FCSR      : illegal_csr_wr = ~has_fpu;
      CYCLE     : illegal_csr_wr = 1'b1; 
      TIME      : illegal_csr_wr = 1'b1;
      INSTRET   : illegal_csr_wr = 1'b1;
      //TODO:hpmcounters
      CYCLEH    : illegal_csr_wr = 1'b1;
      TIMEH     : illegal_csr_wr = 1'b1;
      INSTRETH  : illegal_csr_wr = 1'b1;
      //Supervisor
      SSTATUS   : illegal_csr_wr = ~has_s               | (st_prv_i < PRV_S);
      SEDELEG   : illegal_csr_wr = ~has_s               | (st_prv_i < PRV_S);
      SIDELEG   : illegal_csr_wr = ~has_s               | (st_prv_i < PRV_S);
      SIE       : illegal_csr_wr = ~has_s               | (st_prv_i < PRV_S);
      STVEC     : illegal_csr_wr = ~has_s               | (st_prv_i < PRV_S);
      SCOUNTEREN: illegal_csr_wr = ~has_s               | (st_prv_i < PRV_S);
      SSCRATCH  : illegal_csr_wr = ~has_s               | (st_prv_i < PRV_S);
      SEPC      : illegal_csr_wr = ~has_s               | (st_prv_i < PRV_S);
      SCAUSE    : illegal_csr_wr = ~has_s               | (st_prv_i < PRV_S);
      STVAL     : illegal_csr_wr = ~has_s               | (st_prv_i < PRV_S);
      SIP       : illegal_csr_wr = ~has_s               | (st_prv_i < PRV_S);
      SATP      : illegal_csr_wr = ~has_s               | (st_prv_i < PRV_S)  | (st_prv_i == PRV_S && st_tvm_i);

     //Hypervisor
/*
      HSTATUS   : illegal_csr_wr = (HAS_HYPER == 0)               | (st_prv_i < PRV_H);
      HEDELEG   : illegal_csr_wr = (HAS_HYPER == 0)               | (st_prv_i < PRV_H);
      HIDELEG   : illegal_csr_wr = (HAS_HYPER == 0)               | (st_prv_i < PRV_H);
      HIE       : illegal_csr_wr = (HAS_HYPER == 0)               | (st_prv_i < PRV_H);
      HTVEC     : illegal_csr_wr = (HAS_HYPER == 0)               | (st_prv_i < PRV_H);
      HSCRATCH  : illegal_csr_wr = (HAS_HYPER == 0)               | (st_prv_i < PRV_H);
      HEPC      : illegal_csr_wr = (HAS_HYPER == 0)               | (st_prv_i < PRV_H);
      HCAUSE    : illegal_csr_wr = (HAS_HYPER == 0)               | (st_prv_i < PRV_H);
      HBADADDR  : illegal_csr_wr = (HAS_HYPER == 0)               | (st_prv_i < PRV_H);
      HIP       : illegal_csr_wr = (HAS_HYPER == 0)               | (st_prv_i < PRV_H);
*/
      //Machine
      MVENDORID : illegal_csr_wr = 1'b1;
      MARCHID   : illegal_csr_wr = 1'b1;
      MIMPID    : illegal_csr_wr = 1'b1;
      MHARTID   : illegal_csr_wr = 1'b1;
      MSTATUS   : illegal_csr_wr =                        (st_prv_i < PRV_M);
      MISA      : illegal_csr_wr =                        (st_prv_i < PRV_M);
      MEDELEG   : illegal_csr_wr =                        (st_prv_i < PRV_M);
      MIDELEG   : illegal_csr_wr =                        (st_prv_i < PRV_M);
      MIE       : illegal_csr_wr =                        (st_prv_i < PRV_M);
      MTVEC     : illegal_csr_wr =                        (st_prv_i < PRV_M);
      MNMIVEC   : illegal_csr_wr =                        (st_prv_i < PRV_M);
      MCOUNTEREN: illegal_csr_wr =                        (st_prv_i < PRV_M);
      MSCRATCH  : illegal_csr_wr =                        (st_prv_i < PRV_M);
      MEPC      : illegal_csr_wr =                        (st_prv_i < PRV_M);
      MCAUSE    : illegal_csr_wr =                        (st_prv_i < PRV_M);
      MTVAL     : illegal_csr_wr =                        (st_prv_i < PRV_M);
      MIP       : illegal_csr_wr =                        (st_prv_i < PRV_M);
      PMPCFG0   : illegal_csr_wr =                        (st_prv_i < PRV_M);
      PMPCFG1   : illegal_csr_wr =          (XLEN > 32) | (st_prv_i < PRV_M);
      PMPCFG2   : illegal_csr_wr =          (XLEN > 64) | (st_prv_i < PRV_M);
      PMPCFG3   : illegal_csr_wr =          (XLEN > 32) | (st_prv_i < PRV_M);
      PMPADDR0  : illegal_csr_wr =                        (st_prv_i < PRV_M);
      PMPADDR1  : illegal_csr_wr =                        (st_prv_i < PRV_M);
      PMPADDR2  : illegal_csr_wr =                        (st_prv_i < PRV_M);
      PMPADDR3  : illegal_csr_wr =                        (st_prv_i < PRV_M);
      PMPADDR4  : illegal_csr_wr =                        (st_prv_i < PRV_M);
      PMPADDR5  : illegal_csr_wr =                        (st_prv_i < PRV_M);
      PMPADDR6  : illegal_csr_wr =                        (st_prv_i < PRV_M);
      PMPADDR7  : illegal_csr_wr =                        (st_prv_i < PRV_M);
      PMPADDR8  : illegal_csr_wr =                        (st_prv_i < PRV_M);
      PMPADDR9  : illegal_csr_wr =                        (st_prv_i < PRV_M);
      PMPADDR10 : illegal_csr_wr =                        (st_prv_i < PRV_M);
      PMPADDR11 : illegal_csr_wr =                        (st_prv_i < PRV_M);
      PMPADDR12 : illegal_csr_wr =                        (st_prv_i < PRV_M);
      PMPADDR13 : illegal_csr_wr =                        (st_prv_i < PRV_M);
      PMPADDR14 : illegal_csr_wr =                        (st_prv_i < PRV_M);
      PMPADDR15 : illegal_csr_wr =                        (st_prv_i < PRV_M);
      MCYCLE    : illegal_csr_wr =                        (st_prv_i < PRV_M); 
      MINSTRET  : illegal_csr_wr =                        (st_prv_i < PRV_M);
     //TODO: performance counters
      MCYCLEH   : illegal_csr_wr =          (XLEN > 32) | (st_prv_i < PRV_M);
      MINSTRETH : illegal_csr_wr =          (XLEN > 32) | (st_prv_i < PRV_M);

      default   : illegal_csr_wr = 1'b1;
    endcase

endmodule



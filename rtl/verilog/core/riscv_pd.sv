/////////////////////////////////////////////////////////////////////
//   ,------.                    ,--.                ,--.          //
//   |  .--. ' ,---.  ,--,--.    |  |    ,---. ,---. `--' ,---.    //
//   |  '--'.'| .-. |' ,-.  |    |  |   | .-. | .-. |,--.| .--'    //
//   |  |\  \ ' '-' '\ '-'  |    |  '--.' '-' ' '-' ||  |\ `--.    //
//   `--' '--' `---'  `--`--'    `-----' `---' `-   /`--' `---'    //
//                                             `---'               //
//    RISC-V                                                       //
//    Instruction Pre-Decoder                                      //
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

import riscv_opcodes_pkg::*;
import riscv_state_pkg::*;

module riscv_pd #(
  parameter                       XLEN           = 32,
  parameter  [XLEN          -1:0] PC_INIT        = 'h200,
  parameter                       HAS_RVC        = 0,
  parameter                       HAS_BPU        = 0,
  parameter                       BP_GLOBAL_BITS = 2
)
(
  input                           rst_ni,          //Reset
  input                           clk_i,           //Clock
  
  input                           id_stall_i,
  output                          pd_stall_o,
  input                           du_mode_i,

  input                           bu_flush_i,      //flush pipe & load new program counter
                                  st_flush_i,

  output                          pd_flush_o,

  output rsd_t                    pd_rs1_o,
                                  pd_rs2_o,

  output     [              11:0] pd_csr_reg_o,

  input      [XLEN          -1:0] bu_nxt_pc_i,     //Branch Unit Next Program Counter
                                  st_nxt_pc_i,     //State Next Program Counter
  output reg [XLEN          -1:0] pd_nxt_pc_o,     //Branch Preditor Next Program Counter
  output reg                      pd_latch_nxt_pc_o,

  input      [BP_GLOBAL_BITS-1:0] if_bp_history_i,
  output reg [BP_GLOBAL_BITS-1:0] pd_bp_history_o,

  input      [               1:0] bp_bp_predict_i, //Branch Prediction bits
  output reg [               1:0] pd_bp_predict_o, //push down the pipe

  input      [XLEN          -1:0] if_pc_i,
  output reg [XLEN          -1:0] pd_pc_o,

  input  instruction_t            if_insn_i,
  output instruction_t            pd_insn_o,
  input  instruction_t            id_insn_i,

  input  interrupts_exceptions_t  if_exceptions_i,
  output interrupts_exceptions_t  pd_exceptions_o,
  input  interrupts_exceptions_t  id_exceptions_i,
                                  ex_exceptions_i,
                                  mem_exceptions_i,
                                  wb_exceptions_i
);

  ////////////////////////////////////////////////////////////////
  //
  // Constants
  //

  //Instruction address mask
  localparam ADR_MASK = HAS_RVC != 0 ? {XLEN{1'b1}} << 1 : {XLEN{1'b1}} << 2;


  ////////////////////////////////////////////////////////////////
  //
  // Variables
  //

  //Immediates for branches and jumps
  immUJ_t           immUJ;
  immSB_t           immSB;
  logic [XLEN -1:0] ext_immUJ,
                    ext_immSB;

  logic [      1:0] branch_predicted;

  logic             branch_taken,
                    stalled_branch;

  logic             local_stall;


  ////////////////////////////////////////////////////////////////
  //
  // Module Body
  //

  //All flush signals
  assign pd_flush_o = bu_flush_i | st_flush_i;


  //Stall when write-CSR
  //This can be more advanced, but who cares ... this is not critical
  always @(posedge clk_i, negedge rst_ni)
    if      (!rst_ni     ) local_stall <= 1'b0;
    else if ( local_stall) local_stall <= 1'b0;
    else if (!id_stall_i )
      casex ( decode_opcR(if_insn_i.instr) )
          CSRRW  : local_stall <= ~if_insn_i.bubble;
          CSRRWI : local_stall <= ~if_insn_i.bubble;
          CSRRS  : local_stall <= ~if_insn_i.bubble & |decode_rs1 (if_insn_i.instr);
          CSRRSI : local_stall <= ~if_insn_i.bubble & |decode_immI(if_insn_i.instr);
          CSRRC  : local_stall <= ~if_insn_i.bubble & |decode_rs1 (if_insn_i.instr);
          CSRRCI : local_stall <= ~if_insn_i.bubble & |decode_immI(if_insn_i.instr);
          default: local_stall <= 1'b0;
      endcase


  assign pd_stall_o = id_stall_i | local_stall;


  /*
   * To Register File (registered outputs)
   */
  //address into register file. Gets registered in memory
  assign pd_rs1_o = decode_rs1(if_insn_i.instr);
  assign pd_rs2_o = decode_rs2(if_insn_i.instr);


  /*
   * To State (CSR - registered output)
   */
  assign pd_csr_reg_o = if_insn_i.instr.I.imm;


  //Program counter
  always @(posedge clk_i, negedge rst_ni)
    if      (!rst_ni     ) pd_pc_o <= PC_INIT     & ADR_MASK;
    else if ( st_flush_i ) pd_pc_o <= st_nxt_pc_i & ADR_MASK;
    else if ( bu_flush_i ) pd_pc_o <= bu_nxt_pc_i & ADR_MASK;
    else if (!pd_stall_o ) pd_pc_o <= if_pc_i     & ADR_MASK;


  //Instruction	
  always @(posedge clk_i, negedge rst_ni)
    if      (!rst_ni    ) pd_insn_o.instr <= INSTR_NOP;
    else if (!id_stall_i) pd_insn_o.instr <= if_insn_i.instr;


  //Bubble
  always @(posedge clk_i, negedge rst_ni)
    if      (!rst_ni              ) pd_insn_o.bubble <= 1'b1;
    else if ( pd_flush_o          ) pd_insn_o.bubble <= 1'b1;
    else if ( id_exceptions_i.any  ||
              ex_exceptions_i.any  ||
              mem_exceptions_i.any ||
              wb_exceptions_i.any ) pd_insn_o.bubble <= 1'b1;
    else if (!id_stall_i)
      if (local_stall) pd_insn_o.bubble <= 1'b1;
      else             pd_insn_o.bubble <= if_insn_i.bubble;


  //Exceptions
  always @(posedge clk_i, negedge rst_ni)
    if      (!rst_ni     ) pd_exceptions_o <= 'h0;
    else if ( pd_flush_o ) pd_exceptions_o <= 'h0;
    else if ( pd_stall_o ) pd_exceptions_o <= 'h0;
    else                   pd_exceptions_o <= if_exceptions_i;


  //Branch Predict History
  always @(posedge clk_i)
    if (!pd_stall_o) pd_bp_history_o <= if_bp_history_i;

    
  /*
   * Branches & Jump
   */
  assign immUJ = decode_immUJ(if_insn_i.instr);
  assign immSB = decode_immSB(if_insn_i.instr);
  assign ext_immUJ = { {XLEN-$bits(immUJ){immUJ[$left(immUJ,1)]}}, immUJ};
  assign ext_immSB = { {XLEN-$bits(immSB){immSB[$left(immSB,1)]}}, immSB};


  // Branch and Jump prediction
  always_comb
    casex ( {du_mode_i, if_insn_i.bubble, decode_opcode(if_insn_i.instr)} )
      {1'b0, 1'b0,OPC_JAL   } : begin
                                    branch_taken     = 1'b1;
                                    branch_predicted = 2'b10;
                                    pd_nxt_pc_o      = if_pc_i + ext_immUJ;
                                end
      {1'b0, 1'b0,OPC_BRANCH} : begin
                                   //if this CPU has a Branch Predict Unit, then use it's prediction
                                   //otherwise assume backwards jumps taken, forward jumps not taken
                                   branch_taken     = (HAS_BPU != 0) ? bp_bp_predict_i[1] : ext_immSB[31];
                                   branch_predicted = (HAS_BPU != 0) ? bp_bp_predict_i    : {ext_immSB[31], 1'b0};
                                   pd_nxt_pc_o      = if_pc_i + ext_immSB;
                                end
      default                 : begin
                                    branch_taken     = 1'b0;
                                    branch_predicted = 2'b00;
                                    pd_nxt_pc_o      = 'hx;
                                end
    endcase



  always @(posedge clk_i)
    stalled_branch <= branch_taken & id_stall_i;

  //generate latch strobe
  assign pd_latch_nxt_pc_o = branch_taken & ~stalled_branch;


  //to Branch Prediction Unit
  always @(posedge clk_i, negedge rst_ni)
    if      (!rst_ni    ) pd_bp_predict_o <= 2'b00;
    else if (!pd_stall_o) pd_bp_predict_o <= branch_predicted;

endmodule


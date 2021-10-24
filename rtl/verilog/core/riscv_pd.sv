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
  parameter            XLEN           = 32,
  parameter [XLEN-1:0] PC_INIT        = 'h200,
  parameter            HAS_BPU        = 0
)
(
  input                  rst_ni,          //Reset
  input                  clk_i,           //Clock
  
  input                  id_stall_i,
  output                 pd_stall_o,
  input                  du_mode_i,

  input                  bu_flush_i,      //flush pipe & load new program counter
                         st_flush_i,

  output                 pd_flush_o,

  output rsd_t           pd_rs1_o,
                         pd_rs2_o,

  input      [XLEN -1:0] bu_nxt_pc_i,     //Branch Unit Next Program Counter
                         st_nxt_pc_i,     //State Next Program Counter
  output reg [XLEN -1:0] pd_nxt_pc_o,     //Branch Preditor Next Program Counter
  output reg             pd_latch_nxt_pc_o,

  input      [      1:0] bp_bp_predict_i, //Branch Prediction bits
  output reg [      1:0] pd_bp_predict_o, //push down the pipe

  input      [XLEN -1:0] if_pc_i,
  output reg [XLEN -1:0] pd_pc_o,

  input  instruction_t   if_insn_i,
  output instruction_t   pd_insn_o,

  input  exceptions_t    if_exceptions_i,
  output exceptions_t    pd_exceptions_o,
  input  exceptions_t    id_exceptions_i,
                         ex_exceptions_i,
                         mem_exceptions_i,
                         wb_exceptions_i
);

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
                    dbranch_taken;


  ////////////////////////////////////////////////////////////////
  //
  // Module Body
  //

  //All flush signals
  assign pd_flush_o = bu_flush_i | st_flush_i;

  assign pd_stall_o = id_stall_i;

  /*
   * To Register File (registered outputs)
   */
  //address into register file. Gets registered in memory
  assign pd_rs1_o = decode_rs1(if_insn_i.instr);
  assign pd_rs2_o = decode_rs2(if_insn_i.instr);

  
  //Program counter
  always @(posedge clk_i, negedge rst_ni)
    if      (!rst_ni     ) pd_pc_o <= PC_INIT;
    else if ( st_flush_i ) pd_pc_o <= st_nxt_pc_i;
    else if ( bu_flush_i ) pd_pc_o <= bu_nxt_pc_i;
    else if (!pd_stall_o ) pd_pc_o <= if_pc_i;


  //Instruction	
  always @(posedge clk_i, negedge rst_ni)
    if      (!rst_ni    ) pd_insn_o.instr <= INSTR_NOP;
    else if (!pd_stall_o) pd_insn_o.instr <= if_insn_i.instr;


  //Bubble
  always @(posedge clk_i, negedge rst_ni)
    if      (!rst_ni              ) pd_insn_o.bubble <= 1'b1;
    else if ( pd_flush_o          ) pd_insn_o.bubble <= 1'b1;
    else if ( id_exceptions_i.any  ||
              ex_exceptions_i.any  ||
              mem_exceptions_i.any ||
              wb_exceptions_i.any ) pd_insn_o.bubble <= 1'b1;
    else if (!id_stall_i          ) pd_insn_o.bubble <= if_insn_i.bubble;


  //Exceptions
  always @(posedge clk_i, negedge rst_ni)
    if      (!rst_ni     ) pd_exceptions_o <= 'h0;
    else if ( pd_flush_o ) pd_exceptions_o <= 'h0;
    else if (!id_stall_i ) pd_exceptions_o <= if_exceptions_i;


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
      default           : begin
                              branch_taken     = 1'b0;
			      branch_predicted = 2'b00;
                              pd_nxt_pc_o      = 'hx;
                          end
    endcase


  always @(posedge clk_i)
    dbranch_taken <= branch_taken;


  //generate latch strobe
  assign pd_latch_nxt_pc_o = branch_taken & ~dbranch_taken;


  //to Branch Prediction Unit
  always @(posedge clk_i, negedge rst_ni)
    if      (!rst_ni    ) pd_bp_predict_o <= 2'b00;
    else if (!id_stall_i) pd_bp_predict_o <= branch_predicted;

endmodule


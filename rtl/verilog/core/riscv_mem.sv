/////////////////////////////////////////////////////////////////////
//   ,------.                    ,--.                ,--.          //
//   |  .--. ' ,---.  ,--,--.    |  |    ,---. ,---. `--' ,---.    //
//   |  '--'.'| .-. |' ,-.  |    |  |   | .-. | .-. |,--.| .--'    //
//   |  |\  \ ' '-' '\ '-'  |    |  '--.' '-' ' '-' ||  |\ `--.    //
//   `--' '--' `---'  `--`--'    `-----' `---' `-   /`--' `---'    //
//                                             `---'               //
//    RISC-V                                                       //
//    Memory Unit (Mem Stage)                                      //
//                                                                 //
/////////////////////////////////////////////////////////////////////
//                                                                 //
//             Copyright (C) 2017-2021 ROA Logic BV                //
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


module riscv_mem
import riscv_opcodes_pkg::*;
import riscv_state_pkg::*;
#(
  parameter              XLEN    = 32,
  parameter  [XLEN -1:0] PC_INIT = 'h200
)
(
  input                          rst_ni,
  input                          clk_i,

  input                          mem_stall_i,
  output                         mem_stall_o,

  //Program counter
  input      [XLEN         -1:0] mem_pc_i,
  output reg [XLEN         -1:0] mem_pc_o,

  //Instruction
  input  instruction_t           mem_insn_i,
  output instruction_t           mem_insn_o,

  input  interrupts_exceptions_t mem_exceptions_dn_i,
  output interrupts_exceptions_t mem_exceptions_dn_o,
  input  interrupts_exceptions_t mem_exceptions_up_i,
  output interrupts_exceptions_t mem_exceptions_up_o,

 
  //From upstream (EX)
  input      [XLEN         -1:0] mem_r_i,
                                 mem_memadr_i,

  //To downstream (WB)
  output reg [XLEN         -1:0] mem_r_o,
  output reg [XLEN         -1:0] mem_memadr_o
);
  ////////////////////////////////////////////////////////////////
  //
  // Module Body
  //

  /*
   * Program Counter
   */
  always @(posedge clk_i,negedge rst_ni)
    if      (!rst_ni     ) mem_pc_o <= PC_INIT;
    else if (!mem_stall_i) mem_pc_o <= mem_pc_i;

  /*
   * Stall
   */
  assign mem_stall_o = mem_stall_i;

  
  /*
   * Instruction
   */
  always @(posedge clk_i)
    if (!mem_stall_i) mem_insn_o.instr <= mem_insn_i.instr;


  always @(posedge clk_i, negedge rst_ni)
    if      (!rst_ni     ) mem_insn_o.dbg <= 1'b0;
    else if (!mem_stall_i) mem_insn_o.dbg <= mem_insn_i.dbg;


  always @(posedge clk_i, negedge rst_ni)
    if      (!rst_ni                 ) mem_insn_o.bubble <= 1'b1;
    else if ( mem_exceptions_up_i.any) mem_insn_o.bubble <= 1'b1;
    else if (!mem_stall_i            ) mem_insn_o.bubble <= mem_insn_i.bubble;


  always @(posedge clk_i, negedge rst_ni)
    if      (!rst_ni                 ) mem_insn_o.retired <= 'h0;
    else if ( mem_exceptions_up_i.any) mem_insn_o.retired <= 'h0;
    else if ( mem_stall_i            ) mem_insn_o.retired <= 'h0;
    else                               mem_insn_o.retired <= mem_insn_i.retired;


  /*
   * Data
   */
  always @(posedge clk_i)
    if (!mem_stall_i) mem_r_o <= mem_r_i;

  always @(posedge clk_i)
    if (!mem_stall_i) mem_memadr_o <= mem_memadr_i;


  /*
   * Exception
   */
  assign mem_exceptions_up_o = mem_exceptions_dn_o | mem_exceptions_up_i;

  always @(posedge clk_i, negedge rst_ni)
    if      (!rst_ni                 ) mem_exceptions_dn_o <= 'h0;
    else if ( mem_exceptions_up_o.any) mem_exceptions_dn_o <= 'h0;
    else if (!mem_stall_i            ) mem_exceptions_dn_o <= mem_exceptions_dn_i;

endmodule : riscv_mem


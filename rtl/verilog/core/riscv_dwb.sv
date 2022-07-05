/////////////////////////////////////////////////////////////////////
//   ,------.                    ,--.                ,--.          //
//   |  .--. ' ,---.  ,--,--.    |  |    ,---. ,---. `--' ,---.    //
//   |  '--'.'| .-. |' ,-.  |    |  |   | .-. | .-. |,--.| .--'    //
//   |  |\  \ ' '-' '\ '-'  |    |  '--.' '-' ' '-' ||  |\ `--.    //
//   `--' '--' `---'  `--`--'    `-----' `---' `-   /`--' `---'    //
//                                             `---'               //
//    RISC-V                                                       //
//    Post-Write Back                                              //
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

//Simply delay WriteBack output for Bypass purposes
module riscv_dwb #(
  parameter            XLEN    = 32,
  parameter [XLEN-1:0] PC_INIT = 'h200
)
(
  input                  rst_ni,          //Reset
  input                  clk_i,           //Clock
  
  input  instruction_t   wb_insn_i,
  input                  wb_we_i,
  input      [XLEN -1:0] wb_r_i,

  output instruction_t   dwb_insn_o,
  output reg [XLEN -1:0] dwb_r_o
);


  ////////////////////////////////////////////////////////////////
  //
  // Module Body
  //

  //Instruction	
  always @(posedge clk_i, negedge rst_ni)
    if (!rst_ni) dwb_insn_o.instr <= INSTR_NOP;
    else         dwb_insn_o.instr <= wb_insn_i.instr;


  //Bubble
  always @(posedge clk_i, negedge rst_ni)
    if (!rst_ni) dwb_insn_o.bubble <= 1'b1;
    else         dwb_insn_o.bubble <= ~wb_we_i;


  //DBG
  always @(posedge clk_i, negedge rst_ni)
    if   (!rst_ni) dwb_insn_o.dbg <= 1'b0;
    else           dwb_insn_o.dbg <= wb_insn_i.dbg;


  //Result
  //Latch with wb_we_i to handle stalls
  always @(posedge clk_i)
    if (wb_we_i) dwb_r_o <= wb_r_i;

endmodule


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



import riscv_opcodes_pkg::*;
import riscv_state_pkg::*;

module riscv_mem #(
  parameter              XLEN    = 32,
  parameter  [XLEN -1:0] PC_INIT = 'h200
)
(
  input                          rst_ni,
  input                          clk_i,

  input                          wb_stall_i,
  output                         mem_stall_o,

  //Program counter
  input      [XLEN         -1:0] ex_pc_i,
  output reg [XLEN         -1:0] mem_pc_o,

  //Instruction
  input  instruction_t           ex_insn_i,
  output instruction_t           mem_insn_o,

  input  interrupts_exceptions_t ex_exceptions_i,
  output interrupts_exceptions_t mem_exceptions_o,
  input  interrupts_exceptions_t wb_exceptions_i,
 
  //From EX
  input      [XLEN         -1:0] ex_r_i,
                                 dmem_adr_i,

  //To WB
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
    if      (!rst_ni    ) mem_pc_o <= PC_INIT;
    else if (!wb_stall_i) mem_pc_o <= ex_pc_i;

  /*
   * Stall
   */
  assign mem_stall_o = wb_stall_i;

  
  /*
   * Instruction
   */
  always @(posedge clk_i)
    if (!wb_stall_i) mem_insn_o.instr <= ex_insn_i.instr;


  always @(posedge clk_i,negedge rst_ni)
    if      (!rst_ni             ) mem_insn_o.bubble <= 1'b1;
    else if ( wb_exceptions_i.any) mem_insn_o.bubble <= 1'b1;
    else if (!wb_stall_i         ) mem_insn_o.bubble <= ex_insn_i.bubble;



  /*
   * Data
   */
  always @(posedge clk_i)
    if (!wb_stall_i) mem_r_o <= ex_r_i;

  always @(posedge clk_i)
    if (!wb_stall_i) mem_memadr_o <= dmem_adr_i;


  /*
   * Exception
   */
  always @(posedge clk_i, negedge rst_ni)
    if      (!rst_ni             ) mem_exceptions_o <= 'h0;
    else if ( mem_exceptions_o.any ||
              wb_exceptions_i.any) mem_exceptions_o <= 'h0;
    else if (!wb_stall_i         ) mem_exceptions_o <= ex_exceptions_i;

endmodule : riscv_mem


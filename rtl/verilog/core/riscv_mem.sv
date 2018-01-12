/////////////////////////////////////////////////////////////////
//                                                             //
//    ██████╗  ██████╗  █████╗                                 //
//    ██╔══██╗██╔═══██╗██╔══██╗                                //
//    ██████╔╝██║   ██║███████║                                //
//    ██╔══██╗██║   ██║██╔══██║                                //
//    ██║  ██║╚██████╔╝██║  ██║                                //
//    ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═╝                                //
//          ██╗      ██████╗  ██████╗ ██╗ ██████╗              //
//          ██║     ██╔═══██╗██╔════╝ ██║██╔════╝              //
//          ██║     ██║   ██║██║  ███╗██║██║                   //
//          ██║     ██║   ██║██║   ██║██║██║                   //
//          ███████╗╚██████╔╝╚██████╔╝██║╚██████╗              //
//          ╚══════╝ ╚═════╝  ╚═════╝ ╚═╝ ╚═════╝              //
//                                                             //
//    RISC-V                                                   //
//    Memory Unit                                              //
//                                                             //
/////////////////////////////////////////////////////////////////
//                                                             //
//             Copyright (C) 2017 ROA Logic BV                 //
//             www.roalogic.com                                //
//                                                             //
//    Unless specifically agreed in writing, this software is  //
//  licensed under the RoaLogic Non-Commercial License         //
//  version-1.0 (the "License"), a copy of which is included   //
//  with this file or may be found on the RoaLogic website     //
//  http://www.roalogic.com. You may not use the file except   //
//  in compliance with the License.                            //
//                                                             //
//    THIS SOFTWARE IS PROVIDED "AS IS" AND WITHOUT ANY        //
//  EXPRESS OF IMPLIED WARRANTIES OF ANY KIND.                 //
//  See the License for permissions and limitations under the  //
//  License.                                                   //
//                                                             //
/////////////////////////////////////////////////////////////////

module riscv_mem #(
  parameter            XLEN           = 32,
  parameter            ILEN           = 32,
  parameter [XLEN-1:0] PC_INIT        = 'h200,
  parameter            EXCEPTION_SIZE = 12
)
(
  input                           rstn,
  input                           clk,

  input                           wb_stall,

  //Program counter
  input      [XLEN          -1:0] ex_pc,
  output reg [XLEN          -1:0] mem_pc,

  //Instruction
  input                           ex_bubble,
  input      [ILEN          -1:0] ex_instr,
  output reg                      mem_bubble,
  output reg [ILEN          -1:0] mem_instr,

  input      [EXCEPTION_SIZE-1:0] ex_exception,
                                  wb_exception,
  output reg [EXCEPTION_SIZE-1:0] mem_exception,
 


  //From EX
  input      [XLEN          -1:0] ex_r,
                                  dmem_adr,

  //To WB
  output reg [XLEN          -1:0] mem_r,
  output reg [XLEN          -1:0] mem_memadr
);

  ////////////////////////////////////////////////////////////////
  //
  // Variables
  //
  import riscv_pkg::*;
  import riscv_state_pkg::*;


  ////////////////////////////////////////////////////////////////
  //
  // Module Body
  //

  /*
   * Program Counter
   */
  always @(posedge clk,negedge rstn)
    if      (!rstn    ) mem_pc <= PC_INIT;
    else if (!wb_stall) mem_pc <= ex_pc;


  /*
   * Instruction
   */
  always @(posedge clk,negedge rstn)
    if      (!rstn    ) mem_instr <= INSTR_NOP;
    else if (!wb_stall) mem_instr <= ex_instr;


  always @(posedge clk,negedge rstn)
    if      (!rstn    ) mem_bubble <= 1'b1;
    else if (!wb_stall) mem_bubble <= ex_bubble;


  /*
   * Data
   */
  always @(posedge clk)
    if (!wb_stall) mem_r <= ex_r;

  always @(posedge clk)
    if (!wb_stall) mem_memadr <= dmem_adr;


  /*
   * Exception
   */
  always @(posedge clk, negedge rstn)
    if      (!rstn    ) mem_exception <= 'h0;
    else if (|mem_exception ||
             |wb_exception) mem_exception <= 'h0;
    else if (!wb_stall) mem_exception <= ex_exception;

endmodule : riscv_mem


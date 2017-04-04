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
//    Data Memory Access / Write Back                          //
//                                                             //
/////////////////////////////////////////////////////////////////
//                                                             //
//             Copyright (C) 2014-2017 ROA Logic BV            //
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

module riscv_memwb #(
  parameter            XLEN           = 32,
  parameter [XLEN-1:0] PC_INIT        = 'h200,
  parameter            INSTR_SIZE     = 32,
  parameter            EXCEPTION_SIZE = 12
)
(
  input                           rstn,          //Reset
  input                           clk,           //Clock

  input                           ex_stall,
  output                          wb_stall,     //Stall on RF contention

  input      [XLEN          -1:0] ex_pc,
  output reg [XLEN          -1:0] wb_pc,

  input      [INSTR_SIZE    -1:0] ex_instr,
  input                           ex_bubble,
  output reg [INSTR_SIZE    -1:0] wb_instr,
  output reg                      wb_bubble,

  input      [EXCEPTION_SIZE-1:0] ex_exception,
  output reg [EXCEPTION_SIZE-1:0] wb_exception,
  output reg [XLEN          -1:0] wb_badaddr,

  input      [XLEN          -1:0] ex_r,
                                  ex_memadr,

  //To Register File
  output reg [               4:0] wb_dst,
  output reg [XLEN          -1:0] wb_r,
  output reg                      wb_we
);


  ////////////////////////////////////////////////////////////////
  //
  // Variables
  //
  logic [               6:2] opcode;
  logic [               2:0] func3;
  logic [               6:0] func7;
  logic [               4:0] dst;

  logic                      mem_access;
  logic [XLEN          -1:0] mem_data;
  logic [               7:0] mem_qb;
  logic [              15:0] mem_qh;
  logic [              31:0] mem_qw;


  ////////////////////////////////////////////////////////////////
  //
  // Module Body
  //
  import riscv_pkg::*;
  import riscv_state_pkg::*;


  /*
   * Program Counter
   */
  always @(posedge clk, negedge rstn)
    if      (!rstn    ) wb_pc <= PC_INIT;
    else if (!wb_stall) wb_pc <= ex_pc;


  /*
   * Instruction
   */
  always @(posedge clk, negedge rstn)
    if      (!rstn    ) wb_instr <= INSTR_NOP;
    else if (!wb_stall) wb_instr <= ex_instr;

 
  assign func7      = ex_instr[31:25];
  assign func3      = ex_instr[14:12];
  assign opcode     = ex_instr[ 6: 2];
  assign dst        = ex_instr[11: 7];


  /*
   * Exception
   */
  always @(posedge clk, negedge rstn)
    if      (!rstn    ) wb_exception <= 'h0;
    else if (!wb_stall) wb_exception <= ex_exception;


  always @(posedge clk, negedge rstn)
    if (!rstn)
      wb_badaddr <= 'h0;
    else if (ex_exception[CAUSE_MISALIGNED_LOAD   ] |
             ex_exception[CAUSE_MISALIGNED_STORE  ] |
             ex_exception[CAUSE_LOAD_ACCESS_FAULT ] |
             ex_exception[CAUSE_STORE_ACCESS_FAULT] )
      wb_badaddr <= ex_memadr;
    else
      wb_badaddr <= ex_pc;

  /*
   * Register File contention
   */
  assign wb_stall = 1'b0;




  /*
   * Register File Write Back
   */
  // Destination register
  always @(posedge clk)
    if (!wb_stall) wb_dst <= dst;

  // Result
  /*
   * TODO: Using ex_stall here is (seems) ugly
   *       It's caused by the ID-stage's bypass functionality (only ld_wbr??)
   */
  always @(posedge clk)
//    if (!wb_stall) wb_r <= ex_r;
    if (!ex_stall) wb_r <= ex_r;


  // Register File Write
  always @(posedge clk, negedge rstn)
    if      (!rstn        ) wb_we <= 'b0;
    else if (|ex_exception) wb_we <= 'b0;
    else casex (opcode)
      OPC_MISC_MEM: wb_we <= 'b0;
      OPC_LOAD    : wb_we <= ~ex_bubble & |dst;
      OPC_STORE   : wb_we <= 'b0;
      OPC_STORE_FP: wb_we <= 'b0;
      OPC_BRANCH  : wb_we <= 'b0;
//      OPC_SYSTEM  : wb_we <= 'b0;
      default     : wb_we <= ~ex_bubble & |dst;
    endcase


  // Write Back Bubble
  always @(posedge clk, negedge rstn)
    if (!rstn) wb_bubble <= 1'b1;
    else       wb_bubble <= ex_bubble;


endmodule


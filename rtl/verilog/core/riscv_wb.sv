/////////////////////////////////////////////////////////////////////
//   ,------.                    ,--.                ,--.          //
//   |  .--. ' ,---.  ,--,--.    |  |    ,---. ,---. `--' ,---.    //
//   |  '--'.'| .-. |' ,-.  |    |  |   | .-. | .-. |,--.| .--'    //
//   |  |\  \ ' '-' '\ '-'  |    |  '--.' '-' ' '-' ||  |\ `--.    //
//   `--' '--' `---'  `--`--'    `-----' `---' `-   /`--' `---'    //
//                                             `---'               //
//    RISC-V                                                       //
//    Data Memory Access - Write Back                              //
//                                                                 //
/////////////////////////////////////////////////////////////////////
//                                                                 //
//             Copyright (C) 2014-2018 ROA Logic BV                //
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

module riscv_wb #(
  parameter            XLEN           = 32,
  parameter [XLEN-1:0] PC_INIT        = 'h200
)
(
  input                           rstn,          //Reset
  input                           clk,           //Clock

  output reg                      wb_stall,      //Stall on memory-wait

  input      [XLEN          -1:0] mem_pc,
  output reg [XLEN          -1:0] wb_pc,

  input      [ILEN          -1:0] mem_instr,
  input                           mem_bubble,
  output reg [ILEN          -1:0] wb_instr,
  output reg                      wb_bubble,

  input      [EXCEPTION_SIZE-1:0] mem_exception,
  output reg [EXCEPTION_SIZE-1:0] wb_exception,
  output reg [XLEN          -1:0] wb_badaddr,

  input      [XLEN          -1:0] mem_r,
                                  mem_memadr,

  //From Memory System
  input                           dmem_ack,
  input      [XLEN          -1:0] dmem_q,
  input                           dmem_misaligned,
                                  dmem_page_fault,

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

  logic [EXCEPTION_SIZE-1:0] exception;

  logic [XLEN          -1:0] m_data;
  logic [               7:0] m_qb;
  logic [              15:0] m_qh;
  logic [              31:0] m_qw;


  ////////////////////////////////////////////////////////////////
  //
  // Module Body
  //

  /*
   * Program Counter
   */
  always @(posedge clk, negedge rstn)
    if      (!rstn    ) wb_pc <= PC_INIT;
    else if (!wb_stall) wb_pc <= mem_pc;


  /*
   * Instruction
   */
  always @(posedge clk, negedge rstn)
    if      (!rstn    ) wb_instr <= INSTR_NOP;
    else if (!wb_stall) wb_instr <= mem_instr;

 
  assign func7      = mem_instr[31:25];
  assign func3      = mem_instr[14:12];
  assign opcode     = mem_instr[ 6: 2];
  assign dst        = mem_instr[11: 7];


  /*
   * Exception
   */
  always_comb
    begin
        exception = mem_exception;

        if (opcode == OPC_LOAD && dmem_ack)
          exception[CAUSE_MISALIGNED_LOAD   ] = dmem_misaligned;

        if (opcode == OPC_STORE && dmem_ack)
          exception[CAUSE_MISALIGNED_STORE  ] = dmem_misaligned;

        if (opcode == OPC_LOAD)
          exception[CAUSE_LOAD_ACCESS_FAULT ] = dmem_page_fault;

        if (opcode == OPC_STORE)
          exception[CAUSE_STORE_ACCESS_FAULT] = dmem_page_fault;
    end


  always @(posedge clk, negedge rstn)
    if      (!rstn    ) wb_exception <= 'h0;
    else if (!wb_stall) wb_exception <= exception;


  always @(posedge clk, negedge rstn)
    if (!rstn)
      wb_badaddr <= 'h0;
    else if (exception[CAUSE_MISALIGNED_LOAD   ] |
             exception[CAUSE_MISALIGNED_STORE  ] |
             exception[CAUSE_LOAD_ACCESS_FAULT ] |
             exception[CAUSE_STORE_ACCESS_FAULT] )
      wb_badaddr <= mem_memadr;
    else
      wb_badaddr <= mem_pc;


  /*
   * From Memory
   */
  always_comb
    casex ( {mem_bubble,|mem_exception, opcode} )
      {2'b00,OPC_LOAD }: wb_stall = ~dmem_ack;
      {2'b00,OPC_STORE}: wb_stall = ~dmem_ack;
      default          : wb_stall = 1'b0;
    endcase


  // data from memory
generate
  if (XLEN==64)
  begin
      logic [XLEN-1:0] m_qd;

      assign m_qb = dmem_q >> (8* mem_memadr[2:0]);
      assign m_qh = dmem_q >> (8* mem_memadr[2:0]);
      assign m_qw = dmem_q >> (8* mem_memadr[2:0]);
      assign m_qd = dmem_q;

      always_comb
        casex ( {func7,func3,opcode} )
          LB     : m_data = { {XLEN- 8{m_qb[ 7]}},m_qb};
          LH     : m_data = { {XLEN-16{m_qh[15]}},m_qh};
          LW     : m_data = { {XLEN-32{m_qw[31]}},m_qw};
          LD     : m_data = {                     m_qd};
          LBU    : m_data = { {XLEN- 8{    1'b0}},m_qb};
          LHU    : m_data = { {XLEN-16{    1'b0}},m_qh};
          LWU    : m_data = { {XLEN-32{    1'b0}},m_qw};
          default: m_data = 'hx;
        endcase
  end
  else
  begin
      assign m_qb = dmem_q >> (8* mem_memadr[1:0]);
      assign m_qh = dmem_q >> (8* mem_memadr[1:0]);
      assign m_qw = dmem_q;

      always_comb
        casex ( {func7,func3,opcode} )
          LB     : m_data = { {XLEN- 8{m_qb[ 7]}},m_qb};
          LH     : m_data = { {XLEN-16{m_qh[15]}},m_qh};
          LW     : m_data = {                     m_qw};
          LBU    : m_data = { {XLEN- 8{    1'b0}},m_qb};
          LHU    : m_data = { {XLEN-16{    1'b0}},m_qh};
          default: m_data = 'hx;
        endcase
  end
endgenerate


  /*
   * Register File Write Back
   */
  // Destination register
  always @(posedge clk)
    if (!wb_stall) wb_dst <= dst;


  // Result
  always @(posedge clk)
    if (!wb_stall)
      casex (opcode)
        OPC_LOAD: wb_r <= m_data;
        default : wb_r <= mem_r;
      endcase


  // Register File Write
  always @(posedge clk, negedge rstn)
    if      (!rstn     ) wb_we <= 'b0;
    else if (|exception) wb_we <= 'b0;
    else casex (opcode)
      OPC_MISC_MEM: wb_we <= 'b0;
      OPC_LOAD    : wb_we <= ~mem_bubble & |dst & ~wb_stall;
      OPC_STORE   : wb_we <= 'b0;
      OPC_STORE_FP: wb_we <= 'b0;
      OPC_BRANCH  : wb_we <= 'b0;
//      OPC_SYSTEM  : wb_we <= 'b0;
      default     : wb_we <= ~mem_bubble & |dst;
    endcase


  // Write Back Bubble
  always @(posedge clk, negedge rstn)
    if      (!rstn    ) wb_bubble <= 1'b1;
    else if (!wb_stall) wb_bubble <= mem_bubble;

endmodule


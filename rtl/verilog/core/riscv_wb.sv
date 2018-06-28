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
  parameter            XLEN    = 32,
  parameter [XLEN-1:0] PC_INIT = 'h200
)
(
  input  logic                      rst_ni,        //Reset
  input  logic                      clk_i,         //Clock

  output logic                      wb_stall_o,    //Stall on memory-wait

  input  logic [XLEN          -1:0] mem_pc_i,
  output logic [XLEN          -1:0] wb_pc_o,

  input  logic [ILEN          -1:0] mem_instr_i,
  input  logic                      mem_bubble_i,
  output logic [ILEN          -1:0] wb_instr_o,
  output logic                      wb_bubble_o,

  input  logic [EXCEPTION_SIZE-1:0] mem_exception_i,
  output logic [EXCEPTION_SIZE-1:0] wb_exception_o,
  output logic [XLEN          -1:0] wb_badaddr_o,

  input  logic [XLEN          -1:0] mem_r_i,
                                    mem_memadr_i,

  //From Memory System
  input  logic                      dmem_ack_i,
                                    dmem_err_i,
  input  logic [XLEN          -1:0] dmem_q_i,
  input  logic                      dmem_misaligned_i,
                                    dmem_page_fault_i,

  //To Register File
  output logic [               4:0] wb_dst_o,
  output logic [XLEN          -1:0] wb_r_o,
  output logic                      wb_we_o
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
  always @(posedge clk_i, negedge rst_ni)
    if      (!rst_ni    ) wb_pc_o <= PC_INIT;
    else if (!wb_stall_o) wb_pc_o <= mem_pc_i;


  /*
   * Instruction
   */
  always @(posedge clk_i, negedge rst_ni)
    if      (!rst_ni    ) wb_instr_o <= INSTR_NOP;
    else if (!wb_stall_o) wb_instr_o <= mem_instr_i;

 
  assign func7  = mem_instr_i[31:25];
  assign func3  = mem_instr_i[14:12];
  assign opcode = mem_instr_i[ 6: 2];
  assign dst    = mem_instr_i[11: 7];


  /*
   * Exception
   */
  always_comb
    begin
        exception = mem_exception_i;

        if (opcode == OPC_LOAD && ~mem_bubble_i)
          exception[CAUSE_MISALIGNED_LOAD   ] = dmem_misaligned_i;

        if (opcode == OPC_STORE && ~mem_bubble_i)
          exception[CAUSE_MISALIGNED_STORE  ] = dmem_misaligned_i;

        if (opcode == OPC_LOAD & ~mem_bubble_i)
          exception[CAUSE_LOAD_ACCESS_FAULT ] = dmem_err_i;

        if (opcode == OPC_STORE & ~mem_bubble_i)
          exception[CAUSE_STORE_ACCESS_FAULT] = dmem_err_i;
         
        if (opcode == OPC_LOAD && ~mem_bubble_i)
          exception[CAUSE_LOAD_PAGE_FAULT   ] = dmem_page_fault_i;

        if (opcode == OPC_STORE && ~mem_bubble_i)
          exception[CAUSE_STORE_PAGE_FAULT  ] = dmem_page_fault_i;
    end


  always @(posedge clk_i, negedge rst_ni)
    if      (!rst_ni    ) wb_exception_o <= 'h0;
    else if (!wb_stall_o) wb_exception_o <= exception;


  always @(posedge clk_i, negedge rst_ni)
    if (!rst_ni)
      wb_badaddr_o <= 'h0;
    else if (exception[CAUSE_MISALIGNED_LOAD   ] ||
             exception[CAUSE_MISALIGNED_STORE  ] ||
             exception[CAUSE_LOAD_ACCESS_FAULT ] ||
             exception[CAUSE_STORE_ACCESS_FAULT] ||
             exception[CAUSE_LOAD_PAGE_FAULT   ] ||
             exception[CAUSE_STORE_PAGE_FAULT  ] )
      wb_badaddr_o <= mem_memadr_i;
    else
      wb_badaddr_o <= mem_pc_i;


  /*
   * From Memory
   */
  always_comb
    casex ( {mem_bubble_i,|mem_exception_i, opcode} )
      {2'b00,OPC_LOAD }: wb_stall_o = ~(dmem_ack_i | dmem_err_i);
      {2'b00,OPC_STORE}: wb_stall_o = ~(dmem_ack_i | dmem_err_i);
      default          : wb_stall_o = 1'b0;
    endcase


  // data from memory
generate
  if (XLEN==64)
  begin
      logic [XLEN-1:0] m_qd;

      assign m_qb = dmem_q_i >> (8* mem_memadr_i[2:0]);
      assign m_qh = dmem_q_i >> (8* mem_memadr_i[2:0]);
      assign m_qw = dmem_q_i >> (8* mem_memadr_i[2:0]);
      assign m_qd = dmem_q_i;

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
      assign m_qb = dmem_q_i >> (8* mem_memadr_i[1:0]);
      assign m_qh = dmem_q_i >> (8* mem_memadr_i[1:0]);
      assign m_qw = dmem_q_i;

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
  always @(posedge clk_i)
    if (!wb_stall_o) wb_dst_o <= dst;


  // Result
  always @(posedge clk_i)
    if (!wb_stall_o)
      casex (opcode)
        OPC_LOAD: wb_r_o <= m_data;
        default : wb_r_o <= mem_r_i;
      endcase


  // Register File Write
  always @(posedge clk_i, negedge rst_ni)
    if      (!rst_ni   ) wb_we_o <= 'b0;
    else if (|exception) wb_we_o <= 'b0;
    else casex (opcode)
      OPC_MISC_MEM: wb_we_o <= 'b0;
      OPC_LOAD    : wb_we_o <= ~mem_bubble_i & |dst & ~wb_stall_o;
      OPC_STORE   : wb_we_o <= 'b0;
      OPC_STORE_FP: wb_we_o <= 'b0;
      OPC_BRANCH  : wb_we_o <= 'b0;
//      OPC_SYSTEM  : wb_we <= 'b0;
      default     : wb_we_o <= ~mem_bubble_i & |dst;
    endcase


  // Write Back Bubble
  always @(posedge clk_i, negedge rst_ni)
    if      (!rst_ni    ) wb_bubble_o <= 1'b1;
    else if (!wb_stall_o) wb_bubble_o <= mem_bubble_i;

endmodule


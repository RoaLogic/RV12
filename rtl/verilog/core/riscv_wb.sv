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

module riscv_wb #(
  parameter               XLEN    = 32,
  parameter   [XLEN -1:0] PC_INIT = 'h200
)
(
  input  logic                   rst_ni,        //Reset
  input  logic                   clk_i,         //Clock

  output logic                   wb_stall_o,    //Stall on memory-wait

  input  logic [XLEN       -1:0] mem_pc_i,
  output logic [XLEN       -1:0] wb_pc_o,

  input  instruction_t           mem_insn_i,
  output instruction_t           wb_insn_o,

  input  interrupts_exceptions_t mem_exceptions_i,
  output interrupts_exceptions_t wb_exceptions_o,
  output logic [XLEN       -1:0] wb_badaddr_o,

  input  logic [XLEN       -1:0] mem_r_i,
                                 mem_memadr_i,

  //From Memory System
  input  logic                   dmem_ack_i,
                                 dmem_err_i,
  input  logic [XLEN       -1:0] dmem_q_i,
  input  logic                   dmem_misaligned_i,
                                 dmem_page_fault_i,

  //to ID for early feedback to EX
  output logic [XLEN       -1:0] wb_memq_o,

  //To Register File
  output rsd_t                   wb_dst_o,
  output logic [XLEN       -1:0] wb_r_o,
  output logic                   wb_we_o
);


  ////////////////////////////////////////////////////////////////
  //
  // Variables
  //
  opcR_t                  opcR;
  logic [            6:2] opcode;
  rsd_t                   dst;

  interrupts_exceptions_t exceptions;

`ifdef RV_NO_X_ON_LOAD
  bit   [XLEN       -1:0] dmem_q;
`else
  logic [XLEN       -1:0] dmem_q;
`endif
  logic [            7:0] m_qb;
  logic [           15:0] m_qh;
  logic [           31:0] m_qw;


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
  always @(posedge clk_i)
    if (!wb_stall_o) wb_insn_o.instr <= mem_insn_i.instr;


  always @(posedge clk_i, negedge rst_ni)
    if      (!rst_ni    ) wb_insn_o.dbg <= 1'b0;
    else if (!wb_stall_o) wb_insn_o.dbg <= mem_insn_i.dbg;


  assign opcR = decode_opcR(mem_insn_i.instr);
  assign dst  = decode_rd(mem_insn_i.instr);


  /*
   * Exception
   */
  always_comb
    begin
        exceptions = mem_exceptions_i;

        if (opcR.opcode == OPC_LOAD  && !mem_insn_i.bubble) exceptions.exceptions.misaligned_load    = dmem_misaligned_i;
        if (opcR.opcode == OPC_STORE && !mem_insn_i.bubble) exceptions.exceptions.misaligned_store   = dmem_misaligned_i;
        if (opcR.opcode == OPC_LOAD  && !mem_insn_i.bubble) exceptions.exceptions.load_access_fault  = dmem_err_i;
        if (opcR.opcode == OPC_STORE && !mem_insn_i.bubble) exceptions.exceptions.store_access_fault = dmem_err_i;
        if (opcR.opcode == OPC_LOAD  && !mem_insn_i.bubble) exceptions.exceptions.load_page_fault    = dmem_page_fault_i;
        if (opcR.opcode == OPC_STORE && !mem_insn_i.bubble) exceptions.exceptions.store_page_fault   = dmem_page_fault_i;

        exceptions.any = |exceptions.exceptions | |exceptions.interrupts | exceptions.nmi;
    end


  always @(posedge clk_i, negedge rst_ni)
    if      (!rst_ni    ) wb_exceptions_o <= 'h0;
    else if (!wb_stall_o) wb_exceptions_o <= exceptions;


  always @(posedge clk_i, negedge rst_ni)
    if (!rst_ni)
      wb_badaddr_o <= 'h0;
    else if (exceptions.exceptions.misaligned_load    ||
             exceptions.exceptions.misaligned_store   ||
             exceptions.exceptions.load_access_fault  ||
             exceptions.exceptions.store_access_fault ||
             exceptions.exceptions.load_page_fault    ||
             exceptions.exceptions.store_page_fault   ||
             exceptions.exceptions.breakpoint         )
      wb_badaddr_o <= mem_memadr_i;
    else if (exceptions.exceptions.illegal_instruction)
      wb_badaddr_o <= mem_insn_i.instr[0 +: XLEN];
    else
      wb_badaddr_o <= {XLEN{1'b0}}; //mem_pc_i;


  /*
   * From Memory
   */
  always_comb
    casex ( {mem_insn_i.bubble,mem_exceptions_i.any, wb_exceptions_o.any, opcR.opcode} )
      {3'b000,OPC_LOAD }: wb_stall_o = ~(dmem_ack_i | dmem_err_i | dmem_misaligned_i | dmem_page_fault_i);
      {3'b000,OPC_STORE}: wb_stall_o = ~(dmem_ack_i | dmem_err_i | dmem_misaligned_i | dmem_page_fault_i);
      default           : wb_stall_o = 1'b0;
    endcase


  // data from memory
  assign dmem_q = dmem_q_i; //convert (or not) 'xz'

generate
  if (XLEN==64)
  begin
      logic [XLEN-1:0] m_qd;

      assign m_qb = dmem_q >> (8* mem_memadr_i[2:0]);
      assign m_qh = dmem_q >> (8* mem_memadr_i[2:0]);
      assign m_qw = dmem_q >> (8* mem_memadr_i[2:0]);
      assign m_qd = dmem_q;

      always_comb
        casex ( opcR )
          LB     : wb_memq_o = { {XLEN- 8{m_qb[ 7]}},m_qb};
          LH     : wb_memq_o = { {XLEN-16{m_qh[15]}},m_qh};
          LW     : wb_memq_o = { {XLEN-32{m_qw[31]}},m_qw};
          LD     : wb_memq_o = {                     m_qd};
          LBU    : wb_memq_o = { {XLEN- 8{    1'b0}},m_qb};
          LHU    : wb_memq_o = { {XLEN-16{    1'b0}},m_qh};
          LWU    : wb_memq_o = { {XLEN-32{    1'b0}},m_qw};
          default: wb_memq_o = 'hx;
        endcase
  end
  else
  begin
      assign m_qb = dmem_q >> (8* mem_memadr_i[1:0]);
      assign m_qh = dmem_q >> (8* mem_memadr_i[1:0]);
      assign m_qw = dmem_q;

      always_comb
        casex ( opcR )
          LB     : wb_memq_o = { {XLEN- 8{m_qb[ 7]}},m_qb};
          LH     : wb_memq_o = { {XLEN-16{m_qh[15]}},m_qh};
          LW     : wb_memq_o = {                     m_qw};
          LBU    : wb_memq_o = { {XLEN- 8{    1'b0}},m_qb};
          LHU    : wb_memq_o = { {XLEN-16{    1'b0}},m_qh};
          default: wb_memq_o = 'hx;
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
      casex (opcR.opcode)
        OPC_LOAD: wb_r_o <= wb_memq_o;
        default : wb_r_o <= mem_r_i;
      endcase


  // Register File Write
  always @(posedge clk_i, negedge rst_ni)
    if      (!rst_ni   ) wb_we_o <= 'b0;
    else if (exceptions.any || wb_exceptions_o.any) wb_we_o <= 'b0;
    else casex (opcR.opcode)
      OPC_MISC_MEM: wb_we_o <= 'b0;
      OPC_LOAD    : wb_we_o <= ~mem_insn_i.bubble & |dst & ~wb_stall_o;
      OPC_STORE   : wb_we_o <= 'b0;
      OPC_STORE_FP: wb_we_o <= 'b0;
      OPC_BRANCH  : wb_we_o <= 'b0;
//      OPC_SYSTEM  : wb_we <= 'b0;
      default     : wb_we_o <= ~mem_insn_i.bubble & |dst;
    endcase


  // Write Back Bubble
  always @(posedge clk_i, negedge rst_ni)
    if      (!rst_ni             ) wb_insn_o.bubble <= 1'b1;
    else if ( wb_exceptions_o.any) wb_insn_o.bubble <= 1'b1;
    else if (!wb_stall_o         ) wb_insn_o.bubble <= mem_insn_i.bubble;

endmodule


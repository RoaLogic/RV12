/////////////////////////////////////////////////////////////////////
//   ,------.                    ,--.                ,--.          //
//   |  .--. ' ,---.  ,--,--.    |  |    ,---. ,---. `--' ,---.    //
//   |  '--'.'| .-. |' ,-.  |    |  |   | .-. | .-. |,--.| .--'    //
//   |  |\  \ ' '-' '\ '-'  |    |  '--.' '-' ' '-' ||  |\ `--.    //
//   `--' '--' `---'  `--`--'    `-----' `---' `-   /`--' `---'    //
//                                             `---'               //
//    RISC-V                                                       //
//    Arithmetic & Logical Unit (ALU)                              //
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


module riscv_alu
import riscv_opcodes_pkg::*;
import riscv_state_pkg::*;
#(
  parameter int                  MXLEN   = 32,
  parameter bit                  HAS_RVC = 0
)
(
  input                          rst_ni,
  input                          clk_i,

  input                          ex_stall_i,

  //Program counter
  input      [MXLEN        -1:0] id_pc_i,

  //Instruction
  input  instruction_t           id_insn_i,

  //Operands
  input      [MXLEN        -1:0] opA_i,
                                 opB_i,

  //catch WB-exceptions
  input  interrupts_exceptions_t ex_exceptions_i,
                                 mem_exceptions_i,
                                 wb_exceptions_i,

  //to WB
  output reg                     alu_bubble_o,
  output reg [MXLEN        -1:0] alu_r_o,


  //To State
  output reg [             11:0] ex_csr_reg_o,
  output reg [MXLEN        -1:0] ex_csr_wval_o,
  output reg                     ex_csr_we_o,

  //From State
  input      [MXLEN        -1:0] st_csr_rval_i,
  input      [              1:0] st_xlen_i
);


  ////////////////////////////////////////////////////////////////
  //
  // functions
  //
  function [MXLEN-1:0] sext32;
    input [31:0] operand;
    logic sign;
  begin
    sign   = operand[31];
    sext32 = { {MXLEN-31{sign}}, operand[30:0]};
  end
  endfunction


  ////////////////////////////////////////////////////////////////
  //
  // Variables
  //
  localparam SBITS=$clog2(MXLEN);

  opcR_t             opcR;
  logic              xlen32;
  logic              has_rvc;

  //Operand generation
  logic [      31:0] opA32;
  logic [      31:0] opB32;
  logic [SBITS -1:0] shamt;
  logic [       4:0] shamt32;
  logic [MXLEN -1:0] csri;

  ////////////////////////////////////////////////////////////////
  //
  // Module Body
  //

  /*
   * Instruction
   */
  assign opcR    = decode_opcR(id_insn_i.instr);
  assign xlen32  = (st_xlen_i == RV32I);
  assign has_rvc = (HAS_RVC !=     0);

  /*
   *
   */
  assign opA32   = opA_i[     31:0];
  assign opB32   = opB_i[     31:0];
  assign shamt   = opB_i[SBITS-1:0];
  assign shamt32 = opB_i[      4:0];
  

  /*
   * ALU operations
   */
  always @(posedge clk_i, negedge rst_ni)
    if      (!rst_ni    ) alu_r_o <= 'h0;
    else if (!ex_stall_i)
      casex ( {xlen32, opcR} )
        {1'b?,LUI   }: alu_r_o <= opA_i + opB_i; //actually just opB_i, but simplify encoding
        {1'b?,AUIPC }: alu_r_o <= opA_i + opB_i;
        {1'b?,JAL   }: alu_r_o <= id_pc_i + ('h2 << id_insn_i.instr[1:0]);
        {1'b?,JALR  }: alu_r_o <= id_pc_i + ('h2 << id_insn_i.instr[1:0]);

        //logical operators
        {1'b?,ADDI  }: alu_r_o <= opA_i + opB_i;
        {1'b?,ADD   }: alu_r_o <= opA_i + opB_i;
        {1'b0,ADDIW }: alu_r_o <= sext32(opA32 + opB32);    //RV64
        {1'b0,ADDW  }: alu_r_o <= sext32(opA32 + opB32);    //RV64
        {1'b?,SUB   }: alu_r_o <= opA_i - opB_i;
        {1'b0,SUBW  }: alu_r_o <= sext32(opA32 - opB32);    //RV64
        {1'b?,XORI  }: alu_r_o <= opA_i ^ opB_i;
        {1'b?,XOR   }: alu_r_o <= opA_i ^ opB_i;
        {1'b?,ORI   }: alu_r_o <= opA_i | opB_i;
        {1'b?,OR    }: alu_r_o <= opA_i | opB_i;
        {1'b?,ANDI  }: alu_r_o <= opA_i & opB_i;
        {1'b?,AND   }: alu_r_o <= opA_i & opB_i;
        {1'b?,SLLI  }: alu_r_o <= opA_i << shamt;
        {1'b?,SLL   }: alu_r_o <= opA_i << shamt;
        {1'b0,SLLIW }: alu_r_o <= sext32(opA32 << shamt32); //RV64
        {1'b0,SLLW  }: alu_r_o <= sext32(opA32 << shamt32); //RV64
        {1'b?,SLTI  }: alu_r_o <= {~opA_i[MXLEN-1],opA_i[MXLEN-2:0]} < {~opB_i[MXLEN-1],opB_i[MXLEN-2:0]} ? 'h1 : 'h0;
        {1'b?,SLT   }: alu_r_o <= {~opA_i[MXLEN-1],opA_i[MXLEN-2:0]} < {~opB_i[MXLEN-1],opB_i[MXLEN-2:0]} ? 'h1 : 'h0;
        {1'b?,SLTIU }: alu_r_o <= opA_i < opB_i ? 'h1 : 'h0;
        {1'b?,SLTU  }: alu_r_o <= opA_i < opB_i ? 'h1 : 'h0;
        {1'b?,SRLI  }: alu_r_o <= opA_i >> shamt;
        {1'b?,SRL   }: alu_r_o <= opA_i >> shamt;
        {1'b0,SRLIW }: alu_r_o <= sext32(opA32 >> shamt32); //RV64
        {1'b0,SRLW  }: alu_r_o <= sext32(opA32 >> shamt32); //RV64
        {1'b?,SRAI  }: alu_r_o <= $signed(opA_i) >>> shamt;
        {1'b?,SRA   }: alu_r_o <= $signed(opA_i) >>> shamt;
        {1'b0,SRAIW }: alu_r_o <= sext32($signed(opA32) >>> shamt32);
        {1'b?,SRAW  }: alu_r_o <= sext32($signed(opA32) >>> shamt32);

        //CSR access
        {1'b?,CSRRW }: alu_r_o <= {MXLEN{1'b0}} | st_csr_rval_i;
        {1'b?,CSRRWI}: alu_r_o <= {MXLEN{1'b0}} | st_csr_rval_i;
        {1'b?,CSRRS }: alu_r_o <= {MXLEN{1'b0}} | st_csr_rval_i;
        {1'b?,CSRRSI}: alu_r_o <= {MXLEN{1'b0}} | st_csr_rval_i;
        {1'b?,CSRRC }: alu_r_o <= {MXLEN{1'b0}} | st_csr_rval_i;
        {1'b?,CSRRCI}: alu_r_o <= {MXLEN{1'b0}} | st_csr_rval_i;

        default      : alu_r_o <= 'hx;
      endcase


  always @(posedge clk_i, negedge rst_ni)
    if      (!rst_ni                ) alu_bubble_o <= 1'b1;
    else if ( ex_exceptions_i.any  ||
              mem_exceptions_i.any ||
              wb_exceptions_i.any   ) alu_bubble_o <= 1'b1;
    else if (!ex_stall_i)
      casex ( {xlen32,opcR} )
        {1'b?,LUI   }: alu_bubble_o <= id_insn_i.bubble;
        {1'b?,AUIPC }: alu_bubble_o <= id_insn_i.bubble;
        {1'b?,JAL   }: alu_bubble_o <= id_insn_i.bubble;
        {1'b?,JALR  }: alu_bubble_o <= id_insn_i.bubble;

        //logical operators
        {1'b?,ADDI  }: alu_bubble_o <= id_insn_i.bubble;
        {1'b?,ADD   }: alu_bubble_o <= id_insn_i.bubble;
        {1'b0,ADDIW }: alu_bubble_o <= id_insn_i.bubble;
        {1'b0,ADDW  }: alu_bubble_o <= id_insn_i.bubble;
        {1'b?,SUB   }: alu_bubble_o <= id_insn_i.bubble;
        {1'b0,SUBW  }: alu_bubble_o <= id_insn_i.bubble;
        {1'b?,XORI  }: alu_bubble_o <= id_insn_i.bubble;
        {1'b?,XOR   }: alu_bubble_o <= id_insn_i.bubble;
        {1'b?,ORI   }: alu_bubble_o <= id_insn_i.bubble;
        {1'b?,OR    }: alu_bubble_o <= id_insn_i.bubble;
        {1'b?,ANDI  }: alu_bubble_o <= id_insn_i.bubble;
        {1'b?,AND   }: alu_bubble_o <= id_insn_i.bubble;
        {1'b?,SLLI  }: alu_bubble_o <= id_insn_i.bubble;
        {1'b?,SLL   }: alu_bubble_o <= id_insn_i.bubble;
        {1'b0,SLLIW }: alu_bubble_o <= id_insn_i.bubble;
        {1'b0,SLLW  }: alu_bubble_o <= id_insn_i.bubble;
        {1'b?,SLTI  }: alu_bubble_o <= id_insn_i.bubble;
        {1'b?,SLT   }: alu_bubble_o <= id_insn_i.bubble;
        {1'b?,SLTIU }: alu_bubble_o <= id_insn_i.bubble;
        {1'b?,SLTU  }: alu_bubble_o <= id_insn_i.bubble;
        {1'b?,SRLI  }: alu_bubble_o <= id_insn_i.bubble;
        {1'b?,SRL   }: alu_bubble_o <= id_insn_i.bubble;
        {1'b0,SRLIW }: alu_bubble_o <= id_insn_i.bubble;
        {1'b0,SRLW  }: alu_bubble_o <= id_insn_i.bubble;
        {1'b?,SRAI  }: alu_bubble_o <= id_insn_i.bubble;
        {1'b?,SRA   }: alu_bubble_o <= id_insn_i.bubble;
        {1'b0,SRAIW }: alu_bubble_o <= id_insn_i.bubble;
        {1'b?,SRAW  }: alu_bubble_o <= id_insn_i.bubble;

        //CSR access
        {1'b?,CSRRW }: alu_bubble_o <= id_insn_i.bubble;
        {1'b?,CSRRWI}: alu_bubble_o <= id_insn_i.bubble;
        {1'b?,CSRRS }: alu_bubble_o <= id_insn_i.bubble;
        {1'b?,CSRRSI}: alu_bubble_o <= id_insn_i.bubble;
        {1'b?,CSRRC }: alu_bubble_o <= id_insn_i.bubble;
        {1'b?,CSRRCI}: alu_bubble_o <= id_insn_i.bubble;

        default      : alu_bubble_o <= 1'b1;
    endcase


  /*
   * CSR
   */
  assign csri = {{MXLEN-5{1'b0}},opB_i[4:0]};

  always @(posedge clk_i,negedge rst_ni)
    if (!rst_ni)
    begin
        ex_csr_reg_o  <= 'hx;
        ex_csr_wval_o <= 'hx;
        ex_csr_we_o   <= 1'b0;
    end
    else
    begin
        ex_csr_reg_o <= id_insn_i.instr.I.imm;

        casex ( {id_insn_i.bubble,opcR} )
          {1'b0,CSRRW } : begin
                              ex_csr_we_o   <= 'b1;
                              ex_csr_wval_o <= opA_i;
                          end
          {1'b0,CSRRWI} : begin
                              ex_csr_we_o   <= |csri;
                              ex_csr_wval_o <= csri;
                          end
          {1'b0,CSRRS } : begin
                              ex_csr_we_o   <= |opA_i;
                              ex_csr_wval_o <= st_csr_rval_i | opA_i;
                          end
          {1'b0,CSRRSI} : begin
                              ex_csr_we_o   <= |csri;
                              ex_csr_wval_o <= st_csr_rval_i | csri;
                          end
          {1'b0,CSRRC } : begin
                              ex_csr_we_o   <= |opA_i;
                              ex_csr_wval_o <= st_csr_rval_i & ~opA_i;
                          end
          {1'b0,CSRRCI} : begin
                              ex_csr_we_o   <= |csri;
                              ex_csr_wval_o <= st_csr_rval_i & ~csri;
                          end
          default       : begin
                              ex_csr_we_o   <= 'b0;
                              ex_csr_wval_o <= 'hx;
                          end
    endcase
    end

endmodule 

/////////////////////////////////////////////////////////////////////
//   ,------.                    ,--.                ,--.          //
//   |  .--. ' ,---.  ,--,--.    |  |    ,---. ,---. `--' ,---.    //
//   |  '--'.'| .-. |' ,-.  |    |  |   | .-. | .-. |,--.| .--'    //
//   |  |\  \ ' '-' '\ '-'  |    |  '--.' '-' ' '-' ||  |\ `--.    //
//   `--' '--' `---'  `--`--'    `-----' `---' `-   /`--' `---'    //
//                                             `---'               //
//    RISC-V                                                       //
//    Multiplier Unit                                              //
//                                                                 //
/////////////////////////////////////////////////////////////////////
//                                                                 //
//             Copyright (C) 2017-2018 ROA Logic BV                //
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

module riscv_mul #(
  parameter XLEN         = 32,
  parameter MULT_LATENCY = 0
)
(
  input                 rst_ni,
  input                 clk_i,

  input                 mem_stall_i,
  input                 ex_stall_i,
  output reg            mul_stall_o,

  //Instruction
  input instruction_t   id_insn_i,

  //Operands
  input      [XLEN-1:0] opA_i,
                        opB_i,

  //from State
  input      [     1:0] st_xlen_i,

  //to WB
  output reg            mul_bubble_o,
  output reg [XLEN-1:0] mul_r_o
);

  ////////////////////////////////////////////////////////////////
  //
  // Constants
  //
  localparam DXLEN       = 2*XLEN;

  localparam MAX_LATENCY = 3;
  localparam LATENCY     = MULT_LATENCY > MAX_LATENCY ? MAX_LATENCY : MULT_LATENCY;


  ////////////////////////////////////////////////////////////////
  //
  // Checks (assertions)
  //
  initial
  begin
      a1: assert (MULT_LATENCY <= MAX_LATENCY)
          else $warning("MULT_LATENCY=%0d larger than allowed. Changed to %0d", MULT_LATENCY, MAX_LATENCY);
  end


  ////////////////////////////////////////////////////////////////
  //
  // functions
  //
  function [XLEN-1:0] sext32;
    input [31:0] operand;
    logic sign;

    sign   = operand[31];
    sext32 = { {XLEN-32{sign}}, operand};
  endfunction


  function [XLEN-1:0] twos;
    input [XLEN-1:0] a;

    twos = ~a +'h1;
  endfunction

  function [DXLEN-1:0] twos_dxlen;
    input [DXLEN-1:0] a;

    twos_dxlen = ~a +'h1;
  endfunction


  function [XLEN-1:0] abs;
    input [XLEN-1:0] a;

    abs = a[XLEN-1] ? twos(a) : a;
  endfunction



  ////////////////////////////////////////////////////////////////
  //
  // Variables
  //
  logic              xlen32;
  instr_t            mul_instr;

  opcR_t             opcR, opcR_mul;
  
  //Operand generation
  logic [      31:0] opA32,
                     opB32;


  logic              mult_neg,      mult_neg_reg;
  logic [XLEN  -1:0] mult_opA,      mult_opA_reg,
                     mult_opB,      mult_opB_reg;
  logic [DXLEN -1:0] mult_r,        mult_r_reg,
                     mult_r_signed, mult_r_signed_reg;

  //FSM (bubble, stall generation)
  logic       is_mul;
  logic [1:0] cnt;
  enum logic {ST_IDLE=1'b0, ST_WAIT=1'b1} state;


  ////////////////////////////////////////////////////////////////
  //
  // Module Body
  //

  /*
   * Instruction
   */
  assign opcR     = decode_opcR(id_insn_i.instr);
  assign opcR_mul = decode_opcR(mul_instr);

  assign xlen32  = st_xlen_i == RV32I;


  /*
   * 32bit operands
   */
  assign opA32 = opA_i[31:0];
  assign opB32 = opB_i[31:0];


  /*
   *  Multiply operations
   *
   * Transform all multiplications into 1 unsigned multiplication
   * This avoids building multiple multipliers (signed x signed, signed x unsigned, unsigned x unsigned)
   *   at the expense of potentially making the path slower
   */

  //multiplier operand-A
  always_comb 
    unique casex ( opcR )
      MULW   : mult_opA = abs( sext32(opA32) ); //RV64
      MULHU  : mult_opA =             opA_i   ;
      default: mult_opA = abs(        opA_i  );
    endcase

  //multiplier operand-B
  always_comb 
    unique casex ( opcR )
      MULW   : mult_opB = abs( sext32(opB32) ); //RV64
      MULHSU : mult_opB =             opB_i   ;
      MULHU  : mult_opB =             opB_i   ;
      default: mult_opB = abs(        opB_i  );
    endcase

  //negate multiplier output?
  always_comb 
    unique casex ( opcR )
      MUL    : mult_neg = opA_i[XLEN-1] ^ opB_i[XLEN-1];
      MULH   : mult_neg = opA_i[XLEN-1] ^ opB_i[XLEN-1];
      MULHSU : mult_neg = opA_i[XLEN-1];
      MULHU  : mult_neg = 1'b0;
      MULW   : mult_neg = opA32[31] ^ opB32[31];  //RV64
      default: mult_neg = 'hx;
    endcase


  //Actual multiplier
  assign mult_r        = $unsigned(mult_opA_reg) * $unsigned(mult_opB_reg);

  //Correct sign
  assign mult_r_signed = mult_neg_reg ? twos_dxlen(mult_r_reg) : mult_r_reg;


  /*
   *
   */
generate
  if (LATENCY == 0)
  begin
      /*
       * Single cycle multiplier
       *
       * Registers at: - output
       */
      //Register holding instruction for multiplier-output-selector
      assign mul_instr = id_insn_i.instr;

      //Registers holding multiplier operands
      assign mult_opA_reg = mult_opA;
      assign mult_opB_reg = mult_opB;
      assign mult_neg_reg = mult_neg;

      //Register holding multiplier output
      assign mult_r_reg = mult_r;

      //Register holding sign correction
      assign mult_r_signed_reg = mult_r_signed;
  end
  else
  begin
      /*
       * Multi cycle multiplier
       *
       * Registers at: - input
       *               - output
       */
      //Register holding instruction for multiplier-output-selector
      always @(posedge clk_i)
        if (!ex_stall_i) mul_instr <= id_insn_i.instr;

      //Registers holding multiplier operands
      always @(posedge clk_i)
        if (!ex_stall_i)
        begin
            mult_opA_reg <= mult_opA;
            mult_opB_reg <= mult_opB;
            mult_neg_reg <= mult_neg;
        end

      if (LATENCY == 1)
      begin
          //Register holding multiplier output
          assign mult_r_reg = mult_r;

          //Register holding sign correction
          assign mult_r_signed_reg = mult_r_signed;
      end
      else if (LATENCY == 2)
      begin
          //Register holding multiplier output
          always @(posedge clk_i)
            mult_r_reg <= mult_r;

          //Register holding sign correction
          assign mult_r_signed_reg = mult_r_signed;
      end
      else
      begin
          //Register holding multiplier output
          always @(posedge clk_i)
            mult_r_reg <= mult_r;

          //Register holding sign correction
          always @(posedge clk_i)
            mult_r_signed_reg <= mult_r_signed;
      end
  end
endgenerate



  /*
   * Final output register
   */
  always @(posedge clk_i)
    unique casex ( opcR_mul )
      MUL    : mul_r_o <= mult_r_signed_reg[XLEN -1:   0];
      MULW   : mul_r_o <= sext32( mult_r_signed_reg[31:0] );  //RV64
      default: mul_r_o <= mult_r_signed_reg[DXLEN-1:XLEN];
    endcase


  /*
   * Stall / Bubble generation
   */
  always_comb
    unique casex ( opcR )
      MUL    : is_mul = 1'b1;
      MULH   : is_mul = 1'b1;
      MULW   : is_mul = ~xlen32;
      MULHSU : is_mul = 1'b1;
      MULHU  : is_mul = 1'b1;
      default: is_mul = 1'b0;
    endcase


  always @(posedge clk_i,negedge rst_ni)
    if (!rst_ni)
    begin
        state        <= ST_IDLE;
        cnt          <= LATENCY;

        mul_bubble_o <= 1'b1;
        mul_stall_o  <= 1'b0;
    end
    else
    begin
        mul_bubble_o <= 1'b1;

        unique case (state)
          ST_IDLE: if (!ex_stall_i)
                     if (!id_insn_i.bubble && is_mul)
                     begin
                         if (LATENCY == 0)
                         begin
                             mul_bubble_o <= 1'b0;
                             mul_stall_o  <= 1'b0;
                         end
                         else
                         begin
                             state        <= ST_WAIT;
                             cnt          <= LATENCY -1;

                             mul_bubble_o <= 1'b1;
                             mul_stall_o  <= 1'b1;
                          end
                       end

          ST_WAIT: if (|cnt)
                     cnt <= cnt -1;
                   else if (!mem_stall_i)
                   begin
                       state        <= ST_IDLE;
                       cnt          <= LATENCY;

                       mul_bubble_o <= 1'b0;
                       mul_stall_o  <= 1'b0;
                   end
        endcase
    end

endmodule 

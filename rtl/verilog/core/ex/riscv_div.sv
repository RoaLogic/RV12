/////////////////////////////////////////////////////////////////////
//   ,------.                    ,--.                ,--.          //
//   |  .--. ' ,---.  ,--,--.    |  |    ,---. ,---. `--' ,---.    //
//   |  '--'.'| .-. |' ,-.  |    |  |   | .-. | .-. |,--.| .--'    //
//   |  |\  \ ' '-' '\ '-'  |    |  '--.' '-' ' '-' ||  |\ `--.    //
//   `--' '--' `---'  `--`--'    `-----' `---' `-   /`--' `---'    //
//                                             `---'               //
//    RISC-V                                                       //
//    Division Unit                                                //
//                                                                 //
//    Implements Non-Performing Restoring Division                 //
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

module riscv_div #(
  parameter XLEN = 32
)
(
  input                 rst_ni,
  input                 clk_i,

  input                 mem_stall_i,
  input                 ex_stall_i,
  output reg            div_stall_o,

  //Instruction
  input  instruction_t  id_insn_i,

  //Operands
  input      [XLEN-1:0] opA_i,
                        opB_i,

  //From State
  input      [     1:0] st_xlen_i,

  //To WB
  output reg            div_bubble_o,
  output reg [XLEN-1:0] div_r_o
);
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


  function [XLEN-1:0] abs;
    input [XLEN-1:0] a;

    abs = a[XLEN-1] ? twos(a) : a;
  endfunction



  ////////////////////////////////////////////////////////////////
  //
  // Variables
  //
  logic                    xlen32;
  instr_t                  div_instr;

  opcR_t                   opcR, opcR_div;

  //Operand generation
  logic [            31:0] opA_i32,
                           opB_i32;

  logic [$clog2(XLEN)-1:0] cnt;
  logic                    neg_q, //negate quotient
                           neg_s; //negate remainder

  //divider internals
  typedef struct packed {
    logic [XLEN-1:0] p, a;
  } pa_struct;

  pa_struct                pa,
                           pa_shifted;
  logic [XLEN          :0] p_minus_b;
  logic [XLEN        -1:0] b;


  //FSM
  enum logic [1:0] {ST_CHK=2'b00, ST_DIV=2'b01,ST_RES=2'b10} state;


  ////////////////////////////////////////////////////////////////
  //
  // Module Body
  //

  /*
   * Instruction
   */
  assign opcR     = decode_opcR(id_insn_i.instr);
  assign opcR_div = decode_opcR(div_instr);

  assign xlen32  = st_xlen_i == RV32I;


  //retain instruction
  always @(posedge clk_i)
    if (!ex_stall_i) div_instr <= id_insn_i.instr;


  /*
   * 32bit operands
   */
  assign opA_i32   = opA_i[31:0];
  assign opB_i32   = opB_i[31:0];


  /*
   *  Divide operations
   *
   */
  assign pa_shifted = pa << 1;
  assign p_minus_b  = pa_shifted.p - b;


  //Division: bit-serial. Max XLEN cycles
  // q = z/d + s
  // z: Dividend
  // d: Divisor
  // q: Quotient
  // s: Remainder
  always @(posedge clk_i,negedge rst_ni)
    if (!rst_ni)
    begin
        cnt          <= {$bits(cnt){1'bx}};
        state        <= ST_CHK;
        div_bubble_o <= 1'b1;
        div_stall_o  <= 1'b0;

        div_r_o      <= {$bits(div_r_o){1'bx}};

        pa           <= {$bits(pa){1'bx}};
        b            <= {$bits(b){1'bx}};
        neg_q        <= 1'bx;
        neg_s        <= 1'bx;
    end
    else
    begin
        div_bubble_o <= 1'b1;

        case (state)

          /*
           * Check for exceptions (divide by zero, signed overflow)
           * Setup dividor registers
           */
          ST_CHK: if (!ex_stall_i && !id_insn_i.bubble)
                    unique casex ( {xlen32,opcR} )
                       {1'b?,DIV  } :
                                if (~|opB_i)
                                begin //signed divide by zero
                                    div_r_o      <= {XLEN{1'b1}}; //=-1
                                    div_bubble_o <= 1'b0;
                                end
                                else
                                if (opA_i == {1'b1,{XLEN-1{1'b0}}} && &opB_i) // signed overflow (Dividend=-2^(XLEN-1), Divisor=-1)
                                begin
                                    div_r_o      <= {1'b1,{XLEN-1{1'b0}}};
                                    div_bubble_o <= 1'b0;
                                end
                                else
                                begin
                                    cnt         <= {$bits(cnt){1'b1}};
                                    state       <= ST_DIV;
                                    div_stall_o <= 1'b1;

                                    neg_q       <= opA_i[XLEN-1] ^ opB_i[XLEN-1];
                                    neg_s       <= opA_i[XLEN-1];

                                    pa.p        <= 'h0;
                                    pa.a        <= abs(opA_i);
                                    b           <= abs(opB_i);
                                 end

                       {1'b0,DIVW } :
                                if (~|opB_i32)
                                begin //signed divide by zero
                                    div_r_o      <= {XLEN{1'b1}}; //=-1
                                    div_bubble_o <= 1'b0;
                                end
                                else
                                if (opA_i32 == {1'b1,{31{1'b0}}} && &opB_i32) // signed overflow (Dividend=-2^(XLEN-1), Divisor=-1)
                                begin
                                    div_r_o      <= sext32( {1'b1,{31{1'b0}}} );
                                    div_bubble_o <= 1'b0;
                                end
                                else
                                begin
                                    cnt         <= {1'b0, {$bits(cnt)-1{1'b1}} };
                                    state       <= ST_DIV;
                                    div_stall_o <= 1'b1;

                                    neg_q       <= opA_i32[31] ^ opB_i32[31];
                                    neg_s       <= opA_i32[31];

                                    pa.p        <= 'h0;
                                    pa.a        <= { abs( sext32(opA_i32) ), {XLEN-32{1'b0}}      };
                                    b           <= abs( sext32(opB_i32) );
                                end

                       {1'b?,DIVU } :
                                if (~|opB_i)
                                begin //unsigned divide by zero
                                    div_r_o      <= {XLEN{1'b1}}; //= 2^XLEN -1
                                    div_bubble_o <= 1'b0;
                                end
                                else
                                begin
                                    cnt         <= {$bits(cnt){1'b1}};
                                    state       <= ST_DIV;
                                    div_stall_o <= 1'b1;

                                    neg_q       <= 1'b0;
                                    neg_s       <= 1'b0;

                                    pa.p        <= 'h0;
                                    pa.a        <= opA_i;
                                    b           <= opB_i;
                                end

                       {1'b0,DIVUW} :
                                if (~|opB_i32)
                                begin //unsigned divide by zero
                                    div_r_o      <= {XLEN{1'b1}}; //= 2^XLEN -1
                                    div_bubble_o <= 1'b0;
                                end
                                else
                                begin
                                    cnt         <= {1'b0, {$bits(cnt)-1{1'b1}} };
                                    state       <= ST_DIV;
                                    div_stall_o <= 1'b1;

                                    neg_q       <= 1'b0;
                                    neg_s       <= 1'b0;

                                    pa.p        <= 'h0;
                                    pa.a        <= { opA_i32, {XLEN-32{1'b0}} };
                                    b           <= { {XLEN-32{1'b0}}, opB_i32 };
                                end

                       {1'b?,REM  } :
                                if (~|opB_i)
                                begin //signed divide by zero
                                    div_r_o      <= opA_i;
                                    div_bubble_o <= 1'b0;
                                end
                                else
                                if (opA_i == {1'b1,{XLEN-1{1'b0}}} && &opB_i) // signed overflow (Dividend=-2^(XLEN-1), Divisor=-1)
                                begin
                                    div_r_o      <=  'h0;
                                    div_bubble_o <= 1'b0;
                                end
                                else
                                begin
                                    cnt         <= {$bits(cnt){1'b1}};
                                    state       <= ST_DIV;
                                    div_stall_o <= 1'b1;

                                    neg_q       <= opA_i[XLEN-1] ^ opB_i[XLEN-1];
                                    neg_s       <= opA_i[XLEN-1];

                                    pa.p        <= 'h0;
                                    pa.a        <= abs(opA_i);
                                    b           <= abs(opB_i);
                                end

                       {1'b0,REMW } :
                                if (~|opB_i32)
                                begin //signed divide by zero
                                    div_r_o      <= sext32(opA_i32);
                                    div_bubble_o <= 1'b0;
                                end
                                else
                                if (opA_i32 == {1'b1,{31{1'b0}}} && &opB_i32) // signed overflow (Dividend=-2^(XLEN-1), Divisor=-1)
                                begin
                                    div_r_o      <=  'h0;
                                    div_bubble_o <= 1'b0;
                                end
                                else
                                begin
                                    cnt         <= {1'b0, {$bits(cnt)-1{1'b1}} };
                                    state       <= ST_DIV;
                                    div_stall_o <= 1'b1;

                                    neg_q       <= opA_i32[31] ^ opB_i32[31];
                                    neg_s       <= opA_i32[31];

                                    pa.p        <= 'h0;
                                    pa.a        <= { abs( sext32(opA_i32) ), {XLEN-32{1'b0}}      };
                                    b           <= abs( sext32(opB_i32) );
                                end

                       {1'b?,REMU } :
                                if (~|opB_i)
                                begin //unsigned divide by zero
                                    div_r_o      <= opA_i;
                                    div_bubble_o <= 1'b0;
                                end
                                else
                                begin
                                    cnt         <= {$bits(cnt){1'b1}};
                                    state       <= ST_DIV;
                                    div_stall_o <= 1'b1;

                                    neg_q       <= 1'b0;
                                    neg_s       <= 1'b0;

                                    pa.p        <= 'h0;
                                    pa.a        <= opA_i;
                                    b           <= opB_i;
                                end

                       {1'b0,REMUW} :
                                if (~|opB_i32)
                                begin
                                    div_r_o      <= sext32(opA_i32);
                                    div_bubble_o <= 1'b0;
                                end
                                else
                                begin
                                    cnt         <= {1'b0, {$bits(cnt)-1{1'b1}} };
                                    state       <= ST_DIV;
                                    div_stall_o <= 1'b1;

                                    neg_q       <= 1'b0;
                                    neg_s       <= 1'b0;

                                    pa.p        <= 'h0;
                                    pa.a        <= { opA_i32, {XLEN-32{1'b0}} };
                                    b           <= { {XLEN-32{1'b0}}, opB_i32 };
                                end
                       default: ;
                    endcase


          /*
           * actual division loop
           */
          ST_DIV: begin
                      cnt <= cnt -1;
                      if (~| cnt) state <= ST_RES;

                      //restoring divider section
                      if (p_minus_b[XLEN])
                      begin //sub gave negative result
                          pa.p <=  pa_shifted.p;                   //restore
                          pa.a <= {pa_shifted.a[XLEN-1:1], 1'b0};  //shift in '0' for Q
                      end
                      else
                      begin //sub gave positive result
                          pa.p <=  p_minus_b[XLEN-1:0];            //store sub result
                          pa.a <= {pa_shifted.a[XLEN-1:1], 1'b1};  //shift in '1' for Q
                      end
                  end

          /*
           * Result
           */
          ST_RES: if (!mem_stall_i)
	          begin
                      state        <= ST_CHK;
                      div_bubble_o <= 1'b0;
                      div_stall_o  <= 1'b0;

                      unique casex ( opcR_div )
                         DIV    : div_r_o <=         neg_q ? twos(pa.a) : pa.a; 
                         DIVW   : div_r_o <= sext32( neg_q ? twos(pa.a) : pa.a );
                         DIVU   : div_r_o <=                              pa.a;
                         DIVUW  : div_r_o <= sext32(                      pa.a );
                         REM    : div_r_o <=         neg_s ? twos(pa.p) : pa.p;
                         REMW   : div_r_o <= sext32( neg_s ? twos(pa.p) : pa.p );
                         REMU   : div_r_o <=                              pa.p;
                         REMUW  : div_r_o <= sext32(                      pa.p );
                         default: div_r_o <= 'hx;
                      endcase
                  end
        endcase
    end

endmodule 

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

module riscv_div #(
  parameter XLEN = 32
)
(
  input                 rstn,
  input                 clk,

  input                 ex_stall,
  output reg            div_stall,

  //Instruction
  input                 id_bubble,
  input      [ILEN-1:0] id_instr,

  //Operands
  input      [XLEN-1:0] opA,
                        opB,

  //From State
  input      [     1:0] st_xlen,

  //To WB
  output reg            div_bubble,
  output reg [XLEN-1:0] div_r
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
  logic [ILEN        -1:0] div_instr;

  logic [             6:2] opcode, div_opcode;
  logic [             2:0] func3,  div_func3;
  logic [             6:0] func7,  div_func7;

  //Operand generation
  logic [            31:0] opA32,
                           opB32;

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
  assign func7      = id_instr[31:25];
  assign func3      = id_instr[14:12];
  assign opcode     = id_instr[ 6: 2];

  assign div_func7  = div_instr[31:25];
  assign div_func3  = div_instr[14:12];
  assign div_opcode = div_instr[ 6: 2];


  assign xlen32     = st_xlen == RV32I;


  //retain instruction
  always @(posedge clk)
    if (!ex_stall) div_instr <= id_instr;


  /*
   * 32bit operands
   */
  assign opA32   = opA[     31:0];
  assign opB32   = opB[     31:0];


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
  always @(posedge clk,negedge rstn)
    if (!rstn)
    begin
        state      <= ST_CHK;
        div_bubble <= 1'b1;
        div_stall  <= 1'b0;

        div_r      <=  'hx;

        pa         <=  'hx;
        b          <=  'hx;
        neg_q      <= 1'bx;
        neg_s      <= 1'bx;
    end
    else
    begin
        div_bubble <= 1'b1;

        case (state)

          /*
           * Check for exceptions (divide by zero, signed overflow)
           * Setup dividor registers
           */
          ST_CHK: if (!ex_stall && !id_bubble)
                    unique casex ( {xlen32,func7,func3,opcode} )
                       {1'b?,DIV  } :
                                if (~|opB)
                                begin //signed divide by zero
                                    div_r      <= {XLEN{1'b1}}; //=-1
                                    div_bubble <= 1'b0;
                                end
                                else
                                if (opA == {1'b1,{XLEN-1{1'b0}}} && &opB) // signed overflow (Dividend=-2^(XLEN-1), Divisor=-1)
                                begin
                                    div_r      <= {1'b1,{XLEN-1{1'b0}}};
                                    div_bubble <= 1'b0;
                                end
                                else
                                begin
                                    cnt       <= {$bits(cnt){1'b1}};
                                    state     <= ST_DIV;
                                    div_stall <= 1'b1;

                                    neg_q     <= opA[XLEN-1] ^ opB[XLEN-1];
                                    neg_s     <= opA[XLEN-1];

                                    pa.p      <= 'h0;
                                    pa.a      <= abs(opA);
                                    b         <= abs(opB);
                                 end

                       {1'b0,DIVW } :
                                if (~|opB32)
                                begin //signed divide by zero
                                    div_r      <= {XLEN{1'b1}}; //=-1
                                    div_bubble <= 1'b0;
                                end
                                else
                                if (opA32 == {1'b1,{31{1'b0}}} && &opB32) // signed overflow (Dividend=-2^(XLEN-1), Divisor=-1)
                                begin
                                    div_r      <= sext32( {1'b1,{31{1'b0}}} );
                                    div_bubble <= 1'b0;
                                end
                                else
                                begin
                                    cnt       <= {1'b0, {$bits(cnt)-1{1'b1}} };
                                    state     <= ST_DIV;
                                    div_stall <= 1'b1;

                                    neg_q     <= opA32[31] ^ opB32[31];
                                    neg_s     <= opA32[31];

                                    pa.p      <= 'h0;
                                    pa.a      <= { abs( sext32(opA32) ), {XLEN-32{1'b0}}      };
                                    b         <= abs( sext32(opB32) );
                                end

                       {1'b?,DIVU } :
                                if (~|opB)
                                begin //unsigned divide by zero
                                    div_r      <= {XLEN{1'b1}}; //= 2^XLEN -1
                                    div_bubble <= 1'b0;
                                end
                                else
                                begin
                                    cnt       <= {$bits(cnt){1'b1}};
                                    state     <= ST_DIV;
                                    div_stall <= 1'b1;

                                    neg_q     <= 1'b0;
                                    neg_s     <= 1'b0;

                                    pa.p      <= 'h0;
                                    pa.a      <= opA;
                                    b         <= opB;
                                end

                       {1'b0,DIVUW} :
                                if (~|opB32)
                                begin //unsigned divide by zero
                                    div_r      <= {XLEN{1'b1}}; //= 2^XLEN -1
                                    div_bubble <= 1'b0;
                                end
                                else
                                begin
                                    cnt       <= {1'b0, {$bits(cnt)-1{1'b1}} };
                                    state     <= ST_DIV;
                                    div_stall <= 1'b1;

                                    neg_q     <= 1'b0;
                                    neg_s     <= 1'b0;

                                    pa.p      <= 'h0;
                                    pa.a      <= { opA32, {XLEN-32{1'b0}} };
                                    b         <= { {XLEN-32{1'b0}}, opB32 };
                                end

                       {1'b?,REM  } :
                                if (~|opB)
                                begin //signed divide by zero
                                    div_r      <= opA;
                                    div_bubble <= 1'b0;
                                end
                                else
                                if (opA == {1'b1,{XLEN-1{1'b0}}} && &opB) // signed overflow (Dividend=-2^(XLEN-1), Divisor=-1)
                                begin
                                    div_r      <=  'h0;
                                    div_bubble <= 1'b0;
                                end
                                else
                                begin
                                    cnt       <= {$bits(cnt){1'b1}};
                                    state     <= ST_DIV;
                                    div_stall <= 1'b1;

                                    neg_q     <= opA[XLEN-1] ^ opB[XLEN-1];
                                    neg_s     <= opA[XLEN-1];

                                    pa.p      <= 'h0;
                                    pa.a      <= abs(opA);
                                    b         <= abs(opB);
                                end

                       {1'b0,REMW } :
                                if (~|opB32)
                                begin //signed divide by zero
                                    div_r      <= sext32(opA32);
                                    div_bubble <= 1'b0;
                                end
                                else
                                if (opA32 == {1'b1,{31{1'b0}}} && &opB32) // signed overflow (Dividend=-2^(XLEN-1), Divisor=-1)
                                begin
                                    div_r      <=  'h0;
                                    div_bubble <= 1'b0;
                                end
                                else
                                begin
                                    cnt       <= {1'b0, {$bits(cnt)-1{1'b1}} };
                                    state     <= ST_DIV;
                                    div_stall <= 1'b1;

                                    neg_q     <= opA32[31] ^ opB32[31];
                                    neg_s     <= opA32[31];

                                    pa.p      <= 'h0;
                                    pa.a      <= { abs( sext32(opA32) ), {XLEN-32{1'b0}}      };
                                    b         <= abs( sext32(opB32) );
                                end

                       {1'b?,REMU } :
                                if (~|opB)
                                begin //unsigned divide by zero
                                    div_r      <= opA;
                                    div_bubble <= 1'b0;
                                end
                                else
                                begin
                                    cnt       <= {$bits(cnt){1'b1}};
                                    state     <= ST_DIV;
                                    div_stall <= 1'b1;

                                    neg_q     <= 1'b0;
                                    neg_s     <= 1'b0;

                                    pa.p      <= 'h0;
                                    pa.a      <= opA;
                                    b         <= opB;
                                end

                       {1'b0,REMUW} :
                                if (~|opB32)
                                begin
                                    div_r      <= sext32(opA32);
                                    div_bubble <= 1'b0;
                                end
                                else
                                begin
                                    cnt       <= {1'b0, {$bits(cnt)-1{1'b1}} };
                                    state     <= ST_DIV;
                                    div_stall <= 1'b1;

                                    neg_q     <= 1'b0;
                                    neg_s     <= 1'b0;

                                    pa.p      <= 'h0;
                                    pa.a      <= { opA32, {XLEN-32{1'b0}} };
                                    b         <= { {XLEN-32{1'b0}}, opB32 };
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
          ST_RES: begin
                      state      <= ST_CHK;
                      div_bubble <= 1'b0;
                      div_stall  <= 1'b0;

                      unique casex ( {div_func7,div_func3,div_opcode} )
                         DIV    : div_r <=         neg_q ? twos(pa.a) : pa.a; 
                         DIVW   : div_r <= sext32( neg_q ? twos(pa.a) : pa.a );
                         DIVU   : div_r <=                              pa.a;
                         DIVUW  : div_r <= sext32(                      pa.a );
                         REM    : div_r <=         neg_s ? twos(pa.p) : pa.p;
                         REMW   : div_r <= sext32( neg_s ? twos(pa.p) : pa.p );
                         REMU   : div_r <=                              pa.p;
                         REMUW  : div_r <= sext32(                      pa.p );
                         default: div_r <= 'hx;
                      endcase
                  end
        endcase
    end

endmodule 

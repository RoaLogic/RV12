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
//    Load Store Unit (Memory Request)                         //
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


import riscv_opcodes_pkg::*;
import riscv_state_pkg::*;

module riscv_lsu #(
  parameter XLEN           = 32,
  parameter HAS_A          = 0
)
(
  input                           rstn,
  input                           clk,

  input                           ex_stall,
  output reg                      lsu_stall,


  //Instruction
  input                           id_bubble,
  input      [ILEN          -1:0] id_instr,

  output reg                      lsu_bubble,
  output     [XLEN          -1:0] lsu_r,

  input      [EXCEPTION_SIZE-1:0] id_exception,
                                  ex_exception,
                                  mem_exception,
                                  wb_exception,
  output reg [EXCEPTION_SIZE-1:0] lsu_exception,


  //Operands
  input      [XLEN          -1:0] opA,
                                  opB,

  //From State
  input      [               1:0] st_xlen,

  //To Memory
  output reg [XLEN          -1:0] dmem_adr,
                                  dmem_d,
  output reg                      dmem_req,
                                  dmem_we,
  output reg [XLEN/8        -1:0] dmem_be,

  //From Memory (for AMO)
  input                           dmem_ack,
  input      [XLEN          -1:0] dmem_q,
  input                           dmem_misaligned,
                                  dmem_page_fault
);


  ////////////////////////////////////////////////////////////////
  //
  // Variables
  //
  logic [       6:2] opcode;
  logic [       2:0] func3;
  logic [       6:0] func7;
  logic              xlen32;

  //Operand generation
  logic [XLEN  -1:0] immS;


  //FSM
  enum logic [1:0] {IDLE=2'b00, REQ=2'b01, WAIT4ACK=2'b10} state;

  logic [XLEN  -1:0] adr,
                     d;
  logic [XLEN/8-1:0] be;


  ////////////////////////////////////////////////////////////////
  //
  // Module Body
  //

  /*
   * Instruction
   */
  assign func7  = id_instr[31:25];
  assign func3  = id_instr[14:12];
  assign opcode = id_instr[ 6: 2];

  assign xlen32 = (st_xlen == RV32I);


  assign lsu_r  = 'h0; //for AMO


  /*
   * Decode Immediates
   */
  assign immS = { {XLEN-11{id_instr[31]}}, id_instr[30:25],id_instr[11:8],id_instr[7] };


  //Access Statemachine
  always @(posedge clk, negedge rstn)
    if (!rstn)
    begin
        state      <= IDLE;
        lsu_stall  <= 1'b0;
        lsu_bubble <= 1'b1;
        dmem_req   <= 1'b0;
    end
    else
    begin
        dmem_req   <= 1'b0;

        case (state)
            IDLE : if (!ex_stall)
                   begin
                       if (!id_bubble && ~(|id_exception || |ex_exception || |mem_exception || |wb_exception))
                       begin
                           case (opcode)
                              OPC_LOAD : begin
                                             dmem_req   <= 1'b1;
                                             lsu_bubble <= 1'b0;
                                         end
                              OPC_STORE: begin
                                             dmem_req   <= 1'b1;
                                             lsu_bubble <= 1'b0;
                                         end
                              default  : begin
                                             dmem_req   <= 1'b0;
                                             lsu_bubble <= 1'b1;
                                         end
                           endcase
                       end
                       else
                       begin
                           dmem_req   <= 1'b0;
                           lsu_bubble <= 1'b1;
                       end
                   end

          default: begin
                       dmem_req   <= 1'b0;
                       lsu_stall  <= 1'b0;
                       lsu_bubble <= 1'b1;
                   end
        endcase
    end


  //Memory Control Signals
  always @(posedge clk)
    case (state)
      IDLE   : if (!id_bubble)
                 case (opcode)
                   OPC_LOAD : begin
                                  dmem_we  <= 1'b0;
                                  dmem_be  <= be;
                                  dmem_adr <= adr;
                                  dmem_d   <=  'hx;
                              end
                   OPC_STORE: begin
                                  dmem_we  <= 1'b1;
                                  dmem_be  <= be;
                                  dmem_adr <= adr;
                                  dmem_d   <= d;
                              end
                 endcase
      default: begin
                    dmem_we  <= 1'bx;
                    dmem_be  <=  'hx;
                    dmem_adr <=  'hx;
                    dmem_d   <=  'hx;
                end
    endcase



  //memory address
  always_comb
    casex ( {xlen32,func7,func3,opcode} )
       {1'b?,LB    }: adr = opA + opB;
       {1'b?,LH    }: adr = opA + opB;
       {1'b?,LW    }: adr = opA + opB;
       {1'b0,LD    }: adr = opA + opB;                //RV64
       {1'b?,LBU   }: adr = opA + opB;
       {1'b?,LHU   }: adr = opA + opB;
       {1'b0,LWU   }: adr = opA + opB;                //RV64
       {1'b?,SB    }: adr = opA + immS;
       {1'b?,SH    }: adr = opA + immS;
       {1'b?,SW    }: adr = opA + immS;
       {1'b0,SD    }: adr = opA + immS;               //RV64
       default      : adr = opA + opB; //'hx;
    endcase


generate
  //memory byte enable
  if (XLEN==64) //RV64
  begin
    always_comb
      casex ( {func3,opcode} )
        LB     : be = 8'h1 << adr[2:0];
        LH     : be = 8'h3 << adr[2:0];
        LW     : be = 8'hf << adr[2:0];
        LD     : be = 8'hff;
        LBU    : be = 8'h1 << adr[2:0];
        LHU    : be = 8'h3 << adr[2:0];
        LWU    : be = 8'hf << adr[2:0];
        SB     : be = 8'h1 << adr[2:0];
        SH     : be = 8'h3 << adr[2:0];
        SW     : be = 8'hf << adr[2:0];
        SD     : be = 8'hff;
        default: be = 8'hx;
      endcase

    //memory write data
    always_comb
      casex ( {func3,opcode} )
        SB     : d = opB[ 7:0] << (8* adr[2:0]);
        SH     : d = opB[15:0] << (8* adr[2:0]);
        SW     : d = opB[31:0] << (8* adr[2:0]);
        SD     : d = opB;
        default: d = 'hx;
      endcase
  end
  else //RV32
  begin
    always_comb
      casex ( {func3,opcode} )
        LB     : be = 4'h1 << adr[1:0];
        LH     : be = 4'h3 << adr[1:0];
        LW     : be = 4'hf;
        LBU    : be = 4'h1 << adr[1:0];
        LHU    : be = 4'h3 << adr[1:0];
        SB     : be = 4'h1 << adr[1:0];
        SH     : be = 4'h3 << adr[1:0];
        SW     : be = 4'hf;
        default: be = 4'hx;
      endcase

    //memory write data
    always_comb
      casex ( {func3,opcode} )
        SB     : d = opB[ 7:0] << (8* adr[1:0]);
        SH     : d = opB[15:0] << (8* adr[1:0]);
        SW     : d = opB;
        default: d = 'hx;
      endcase
  end
endgenerate


  /*
   * Exceptions
   * Regular memory exceptions are caught in the WB stage
   * However AMO accesses handle the 'load' here.
   */
  always @(posedge clk, negedge rstn)
    if      (!rstn     ) lsu_exception <= 'h0;
    else if (!lsu_stall)
    begin
        lsu_exception <= id_exception;
    end


  /*
   * Assertions
   */

  //assert that address is known when memory is accessed
//  assert property ( @(posedge clk)(dmem_req) |-> (!isunknown(dmem_adr)) );


endmodule : riscv_lsu

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
//    Instruction Fetch                                        //
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


import riscv_opcodes_pkg::*;
import riscv_state_pkg::*;

module riscv_if #(
  parameter            XLEN           = 32,
  parameter [XLEN-1:0] PC_INIT        = 'h200,
  parameter            PARCEL_SIZE    = 32,
  parameter            HAS_BPU        = 0,
  parameter            HAS_RVC        = 0
)
(
  input                           rstn,          //Reset
  input                           clk,           //Clock
  input                           id_stall,

  input                           if_stall_nxt_pc,
  input      [PARCEL_SIZE   -1:0] if_parcel,
  input      [XLEN          -1:0] if_parcel_pc,
  input                           if_parcel_valid,
  input                           if_parcel_misaligned, 
  input                           if_parcel_page_fault,

  output reg [ILEN          -1:0] if_instr,      //Instruction out
  output reg                      if_bubble,     //Insert bubble in the pipe (NOP instruction)
  output reg [EXCEPTION_SIZE-1:0] if_exception,  //Exceptions


  input      [               1:0] bp_bp_predict, //Branch Prediction bits
  output reg [               1:0] if_bp_predict, //push down the pipe

  input                           bu_flush,      //flush pipe & load new program counter
                                  st_flush,
                                  du_flush,      //flush pipe after debug exit

  input      [XLEN          -1:0] bu_nxt_pc,     //Branch Unit Next Program Counter
                                  st_nxt_pc,     //State Next Program Counter

  output reg [XLEN          -1:0] if_nxt_pc,     //next Program Counter
  output                          if_stall,      //stall instruction fetch BIU (cache/bus-interface)
  output                          if_flush,      //flush instruction fetch BIU (cache/bus-interface)
  output reg [XLEN          -1:0] if_pc          //Program Counter
);


  ////////////////////////////////////////////////////////////////
  //
  // Variables
  //

  //Instruction size
  logic is_16bit_instruction;
  logic is_32bit_instruction;
//  logic is_48bit_instruction;
//  logic is_64bit_instruction;

  logic                      flushes;      //OR all flush signals

  logic [2*ILEN        -1:0] parcel_shift_register;
  logic [ILEN          -1:0] new_parcel,
                             active_parcel,
                             converted_instruction,
                             pd_instr;
  logic                      pd_bubble;

  logic [XLEN          -1:0] pd_pc;
  logic                      parcel_valid;
  logic [               2:0] parcel_sr_valid,
                             parcel_sr_bubble;

  logic [               6:2] opcode;

  logic [EXCEPTION_SIZE-1:0] parcel_exception,
                             pd_exception;

  logic [XLEN          -1:0] branch_pc;
  logic                      branch_taken;

  logic [XLEN          -1:0] immB,
                             immJ;


  ////////////////////////////////////////////////////////////////
  //
  // Module Body
  //

  //All flush signals
  assign flushes = bu_flush | st_flush | du_flush;

  //Flush upper layer (memory BIU) 
  assign if_flush = bu_flush | st_flush | du_flush | branch_taken;

  //stall program counter on ID-stall and when instruction-hold register is full
  assign if_stall = id_stall | (&parcel_sr_valid & ~flushes);



  //parcel is valid when bus-interface says so AND when received PC is requested PC
  always @(posedge clk,negedge rstn)
    if (!rstn) parcel_valid <= 1'b0;
    else       parcel_valid <= if_parcel_valid;


  /*
   * Next Program Counter
   */
  always @(posedge clk,negedge rstn)
    if      (!rstn                        ) if_nxt_pc <= PC_INIT;
    else if ( st_flush                    ) if_nxt_pc <= st_nxt_pc;
    else if ( bu_flush        ||  du_flush) if_nxt_pc <= bu_nxt_pc; //flush takes priority
    else if ( branch_taken    && !id_stall) if_nxt_pc <= branch_pc;
    else if (!if_stall_nxt_pc && !id_stall) if_nxt_pc <= if_nxt_pc + 'h4;
//TODO: handle if_stall and 16bit instructions

  always @(posedge clk,negedge rstn)
    if      (!rstn                        ) pd_pc <= PC_INIT;
    else if ( st_flush                    ) pd_pc <= st_nxt_pc;
    else if ( bu_flush        ||  du_flush) pd_pc <= bu_nxt_pc;
    else if ( branch_taken    && !id_stall) pd_pc <= branch_pc;
    else if ( if_parcel_valid && !id_stall) pd_pc <= if_parcel_pc;

  always @(posedge clk,negedge rstn)
    if      (!rstn                ) if_pc <= PC_INIT;
    else if ( st_flush            ) if_pc <= st_nxt_pc;
    else if ( bu_flush || du_flush) if_pc <= bu_nxt_pc;
    else if (!id_stall            ) if_pc <= pd_pc;


  /*
   *  Instruction
   */
  //instruction shift register, for 16bit instruction support
//  assign new_parcel = if_parcel_valid ? if_parcel : INSTR_NOP; //RiH: was parcel_valid, handle in-flight faulty instruction
  assign new_parcel = if_parcel;
  always @(posedge clk,negedge rstn)
    if      (!rstn    ) parcel_shift_register <= {INSTR_NOP,INSTR_NOP};
    else if ( flushes ) parcel_shift_register <= {INSTR_NOP,INSTR_NOP};
    else if (!id_stall)
      if (branch_taken)
          parcel_shift_register <= {INSTR_NOP,INSTR_NOP};
      else
        case (parcel_sr_valid)
            3'b000:                           parcel_shift_register <= {INSTR_NOP , new_parcel};
            3'b001: if (is_16bit_instruction) parcel_shift_register <= {INSTR_NOP , new_parcel};
                    else                      parcel_shift_register <= {new_parcel, parcel_shift_register[15:0]};
            3'b011: if (is_16bit_instruction) parcel_shift_register <= {new_parcel, parcel_shift_register[16 +: ILEN]};
                    else                      parcel_shift_register <= {INSTR_NOP , new_parcel};
            3'b111: if (is_16bit_instruction) parcel_shift_register <= {INSTR_NOP , parcel_shift_register[16 +: ILEN]};
                    else                      parcel_shift_register <= {new_parcel, parcel_shift_register[32 +: 16]};
        endcase


  always @(posedge clk,negedge rstn)
    if      (!rstn    ) parcel_sr_valid <= 'h0;
    else if ( flushes ) parcel_sr_valid <= 'h0;
    else if (!id_stall)
      if (branch_taken)
          parcel_sr_valid <= 'h0;
      else
        case (parcel_sr_valid)
//branch to 16bit address would yield 3'b010
            3'b000:                           parcel_sr_valid <= {           1'b0, if_parcel_valid, if_parcel_valid}; //3'b011;
            3'b001: if (is_16bit_instruction) parcel_sr_valid <= {           1'b0, if_parcel_valid, if_parcel_valid}; //3'b011;
                    else                      parcel_sr_valid <= {if_parcel_valid, if_parcel_valid,            1'b1}; //3'b111;
            3'b011: if (is_16bit_instruction) parcel_sr_valid <= {if_parcel_valid, if_parcel_valid,            1'b1}; //3'b111;
                    else                      parcel_sr_valid <= {           1'b0, if_parcel_valid, if_parcel_valid}; //3'b011;
            3'b111: if (is_16bit_instruction) parcel_sr_valid <= {           1'b0,            1'b1,            1'b1}; //3'b011;
                    else                      parcel_sr_valid <= {if_parcel_valid, if_parcel_valid,            1'b1}; //3'b111;
        endcase

  assign active_parcel = parcel_shift_register[ILEN-1:0];
  assign pd_bubble     = is_16bit_instruction ? ~parcel_sr_valid[0] : ~&parcel_sr_valid[1:0];

  assign is_16bit_instruction = ~&active_parcel[1:0];
  assign is_32bit_instruction =  &active_parcel[1:0];
//  assign is_48bit_instruction =   active_parcel[5:0] == 6'b011111;
//  assign is_64bit_instruction =   active_parcel[6:0] == 7'b0111111;

  
  //Convert 16bit instructions to 32bit instructions here.
  always_comb
    case(active_parcel)
      WFI    : pd_instr = INSTR_NOP;                                 //Implement WFI as a nop 
      default: if (is_32bit_instruction) pd_instr = active_parcel;
               else                      pd_instr = -1;              //Illegal
    endcase


  always @(posedge clk,negedge rstn)
    if      (!rstn    ) if_instr <= INSTR_NOP;
    else if ( flushes ) if_instr <= INSTR_NOP;
    else if (!id_stall) if_instr <= pd_instr;


  always @(posedge clk,negedge rstn)
    if      (!rstn    ) if_bubble <= 1'b1;
    else if ( flushes ) if_bubble <= 1'b1;
    else if (!id_stall) if_bubble <= pd_bubble;


  /*
   * Branches & Jump
   */
  assign immB = {{XLEN-12{pd_instr[31]}},                pd_instr[ 7],pd_instr[30:25],pd_instr[11: 8],1'b0};
  assign immJ = {{XLEN-20{pd_instr[31]}},pd_instr[19:12],pd_instr[20],pd_instr[30:25],pd_instr[24:21],1'b0};

  assign opcode = pd_instr[6:2];

  // Branch and Jump prediction
  always_comb
    casex ({pd_bubble,opcode})
      {1'b0,OPC_JAL   } : begin
                             branch_taken = 1'b1;
                             branch_pc    = pd_pc + immJ;
                          end
      {1'b0,OPC_BRANCH} : begin
                              //if this CPU has a Branch Predict Unit, then use it's prediction
                              //otherwise assume backwards jumps taken, forward jumps not taken
                              branch_taken = HAS_BPU ? bp_bp_predict[1] : immB[31];
                              branch_pc    = pd_pc + immB;
                          end
      default           : begin
                              branch_taken = 1'b0;
                              branch_pc    = 'hx;
                          end
    endcase

  always @(posedge clk,negedge rstn)
    if      (!rstn    ) if_bp_predict <= 2'b00;
    else if (!id_stall) if_bp_predict <= (HAS_BPU) ? bp_bp_predict : {branch_taken,1'b0};



  /*
   * Exceptions
   */
  //parcel-fetch
  always @(posedge clk,negedge rstn)
    if      (!rstn                     ) parcel_exception <= 'h0;
    else if ( flushes                  ) parcel_exception <= 'h0;
    else if ( parcel_valid && !id_stall)
    begin
        parcel_exception <= 'h0;

        parcel_exception[CAUSE_MISALIGNED_INSTRUCTION  ] <= if_parcel_misaligned;
        parcel_exception[CAUSE_INSTRUCTION_ACCESS_FAULT] <= if_parcel_page_fault;
    end 


  //pre-decode
  always @(posedge clk,negedge rstn)
    if      (!rstn                     ) pd_exception <= 'h0;
    else if ( flushes                  ) pd_exception <= 'h0;
    else if ( parcel_valid && !id_stall) pd_exception <= parcel_exception;


  //instruction-fetch
  always @(posedge clk,negedge rstn)
    if      (!rstn                     ) if_exception <= 'h0;
    else if ( flushes                  ) if_exception <= 'h0;
    else if ( parcel_valid && !id_stall) if_exception <= pd_exception;

endmodule


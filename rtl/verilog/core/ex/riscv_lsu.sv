/////////////////////////////////////////////////////////////////////
//   ,------.                    ,--.                ,--.          //
//   |  .--. ' ,---.  ,--,--.    |  |    ,---. ,---. `--' ,---.    //
//   |  '--'.'| .-. |' ,-.  |    |  |   | .-. | .-. |,--.| .--'    //
//   |  |\  \ ' '-' '\ '-'  |    |  '--.' '-' ' '-' ||  |\ `--.    //
//   `--' '--' `---'  `--`--'    `-----' `---' `-   /`--' `---'    //
//                                             `---'               //
//    RISC-V                                                       //
//    Load Store Unit                                              //
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


module riscv_lsu
import riscv_opcodes_pkg::*;
import riscv_state_pkg::*;
import biu_constants_pkg::*;
#(
  parameter XLEN           = 32,
  parameter HAS_A          = 0
)
(
  input                           rst_ni,
  input                           clk_i,

  input                           ex_stall_i,
  output reg                      lsu_stall_o,


  //Instruction
  input  instruction_t            id_insn_i,

  output reg                      lsu_bubble_o,
  output     [XLEN          -1:0] lsu_r_o,

  input  interrupts_exceptions_t  id_exceptions_i,
                                  ex_exceptions_i,
                                  mem_exceptions_i,
                                  wb_exceptions_i,
				  
  output interrupts_exceptions_t  lsu_exceptions_o,


  //Operands
  input      [XLEN          -1:0] opA_i,
                                  opB_i,

  //From State
  input      [               1:0] st_xlen_i,
  input                           st_be_i,

  //To Memory
  output reg                      dmem_req_o,
                                  dmem_lock_o,
                                  dmem_we_o,
  output biu_size_t               dmem_size_o,
  output reg [XLEN          -1:0] dmem_adr_o,
                                  dmem_d_o,


  //From Memory (for AMO)
  input                           dmem_ack_i,
  input      [XLEN          -1:0] dmem_q_i,
  input                           dmem_misaligned_i,
                                  dmem_page_fault_i
);

  ////////////////////////////////////////////////////////////////
  //
  // Variables
  //
  opcR_t             opcR;
  logic              xlen32;

  //Operand generation
  immS_t             immS;
  logic [XLEN  -1:0] ext_immS;


  //FSM
  enum logic [1:0] {IDLE=2'b00} state;

  logic [XLEN  -1:0] adr,
                     d;
  biu_size_t         size;


  ////////////////////////////////////////////////////////////////
  //
  // Module Body
  //

  /*
   * Instruction
   */
  assign opcR   = decode_opcR(id_insn_i.instr);
  assign xlen32 = (st_xlen_i == RV32I);

  assign lsu_r_o  = 'h0; //for AMO


  /*
   * Decode Immediates
   */
  assign immS     = decode_immS(id_insn_i.instr);
  assign ext_immS = { {XLEN-$bits(immS){immS[$left(immS,1)]}}, immS};


  //Access Statemachine
  always @(posedge clk_i, negedge rst_ni)
    if (!rst_ni)
    begin
        state        <= IDLE;
        lsu_stall_o  <= 1'b0;
        lsu_bubble_o <= 1'b1;
        dmem_req_o   <= 1'b0;
        dmem_lock_o  <= 1'b0;
    end
    else
    begin
        dmem_req_o   <= 1'b0;

        unique case (state)
            IDLE : if (!ex_stall_i)
                   begin
                       if (!id_insn_i.bubble && ~(id_exceptions_i.any || ex_exceptions_i.any || mem_exceptions_i.any || wb_exceptions_i.any))
                       begin
                           unique case (opcR.opcode)
                              OPC_LOAD : begin
                                             dmem_req_o   <= 1'b1;
                                             dmem_lock_o  <= 1'b0;
                                             lsu_stall_o  <= 1'b0;
                                             lsu_bubble_o <= 1'b0;
                                             state        <= IDLE;
                                         end
                              OPC_STORE: begin
                                             dmem_req_o   <= 1'b1;
                                             dmem_lock_o  <= 1'b0;
                                             lsu_stall_o  <= 1'b0;
                                             lsu_bubble_o <= 1'b0;
                                             state        <= IDLE;
                                         end
                              default  : begin
                                             dmem_req_o   <= 1'b0;
                                             dmem_lock_o  <= 1'b0;
                                             lsu_stall_o  <= 1'b0;
                                             lsu_bubble_o <= 1'b1;
                                             state        <= IDLE;
                                         end
                           endcase
                       end
                       else
                       begin
                           dmem_req_o   <= 1'b0;
                           dmem_lock_o  <= 1'b0;
                           lsu_stall_o  <= 1'b0;
                           lsu_bubble_o <= 1'b1;
                           state        <= IDLE;
                       end
                   end

          default: begin
                       dmem_req_o   <= 1'b0;
                       dmem_lock_o  <= 1'b0;
                       lsu_stall_o  <= 1'b0;
                       lsu_bubble_o <= 1'b1;
                       state        <= IDLE;
                   end
        endcase
    end


  //Memory Control Signals
  always @(posedge clk_i)
    unique case (state)
      IDLE   : if (!id_insn_i.bubble)
                 unique case (opcR.opcode)
                   OPC_LOAD : begin
                                  dmem_we_o   <= 1'b0;
                                  dmem_size_o <= size;
                                  dmem_adr_o  <= adr;
                                  dmem_d_o    <=  'hx;
                              end
                   OPC_STORE: begin
                                  dmem_we_o   <= 1'b1;
                                  dmem_size_o <= size;
                                  dmem_adr_o  <= adr;
                                  dmem_d_o    <= d;
                              end
                   default  : ; //do nothing
                 endcase

      default: begin
                    dmem_we_o   <= 1'bx;
                    dmem_size_o <= UNDEF_SIZE;
                    dmem_adr_o  <=  'hx;
                    dmem_d_o    <=  'hx;
                end
    endcase



  //memory address
  always_comb
    casex ( {xlen32,opcR} )
       {1'b?,LB    }: adr = opA_i + opB_i;
       {1'b?,LH    }: adr = opA_i + opB_i;
       {1'b?,LW    }: adr = opA_i + opB_i;
       {1'b0,LD    }: adr = opA_i + opB_i;              //RV64
       {1'b?,LBU   }: adr = opA_i + opB_i;
       {1'b?,LHU   }: adr = opA_i + opB_i;
       {1'b0,LWU   }: adr = opA_i + opB_i;              //RV64
       {1'b?,SB    }: adr = opA_i + ext_immS;
       {1'b?,SH    }: adr = opA_i + ext_immS;
       {1'b?,SW    }: adr = opA_i + ext_immS;
       {1'b0,SD    }: adr = opA_i + ext_immS;           //RV64
       default      : adr = opA_i + opB_i;              //'hx;
    endcase


generate
  //memory byte enable
  if (XLEN==64) //RV64
  begin
    always_comb
      casex ( opcR )
        LB     : size = BYTE;
        LH     : size = HWORD;
        LW     : size = WORD;
        LD     : size = DWORD;
        LBU    : size = BYTE;
        LHU    : size = HWORD;
        LWU    : size = WORD;
        SB     : size = BYTE;
        SH     : size = HWORD;
        SW     : size = WORD;
        SD     : size = DWORD;
        default: size = UNDEF_SIZE;
      endcase


    //memory write data
    always_comb
      casex ( opcR )
        SB     : d =              opB_i[ 7: 0]   << (8* adr[2:0]);
        SH     : d = (!st_be_i ?  opB_i[15: 0]
                               : {opB_i[ 7: 0],
                                  opB_i[15: 8]}) << (8* adr[2:0]);
        SW     : d = (!st_be_i ?  opB_i[31: 0]
                               : {opB_i[ 7: 0],
                                  opB_i[15: 8],
                                  opB_i[23:16],
                                  opB_i[31:24]}) << (8* adr[2:0]);
        SD     : d =  !st_be_i ?  opB_i
                               : {opB_i[ 7: 0],
                                  opB_i[15: 8],
                                  opB_i[23:16],
                                  opB_i[31:24],
                                  opB_i[39:32],
                                  opB_i[47:40],
                                  opB_i[55:48],
                                  opB_i[63:56]};
        default: d = 'hx;
      endcase
  end
  else //RV32
  begin
    always_comb
      casex ( opcR )
        LB     : size = BYTE;
        LH     : size = HWORD;
        LW     : size = WORD;
        LBU    : size = BYTE;
        LHU    : size = HWORD;
        SB     : size = BYTE;
        SH     : size = HWORD;
        SW     : size = WORD;
        default: size = UNDEF_SIZE;
      endcase


    //memory write data
    always_comb
      casex ( opcR )
        SB     : d = opB_i[ 7:0] << (8* adr[1:0]);
        SH     : d = opB_i[15:0] << (8* adr[1:0]);
        SW     : d = opB_i;
        default: d = 'hx;
      endcase
  end
endgenerate


  /*
   * Exceptions
   * Regular memory exceptions are caught in the WB stage
   * However AMO accesses handle the 'load' here.
   */
  always @(posedge clk_i, negedge rst_ni)
    if      (!rst_ni     ) lsu_exceptions_o <= 'h0;
    else if (!lsu_stall_o)
    begin
        lsu_exceptions_o <= id_exceptions_i;
    end


  /*
   * Assertions
   */

  //assert that address is known when memory is accessed
//  assert property ( @(posedge clk_i)(dmem_req_o) |-> (!isunknown(dmem_adr_o)) );

endmodule : riscv_lsu

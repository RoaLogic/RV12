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
//    Load/Store Unit                                          //
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

module riscv_lsu #(
  parameter XLEN           = 32,
  parameter INSTR_SIZE     = 32,
  parameter EXCEPTION_SIZE = 12
)
(
  input                           rstn,
  input                           clk,

  output reg                      lsu_stall,

  //Instruction
  input                           id_bubble,
  input      [INSTR_SIZE    -1:0] id_instr,
                                  ex_instr,

  //from ID
  input      [XLEN          -1:0] opA,
                                  opB,

  //to WB
  output reg                      lsu_bubble,
  output reg [XLEN          -1:0] lsu_memadr,
                                  lsu_r,
  output reg [EXCEPTION_SIZE-1:0] lsu_exception,


  //To DCACHE/Memory
  output reg [XLEN          -1:0] mem_adr,
                                  mem_d,
  output reg                      mem_req,
                                  mem_we,
  output reg [XLEN/8        -1:0] mem_be,
  input                           mem_ack,
  input      [XLEN          -1:0] mem_q,
  input                           mem_misaligned,
                                  mem_page_fault
);


  ////////////////////////////////////////////////////////////////
  //
  // Variables
  //
  localparam SBITS=$clog2(XLEN);

  logic [             6:2] opcode, ex_opcode;
  logic [             2:0] func3,  ex_func3;
  logic [             6:0] func7,  ex_func7;
  logic                    is_rv64;

  //Operand generation
  logic [XLEN        -1:0] immS;


  //DCACHE/Memory data
  logic [XLEN        -1:0] mem_data;
  logic [             7:0] mem_qb;
  logic [            15:0] mem_qh;
  logic [            31:0] mem_qw;


  //FSM
  enum logic [1:0] {IDLE=2'b00, REQ=2'b01, WAIT4ACK=2'b10} state;


  ////////////////////////////////////////////////////////////////
  //
  // Module Body
  //
  import riscv_pkg::*;
  import riscv_state_pkg::*;


  /*
   * Instruction
   */
  assign func7  = id_instr[31:25];
  assign func3  = id_instr[14:12];
  assign opcode = id_instr[ 6: 2];

  assign ex_func7  = ex_instr[31:25];
  assign ex_func3  = ex_instr[14:12];
  assign ex_opcode = ex_instr[ 6: 2];

  assign is_rv64 = (XLEN == 64);


  /*
   * Decode Immediates
   */
  assign immS = { {XLEN-11{id_instr[31]}},                             id_instr[30:25],id_instr[11: 8],id_instr[ 7] };


  /*
   *  Memory Access
   *
   *  FPGA and Structured ASIC memories have registered inputs, therefore output
   *   the controls here, such that the memory is ready in the MEM state
   *  This actually reduces the critical path through 'result', because the
   *   number of bypasses can now be reduced
   */
  always @(posedge clk, negedge rstn)
    if (!rstn)
    begin
        state      <= IDLE;
        lsu_stall  <= 1'b0;
        lsu_bubble <= 1'b1;
    end
    else
    begin
        lsu_bubble <= 1'b1;

        case (state)
          IDLE    : if (!id_bubble && (opcode == OPC_LOAD || opcode == OPC_STORE))
                    begin
                        state      <= WAIT4ACK;
                        lsu_stall  <= 1'b1;
                    end

          REQ     : begin
                    end

          WAIT4ACK: if (mem_ack)
                      if (!id_bubble && (opcode == OPC_LOAD || opcode == OPC_STORE))
                      begin //new memory access request 
                          state      <= WAIT4ACK;
                          lsu_stall  <= 1'b1;
                          lsu_bubble <= 1'b0;
                      end
                      else
                      begin
                          state      <= IDLE;
                          lsu_stall  <= 1'b0;
                          lsu_bubble <= 1'b0;
                      end
      endcase
    end


  //memory request
  always_comb
    case (state)
      IDLE   : casex ( {id_bubble,opcode} )
                 {1'b0,OPC_LOAD }: mem_req = 1'b1; //~lsu_stall;
                 {1'b0,OPC_STORE}: mem_req = 1'b1; //~lsu_stall;
                 default         : mem_req =  'b0;
               endcase
      default: mem_req = 'b0;
    endcase


  //memory address
  always_comb
    casex ( {is_rv64,func7,func3,opcode} )
       {1'b?,LB    }: mem_adr = opA + opB;
       {1'b?,LH    }: mem_adr = opA + opB;
       {1'b?,LW    }: mem_adr = opA + opB;
       {1'b1,LD    }: mem_adr = opA + opB;                //RV64
       {1'b?,LBU   }: mem_adr = opA + opB;
       {1'b?,LHU   }: mem_adr = opA + opB;
       {1'b1,LWU   }: mem_adr = opA + opB;                //RV64
       {1'b?,SB    }: mem_adr = opA + immS;
       {1'b?,SH    }: mem_adr = opA + immS;
       {1'b?,SW    }: mem_adr = opA + immS;
       {1'b1,SD    }: mem_adr = opA + immS;               //RV64
       default      : mem_adr = opA + opB; //'hx;
    endcase


  //memory write enable
  always_comb
    casex (opcode)
      OPC_STORE: mem_we = 'b1;
      default  : mem_we = 'b0;
    endcase

generate
  //memory byte enable
  if (XLEN==64) //RV64
  begin
    always_comb
      casex ( {func3,opcode} )
        LB     : mem_be = 8'h1 << mem_adr[2:0];
        LH     : mem_be = 8'h3 << mem_adr[2:0];
        LW     : mem_be = 8'hf << mem_adr[2:0];
        LD     : mem_be = 8'hff;
        LBU    : mem_be = 8'h1 << mem_adr[2:0];
        LHU    : mem_be = 8'h3 << mem_adr[2:0];
        LWU    : mem_be = 8'hf << mem_adr[2:0];
        SB     : mem_be = 8'h1 << mem_adr[2:0];
        SH     : mem_be = 8'h3 << mem_adr[2:0];
        SW     : mem_be = 8'hf << mem_adr[2:0];
        SD     : mem_be = 8'hff;
        default: mem_be = 8'hx;
      endcase

    //memory write data
    always_comb
      casex ( {func3,opcode} )
        SB     : mem_d = opB[ 7:0] << (8* mem_adr[2:0]);
        SH     : mem_d = opB[15:0] << (8* mem_adr[2:0]);
        SW     : mem_d = opB[31:0] << (8* mem_adr[2:0]);
        SD     : mem_d = opB;
        default: mem_d = 'hx;
      endcase
  end
  else //RV32
  begin
    always_comb
      casex ( {func3,opcode} )
        LB     : mem_be = 4'h1 << mem_adr[1:0];
        LH     : mem_be = 4'h3 << mem_adr[1:0];
        LW     : mem_be = 4'hf;
        LBU    : mem_be = 4'h1 << mem_adr[1:0];
        LHU    : mem_be = 4'h3 << mem_adr[1:0];
        SB     : mem_be = 4'h1 << mem_adr[1:0];
        SH     : mem_be = 4'h3 << mem_adr[1:0];
        SW     : mem_be = 4'hf;
        default: mem_be = 4'hx;
      endcase

    //memory write data
    always_comb
      casex ( {func3,opcode} )
        SB     : mem_d = opB[ 7:0] << (8* mem_adr[1:0]);
        SH     : mem_d = opB[15:0] << (8* mem_adr[1:0]);
        SW     : mem_d = opB;
        default: mem_d = 'hx;
      endcase
  end
endgenerate



  /*
   * To WB
   */
  always @(posedge clk)
    if (!lsu_stall) lsu_memadr <= mem_adr;


  // data from memory
generate
  if (XLEN==64)
  begin
      assign mem_qb = mem_q >> (8* lsu_memadr[2:0]);
      assign mem_qh = mem_q >> (8* lsu_memadr[2:0]);
      assign mem_qw = mem_q >> (8* lsu_memadr[2:0]);

      always_comb
        casex ( {ex_func7,ex_func3,ex_opcode} )
          LB     : mem_data = { {XLEN- 8{mem_qb[ 7]}},mem_qb};
          LH     : mem_data = { {XLEN-16{mem_qh[15]}},mem_qh};
          LW     : mem_data = { {XLEN-32{mem_qw[31]}},mem_qw};
          LD     : mem_data = {                       mem_q };
          LBU    : mem_data = { {XLEN- 8{      1'b0}},mem_qb};
          LHU    : mem_data = { {XLEN-16{      1'b0}},mem_qh};
          LWU    : mem_data = { {XLEN-32{      1'b0}},mem_qw};
          default: mem_data = 'hx;
        endcase
  end
  else
  begin
      assign mem_qb = mem_q >> (8* lsu_memadr[1:0]);
      assign mem_qh = mem_q >> (8* lsu_memadr[1:0]);
      assign mem_qw = mem_q;

      always_comb
        casex ( {ex_func7,ex_func3,ex_opcode} )
          LB     : mem_data = { {XLEN- 8{mem_qb[ 7]}},mem_qb};
          LH     : mem_data = { {XLEN-16{mem_qh[15]}},mem_qh};
          LW     : mem_data = {                       mem_qw};
          LBU    : mem_data = { {XLEN- 8{      1'b0}},mem_qb};
          LHU    : mem_data = { {XLEN-16{      1'b0}},mem_qh};
          default: mem_data = 'hx;
        endcase
  end
endgenerate

  always @(posedge clk)
    if (mem_ack) lsu_r <= mem_data;


  /*
   * Exceptions
   */
  always @(posedge clk)
    begin
        lsu_exception = 'h0;

        if (ex_opcode == OPC_LOAD && mem_ack)
          lsu_exception[CAUSE_MISALIGNED_LOAD   ] <= mem_misaligned;

        if (ex_opcode == OPC_STORE && mem_ack)
          lsu_exception[CAUSE_MISALIGNED_STORE  ] <= mem_misaligned;

        if (ex_opcode == OPC_LOAD)
          lsu_exception[CAUSE_LOAD_ACCESS_FAULT ] <= mem_page_fault;

        if (ex_opcode == OPC_STORE)
          lsu_exception[CAUSE_STORE_ACCESS_FAULT] <= mem_page_fault;
    end

endmodule 

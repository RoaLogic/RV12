/////////////////////////////////////////////////////////////////////
//   ,------.                    ,--.                ,--.          //
//   |  .--. ' ,---.  ,--,--.    |  |    ,---. ,---. `--' ,---.    //
//   |  '--'.'| .-. |' ,-.  |    |  |   | .-. | .-. |,--.| .--'    //
//   |  |\  \ ' '-' '\ '-'  |    |  '--.' '-' ' '-' ||  |\ `--.    //
//   `--' '--' `---'  `--`--'    `-----' `---' `-   /`--' `---'    //
//                                             `---'               //
//    RISC-V                                                       //
//    Instruction Fetch                                            //
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

module riscv_if #(
  parameter            XLEN           = 32,
  parameter [XLEN-1:0] PC_INIT        = 'h200,
  parameter            HAS_RVC        = 0,

  localparam PARCEL_SIZE = 16
)
(
  input                             rst_ni,                   //Reset
  input                             clk_i,                    //Clock

  output reg [XLEN            -1:0] imem_adr_o,               //next Instruction Memory location
  output                            imem_req_o,               //request new parcel from BIU (cache/bus-interface)
  input                             imem_ack_i,               //acknowledge from BIU; send new imem_adr
  output                            imem_flush_o,             //flush instruction fetch BIU (cache/bus-interface)

  input      [XLEN            -1:0] imem_parcel_i,
  input      [XLEN/PARCEL_SIZE-1:0] imem_parcel_valid_i,
  input                             imem_parcel_misaligned_i,
  input                             imem_parcel_page_fault_i,
  input                             imem_parcel_error_i,

  output reg [XLEN            -1:0] if_bp_pc_o,               //Program counter toward Branch Prediction
                                    if_pc_o,                  //Program Counter
  output instruction_t              if_insn_o,
  output exceptions_t               if_exceptions_o,          //Exceptions

  input                             pd_stall_i,
                                    pd_flush_i,
				    pd_latch_nxt_pc_i,

  input                             bu_flush_i,               //flush pipe & load new program counter
                                    st_flush_i,

				    du_stall_i,
                                    du_latch_nxt_pc_i,

  input      [XLEN            -1:0] pd_nxt_pc_i,              //pre-decoder Next Program Counter
                                    bu_nxt_pc_i,              //Branch Unit Next Program Counter
                                    st_nxt_pc_i,              //State Next Program Counter

  input      [                 1:0] st_xlen_i                 //Current XLEN setting
);

  ////////////////////////////////////////////////////////////////
  //
  // Constants
  //

  //Hanlde up to 2 inflight instruction fetches
  localparam INFLIGHT_CNT   = 2;

  //Queue depth, in parcels
  localparam QUEUE_DEPTH    = 3*INFLIGHT_CNT * XLEN/PARCEL_SIZE;

  //Halt instruction fetches when FULL_THRESHOLD (in parcels) reached
  localparam FULL_THRESHOLD = QUEUE_DEPTH - (INFLIGHT_CNT+1)*XLEN/PARCEL_SIZE;


  ////////////////////////////////////////////////////////////////
  //
  // Variables
  //

  logic             has_rvc,
                    xlen32,
                    xlen64,
                    xlen128;

  logic             flushes;


  //Parcel queue signals
  logic             parcel_queue_full;
  logic             parcel_queue_empty;

  logic [      1:0] parcel_queue_rd;

  logic             parcel_valid;
  instr_t           ext_parcel,
                    active_parcel,     //parcel from queue
                    rv_instr;
  rvc_instr_t       rvc_parcel;

  logic             rv_bubble;

  exceptions_t      parcel_exceptions;

  logic [XLEN -1:0] pc;

  //Instruction length decoding
  logic             is_16bit_instruction;
  logic             is_32bit_instruction;
//  logic             is_48bit_instruction;
//  logic             is_64bit_instruction;






  ////////////////////////////////////////////////////////////////
  //
  // Module Body
  //

  assign has_rvc = (HAS_RVC != 0);

  
  /*
   * Next Parcel
   * Ideally the CPU would issue a new PC and receive the instruction on the
   * next cycle. Unfortunately that's not possible due to the registered
   * (input and sometimes output) of new (FPGA) memories
   * Therefore we generated a linear stream of addresses and assume the
   * CPU executes sequentially (which is a fair assumption for a program)
   * The received parcels (unit of instruction size: 16bits) are pushed into
   *  a shift register, from which then the actual instructions are extracted
   *
   * A flush means the parcel shift register and the upstream bus interface
   * unit (BIU) must be flushed
   */

  //All flush signals
  assign flushes = pd_flush_i;
  assign is_rv32  = st_xlen_i == RV32I;
  assign is_rv64  = st_xlen_i == RV64I;
  assign is_rv128 = st_xlen_i == RV128I;


  //request new parcel when parcel_queue not full and no flushes
  assign imem_req_o = ~parcel_queue_full & ~flushes;


  //Instruction Memory Address generator
  //Branches can go to misaligned addresses, however next address is aligned
  always @(posedge clk_i, negedge rst_ni)
    if      (!rst_ni                          ) imem_adr_o <= PC_INIT;
    else if ( st_flush_i                      ) imem_adr_o <= st_nxt_pc_i;
    else if ( bu_flush_i || du_latch_nxt_pc_i ) imem_adr_o <= bu_nxt_pc_i;
    else
    begin
        if      ( pd_latch_nxt_pc_i        )    imem_adr_o <= pd_nxt_pc_i;
        else if ( imem_req_o && imem_ack_i )    imem_adr_o <= (imem_adr_o + (XLEN/8)) & ( {XLEN{1'b1}} << $clog2(XLEN/8) );
    end


  //Flush upper layer (memory BIU) 
  assign imem_flush_o = flushes | pd_latch_nxt_pc_i;

  
  /*
   * Received parcels are pushed into a parcel queue
   * There's extra room in the queue to adjust for any
   * pipeline stalls while parcels are in flight
   */
  riscv_parcel_queue #(
    .DEPTH                   ( QUEUE_DEPTH      ),
    .WR_PARCELS              ( XLEN/PARCEL_SIZE ),
    .RD_PARCELS              ( 4                ), //max 32bit instructions
    .ALMOST_EMPTY_THRESHOLD  ( 1                ),
    .ALMOST_FULL_THRESHOLD   ( FULL_THRESHOLD   )
  )
  parcel_queue_inst (
    .rst_ni              ( rst_ni                   ),
    .clk_i               ( clk_i                    ),

    .flush_i             ( imem_flush_o             ),

    .parcel_i            ( imem_parcel_i            ),
    .parcel_valid_i      ( imem_parcel_valid_i      ),
    .parcel_misaligned_i ( imem_parcel_misaligned_i ),
    .parcel_page_fault_i ( imem_parcel_page_fault_i ),
    .parcel_error_i      ( imem_parcel_error_i      ),

    .parcel_rd_i         ( {1'b0,parcel_queue_rd}          ),
    .parcel_q_o          ( {ext_parcel,active_parcel}            ),
    .parcel_misaligned_o ( parcel_misaligned        ),
    .parcel_page_fault_o ( parcel_page_fault        ),
    .parcel_error_o      ( parcel_error             ),

    .almost_empty_o      ( parcel_queue_empty       ),
    .almost_full_o       ( parcel_queue_full        ),
    .empty_o             (                          ),
    .full_o              (                          ) );
 

  //queue points to valid parcel
  assign parcel_valid = ~parcel_queue_empty;


  //instruction lenght decoding
  assign is_16bit_instruction = ~&active_parcel[1:0];
  assign is_32bit_instruction = ~&active_parcel[4:2] & &active_parcel[1:0];
//  assign is_48bit_instruction =   active_parcel[5:0] == 6'b011111;
//  assign is_64bit_instruction =   active_parcel[6:0] == 7'b0111111;


  //queue read signal
  assign parcel_queue_rd = {~pd_stall_i & parcel_valid & is_32bit_instruction,
                            ~pd_stall_i & parcel_valid & is_16bit_instruction};


  //assign parcel exception signals
  always_comb
  begin
      parcel_exceptions = 0;
      parcel_exceptions.misaligned_instruction   = parcel_valid & parcel_misaligned;
      parcel_exceptions.instruction_access_fault = parcel_valid & parcel_error;
      parcel_exceptions.instruction_page_fault   = parcel_valid & parcel_page_fault;

      parcel_exceptions.any                      = parcel_valid & (parcel_misaligned |
                                                                   parcel_error      |
                                                                   parcel_page_fault );
  end

  /*
   * Instruction Translation (RVC -> RV, op-fusion)
   */

  logic test;

  //                         f3  opcode(ADDI) opcode(AUIPC)
  parameter AUIPC_ADDI = 17'b000_00100_11_____01101_11;
//  always_comb
//    casex
//    endcase


  //RVC parcel
  assign rvc_parcel = active_parcel.instr[15:0];

  //Instruction Bubble
  assign rv_bubble = flushes | ~parcel_valid;


  //Instruction conversion
  always_comb
    if (has_rvc && is_16bit_instruction) //Convert RVC to RV
    casex ( {xlen128, xlen64, xlen32, decode_rvc_opcA(rvc_parcel)} )

      {3'b???,C_LWSP}    : rv_instr = rvc_parcel.CI.rd == 0
                                    ? ILLEGAL                                          //reserved
                                    : encode_I (LW,                                    //C.LWSP=lw rd,imm(x2)
                                                rvc_parcel.CI.rd,
                                                rsd_t'             ( 5'h2      ),      //x2
                                                rvc_decode_immCIWSP(rvc_parcel ),
                                                rvc_parcel.CI.size
                                               );


      {3'b??0,C_LDSP}    : rv_instr = rvc_parcel.CI.rd == 0
                                    ? ILLEGAL                                          //reserved
				    : encode_I (LD,                                    //C.LDSP=ld rd,imm(x2)
                                                rvc_parcel.CI.rd,
                                                rsd_t'             ( 5'h2      ),
                                                rvc_decode_immCIDSP(rvc_parcel ),      //x2
                                                rvc_parcel.CI.size
                                               );


    //{3'b1??,C_LQSP}
    //{3'b??1,C_FLWSP} F-only
    //{3'0b??,C_FLDSP} D-only

      {3'b???,C_SWSP}    : rv_instr = encode_S (SW,                                    //C.SWSP=sw rs2,imm(x2)
                                                rsd_t'              ( 5'h2      ),     //x2
                                                rvc_parcel.CSS.rs2,
                                                rvc_decode_immCSSWSP(rvc_parcel ),
                                                rvc_parcel.CSS.size
                                               );


      {3'b??0,C_SDSP}    : rv_instr = encode_S(SD,                                     //C.SDSP=sd rs2,imm(x2)
                                               rsd_t'              ( 5'h2      ),      //x2
                                               rvc_parcel.CSS.rs2,
                                               rvc_decode_immCSSDSP(rvc_parcel ),
                                               rvc_parcel.CSS.size
                                              );


    //{3'b1??,C_SQSP}
    //{3'b??1,C_FSWSP}  F-only
    //{3'b0??,C_FSDSP}  D-only

      {3'b???,C_LW}      : rv_instr = encode_I (LW,                                    //C.LW=lw rd',imm(rs1')
                                                rvc_rsdp2rsd     (rvc_parcel.CL.rd ),
                                                rvc_rsdp2rsd     (rvc_parcel.CL.rs1),
					        rvc_decode_immCLW(rvc_parcel       ),
                                                rvc_parcel.CL.size
                                               );


      {3'b??0,C_LD}      : rv_instr = encode_I (LD,                                    //C.LD=ld rd',imm(rs1')
                                                rvc_rsdp2rsd     (rvc_parcel.CL.rd ),
                                                rvc_rsdp2rsd     (rvc_parcel.CL.rs1),
					        rvc_decode_immCLD(rvc_parcel       ),
                                                rvc_parcel.CL.size
                                               );


    //{3'b1??,C_LQ}
    //{3'b??1,C_FLW} F-only
    //{3'b0??,C_FLD} D-only

      {3'b???,C_SW}      : rv_instr = encode_S (SW,                                    //C.SW=sw rs2',imm(rs1')
                                                rvc_rsdp2rsd     (rvc_parcel.CS.rs1),
                                                rvc_rsdp2rsd     (rvc_parcel.CS.rs2),
                                                rvc_decode_immCSW(rvc_parcel       ),
                                                rvc_parcel.CS.size
                                               );


      {3'b??0,C_SD}      : rv_instr = encode_S (SD,                                    //C.SD=sd rs2',imm(rs1')
                                                rvc_rsdp2rsd     (rvc_parcel.CS.rs1),
                                                rvc_rsdp2rsd     (rvc_parcel.CS.rs2),
                                                rvc_decode_immCSD(rvc_parcel       ),
					        rvc_parcel.CS.size
                                               );


    //{3'b1??,C_SQ}
    //{3'b??1,C_FSW} F-only
    //{3'b0??,C_FSD} D-only
 
      {3'b???,C_J}       : rv_instr = encode_UJ(JAL,                                   //C.J=jal x0,imm
                                                rsd_t'          ( 5'h0      ),         //x0
                                                rvc_decode_immCJ(rvc_parcel ),
                                                rvc_parcel.CJ.size
                                               );


      {3'b??1,C_JAL}     : rv_instr = encode_UJ(JAL,                                   //C.JAL=jal x1,imm
                                                rsd_t'          ( 5'h1      ),         //x1
                                                rvc_decode_immCJ(rvc_parcel ),
                                                rvc_parcel.CJ.size
                                               );

      //C.JR and C.MV
      {3'b???,C_JR}      : rv_instr = rvc_parcel.CR.rs2 != 0
				    ? encode_R(ADD,                                    //C.MV=add rd,x0,rs2
                                               rvc_parcel.CR.rd,                       //rd=x0-->hints
                                               rsd_t' (5'h0),                          //x0
                                               rvc_parcel.CR.rs2,
                                               rvc_parcel.CR.size
                                              )
                                    : rvc_parcel.CR.rd == 0
				    ? ILLEGAL                                          //reserved
                                    : encode_I (JALR,                                  //C.JR=jalr x0, 0(rd)
                                                rsd_t'(0),                             //x0
						rvc_parcel.CR.rd,
						immI_t'(0),                            //imm=0
                                                rvc_parcel.CR.size
                                               );


      //C.JALR and and C.ADD and C.EBREAK
      {3'b???,C_JALR}    : rv_instr = rvc_parcel.CR.rs2 != 0
                                    ? encode_R(ADD,                                    //C.ADD=add rd,rd,rs2
                                               rvc_parcel.CR.rd,                       //rd=x0-->hints
                                               rvc_parcel.CR.rd,
                                               rvc_parcel.CR.rs2,
                                               rvc_parcel.CR.size
                                              )
                                    : rvc_parcel.CR.rd != 0
                                    ? encode_I (JALR,                                  //C.JALR=jalr x1,0(rd)
                                                rsd_t'(5'h1),                          //x1
                                                rvc_parcel.CR.rd,
                                                immI_t'(0),                            //imm=0
                                                rvc_parcel.CJ.size
                                               )
                                    : EBREAK;                                          //C.EBREAK


      {3'b???,C_BEQZ}    : rv_instr = encode_SB(BEQ,                                   //C.BEQZ=beq rs1',x0,imm
                                                rvc_rsdp2rsd    ( rvc_parcel.CB.rs1 ),
                                                rsd_t'          ( 5'h0              ), //x0
                                                rvc_decode_immCB(rvc_parcel         ),
                                                rvc_parcel.CB.size
                                               );


      {3'b???,C_BNEZ}    : rv_instr = encode_SB(BNE,                                   //C.BNEZ=bne rs1',x0,imm
                                                rvc_rsdp2rsd    ( rvc_parcel.CB.rs1 ),
                                                rsd_t'          ( 5'h0              ), //x0
                                                rvc_decode_immCB(rvc_parcel         ),
                                                rvc_parcel.CB.size
                                               );


      {3'b???,C_LI}      : rv_instr = encode_I (ADDI,                                  //C.LI=addi rd,x0,imm
                                                rvc_parcel.CI.rd,
                                                rsd_t'          (5'h0       ),         //x0
                                                rvc_decode_immCI(rvc_parcel ),
                                                rvc_parcel.CI.size
                                               );

      //C.LUI and C.ADDI16SP
      {3'b???,C_ADDI16SP}: rv_instr = {rvc_parcel.CI.pos12,rvc_parcel.CI.pos6_2} == 0
                                    ? ILLEGAL                                          //reserved
                                    : rvc_parcel.CI.rd == 2
                                    ? encode_I (ADDI,                                  //C.ADDI16SP=addi x2,x2,imm
                                                rsd_t'           (5'h2       ),        //x2
                                                rsd_t'           (5'h2       ),        //x2
                                                rvc_decode_immCI4(rvc_parcel ),
                                                rvc_parcel.CI.size
                                               )
                                    : encode_U (LUI,                                   //C.LUI=lui rd,imm
                                                rvc_parcel.CI.rd,                      //rd=x0-->hints
                                                rvc_decode_immCI12(rvc_parcel ),
                                                rvc_parcel.CI.size
                                               );


      //C.NOP and C.ADDI
      {3'b???,C_ADDI}    : rv_instr = rvc_parcel.CI.rd == 0
                                    ? NOP                                              //NOP
                                    : encode_I (ADDI,                                  //C.ADDI=addi rd,rd,imm
                                                rvc_parcel.CI.rd,
                                                rvc_parcel.CI.rd,
                                                rvc_decode_immCI(rvc_parcel ),         //imm=0-->hint
                                                rvc_parcel.CI.size
                                               );


      {3'b??0,C_ADDIW}   : rv_instr = rvc_parcel.CI.rd == 0
                                    ? ILLEGAL                                          //reserved
                                    : encode_I (ADDIW,                                 //C.ADDIW=addiw rd,rd,imm
                                                rvc_parcel.CI.rd,
                                                rvc_parcel.CI.rd,
                                                rvc_decode_immCI(rvc_parcel ),
                                                rvc_parcel.CI.size
                                               );


      {3'b???,C_ADDI4SPN}: rv_instr = (rvc_parcel == 16'h0)                            //All zeros is defined illegal
                                    ? ILLEGAL                                          //illegal instruction
                                    : encode_I (ADDI,
                                                rvc_rsdp2rsd     (rvc_parcel.CIW.rd),
                                                rsd_t'           (5'h2             ),  //x2
                                                rvc_decode_immCIW(rvc_parcel       ),
                                                rvc_parcel.CIW.size
                                               );


      {3'b???,C_SLLI}    : rv_instr = encode_Ishift(SLLI,                              //C.SLLI=slli rd,rd,imm
                                               rvc_parcel.CI.rd,
                                               rvc_parcel.CI.rd,
                                               rvc_decode_immCI(rvc_parcel ),          //imm=0-->hint (RV32/64)
                                               rvc_parcel.CI.size
                                              );


      {3'b???,C_SRLI}    : rv_instr = encode_Ishift(SRLI,                              //C.SRLI=srli rd',rd',imm
                                               rvc_rsdp2rsd     (rvc_parcel.CIB.rd),
                                               rvc_rsdp2rsd     (rvc_parcel.CIB.rd),
                                               rvc_decode_immCIB(rvc_parcel       ),
                                               rvc_parcel.CIB.size
                                              );


      {3'b???,C_SRAI}    : rv_instr = encode_Ishift(SRAI,                              //C.SRAI=srai rd',rd',imm
                                               rvc_rsdp2rsd     (rvc_parcel.CIB.rd),
                                               rvc_rsdp2rsd     (rvc_parcel.CIB.rd),
                                               rvc_decode_immCIB(rvc_parcel       ),
                                               rvc_parcel.CIB.size
                                              );


      {3'b???,C_ANDI}    : rv_instr = encode_I(ANDI,                                   //C.ANDI=andi rd',rd',imm
                                               rvc_rsdp2rsd     ( rvc_parcel.CIB.rd ),
                                               rvc_rsdp2rsd     ( rvc_parcel.CIB.rd ),
                                               rvc_decode_immCIB(rvc_parcel         ),
                                               rvc_parcel.CIB.size
                                              );


      {3'b???,C_AND}     : rv_instr = encode_R(AND,                                    //C.AND=and rd',rd',rs2'
                                               rvc_rsdp2rsd (rvc_parcel.CR.rd ),
                                               rvc_rsdp2rsd (rvc_parcel.CR.rd ),
                                               rvc_rsdp2rsd (rvc_parcel.CR.rs2),
                                               rvc_parcel.CR.size
                                              );


      {3'b???,C_OR}      : rv_instr = encode_R(OR,                                     //C.OR=or rd',rd',rs2'
                                               rvc_rsdp2rsd (rvc_parcel.CR.rd ),
                                               rvc_rsdp2rsd (rvc_parcel.CR.rd ),
                                               rvc_rsdp2rsd (rvc_parcel.CR.rs2),
                                               rvc_parcel.CR.size
                                              );


      {3'b???,C_XOR}     : rv_instr = encode_R(XOR,                                    //C.XOR=xor rd',rd',rs2'
                                               rvc_rsdp2rsd (rvc_parcel.CR.rd ),
                                               rvc_rsdp2rsd (rvc_parcel.CR.rd ),
                                               rvc_rsdp2rsd (rvc_parcel.CR.rs2),
                                               rvc_parcel.CR.size
                                              );


      {3'b???,C_SUB}     : rv_instr = encode_R(SUB,                                    //C.SUB=sub rd',rd',rs2'
                                               rvc_rsdp2rsd (rvc_parcel.CR.rd ),
                                               rvc_rsdp2rsd (rvc_parcel.CR.rd ),
                                               rvc_rsdp2rsd (rvc_parcel.CR.rs2),
                                               rvc_parcel.CR.size
                                              );


      {3'b??0,C_ADDW}    : rv_instr = encode_R(ADDW,                                   //C.ADDW=addw rd',rd',rs2'
                                               rvc_rsdp2rsd (rvc_parcel.CR.rd ),
                                               rvc_rsdp2rsd (rvc_parcel.CR.rd ),
                                               rvc_rsdp2rsd (rvc_parcel.CR.rs2),
                                               rvc_parcel.CR.size
                                              );


      {3'b??0,C_SUBW}    : rv_instr = encode_R(SUBW,                                   //C.SUBS=subw rd',rd',rs2'
                                               rvc_rsdp2rsd (rvc_parcel.CR.rd ),
                                               rvc_rsdp2rsd (rvc_parcel.CR.rd ),
                                               rvc_rsdp2rsd (rvc_parcel.CR.rs2),
                                               rvc_parcel.CR.size
                                              );


      default            : rv_instr = ILLEGAL;
    endcase
    else    //32bit instructions
    case(active_parcel)
      WFI    : rv_instr = NOP;            //Implement WFI as a nop 
      default: rv_instr = active_parcel;
    endcase


  /*
   * IF Outputs
   */

  //Internal program counter
  always @(posedge clk_i, negedge rst_ni)
    if      (!rst_ni                         ) pc <= PC_INIT;
    else if ( st_flush_i                     ) pc <= st_nxt_pc_i;
    else if ( bu_flush_i || du_latch_nxt_pc_i) pc <= bu_nxt_pc_i;
    else if ( pd_latch_nxt_pc_i              ) pc <= pd_nxt_pc_i;
    else if (!pd_stall_i && !rv_bubble)
      if (is_16bit_instruction) pc <= pc +2;
      else                      pc <= pc +4;


  //Branch Predictor PC
  assign if_bp_pc_o = pc;



  //Program Counter
  always @(posedge clk_i, negedge rst_ni)
    if       (!rst_ni    ) if_pc_o <= PC_INIT;
    else  if (!pd_stall_i) if_pc_o <= pc;


  //Instruction
  always @(posedge clk_i, negedge rst_ni)
    if      (!rst_ni    ) if_insn_o.instr  <= NOP;
    else if (!pd_stall_i) if_insn_o.instr  <= rv_instr;


  always @(posedge clk_i, negedge rst_ni)
    if      (!rst_ni    ) if_insn_o.bubble <= 1'b1;
    else if ( pd_flush_i) if_insn_o.bubble <= 1'b1;
    else if ( du_stall_i) if_insn_o.bubble <= 1'b1;
    else if (!pd_stall_i)
      if (pd_latch_nxt_pc_i) if_insn_o.bubble <= 1'b1;
      else                   if_insn_o.bubble <= rv_bubble;

      
  //exceptions
  always @(posedge clk_i, negedge rst_ni)
    if      (!rst_ni    ) if_exceptions_o <= {$bits(if_exceptions_o){1'b0}};
    else if (!pd_stall_i) if_exceptions_o <= parcel_exceptions;
endmodule


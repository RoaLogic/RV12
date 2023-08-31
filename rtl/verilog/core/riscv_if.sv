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


module riscv_if
import riscv_opcodes_pkg::*;
import riscv_state_pkg::*;
#(
  parameter                           XLEN           = 32,
  parameter    [XLEN            -1:0] PC_INIT        = 'h200,
  parameter                           HAS_RVC        = 0,
  parameter                           BP_GLOBAL_BITS = 2,

  localparam                          PARCEL_SIZE    = 16
)
(
  input                               rst_ni,                   //Reset
  input                               clk_i,                    //Clock

  output logic [XLEN            -1:0] imem_adr_o,               //next Instruction Memory location
  output                              imem_req_o,               //request new parcel from BIU (cache/bus-interface)
  input                               imem_ack_i,               //acknowledge from BIU; send new imem_adr
  output                              imem_flush_o,             //flush instruction fetch BIU (cache/bus-interface)

  input        [XLEN            -1:0] imem_parcel_i,
  input        [XLEN/PARCEL_SIZE-1:0] imem_parcel_valid_i,
  input                               imem_parcel_misaligned_i,
  input                               imem_parcel_page_fault_i,
  input                               imem_parcel_error_i,

  input        [BP_GLOBAL_BITS  -1:0] bu_bp_history_i,          //Branch Predictor History
  output       [BP_GLOBAL_BITS  -1:0] if_predict_history_o,     //Predictor History to BP unit
  output reg   [BP_GLOBAL_BITS  -1:0] if_bp_history_o,          //Predictor History to PD
  output logic [XLEN            -1:0] if_predict_pc_o,          //Early program counters towards predictor
  output reg   [XLEN            -1:0] if_nxt_pc_o,              //Next Program Counter
                                      if_pc_o,                  //Program Counter
  output instruction_t                if_nxt_insn_o,
                                      if_insn_o,
  output interrupts_exceptions_t      if_exceptions_o,          //Interrupts and Exceptions
  input  interrupts_exceptions_t      pd_exceptions_i,
                                      id_exceptions_i,
                                      ex_exceptions_i,
                                      mem_exceptions_i,
                                      wb_exceptions_i,

  input        [XLEN            -1:0] pd_pc_i,
  input                               pd_stall_i,
                                      pd_flush_i,
	                              pd_latch_nxt_pc_i,

  input                               bu_flush_i,               //flush pipe & load new program counter
                                      st_flush_i,

                                      du_stall_i,
                                      du_we_pc_i,
                                      du_latch_nxt_pc_i,
	                              du_flush_i,
  input        [XLEN            -1:0] du_dato_i,

  input        [XLEN            -1:0] pd_nxt_pc_i,              //pre-decoder Next Program Counter
                                      bu_nxt_pc_i,              //Branch Unit Next Program Counter
                                      st_nxt_pc_i,              //State Next Program Counter

  input        [                 1:0] st_xlen_i                 //Current XLEN setting
);

  ////////////////////////////////////////////////////////////////
  //
  // Constants
  //

  //Instruction address mask
  localparam ADR_MASK = HAS_RVC != 0 ? {XLEN{1'b1}} << 1 : {XLEN{1'b1}} << 2;

  //HandLe up to 2 inflight instruction fetches
  localparam INFLIGHT_CNT   = 3;

  //Queue depth, in parcels
  localparam QUEUE_DEPTH    = 3*INFLIGHT_CNT * XLEN/PARCEL_SIZE;

  //Halt instruction fetches when FULL_THRESHOLD (in parcels) reached
  localparam FULL_THRESHOLD = QUEUE_DEPTH - (INFLIGHT_CNT+1)*XLEN/PARCEL_SIZE;


  ////////////////////////////////////////////////////////////////
  //
  // Functions
  //


  //Illegal RVC opcode
  function automatic logic rvc_is_illegal;
    input logic       xlen128, xlen64, xlen32;
    input rvc_instr_t parcel;

    //default value
    rvc_is_illegal = 0;

    casex ( {xlen128, xlen64, xlen32, decode_rvc_opcA(parcel)} )

      {3'b???,C_LWSP}    : rvc_is_illegal = parcel.CI.rd == 0
                                          ? 1'b1                                       //reserved ILLEGAL
                                          : 1'b0;

      {3'b??0,C_LDSP}    : rvc_is_illegal = parcel.CI.rd == 0
                                          ? 1'b1                                       //reserved ILLEGAL
                                          : 1'b0;

    //{3'b1??,C_LQSP}
    //{3'b??1,C_FLWSP} F-only
    //{3'0b??,C_FLDSP} D-only

      {3'b???,C_SWSP}    : rvc_is_illegal = 1'b0;

      {3'b??0,C_SDSP}    : rvc_is_illegal = 1'b0;

    //{3'b1??,C_SQSP}
    //{3'b??1,C_FSWSP}  F-only
    //{3'b0??,C_FSDSP}  D-only

      {3'b???,C_LW}      : rvc_is_illegal = 1'b0;

      {3'b??0,C_LD}      : rvc_is_illegal = 1'b0;

    //{3'b1??,C_LQ}
    //{3'b??1,C_FLW} F-only
    //{3'b0??,C_FLD} D-only

      {3'b???,C_SW}      : rvc_is_illegal = 1'b0;

      {3'b??0,C_SD}      : rvc_is_illegal = 1'b0;

    //{3'b1??,C_SQ}
    //{3'b??1,C_FSW} F-only
    //{3'b0??,C_FSD} D-only
 
      {3'b???,C_J}       : rvc_is_illegal = 1'b0;

      {3'b??1,C_JAL}     : rvc_is_illegal = 1'b0;

      //C.JR and C.MV
      {3'b???,C_JR}      : rvc_is_illegal = parcel.CR.rs2 != 0
				          ? 1'b0
                                          : parcel.CR.rd == 0
				          ? 1'b1
                                          : 1'b0;

      //C.JALR and and C.ADD and C.EBREAK
      {3'b???,C_JALR}    : rvc_is_illegal = 1'b0;

      {3'b???,C_BEQZ}    : rvc_is_illegal = 1'b0;

      {3'b???,C_BNEZ}    : rvc_is_illegal = 1'b0;

      {3'b???,C_LI}      : rvc_is_illegal = 1'b0;

      //C.LUI and C.ADDI16SP
      {3'b???,C_ADDI16SP}: rvc_is_illegal = {parcel.CI.pos12,parcel.CI.pos6_2} == 0
                                          ? 1'b1
                                          : 1'b0;

      //C.NOP and C.ADDI
      {3'b???,C_ADDI}    : rvc_is_illegal = 1'b0;

      {3'b??0,C_ADDIW}   : rvc_is_illegal = parcel.CI.rd == 0
                                          ? 1'b1
                                          : 1'b0;

      {3'b???,C_ADDI4SPN}: rvc_is_illegal = (parcel[12:5] == 5'h0)                     //nzuimm=0 is illegal
                                          ? 1'b1
                                          : 1'b0;

      {3'b???,C_SLLI}    : rvc_is_illegal = 1'b0;

      {3'b???,C_SRLI}    : rvc_is_illegal = 1'b0;

      {3'b???,C_SRAI}    : rvc_is_illegal = 1'b0;

      {3'b???,C_ANDI}    : rvc_is_illegal = 1'b0;
      {3'b???,C_AND}     : rvc_is_illegal = 1'b0;
      {3'b???,C_OR}      : rvc_is_illegal = 1'b0;
      {3'b???,C_XOR}     : rvc_is_illegal = 1'b0;
      {3'b???,C_SUB}     : rvc_is_illegal = 1'b0;
      {3'b??0,C_ADDW}    : rvc_is_illegal = 1'b0;
      {3'b??0,C_SUBW}    : rvc_is_illegal = 1'b0;

      default            : rvc_is_illegal = 1'b1;
    endcase
  endfunction: rvc_is_illegal;



  ////////////////////////////////////////////////////////////////
  //
  // Variables
  //

  logic                   has_rvc,
                          xlen32,
                          xlen64,
                          xlen128;

  logic                   flushes;
  logic                   ddu_we_pc,
                          du_we_pc_strb;


  //Parcel queue signals
  logic                   parcel_misaligned;
  logic                   parcel_page_fault;
  logic                   parcel_error;
  logic                   parcel_queue_full;
  logic                   parcel_queue_empty;

  logic [            1:0] parcel_queue_rd;

  logic                   parcel_valid;
  instr_t                 parcel34,            //parcels 3&4 from queue
                          parcel12,            //parcels 1&2 from queue
                          rv_instr;
  rvc_instr_t             rvc_parcel1,
                          rvc_parcel2;
  logic                   rvc_illegal;

  interrupts_exceptions_t parcel_exceptions;


  //Instruction length decoding
  logic                   is_16bit_instruction;
  logic                   is_32bit_instruction;
//  logic             is_48bit_instruction;
//  logic             is_64bit_instruction;



  ////////////////////////////////////////////////////////////////
  //
  // Module Body
  //
  assign has_rvc = (HAS_RVC != 0);


  //Create strobed PC write signal
  always @(posedge clk_i)
    ddu_we_pc <= du_we_pc_i;

  assign du_we_pc_strb = du_we_pc_i & ~ddu_we_pc;

  
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
  assign flushes = pd_flush_i | du_flush_i;
  assign xlen32  = st_xlen_i == RV32I;
  assign xlen64  = st_xlen_i == RV64I;
  assign xlen128 = st_xlen_i == RV128I;


  //request new parcel when parcel_queue not full and no flushes
  assign imem_req_o = ~parcel_queue_full & ~flushes & ~du_stall_i;


  //Instruction Memory Address generator
  //Branches can go to misaligned addresses, however next address is aligned
  always @(posedge clk_i, negedge rst_ni)
    if      (!rst_ni     ) imem_adr_o <= PC_INIT     & ADR_MASK;
    else if ( st_flush_i ) imem_adr_o <= st_nxt_pc_i & ADR_MASK;
    else if ( du_stall_i ) imem_adr_o <= if_nxt_pc_o & ADR_MASK;
    else if ( bu_flush_i ) imem_adr_o <= bu_nxt_pc_i & ADR_MASK;
    else
    begin
        if      ( pd_latch_nxt_pc_i        ) imem_adr_o <= pd_nxt_pc_i & ADR_MASK;
        else if ( imem_req_o && imem_ack_i ) imem_adr_o <= (imem_adr_o + (XLEN/8)) & ( {XLEN{1'b1}} << $clog2(XLEN/8) );
    end


  //Flush upper layer (memory BIU) 
  assign imem_flush_o = flushes | pd_latch_nxt_pc_i | du_latch_nxt_pc_i;

  
  /*
   * Received parcels are pushed into a parcel queue
   * There's extra room in the queue to adjust for any
   * pipeline stalls while parcels are in flight
   */
  riscv_parcel_queue #(
    .DEPTH                   ( QUEUE_DEPTH      ),
    .WR_PARCELS              ( XLEN/PARCEL_SIZE ),
    .RD_PARCELS              ( 4                ), //max 32bit instructions
    .ALMOST_EMPTY_THRESHOLD  ( 1                ), //must update for marco-fusion
    .ALMOST_FULL_THRESHOLD   ( FULL_THRESHOLD   )
  )
  parcel_queue_inst (
    .rst_ni              ( rst_ni                     ),
    .clk_i               ( clk_i                      ),

    .flush_i             ( imem_flush_o               ),

    .parcel_i            ( imem_parcel_i              ),
    .parcel_valid_i      ( imem_parcel_valid_i        ),
    .parcel_misaligned_i ( imem_parcel_misaligned_i   ),
    .parcel_page_fault_i ( imem_parcel_page_fault_i   ),
    .parcel_error_i      ( imem_parcel_error_i        ),

    .parcel_rd_i         ( {1'b0,parcel_queue_rd}     ),
    .parcel_q_o          ( {parcel34,parcel12} ),
    .parcel_misaligned_o ( parcel_misaligned          ),
    .parcel_page_fault_o ( parcel_page_fault          ),
    .parcel_error_o      ( parcel_error               ),

    //use almost_empty, because we (can) read more than 1 parcel (16bit) at a time
    .almost_empty_o      ( parcel_queue_empty         ),
    .almost_full_o       ( parcel_queue_full          ),
    .empty_o             (                            ),
    .full_o              (                            ) );
 

  //queue points to valid parcel
  assign parcel_valid = ~parcel_queue_empty;


  //instruction lenght decoding
  assign is_16bit_instruction = ~&parcel12[1:0];
  assign is_32bit_instruction = ~&parcel12[4:2] & &parcel12[1:0];
//  assign is_48bit_instruction =   parcel12[5:0] == 6'b011111;
//  assign is_64bit_instruction =   parcel12[6:0] == 7'b0111111;


  //queue read signal
  assign parcel_queue_rd = {~pd_stall_i & ~du_stall_i & parcel_valid & is_32bit_instruction,
                            ~pd_stall_i & ~du_stall_i & parcel_valid & is_16bit_instruction};


  //assign parcel exception signals
  always_comb
  begin
      parcel_exceptions = 0;
      parcel_exceptions.exceptions.misaligned_instruction   = parcel_valid & parcel_misaligned;
      parcel_exceptions.exceptions.instruction_access_fault = parcel_valid & parcel_error;
      parcel_exceptions.exceptions.instruction_page_fault   = parcel_valid & parcel_page_fault;

      parcel_exceptions.any                                 = |parcel_exceptions.exceptions;
  end

  /*
   * Instruction Translation (RVC -> RV, op-fusion)
   */

  //
  // Macro Fusion
  //

  //                         f3  opcode(ADDI) opcode(AUIPC)
  parameter AUIPC_ADDI = 17'b000_00100_11_____01101_11;
//  always_comb
//    casex
//    endcase


  //
  //RVC
  //
  assign rvc_parcel1 = parcel12.instr[15: 0];
  assign rvc_parcel2 = parcel12.instr[31:16];


  //Instruction Bubble
  assign if_nxt_insn_o.bubble = flushes | ~parcel_valid;


   //RVC Illegal Instruction
  always_comb
    if (!has_rvc || !is_16bit_instruction)
      rvc_illegal = 1'b0;
    else
      rvc_illegal = rvc_is_illegal(xlen128, xlen64, xlen32, rvc_parcel1);

/*	    
    casex ( {xlen128, xlen64, xlen32, decode_rvc_opcA(rvc_parcel1)} )

      {3'b???,C_LWSP}    : rvc_illegal = rvc_parcel1.CI.rd == 0
                                       ? 1'b1                                          //reserved ILLEGAL
                                       : 1'b0;

      {3'b??0,C_LDSP}    : rvc_illegal = rvc_parcel1.CI.rd == 0
                                       ? 1'b1                                          //reserved ILLEGAL
                                       : 1'b0;

    //{3'b1??,C_LQSP}
    //{3'b??1,C_FLWSP} F-only
    //{3'0b??,C_FLDSP} D-only

      {3'b???,C_SWSP}    : rvc_illegal = 1'b0;

      {3'b??0,C_SDSP}    : rvc_illegal = 1'b0;

    //{3'b1??,C_SQSP}
    //{3'b??1,C_FSWSP}  F-only
    //{3'b0??,C_FSDSP}  D-only

      {3'b???,C_LW}      : rvc_illegal = 1'b0;

      {3'b??0,C_LD}      : rvc_illegal = 1'b0;

    //{3'b1??,C_LQ}
    //{3'b??1,C_FLW} F-only
    //{3'b0??,C_FLD} D-only

      {3'b???,C_SW}      : rvc_illegal = 1'b0;

      {3'b??0,C_SD}      : rvc_illegal = 1'b0;

    //{3'b1??,C_SQ}
    //{3'b??1,C_FSW} F-only
    //{3'b0??,C_FSD} D-only
 
      {3'b???,C_J}       : rvc_illegal = 1'b0;

      {3'b??1,C_JAL}     : rvc_illegal = 1'b0;

      //C.JR and C.MV
      {3'b???,C_JR}      : rvc_illegal = rvc_parcel1.CR.rs2 != 0
				       ? 1'b0
                                       : rvc_parcel1.CR.rd == 0
				       ? 1'b1
                                       : 1'b0;

      //C.JALR and and C.ADD and C.EBREAK
      {3'b???,C_JALR}    : rvc_illegal = 1'b0;

      {3'b???,C_BEQZ}    : rvc_illegal = 1'b0;

      {3'b???,C_BNEZ}    : rvc_illegal = 1'b0;

      {3'b???,C_LI}      : rvc_illegal = 1'b0;

      //C.LUI and C.ADDI16SP
      {3'b???,C_ADDI16SP}: rvc_illegal = {rvc_parcel1.CI.pos12,rvc_parcel1.CI.pos6_2} == 0
                                       ? 1'b1
                                       : 1'b0;

      //C.NOP and C.ADDI
      {3'b???,C_ADDI}    : rvc_illegal = 1'b0;

      {3'b??0,C_ADDIW}   : rvc_illegal = rvc_parcel1.CI.rd == 0
                                       ? 1'b1
                                       : 1'b0;

      {3'b???,C_ADDI4SPN}: rvc_illegal = (rvc_parcel1 == 16'h0)                         //All zeros is defined illegal
                                       ? 1'b1
                                       : 1'b0;

      {3'b???,C_SLLI}    : rvc_illegal = 1'b0;

      {3'b???,C_SRLI}    : rvc_illegal = 1'b0;

      {3'b???,C_SRAI}    : rvc_illegal = 1'b0;

      {3'b???,C_ANDI}    : rvc_illegal = 1'b0;
      {3'b???,C_AND}     : rvc_illegal = 1'b0;
      {3'b???,C_OR}      : rvc_illegal = 1'b0;
      {3'b???,C_XOR}     : rvc_illegal = 1'b0;
      {3'b???,C_SUB}     : rvc_illegal = 1'b0;
      {3'b??0,C_ADDW}    : rvc_illegal = 1'b0;
      {3'b??0,C_SUBW}    : rvc_illegal = 1'b0;

      default            : rvc_illegal = 1'b1;
    endcase
*/


  //Instruction conversion RVC-->RV
  always_comb
    if (has_rvc && is_16bit_instruction) //Convert RVC to RV
    casex ( {xlen128, xlen64, xlen32, decode_rvc_opcA(rvc_parcel1)} )

      {3'b???,C_LWSP}    : rv_instr = rvc_parcel1.CI.rd == 0
                                    ? {{XLEN-16{1'b0}},rvc_parcel1}                    //reserved ILLEGAL
                                    : encode_I (LW,                                    //C.LWSP=lw rd,imm(x2)
                                                rvc_parcel1.CI.rd,
                                                rsd_t'             ( 5'h2      ),      //x2
                                                rvc_decode_immCIWSP(rvc_parcel1),
                                                rvc_parcel1.CI.size
                                               );


      {3'b??0,C_LDSP}    : rv_instr = rvc_parcel1.CI.rd == 0
                                    ? {{XLEN-16{1'b0}},rvc_parcel1}                    //reserved ILLEGAL
                                    : encode_I (LD,                                    //C.LDSP=ld rd,imm(x2)
                                                rvc_parcel1.CI.rd,
                                                rsd_t'             ( 5'h2      ),
                                                rvc_decode_immCIDSP(rvc_parcel1),      //x2
                                                rvc_parcel1.CI.size
                                               );


    //{3'b1??,C_LQSP}
    //{3'b??1,C_FLWSP} F-only
    //{3'0b??,C_FLDSP} D-only

      {3'b???,C_SWSP}    : rv_instr = encode_S (SW,                                    //C.SWSP=sw rs2,imm(x2)
                                                rsd_t'              ( 5'h2      ),     //x2
                                                rvc_parcel1.CSS.rs2,
                                                rvc_decode_immCSSWSP(rvc_parcel1),
                                                rvc_parcel1.CSS.size
                                               );


      {3'b??0,C_SDSP}    : rv_instr = encode_S(SD,                                     //C.SDSP=sd rs2,imm(x2)
                                               rsd_t'              ( 5'h2      ),      //x2
                                               rvc_parcel1.CSS.rs2,
                                               rvc_decode_immCSSDSP(rvc_parcel1),
                                               rvc_parcel1.CSS.size
                                              );


    //{3'b1??,C_SQSP}
    //{3'b??1,C_FSWSP}  F-only
    //{3'b0??,C_FSDSP}  D-only

      {3'b???,C_LW}      : rv_instr = encode_I (LW,                                    //C.LW=lw rd',imm(rs1')
                                                rvc_rsdp2rsd     (rvc_parcel1.CL.rd ),
                                                rvc_rsdp2rsd     (rvc_parcel1.CL.rs1),
					        rvc_decode_immCLW(rvc_parcel1       ),
                                                rvc_parcel1.CL.size
                                               );


      {3'b??0,C_LD}      : rv_instr = encode_I (LD,                                    //C.LD=ld rd',imm(rs1')
                                                rvc_rsdp2rsd     (rvc_parcel1.CL.rd ),
                                                rvc_rsdp2rsd     (rvc_parcel1.CL.rs1),
					        rvc_decode_immCLD(rvc_parcel1       ),
                                                rvc_parcel1.CL.size
                                               );


    //{3'b1??,C_LQ}
    //{3'b??1,C_FLW} F-only
    //{3'b0??,C_FLD} D-only

      {3'b???,C_SW}      : rv_instr = encode_S (SW,                                    //C.SW=sw rs2',imm(rs1')
                                                rvc_rsdp2rsd     (rvc_parcel1.CS.rs1),
                                                rvc_rsdp2rsd     (rvc_parcel1.CS.rs2),
                                                rvc_decode_immCSW(rvc_parcel1       ),
                                                rvc_parcel1.CS.size
                                               );


      {3'b??0,C_SD}      : rv_instr = encode_S (SD,                                    //C.SD=sd rs2',imm(rs1')
                                                rvc_rsdp2rsd     (rvc_parcel1.CS.rs1),
                                                rvc_rsdp2rsd     (rvc_parcel1.CS.rs2),
                                                rvc_decode_immCSD(rvc_parcel1       ),
					        rvc_parcel1.CS.size
                                               );


    //{3'b1??,C_SQ}
    //{3'b??1,C_FSW} F-only
    //{3'b0??,C_FSD} D-only
 
      {3'b???,C_J}       : rv_instr = encode_UJ(JAL,                                   //C.J=jal x0,imm
                                                rsd_t'          ( 5'h0      ),         //x0
                                                rvc_decode_immCJ(rvc_parcel1),
                                                rvc_parcel1.CJ.size
                                               );


      {3'b??1,C_JAL}     : rv_instr = encode_UJ(JAL,                                   //C.JAL=jal x1,imm
                                                rsd_t'          ( 5'h1      ),         //x1
                                                rvc_decode_immCJ(rvc_parcel1),
                                                rvc_parcel1.CJ.size
                                               );

      //C.JR and C.MV
      {3'b???,C_JR}      : rv_instr = rvc_parcel1.CR.rs2 != 0
				    ? encode_R(ADD,                                    //C.MV=add rd,x0,rs2
                                               rvc_parcel1.CR.rd,                      //rd=x0-->hints
                                               rsd_t' (5'h0),                          //x0
                                               rvc_parcel1.CR.rs2,
                                               rvc_parcel1.CR.size
                                              )
                                    : rvc_parcel1.CR.rd == 0
				    ? {{XLEN-16{1'b0}},rvc_parcel1}                    //reserved ILLEGAL
                                    : encode_I (JALR,                                  //C.JR=jalr x0, 0(rd)
                                                rsd_t'(0),                             //x0
						rvc_parcel1.CR.rd,
						immI_t'(0),                            //imm=0
                                                rvc_parcel1.CR.size
                                               );


      //C.JALR and and C.ADD and C.EBREAK
      {3'b???,C_JALR}    : rv_instr = rvc_parcel1.CR.rs2 != 0
                                    ? encode_R(ADD,                                    //C.ADD=add rd,rd,rs2
                                               rvc_parcel1.CR.rd,                      //rd=x0-->hints
                                               rvc_parcel1.CR.rd,
                                               rvc_parcel1.CR.rs2,
                                               rvc_parcel1.CR.size
                                              )
                                    : rvc_parcel1.CR.rd != 0
                                    ? encode_I (JALR,                                  //C.JALR=jalr x1,0(rd)
                                                rsd_t'(5'h1),                          //x1
                                                rvc_parcel1.CR.rd,
                                                immI_t'(0),                            //imm=0
                                                rvc_parcel1.CJ.size
                                               )
                                    : EBREAK;                                          //C.EBREAK


      {3'b???,C_BEQZ}    : rv_instr = encode_SB(BEQ,                                   //C.BEQZ=beq rs1',x0,imm
                                                rvc_rsdp2rsd    ( rvc_parcel1.CB.rs1),
                                                rsd_t'          ( 5'h0              ), //x0
                                                rvc_decode_immCB(rvc_parcel1        ),
                                                rvc_parcel1.CB.size
                                               );


      {3'b???,C_BNEZ}    : rv_instr = encode_SB(BNE,                                   //C.BNEZ=bne rs1',x0,imm
                                                rvc_rsdp2rsd    ( rvc_parcel1.CB.rs1),
                                                rsd_t'          ( 5'h0              ), //x0
                                                rvc_decode_immCB(rvc_parcel1        ),
                                                rvc_parcel1.CB.size
                                               );


      {3'b???,C_LI}      : rv_instr = encode_I (ADDI,                                  //C.LI=addi rd,x0,imm
                                                rvc_parcel1.CI.rd,
                                                rsd_t'          (5'h0        ),        //x0
                                                rvc_decode_immCI(rvc_parcel1 ),
                                                rvc_parcel1.CI.size
                                               );

      //C.LUI and C.ADDI16SP
      {3'b???,C_ADDI16SP}: rv_instr = {rvc_parcel1.CI.pos12,rvc_parcel1.CI.pos6_2} == 0
                                    ? {{XLEN-16{1'b0}},rvc_parcel1}                    //reserved ILLEGAL
                                    : rvc_parcel1.CI.rd == 2
                                    ? encode_I (ADDI,                                  //C.ADDI16SP=addi x2,x2,imm
                                                rsd_t'           (5'h2        ),       //x2
                                                rsd_t'           (5'h2        ),       //x2
                                                rvc_decode_immCI4(rvc_parcel1 ),
                                                rvc_parcel1.CI.size
                                               )
                                    : encode_U (LUI,                                   //C.LUI=lui rd,imm
                                                rvc_parcel1.CI.rd,                     //rd=x0-->hints
                                                rvc_decode_immCI12(rvc_parcel1),
                                                rvc_parcel1.CI.size
                                               );


      //C.NOP and C.ADDI
      {3'b???,C_ADDI}    : rv_instr = rvc_parcel1.CI.rd == 0
                                    ? NOP                                              //NOP
                                    : encode_I (ADDI,                                  //C.ADDI=addi rd,rd,imm
                                                rvc_parcel1.CI.rd,
                                                rvc_parcel1.CI.rd,
                                                rvc_decode_immCI(rvc_parcel1  ),       //imm=0-->hint
                                                rvc_parcel1.CI.size
                                               );


      {3'b??0,C_ADDIW}   : rv_instr = rvc_parcel1.CI.rd == 0
                                    ? {{XLEN-16{1'b0}},rvc_parcel1}                    //reserved ILLEGAL
                                    : encode_I (ADDIW,                                 //C.ADDIW=addiw rd,rd,imm
                                                rvc_parcel1.CI.rd,
                                                rvc_parcel1.CI.rd,
                                                rvc_decode_immCI(rvc_parcel1 ),
                                                rvc_parcel1.CI.size
                                               );


      {3'b???,C_ADDI4SPN}: rv_instr = (rvc_parcel1 == 16'h0)                           //All zeros is defined illegal
                                    ? {{XLEN-16{1'b0}},rvc_parcel1}                    //illegal instruction (definition)
                                    : encode_I (ADDI,
                                                rvc_rsdp2rsd     (rvc_parcel1.CIW.rd),
                                                rsd_t'           (5'h2             ),  //x2
                                                rvc_decode_immCIW(rvc_parcel1       ),
                                                rvc_parcel1.CIW.size
                                               );


      {3'b???,C_SLLI}    : rv_instr = encode_Ishift(SLLI,                              //C.SLLI=slli rd,rd,imm
                                               rvc_parcel1.CI.rd,
                                               rvc_parcel1.CI.rd,
                                               rvc_decode_immCI(rvc_parcel1 ),         //imm=0-->hint (RV32/64)
                                               rvc_parcel1.CI.size
                                              );


      {3'b???,C_SRLI}    : rv_instr = encode_Ishift(SRLI,                              //C.SRLI=srli rd',rd',imm
                                               rvc_rsdp2rsd     (rvc_parcel1.CIB.rd),
                                               rvc_rsdp2rsd     (rvc_parcel1.CIB.rd),
                                               rvc_decode_immCIB(rvc_parcel1       ),
                                               rvc_parcel1.CIB.size
                                              );


      {3'b???,C_SRAI}    : rv_instr = encode_Ishift(SRAI,                              //C.SRAI=srai rd',rd',imm
                                               rvc_rsdp2rsd     (rvc_parcel1.CIB.rd),
                                               rvc_rsdp2rsd     (rvc_parcel1.CIB.rd),
                                               rvc_decode_immCIB(rvc_parcel1       ),
                                               rvc_parcel1.CIB.size
                                              );


      {3'b???,C_ANDI}    : rv_instr = encode_I(ANDI,                                   //C.ANDI=andi rd',rd',imm
                                               rvc_rsdp2rsd     (rvc_parcel1.CIB.rd ),
                                               rvc_rsdp2rsd     (rvc_parcel1.CIB.rd ),
                                               rvc_decode_immCIB(rvc_parcel1        ),
                                               rvc_parcel1.CIB.size
                                              );


      {3'b???,C_AND}     : rv_instr = encode_R(AND,                                    //C.AND=and rd',rd',rs2'
                                               rvc_rsdp2rsd (rvc_parcel1.CR.rd ),
                                               rvc_rsdp2rsd (rvc_parcel1.CR.rd ),
                                               rvc_rsdp2rsd (rvc_parcel1.CR.rs2),
                                               rvc_parcel1.CR.size
                                              );


      {3'b???,C_OR}      : rv_instr = encode_R(OR,                                     //C.OR=or rd',rd',rs2'
                                               rvc_rsdp2rsd (rvc_parcel1.CR.rd ),
                                               rvc_rsdp2rsd (rvc_parcel1.CR.rd ),
                                               rvc_rsdp2rsd (rvc_parcel1.CR.rs2),
                                               rvc_parcel1.CR.size
                                              );


      {3'b???,C_XOR}     : rv_instr = encode_R(XOR,                                    //C.XOR=xor rd',rd',rs2'
                                               rvc_rsdp2rsd (rvc_parcel1.CR.rd ),
                                               rvc_rsdp2rsd (rvc_parcel1.CR.rd ),
                                               rvc_rsdp2rsd (rvc_parcel1.CR.rs2),
                                               rvc_parcel1.CR.size
                                              );


      {3'b???,C_SUB}     : rv_instr = encode_R(SUB,                                    //C.SUB=sub rd',rd',rs2'
                                               rvc_rsdp2rsd (rvc_parcel1.CR.rd ),
                                               rvc_rsdp2rsd (rvc_parcel1.CR.rd ),
                                               rvc_rsdp2rsd (rvc_parcel1.CR.rs2),
                                               rvc_parcel1.CR.size
                                              );


      {3'b??0,C_ADDW}    : rv_instr = encode_R(ADDW,                                   //C.ADDW=addw rd',rd',rs2'
                                               rvc_rsdp2rsd (rvc_parcel1.CR.rd ),
                                               rvc_rsdp2rsd (rvc_parcel1.CR.rd ),
                                               rvc_rsdp2rsd (rvc_parcel1.CR.rs2),
                                               rvc_parcel1.CR.size
                                              );


      {3'b??0,C_SUBW}    : rv_instr = encode_R(SUBW,                                   //C.SUBS=subw rd',rd',rs2'
                                               rvc_rsdp2rsd (rvc_parcel1.CR.rd ),
                                               rvc_rsdp2rsd (rvc_parcel1.CR.rd ),
                                               rvc_rsdp2rsd (rvc_parcel1.CR.rs2),
                                               rvc_parcel1.CR.size
                                              );


      default            : rv_instr = {{XLEN-16{1'b0}},rvc_parcel1};                    //ILLEGAL
    endcase
    else    //32bit instructions
    case(parcel12)
      WFI    : rv_instr = NOP;            //Implement WFI as a nop 
      default: rv_instr = parcel12;
    endcase


    assign if_nxt_insn_o.instr = rv_instr;


  /*
   * IF Outputs
   */


  //Next Program Counter

  //Combinatorial to Predictor predict_pc is registered by the memory address
  //register. Then we can use registered output to reduce critical path
  always_comb
    if      ( st_flush_i        ) if_predict_pc_o = st_nxt_pc_i    & ADR_MASK;
    else if ( du_we_pc_strb     ) if_predict_pc_o = du_dato_i      & ADR_MASK; 
    else if ( bu_flush_i        ) if_predict_pc_o = bu_nxt_pc_i    & ADR_MASK;
    else if ( pd_latch_nxt_pc_i ) if_predict_pc_o = pd_nxt_pc_i    & ADR_MASK; //pd_flush absolutely breaks the CPU here
    else if (!pd_stall_i           &&
	     !if_nxt_insn_o.bubble &&
	     !du_stall_i)
      if (is_16bit_instruction)   if_predict_pc_o = if_nxt_pc_o +2 & ADR_MASK;
      else                        if_predict_pc_o = if_nxt_pc_o +4 & ADR_MASK;
    else                          if_predict_pc_o = if_nxt_pc_o    & ADR_MASK;


  //BP history aligned with predict PC
  assign if_predict_history_o = bu_bp_history_i;


  always @(posedge clk_i, negedge rst_ni)
    if (!rst_ni ) if_nxt_pc_o <= PC_INIT;
    else          if_nxt_pc_o <= if_predict_pc_o;


    
  //Current Program Counter
  always @(posedge clk_i, negedge rst_ni)
    if      (!rst_ni        ) if_pc_o <= PC_INIT;
    else if ( du_we_pc_strb ) if_pc_o <= du_dato_i;
    else if (!pd_stall_i &&
             !du_stall_i    ) if_pc_o <= if_nxt_pc_o;


  //Instruction
  always @(posedge clk_i, negedge rst_ni)
    if      (!rst_ni    ) if_insn_o.instr  <= NOP;
    else if (!pd_stall_i) if_insn_o.instr  <= if_nxt_insn_o.instr;


  always @(posedge clk_i, negedge rst_ni)
    if      (!rst_ni               ) if_insn_o.bubble <= 1'b1;
    else if ( pd_flush_i           ) if_insn_o.bubble <= 1'b1;
    else if ( du_stall_i           ) if_insn_o.bubble <= 1'b1;
    else if ( pd_exceptions_i.any  ||
	      id_exceptions_i.any  ||
	      ex_exceptions_i.any  ||
	      mem_exceptions_i.any ||
	      wb_exceptions_i.any  ) if_insn_o.bubble <= 1'b1;
    else if (!pd_stall_i)
      if (pd_latch_nxt_pc_i)         if_insn_o.bubble <= 1'b1;
      else                           if_insn_o.bubble <= if_nxt_insn_o.bubble;


  always @(posedge clk_i, negedge rst_ni)
    if (!rst_ni) if_insn_o.dbg <= 1'b0;
    else         if_insn_o.dbg <= du_stall_i;


  //exceptions
  always @(posedge clk_i, negedge rst_ni)
    if      (!rst_ni    ) if_exceptions_o <= {$bits(if_exceptions_o){1'b0}};
    else if ( pd_flush_i) if_exceptions_o <= {$bits(if_exceptions_o){1'b0}};
    else if (!pd_stall_i)
    begin
        if_exceptions_o                                <= parcel_exceptions;
	if_exceptions_o.exceptions.illegal_instruction <= rvc_illegal & ~parcel_queue_empty;
    end


  //BP history
  always @(posedge clk_i)
    if (!pd_stall_i) if_bp_history_o <= bu_bp_history_i;
endmodule


/////////////////////////////////////////////////////////////////
//                                                             //
//    ???????  ???????  ??????                                 //
//    ?????????????????????????                                //
//    ???????????   ???????????                                //
//    ???????????   ???????????                                //
//    ???  ???????????????  ???                                //
//    ???  ??? ??????? ???  ???                                //
//          ???      ???????  ??????? ??? ???????              //
//          ???     ????????????????? ???????????              //
//          ???     ???   ??????  ??????????                   //
//          ???     ???   ??????   ?????????                   //
//          ?????????????????????????????????????              //
//          ???????? ???????  ??????? ??? ???????              //
//                                                             //
//    RISC-V                                                   //
//    Pre-decode                                               //
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

// Module parameters
module riscv_pd #(
  parameter            XLEN           = 32,
  parameter [XLEN-1:0] PC_INIT        = 'h200,
  parameter            INSTR_SIZE     = 32,
  parameter            PARCEL_SIZE    = 32,
  parameter            EXCEPTION_SIZE = 12,
  parameter            HAS_BPU        = 0,
  parameter            HAS_RVC        = 0
)

// Input and outputs
(
  input                           rstn,          //Reset
  input                           clk,           //Clock
  input                           id_stall,	 //Stall input instruction decode

  input      [               1:0] bp_bp_predict, //Branch Prediction bits

  // Flush inputs from down the pipe
  input                           bu_flush,      //flush pipe & load new program counter
                                  st_flush,
                                  du_flush,      //flush pipe after debug exit

  // Inputs from instruction fetch
  input reg [XLEN           -1:0] if_pc,	  //Program counter for the instruction to id 
  input reg [INSTR_SIZE     -1:0] if_instr,	  //Instruction output to instruction decode
  input reg                       if_bubble, 	  //Insert bublle in the pipe (NOP instruction)
  input reg [EXCEPTION_SIZE -1:0] if_exception,   //Exception bit for down the pipe
  input reg                       if_valid_instr, //Check which part of incoming data is valid, for use with 16bit instructions
  
  // Type of instruction
  input                           is_16bit_instruction,
  input                           is_32bit_instruction,

  // Branch prediction outputs
  output [XLEN              -1:0] branch_pc,
  output                          branch_taken,

  //outputs for instruction decode
  output reg [XLEN           -1:0] pd_pc,	 //Program counter for the instruction to id 
  output reg [INSTR_SIZE     -1:0] pd_instr,	 //Instruction output to instruction decode
  output reg                       pd_bubble, 	 //Insert bublle in the pipe (NOP instruction)
  output reg [                1:0] pd_bp_predict,//Branch predict bits for the pipe
  output reg [EXCEPTION_SIZE -1:0] pd_exception  //Exception bit for down the pipe
);


  //////////////////////////////////////////////////////////////////////////
  //  
  // Variables

  logic                            flushes;      //OR all flush signals

  logic                            is_rv64;

  logic [INSTR_SIZE          -1:0] decoded_instr;

  logic [XLEN                -1:0] immB,
                                   immJ;

  logic [                     6:2] opcode;

  logic	                           pd_branch_taken;
  logic [XLEN                -1:0] pd_branch_pc;

  // Struct for decoding rvc instructions
  typedef struct {
    logic [             1:0] op;
    logic [             2:0] funct3;			     
    logic [             3:0] funct4;
    logic [             4:0] funct,
                             rd,
                             rs2,
                             crd,
                             crs2,
                             crs1,
                             immL,
                             immS;
    logic [             5:0] immI,
                             immSS;
    logic [             7:0] immIW,
                             immB;
    logic [	       19:0] jump;

  }c_instruction_format;

  c_instruction_format rvc;  
  
  /////////////////////////////////////////////////////////////////////////
  //
  // Module body

  import riscv_pkg::*;		
  import riscv_state_pkg::*;

  //All flush signals combined
  assign flushes = bu_flush | st_flush | du_flush;

  // Decoding rvc instructions according to their instruction formats
  // function decoding 
  assign rvc.op     =   if_instr [1:0];
  assign rvc.funct3 =   if_instr [15:13];
  assign rvc.funct  =  {if_instr [12:10], if_instr [6:5]};
  assign rvc.funct4 =   if_instr [15:12];
	
  // 16 bit immediate parameters
  assign rvc.immSS = if_instr [12: 7];
  assign rvc.immIW = if_instr [12: 5];
  assign rvc.immI  = {if_instr[12]   , if_instr[6:2]};
  assign rvc.immL  = {if_instr[12:10], if_instr[6:5]};
  assign rvc.immS  = {if_instr[12:10], if_instr[6:5]};
  assign rvc.immB  = {if_instr[12:10], if_instr[6:2]};
  assign rvc.jump  = {if_instr[12]   , if_instr[8],  if_instr[10:9], if_instr[6], if_instr[7], if_instr[2], if_instr[11], if_instr[5:3], {9 {if_instr[12]}}};

  // 16 bit register parameter
  // C extensions uses favourite register x8-x15, because of the encoding some only encode the last 3 bits of the register set
  // therefore the register will be added with 8 to transform to the given registers off x8-x15
  assign rvc.rd	  = if_instr [11: 7];
  assign rvc.rs2  = if_instr [ 6: 2];
  assign rvc.crd  = {2'b01,  if_instr [ 4: 2]}; 
  assign rvc.crs2 = {2'b01,  if_instr [ 4: 2]};
  assign rvc.crs1 = {2'b01,  if_instr [ 9: 7]};

  // check if processor is 64bit
  assign is_rv64  = (XLEN == 64);


  // Decoding the rvc instructions to normal integer instructions
  always_comb
    casex(if_instr)
      	WFI    	  :  decoded_instr<= INSTR_NOP;                                 //Implement WFI as a nop
        CILLEGAL  :  decoded_instr<= -1;
        CADDI4SPN :  decoded_instr<= {2'b00,rvc.immIW[5:2], rvc.immIW[7:6], rvc.immIW[0], rvc.immIW[1], 2'b00, SP, rvc.funct3, rvc.crd, OPC_OP_IMM, rvc.op};
        CLOADDQ	  :  decoded_instr<= -1; 														      // Double instruction and rv128 instructions not implemented
        CLW       :  decoded_instr<=           {5'b00000, rvc.immL[0], rvc.immL[4:2], rvc.immL[1], 2'b00 , rvc.crs1, 3'b010, rvc.crd, OPC_LOAD, rvc.op};
        CLOADFD	  :  decoded_instr<= is_rv64 ? {4'b0000 , rvc.immL[0], rvc.immL[4:2], rvc.immL[1], 3'b000, rvc.crs1, 3'b011, rvc.crd, OPC_LOAD, rvc.op}: -1; // C.LW when 64bit processor, floating point instruction not implemented
        CSTOREDQ  :  decoded_instr<= -1; 														     // Double instruction and rv128 instructions not implemented
        CSW       :  decoded_instr<=           {5'b00000, rvc.immS[0]  , rvc.immS[4], rvc.crs2, rvc.crs1, 3'b010, rvc.immS[3:2], rvc.immS[1], 2'b00, OPC_STORE, rvc.op};
        CSTOREFD  :  decoded_instr<= is_rv64 ? {4'b0000 , rvc.immS[1:0], rvc.immS[4], rvc.crs2, rvc.crs1, 3'b011, rvc.immS[3:2], 3'b000,             OPC_STORE, rvc.op}: -1; // Floating point instruction not implemented

        CADDI     :  decoded_instr<=              {{7 {rvc.immI[5]}}, rvc.immI[4:0], rvc.rd, 3'b000, rvc.rd, OPC_OP_IMM,   rvc.op};
        CJALADDIW :  decoded_instr<= is_rv64    ? {{7 {rvc.immI[5]}}, rvc.immI[4:0], rvc.rd, 3'b000, rvc.rd, OPC_OP_IMM32, rvc.op}: 
                                                  {rvc.jump, X1, OPC_JAL, rvc.op}; //c.jal
        CLI       :  decoded_instr<=              {{7 {rvc.immI[5]}}, rvc.immI[4:0], X0,     3'b000, rvc.rd, OPC_OP_IMM,   rvc.op};
        CLUIADDI16:  case(rvc.rd)
                        X0      : decoded_instr<= -1;	
                        SP      : decoded_instr<= {{  3{rvc.immI[5]}}, rvc.immI[2:1], rvc.immI[3], rvc.immI[0], rvc.immI[4], 4'b0000, SP, 3'b000, SP, OPC_OP_IMM, rvc.op}; //c.addi16sp
                        default : decoded_instr<= {{ 16{rvc.immI[5]}}, rvc.immI[4:0], rvc.rd, OPC_LUI, rvc.op}; // c.lui
                     endcase
        CALU	  :  casex(rvc.funct)
                        CSRLI   : decoded_instr<=           { 6'b000000, rvc.immB[7], rvc.immB[4:0], rvc.crs1, 3'b101, rvc.crs1, OPC_OP_IMM, rvc.op}; 
                        CSRAI   : decoded_instr<=           { 6'b010000, rvc.immB[7], rvc.immB[4:0], rvc.crs1, 3'b101, rvc.crs1, OPC_OP_IMM, rvc.op};
                        CANDI   : decoded_instr<=           {{7 {rvc.immB[7]}},       rvc.immB[4:0], rvc.crs1, 3'b111, rvc.crs1, OPC_OP_IMM, rvc.op}; 
                        CSUB    : decoded_instr<=           { 7'b0100000, rvc.crs2, rvc.crs1, 3'b000, rvc.crs1, OPC_OP, rvc.op};
                        CXOR    : decoded_instr<=           { 7'b0000000, rvc.crs2, rvc.crs1, 3'b100, rvc.crs1, OPC_OP, rvc.op};
                        COR     : decoded_instr<=           { 7'b0000000, rvc.crs2, rvc.crs1, 3'b110, rvc.crs1, OPC_OP, rvc.op};
                        CAND    : decoded_instr<=           { 7'b0000000, rvc.crs2, rvc.crs1, 3'b111, rvc.crs1, OPC_OP, rvc.op};
                        CSUBW   : decoded_instr<= is_rv64 ? { 7'b0100000, rvc.crs2, rvc.crs1, 3'b000, rvc.crs1, OPC_OP32, rvc.op} : -1;
                        CADDW   : decoded_instr<= is_rv64 ? { 7'b0000000, rvc.crs2, rvc.crs1, 3'b000, rvc.crs1, OPC_OP32, rvc.op} : -1;
                        default : decoded_instr<= -1;
                     endcase
        CJ	  :  decoded_instr<= {rvc.jump, X0, OPC_JAL, rvc.op};
        CBEQZ	  :  decoded_instr<= {{ 4{rvc.immB[7]}}, rvc.immB[4:3], rvc.immB[0], X0, rvc.crs1, 3'b000, rvc.immB[6:5], rvc.immB[2:1], rvc.immB[7], OPC_BRANCH, rvc.op};
        CBNEZ	  :  decoded_instr<= {{ 4{rvc.immB[7]}}, rvc.immB[4:3], rvc.immB[0], X0, rvc.crs1, 3'b001, rvc.immB[6:5], rvc.immB[2:1], rvc.immB[7], OPC_BRANCH, rvc.op};

        CSLLI	  :  decoded_instr<=           {6'b000000, rvc.immI[5], rvc.immI[4:0], rvc.rd, 3'b001, rvc.rd, OPC_OP_IMM, rvc.op};
        CSPLDQ 	  :  decoded_instr<= -1; // Floating point instruction, not implemented
        CLWSP	  :  decoded_instr<=           {2'b00, rvc.immI[1:0], rvc.immI[5], rvc.immI[4:2], 2'b00 , SP, 3'b010, rvc.rd, OPC_LOAD, rvc.op};
        CSPLFD	  :  decoded_instr<= is_rv64 ? {1'b0 , rvc.immI[2:0], rvc.immI[5], rvc.immI[4:3], 3'b000, SP, 3'b011, rvc.rd, OPC_LOAD, rvc.op} : -1; // C.LDSP when RV64bit processor, floating point instruction not implemented
        CSYSTEM	  :  case(rvc.funct4)
                        4'b1000	: if       ( rvc.rs2 == 5'b00000) decoded_instr<= {12'b000000000000, rvc.rd,  3'b000, X0,             OPC_JALR,   rvc.op}; // c.jr
                                  else 			  	  decoded_instr<= { 6'b000000, 	     rvc.rs2, X0,     3'b000, rvc.rd, OPC_OP,     rvc.op}; // c.mv
                        4'b1001	: if       ( rvc.rd  == 5'b00000) decoded_instr<= {12'b000000000001, X0,      3'b000, X0,             OPC_SYSTEM, rvc.op}; // c.ebreak
                                  else if  ( rvc.rs2 == 5'b00000) decoded_instr<= {12'b000000000000, rvc.rd,  3'b000, X1,             OPC_JALR,   rvc.op}; // c.jalr
                                  else                            decoded_instr<= { 6'b000000,       rvc.rs2, rvc.rd, 3'b000, rvc.rd, OPC_OP,     rvc.op}; // c.add
                        default	: decoded_instr<= -1;
                     endcase
        CSPSDQ	  :  decoded_instr<= -1; // floating point instructie
        CSWSP	  :  decoded_instr<=           {4'b0000, rvc.immSS[1:0], rvc.immSS[5], rvc.rs2, SP, 3'b010, rvc.immSS[4:2], 2'b00 , OPC_STORE, rvc.op};
        CSPSFD	  :  decoded_instr<= is_rv64 ? {3'b000 , rvc.immSS[2:0], rvc.immSS[5], rvc.rs2, SP, 3'b011, rvc.immSS[4:3], 3'b000, OPC_STORE, rvc.op }: -1; //C.SDSP when 64bit processor, floating point instruction not implemented
  
        default	:  if (is_32bit_instruction)  decoded_instr <= if_instr;	 		
                   else                       decoded_instr <= -1;             //Illegal
    endcase

  // Program counter 
  always @(posedge clk, negedge rstn)
    if	        (!rstn      ) pd_pc <= PC_INIT;
    else if     (!id_stall  ) pd_pc <= if_pc;

  // Assign decoded instruction to instruction decode
  always @(posedge clk, negedge rstn)
    if	    (!rstn      )  pd_instr <= INSTR_NOP;
    else if ( flushes 	)  pd_instr <= INSTR_NOP;
    else if (!id_stall 	)  pd_instr <= decoded_instr;

  // Instruction bubble to instruction decode bubble
  always @(posedge clk, negedge rstn)
    if      (!rstn      )  pd_bubble <= 1'b1;
    else if ( flushes 	)  pd_bubble <= 1'b1;
    else if (!id_stall  )  pd_bubble <= if_bubble;

  // Branches and jumps
  assign immB = {{XLEN-12{decoded_instr[31]}},decoded_instr[ 7],decoded_instr[30:25],decoded_instr[11: 8],1'b0};
  assign immJ = {{XLEN-20{decoded_instr[31]}},decoded_instr[19:12],decoded_instr[20],decoded_instr[30:25],decoded_instr[24:21],1'b0};

  assign opcode       = decoded_instr[6:2];
  assign branch_taken = pd_branch_taken; 	
  assign branch_pc    = pd_branch_pc;		

  //branch and jump prediction
  always_comb
    (* synthesis,parallel_case *)
    casex ({if_bubble,opcode})
      {1'b0,OPC_JAL   } : begin
                               pd_branch_taken = 1'b1;
                               pd_branch_pc    = if_pc + immJ;
                          end
      {1'b0,OPC_BRANCH} : begin
                                // if CPU has branch predict unit, then use it;s prediction
                                // otherwise assume backwards jumps taken, forward jumps not taken
                                pd_branch_taken = HAS_BPU ? bp_bp_predict[1] : immB[31];
                                pd_branch_pc = if_pc + immB;
                          end
      default           : begin
                                pd_branch_taken = 1'b0;
                                pd_branch_pc    = 'hx;
                          end
    endcase

  // pre decode branch prediction
  always@(posedge clk, negedge rstn)
    if     (!rstn       ) pd_bp_predict <= 2'b00;
    else if(!id_stall   ) pd_bp_predict <= (HAS_BPU) ? bp_bp_predict : {branch_taken,1'b0};

  // pre decode exception
  always @(posedge clk, negedge rstn)
    if      (!rstn     ) pd_exception <= 'h0;
    else if ( flushes  ) pd_exception <= 'h0;
    else if (!id_stall ) pd_exception <= if_exception;

endmodule	



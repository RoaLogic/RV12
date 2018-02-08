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

// Module parameters
module riscv_if #(
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

  // Inputs from instruction cache/bus
  input                           if_stall_nxt_pc,
  input      [PARCEL_SIZE   -1:0] if_parcel,
  input      [XLEN          -1:0] if_parcel_pc,
  input      [               1:0] if_parcel_valid,
  input                           if_parcel_misaligned, 
  input                           if_parcel_page_fault,

  // Flush input from down the pipe
  input                           bu_flush,      
                                  st_flush,
                                  du_flush, 
  // Program counter changes     
  input      [XLEN          -1:0] bu_nxt_pc,     //Branch Unit Next Program Counter
                                  st_nxt_pc,     //State Next Program Counter
                                  id_pc,         //ID next program counter (used by debug unit)

  // Outputs for instruction cache/bus 
  output reg [XLEN          -1:0] if_nxt_pc,	 //Program counter to get the next instruction
  output                          if_stall, 	 //Stall instruction fetch BIU (cache/bus-interface)
  output                          if_flush,      //Flush instruction fetch BIU (cache/bus-interface)
    
  // Outputs for pre decode
  output reg [XLEN           -1:0] if_pc,	   //Program counter for the instruction to id 
  output reg [INSTR_SIZE     -1:0] if_instr,	   //Instruction output to instruction decode
  output reg                       if_bubble, 	   //Insert bublle in the pipe (NOP instruction)
  output reg [EXCEPTION_SIZE -1:0] if_exception,   //Exception bit for down the pipe
  output reg                       if_valid_instr,

  // Instruction size
  output 			   is_16bit_instruction,
  output 			   is_32bit_instruction,
//output			   is_48bit_instruction,
//output			   is_64bit_instruction,


  // Inputs from  pre decode for branches
  input      [XLEN          -1:0] branch_pc,
  input                           branch_taken
  
);

  //////////////////////////////////////////////////////////////////////////
  //  
  // Variables

  logic                      flushes;      //OR all flush signals

  logic [2*INSTR_SIZE  -1:0] parcel_shift_register;
  logic [INSTR_SIZE    -1:0] new_parcel;

  logic [               3:0] parcel_sr_valid;
  logic [               1:0] if_valid;

  logic [EXCEPTION_SIZE-1:0] parcel_exception;

  logic [XLEN          -1:0] pc;

  /////////////////////////////////////////////////////////////////////////
  //
  // Module body


  ////////////////////////////////////////////////////////////////////////
  //
  // Instruction fetch

  import riscv_pkg::*;		
  import riscv_state_pkg::*;

  //All flush signals combined
  assign flushes = bu_flush | st_flush | du_flush;

  //Flush upper layer (memory BIU) 
  assign if_flush = bu_flush | st_flush | du_flush | branch_taken;

  //stall program counter on ID-stall and when instruction-hold register is full
  assign if_stall = id_stall | (&parcel_sr_valid & ~flushes);

  //parcel is valid when bus-interface says so AND when received PC is requested PC 
  always @(posedge clk,negedge rstn)
    if (!rstn) if_valid <= 2'b0;
    else       if_valid <= if_parcel_valid;

  // let pre-decode know if fetched instructions is valid 
  assign if_valid_instr = if_valid[0] & (if_valid[1] | is_16bit_instruction); 

  /*
   * Next Program Counter
   */

   // TODO: change naming, is not a program counter, only for fetching data
   always @(posedge clk,negedge rstn)
     if      (!rstn                                         ) if_nxt_pc <= PC_INIT;
     else if ( st_flush	                                    ) if_nxt_pc <= st_nxt_pc;
     else if ( bu_flush		|| du_flush                     ) if_nxt_pc <= bu_nxt_pc; //flush takes priority
     else if ( branch_taken	&& !id_stall                    ) if_nxt_pc <= branch_pc;
     else if (!if_stall_nxt_pc	&& !id_stall 	&& !if_stall) if_nxt_pc <= if_nxt_pc[1] ? if_nxt_pc + 'h2 : if_nxt_pc + 'h4; // When if_nxt_pc[1] is set, got 16bit data, add 2, else add 4

  /*
   *  Instruction state machine  
   */ 
 always @(posedge clk,negedge rstn)
  if      (!rstn    ) parcel_shift_register <= {INSTR_NOP,INSTR_NOP};
  else if ( flushes ) parcel_shift_register <= {INSTR_NOP,INSTR_NOP};
  else if (!id_stall)
    if (branch_taken)
          parcel_shift_register <= {INSTR_NOP,INSTR_NOP};
    else
        case (parcel_sr_valid)
		4'b0000: case (if_parcel_valid)
			  2'b00 : parcel_shift_register <= {INSTR_NOP , INSTR_NOP};
			  2'b01 : parcel_shift_register <= {INSTR_NOP , new_parcel};
			  2'b10 : parcel_shift_register <= {INSTR_NOP , 16'h0000, new_parcel[16+:16]};
			  2'b11 : parcel_shift_register <= {INSTR_NOP , new_parcel};
			endcase

		4'b0001: case (if_parcel_valid)
			  2'b00 : parcel_shift_register <= is_16bit_instruction ? {INSTR_NOP, INSTR_NOP}  :
                                                                      {INSTR_NOP, parcel_shift_register[0+: INSTR_SIZE]};
			  2'b01 : parcel_shift_register <= is_16bit_instruction ? {INSTR_NOP, new_parcel} :
                                                                      {INSTR_NOP, new_parcel[ 0+: 16], parcel_shift_register[0+: 16]};
			  2'b10 : parcel_shift_register <= is_16bit_instruction ? {INSTR_NOP, new_parcel[ 0+: 16], new_parcel[16+:16]} :
                                                                      {INSTR_NOP, new_parcel[16+: 16], parcel_shift_register[0+: 16]};
			  2'b11 : parcel_shift_register <= is_16bit_instruction ? {INSTR_NOP, new_parcel} :
                                                                      {16'h0000 , new_parcel, parcel_shift_register[0+: 16]};
			endcase

		4'b0011: case (if_parcel_valid)
			  2'b00 : parcel_shift_register <= is_16bit_instruction ? {INSTR_NOP , parcel_shift_register[16+: INSTR_SIZE]}:
                                                                                  {INSTR_NOP , INSTR_NOP};
			  2'b01 : parcel_shift_register <= is_16bit_instruction ? {INSTR_NOP , new_parcel[ 0+:16], parcel_shift_register[16+: 16]}:
                                                                                  {INSTR_NOP , new_parcel};
			  2'b10 : parcel_shift_register <= is_16bit_instruction ? {INSTR_NOP , new_parcel[16+:16], parcel_shift_register[16+: 16]}:
                                                                                  {INSTR_NOP , 16'h0000  , new_parcel[16+: 16]};
			  2'b11 : parcel_shift_register <= is_16bit_instruction ? {16'h0000  , new_parcel, parcel_shift_register[16+: 16]}:
                                                                                  {INSTR_NOP , new_parcel};
			endcase
		4'b0111: case (if_parcel_valid)
			  2'b00 : parcel_shift_register <= is_16bit_instruction ? {INSTR_NOP , parcel_shift_register[16+: INSTR_SIZE]}: 
                                                                                  {INSTR_NOP , parcel_shift_register[32+: INSTR_SIZE]};
			  2'b01 : parcel_shift_register <= is_16bit_instruction ? {new_parcel, parcel_shift_register[16+: INSTR_SIZE]}: 
                                                                                  {16'h0000  , new_parcel, parcel_shift_register[32+: 16]};
			  2'b10 : parcel_shift_register <= is_16bit_instruction ? {16'h0000  , new_parcel[16+: 16], parcel_shift_register[16+: INSTR_SIZE]}: 
                                                                                  {INSTR_NOP , new_parcel[16+: 16], parcel_shift_register[16+:16]};
			  2'b11 : parcel_shift_register <= is_16bit_instruction ? {new_parcel, parcel_shift_register[16+: INSTR_SIZE]}: 
                                                                                  {16'h0000  , new_parcel, parcel_shift_register[32+: 16]};
			endcase


		4'b1111: if     (is_16bit_instruction) parcel_shift_register <= {16'h0000 , parcel_shift_register[16+: 48]};
                         else                          parcel_shift_register <= {INSTR_NOP, parcel_shift_register[32+: INSTR_SIZE]};
        endcase

  always @(posedge clk,negedge rstn)
  if      (!rstn    ) parcel_sr_valid <= {4'b0000};
  else if ( flushes ) parcel_sr_valid <= {4'b0000};
  else if (!id_stall)
    if (branch_taken)
          parcel_sr_valid <= {4'b0000};
    else
        case (parcel_sr_valid)
             4'b0000: case (if_parcel_valid)
                          2'b00 : parcel_sr_valid <= {4'b0000};
                          2'b01 : parcel_sr_valid <= {4'b0001};
                          2'b10 : parcel_sr_valid <= {4'b0001};
                          2'b11 : parcel_sr_valid <= {4'b0011};
                      endcase

            4'b0001: case (if_parcel_valid)
                          2'b00 : parcel_sr_valid <= is_16bit_instruction ? {4'b0000} : {4'b0001};
                          2'b01 : parcel_sr_valid <= is_16bit_instruction ? {4'b0001} : {4'b0011};
                          2'b10 : parcel_sr_valid <= is_16bit_instruction ? {4'b0001} : {4'b0011};
                          2'b11 : parcel_sr_valid <= is_16bit_instruction ? {4'b0011} : {4'b0111};
                     endcase


            4'b0011: case (if_parcel_valid)
                          2'b00 : parcel_sr_valid <= is_16bit_instruction ? {4'b0001} : {4'b0000};
                          2'b01 : parcel_sr_valid <= is_16bit_instruction ? {4'b0011} : {4'b0001};
                          2'b10 : parcel_sr_valid <= is_16bit_instruction ? {4'b0011} : {4'b0001};
                          2'b11 : parcel_sr_valid <= is_16bit_instruction ? {4'b0111} : {4'b0011};
                     endcase

            4'b0111: case (if_parcel_valid)
                          2'b00 : parcel_sr_valid <= is_16bit_instruction ? {4'b0011} : {4'b0001};
                          2'b01 : parcel_sr_valid <= is_16bit_instruction ? {4'b0111} : {4'b0011};
                          2'b10 : parcel_sr_valid <= is_16bit_instruction ? {4'b0111} : {4'b0011};
                          2'b11 : parcel_sr_valid <= is_16bit_instruction ? {4'b1111} : {4'b0111};
		     endcase


            4'b1111: if   (is_16bit_instruction)  parcel_sr_valid <=  {4'b0111};
                     else                         parcel_sr_valid <=  {4'b0011};
        endcase


  // When only 16bit data is valid in shift register and this is 16bit instruction add pc with 'h2
  // When 32bit or more data is valid in shift register add pc with 'h2 when 16-bit instruction and with 'h4 when not 16bit instruction
   always @(posedge clk,negedge rstn)
     if      (!rstn                                                                               ) pc <= PC_INIT;
     else if ( st_flush	                                                                          ) pc <= st_nxt_pc;
     else if ( bu_flush		                                                         || du_flush  ) pc <= bu_nxt_pc; //flush takes priority
     else if ( branch_taken	                                                         && !id_stall ) pc <= branch_pc;
     else if ( (parcel_sr_valid[1] || (parcel_sr_valid[0] && is_16bit_instruction))  && !id_stall ) pc <= is_16bit_instruction ? pc + 'h2 : pc + 'h4;

  // link incoming instruction to new_parcel 
  assign new_parcel = if_parcel;

  // Link the outcoming values to the associated values for pre decode
  assign if_instr  = parcel_shift_register[INSTR_SIZE-1:0]; 

  // When valid data is present in the shift register, no if_bubble
  assign if_bubble = ~(parcel_sr_valid[1] | (parcel_sr_valid[0] & is_16bit_instruction));
  assign if_pc 	   = pc;

  assign is_16bit_instruction = ~&if_instr[1:0];
  assign is_32bit_instruction =  &if_instr[1:0];
//  assign is_48bit_instruction =   active_parcel[5:0] == 6'b011111;
//  assign is_64bit_instruction =   active_parcel[6:0] == 7'b0111111;

  
  always @(posedge clk, negedge rstn)
    if	    (!rstn                                    ) if_exception <= 'h0; 
    else if ( flushes                                 ) if_exception <= 'h0;
    else if ( if_valid[0] || if_valid[1] && !id_stall ) if_exception <= parcel_exception;


  // parcel-fetch exception
  always @(posedge clk,negedge rstn)
    if      (!rstn                                   ) parcel_exception <= 'h0;
    else if ( flushes                                ) parcel_exception <= 'h0;
    else if ( if_valid[0] || if_valid[1] && !id_stall)
    begin
        parcel_exception <= 'h0;
        parcel_exception[CAUSE_MISALIGNED_INSTRUCTION  ] <= if_parcel_misaligned;
        parcel_exception[CAUSE_INSTRUCTION_ACCESS_FAULT] <= if_parcel_page_fault;
    end 

  endmodule	










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
  output                          if_out_order,
    
  // Outputs for pre decode
  output reg [XLEN           -1:0] if_pc,	 //Program counter for the instruction to id 
  output reg [INSTR_SIZE     -1:0] if_instr,	 //Instruction output to instruction decode
  output reg                       if_bubble, 	 //Insert bublle in the pipe (NOP instruction)
  output reg [EXCEPTION_SIZE -1:0] if_exception,  //Exception bit for down the pipe

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
  logic [2*XLEN	       -1:0] pc_shift_register;
  logic [INSTR_SIZE    -1:0] new_parcel;

  logic                      parcel_valid;
  logic [               3:0] parcel_sr_valid;

  logic [EXCEPTION_SIZE-1:0] parcel_exception;

  logic                      is_rv64;
  logic	[XLEN	       -1:0] dummy_pc;
  logic	                     out_order;

  /////////////////////////////////////////////////////////////////////////
  //
  // Module body


  ////////////////////////////////////////////////////////////////////////
  //
  // Instruction fetch

  import riscv_pkg::*;		
  import riscv_state_pkg::*;

  assign is_rv64 = (XLEN == 64);
  assign dummy_pc = is_rv64 ? 64'h0000000000000000 : 32'h00000000;

  //All flush signals combined
  assign flushes = bu_flush | st_flush | du_flush;

  //Flush upper layer (memory BIU) 
  assign if_flush = bu_flush | st_flush | du_flush | branch_taken;

  //stall program counter on ID-stall and when instruction-hold register is full
  assign if_stall = id_stall | (&parcel_sr_valid & ~flushes);


  //parcel is valid when bus-interface says so AND when received PC is requested PC 
  always @(posedge clk,negedge rstn)
    if (!rstn) parcel_valid <= 1'b0;
    else       parcel_valid <= if_parcel_valid[0] | if_parcel_valid[1];

  /*
   * Next Program Counter
   */
   always @(posedge clk,negedge rstn)
     if      (!rstn                                         ) if_nxt_pc <= PC_INIT;
     else if ( st_flush	                                    ) if_nxt_pc <= st_nxt_pc[1] ? st_nxt_pc -'h2 : st_nxt_pc;
     else if ( bu_flush		|| du_flush                 ) if_nxt_pc <= bu_nxt_pc[1] ? bu_nxt_pc -'h2 : bu_nxt_pc; //flush takes priority
     else if ( branch_taken	&& !id_stall                ) if_nxt_pc <= branch_pc[1] ? branch_pc -'h2 : branch_pc;
     else if (!if_stall_nxt_pc	&& !id_stall 	&& !if_stall) if_nxt_pc <= if_nxt_pc + 'h4;

   
  always @(posedge clk, negedge rstn)
     if	     (!rstn                                     ) out_order <= 1'b0;
     else if ( st_flush                                 ) out_order <= st_nxt_pc[1];
     else if ( bu_flush || du_flush                     ) out_order <= bu_nxt_pc[1];
     else if ( branch_taken && !id_stall                ) out_order <= branch_pc[1];
     else if (!if_stall_nxt_pc && !id_stall && !if_stall) out_order <= out_order;	 
    

  assign if_out_order = out_order;
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
			  2'b01 : parcel_shift_register <= {new_parcel, INSTR_NOP};
			  2'b10 : parcel_shift_register <= {16'h0000  , new_parcel[16+:16], INSTR_NOP};
			  2'b11 : parcel_shift_register <= {INSTR_NOP , new_parcel};
			endcase

		4'b0100: case (if_parcel_valid)
			  2'b00 : parcel_shift_register <= {parcel_shift_register[32+: INSTR_SIZE], INSTR_NOP};
			  2'b01 : parcel_shift_register <= {INSTR_NOP, new_parcel[ 0+: 16], parcel_shift_register[32+: 16]};
			  2'b10 : parcel_shift_register <= {INSTR_NOP, new_parcel[16+: 16], parcel_shift_register[32+: 16]};
			  2'b11 : parcel_shift_register <= {16'h0000 , new_parcel, parcel_shift_register[32+: 16]};
			endcase

		4'b0011: case (if_parcel_valid)
			  2'b00 : parcel_shift_register <= is_16bit_instruction ? {parcel_shift_register[16+: INSTR_SIZE], INSTR_NOP}:
                                                                                  {INSTR_NOP , INSTR_NOP};
			  2'b01 : parcel_shift_register <= is_16bit_instruction ? {INSTR_NOP , new_parcel[ 0+:16], parcel_shift_register[16+: 16]}:
                                                                                  {new_parcel, INSTR_NOP};
			  2'b10 : parcel_shift_register <= is_16bit_instruction ? {INSTR_NOP , new_parcel[16+:16], parcel_shift_register[16+: 16]}:
                                                                                  {16'h0000  , new_parcel[16+: 16], INSTR_NOP};
			  2'b11 : parcel_shift_register <= is_16bit_instruction ? {16'h0000  , new_parcel, parcel_shift_register[16+: 16]}:
                                                                                  {INSTR_NOP , new_parcel};
			endcase
		4'b0111: case (if_parcel_valid)
			  2'b00 : parcel_shift_register <= is_16bit_instruction ? {INSTR_NOP , parcel_shift_register[16+: INSTR_SIZE]}: 
                                                                                  {parcel_shift_register[32+: INSTR_SIZE], INSTR_NOP};
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
                          2'b01 : parcel_sr_valid <= {4'b0100};
                          2'b10 : parcel_sr_valid <= {4'b0100};
                          2'b11 : parcel_sr_valid <= {4'b0011};
                      endcase

            4'b0100: case (if_parcel_valid)
                          2'b00 : parcel_sr_valid <= {4'b0100};
                          2'b01 : parcel_sr_valid <= {4'b0011};
                          2'b10 : parcel_sr_valid <= {4'b0011};
                          2'b11 : parcel_sr_valid <= {4'b0111};
                     endcase


            4'b0011: case (if_parcel_valid)
                          2'b00 : parcel_sr_valid <= is_16bit_instruction ? {4'b0100} : {4'b0000};
                          2'b01 : parcel_sr_valid <= is_16bit_instruction ? {4'b0011} : {4'b0100};
                          2'b10 : parcel_sr_valid <= is_16bit_instruction ? {4'b0011} : {4'b0100};
                          2'b11 : parcel_sr_valid <= is_16bit_instruction ? {4'b0111} : {4'b0011};
                     endcase

            4'b0111: case (if_parcel_valid)
                          2'b00 : parcel_sr_valid <= is_16bit_instruction ? {4'b0011} : {4'b0100};
                          2'b01 : parcel_sr_valid <= is_16bit_instruction ? {4'b0111} : {4'b0011};
                          2'b10 : parcel_sr_valid <= is_16bit_instruction ? {4'b0111} : {4'b0011};
                          2'b11 : parcel_sr_valid <= is_16bit_instruction ? {4'b1111} : {4'b0111};
		     endcase


            4'b1111: if   (is_16bit_instruction)  parcel_sr_valid <=  {4'b0111};
                     else                         parcel_sr_valid <=  {4'b0011};
        endcase


  //change program counter for output to instruction decode
  always @(posedge clk, negedge rstn)
    if	    (!rstn	            ) pc_shift_register<= {dummy_pc, PC_INIT};
    else if ( st_flush              ) pc_shift_register<= {dummy_pc, st_nxt_pc};
    else if ( bu_flush || du_flush  ) pc_shift_register<= {dummy_pc, bu_nxt_pc};
    else if (!id_stall              ) 
      if (branch_taken)
        pc_shift_register <= pc_shift_register;
      else
          case(parcel_sr_valid)
                4'b0000: case(if_parcel_valid)
                          2'b00 : pc_shift_register<= {dummy_pc, if_parcel_pc};
                          2'b01 : pc_shift_register<= {if_parcel_pc, pc_shift_register[ 0+: XLEN]};
                          2'b10 : pc_shift_register<= {if_parcel_pc, pc_shift_register[ 0+: XLEN]};
                          2'b11 : pc_shift_register<= {dummy_pc, if_parcel_pc};
                         endcase
		
                4'b0100: case(if_parcel_valid)
                          2'b00 : pc_shift_register<= pc_shift_register; 
                         //2'b11 : pc_shift_register<= {if_parcel_pc, pc_shift_register[   0+: XLEN]};
                          default: pc_shift_register<= {if_parcel_pc, pc_shift_register[XLEN+: XLEN] +'h2};		
                         endcase		

                4'b0011: case(if_parcel_valid)
                          2'b00 : pc_shift_register<= is_16bit_instruction ? {pc_shift_register[ 0+: XLEN], pc_shift_register[   0+: XLEN]}: 
                                                                             {dummy_pc, if_parcel_pc};
                          2'b01 : pc_shift_register<= is_16bit_instruction ? {if_parcel_pc, pc_shift_register[   0+: XLEN] +'h2}:
                                                                             {if_parcel_pc, pc_shift_register[XLEN+: XLEN]};
                          2'b10 : pc_shift_register<= is_16bit_instruction ? {if_parcel_pc, pc_shift_register[   0+: XLEN] + 'h2}:
                                                                             {if_parcel_pc, pc_shift_register[XLEN+: XLEN]};
                          2'b11 : pc_shift_register<= is_16bit_instruction ? {if_parcel_pc, pc_shift_register[   0+: XLEN] + 'h2}:
                                                                             {dummy_pc, if_parcel_pc};
                         endcase

                4'b0111: case(if_parcel_valid)
                          2'b00 : pc_shift_register<= is_16bit_instruction ? {pc_shift_register[XLEN+: XLEN], pc_shift_register[XLEN+: XLEN]} :  
                                                                             {pc_shift_register[XLEN+: XLEN], pc_shift_register[   0+: XLEN]}; 
                          2'b01 : pc_shift_register<= is_16bit_instruction ? {if_parcel_pc, pc_shift_register[XLEN+: XLEN]}:
                                                                             {if_parcel_pc, pc_shift_register[   0+: XLEN]+ 'h2};
                          2'b10 : pc_shift_register<= is_16bit_instruction ? {if_parcel_pc, pc_shift_register[XLEN+: XLEN]}:
                                                                             {if_parcel_pc, pc_shift_register[   0+: XLEN]+ 'h2};
                          2'b11 : pc_shift_register<= is_16bit_instruction ? {if_parcel_pc, pc_shift_register[XLEN+: XLEN]}: 
                                                                             {if_parcel_pc, pc_shift_register[XLEN+: XLEN] +'h2};
                         endcase


                4'b1111: if   (is_16bit_instruction) pc_shift_register<= {pc_shift_register[XLEN+: XLEN], pc_shift_register[ 0+: XLEN] +'h2};
                         else                        pc_shift_register<= {if_parcel_pc, pc_shift_register[XLEN+: XLEN]};
	
	endcase
  // link incoming instruction to new_parcel 
  assign new_parcel = if_parcel;

  // Link the outcoming values to the associated values for pre decode
  assign if_instr  = parcel_shift_register[INSTR_SIZE-1:0]; 
  assign if_bubble = ~parcel_sr_valid[0];
  assign if_pc 	   = pc_shift_register[INSTR_SIZE -1:0];

  assign is_16bit_instruction = ~&if_instr[1:0];
  assign is_32bit_instruction =  &if_instr[1:0];
//  assign is_48bit_instruction =   active_parcel[5:0] == 6'b011111;
//  assign is_64bit_instruction =   active_parcel[6:0] == 7'b0111111;

  
  always @(posedge clk, negedge rstn)
    if	    (!rstn                      ) if_exception <= 'h0; 
    else if ( flushes                   ) if_exception <= 'h0;
    else if ( parcel_valid && !id_stall	) if_exception <= parcel_exception;


  // parcel-fetch exception
  always @(posedge clk,negedge rstn)
    if      (!rstn                     ) parcel_exception <= 'h0;
    else if ( flushes                  ) parcel_exception <= 'h0;
    else if ( parcel_valid && !id_stall)
    begin
        parcel_exception <= 'h0;
        parcel_exception[CAUSE_MISALIGNED_INSTRUCTION  ] <= if_parcel_misaligned;
        parcel_exception[CAUSE_INSTRUCTION_ACCESS_FAULT] <= if_parcel_page_fault;
    end 

  endmodule	










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
//    No-Instruction Cache Core Logic                          //
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

module riscv_noicache_core #(
  parameter XLEN           = 32,
  parameter PHYS_ADDR_SIZE = XLEN, //MSB determines cacheable(0) and non-cacheable(1)
  parameter PARCEL_SIZE    = 32
)
(
  input                           rstn,
  input                           clk,
 
  //CPU side
  output reg                      if_stall_nxt_pc,
  input                           if_stall,
                                  if_flush,
  input				  if_out_order,
  input      [XLEN          -1:0] if_nxt_pc,
  output reg [XLEN          -1:0] if_parcel_pc,
  output reg [PARCEL_SIZE   -1:0] if_parcel,
  output reg [		     1:0] if_parcel_valid,
  output                          if_parcel_misaligned,
  input                           bu_cacheflush,
                                  dcflush_rdy,
  input       [              1:0] st_prv,

  //To BIU
  output reg                      biu_stb,
  input                           biu_stb_ack,
  output     [PHYS_ADDR_SIZE-1:0] biu_adri,
  input      [PHYS_ADDR_SIZE-1:0] biu_adro,
  output     [XLEN/8        -1:0] biu_be,       //Byte enables
  output reg [               2:0] biu_type,     //burst type -AHB style
  output                          biu_lock,
  output                          biu_we,
  output     [XLEN          -1:0] biu_di,
  input      [XLEN          -1:0] biu_do,
  input                           biu_rack,     //data acknowledge, 1 per data
  input                           biu_err,      //data error

  output                          biu_is_cacheable,
                                  biu_is_instruction,
  output     [               1:0] biu_prv
);

  //////////////////////////////////////////////////////////////////
  //
  // Constants
  //
  import ahb3lite_pkg::*;


  //////////////////////////////////////////////////////////////////
  //
  // Functions
  //


  //////////////////////////////////////////////////////////////////
  //
  // Typedefs
  //
  typedef struct packed {
    logic                       valid;
    logic [XLEN           -1:0] dat;
    logic [PHYS_ADDR_SIZE -1:0] adr;
  } fifo_struct;

  typedef struct packed {
    logic	                valid;
    logic [XLEN		  -1:0] pc;
  } pc_struct;


  //////////////////////////////////////////////////////////////////
  //
  // Variables
  //
  logic        is_cacheable;

  logic  [1:0] biu_stb_cnt;
  fifo_struct  biu_fifo[3];
  pc_struct    pc_fifo[3];
  logic        if_flush_dly;

  logic		lsb_valid;
  logic		msb_valid;
  logic [XLEN		-1:0] if_nxt_pc_dly;
  logic [XLEN		-1:0] asked_pc_previous;


  //////////////////////////////////////////////////////////////////
  //
  // Module Body
  //
  import riscv_pkg::*;


  //Is this a cacheable region?
  //MSB=1 non-cacheable (IO region)
  //MSB=0 cacheabel (instruction/data region)
  assign is_cacheable = ~if_nxt_pc[PHYS_ADDR_SIZE-1];

  //For now don't support 16bit accesses
  // if (has rvc) parcelmisaligned = if_nxt_pc[0]
  // else parcelmisaligned = |if_nxt_pc[1:0]

  assign if_parcel_misaligned = if_nxt_pc[0]; //send out together with instruction

  //delay IF-flush
  always @(posedge clk,negedge rstn)
    if (!rstn) if_flush_dly <= 1'b0;
    else       if_flush_dly <= if_flush;

  // fifo buffer for program counter
  always @(posedge clk, negedge rstn)
    if(!rstn)
	begin 
	  pc_fifo[0].valid <= 1'b0;  
	  pc_fifo[1].valid <= 1'b0;
	  pc_fifo[2].valid <= 1'b0;
   	end
    else if( if_flush)
	begin
	  pc_fifo[0].valid <= 1'b0;
	  pc_fifo[1].valid <= 1'b0;
	  pc_fifo[2].valid <= 1'b0;
	end
    else 
	case({!if_stall_nxt_pc, if_parcel_valid[1] | if_parcel_valid[0]})
	  2'b00: ; // no write, no read -> nothing to do
	  
	  // read from buffer
	  2'b01: begin 
		   pc_fifo[0].pc    <= pc_fifo[1].pc; 
		   pc_fifo[0].valid <= pc_fifo[1].valid;
		   pc_fifo[1].pc    <= pc_fifo[2].pc;
		   pc_fifo[1].valid <= pc_fifo[2].valid;
		   pc_fifo[2].pc    <= 'hx;
		   pc_fifo[2].valid <= 1'b0;
		 end
	  
	  2'b10: // write from buffer
		case({pc_fifo[1].valid, pc_fifo[0].valid})
	  	  2'b11:   begin
	 		     pc_fifo[2].pc    <= if_out_order ? if_nxt_pc + 'h2 : if_nxt_pc;
			     pc_fifo[2].valid <= 1'b1;
			   end
		  2'b01:   begin
			     pc_fifo[1].pc    <= if_out_order ? if_nxt_pc +'h2 : if_nxt_pc;
			     pc_fifo[1].valid <= 1'b1; 
			   end
		  default: begin
			     pc_fifo[0].pc    <= if_out_order ? if_nxt_pc +'h2: if_nxt_pc;
			     pc_fifo[0].valid <= 1'b1;
			   end
		 endcase

	  2'b11: // read and write from buffer
		casex({pc_fifo[2].valid, pc_fifo[1].valid, pc_fifo[0].valid})
		  3'b1?? : begin
			     pc_fifo[2].pc    <= if_out_order ? if_nxt_pc + 'h2 : if_nxt_pc;
			     pc_fifo[2].valid <= 1'b1; 
		
			     pc_fifo[0].pc    <= pc_fifo[1].pc;
			     pc_fifo[0].valid <= pc_fifo[1].valid;
			     pc_fifo[1].pc    <= pc_fifo[2].pc;
			     pc_fifo[1].valid <= pc_fifo[2].valid;
			   end

		 3'b01? :  begin
			     pc_fifo[1].pc    <= if_out_order ? if_nxt_pc + 'h2 : if_nxt_pc;
			     pc_fifo[1].valid <= 1'b1;
			
			     pc_fifo[0].pc    <= pc_fifo[1].pc;
			     pc_fifo[0].valid <= pc_fifo[1].valid;

			     pc_fifo[2].pc    <= 'hx;
			     pc_fifo[2].valid <= 1'b0;
			   end

		 default:  begin
			     pc_fifo[0].pc    <= if_out_order ? if_nxt_pc + 'h2 : if_nxt_pc;
			     pc_fifo[0].valid <= 1'b1;

			     pc_fifo[1].pc    <= 'hx;
			     pc_fifo[1].valid <= 1'b0;
			     pc_fifo[2].pc    <= 'hx;
			     pc_fifo[2].valid <= 1'b0;
			   end
		endcase
	endcase
		

  /*
   * To CPU
   */
  assign if_stall_nxt_pc    = ~dcflush_rdy | ~biu_stb_ack | biu_fifo[1].valid & ~if_stall;
  assign if_parcel_valid[0] = dcflush_rdy & ~(if_flush | if_flush_dly) & ~if_stall & biu_fifo[0].valid & lsb_valid;
  assign if_parcel_valid[1] = dcflush_rdy & ~(if_flush | if_flush_dly) & ~if_stall & biu_fifo[0].valid & msb_valid;
  assign if_parcel_pc       = {{XLEN-PHYS_ADDR_SIZE{1'b0}}, biu_fifo[0].adr};
  assign if_parcel          = biu_fifo[0].dat[ if_parcel_pc[$clog2(XLEN/32)+1:1]*16 +: PARCEL_SIZE ];  

  always @(posedge clk, negedge rstn)
	if	(if_parcel_valid[0] | if_parcel_valid[1])  	asked_pc_previous <= pc_fifo[0].pc;
	else 	 						asked_pc_previous <= asked_pc_previous;

  always_comb // @(posedge clk, negedge rstn)
	if 	(biu_fifo[0].adr == pc_fifo[0].pc)		lsb_valid <= 1'b1;
	else if	(biu_fifo[0].adr == asked_pc_previous + 'h2)	lsb_valid <= 1'b1;
	else 							lsb_valid <= 1'b0;

  always_comb // @(posedge clk, negedge rstn)
	if	(biu_fifo[0].adr + 'h2 == pc_fifo[0].pc +'h2)  msb_valid <= 1'b1;
	else if (biu_fifo[0].adr       == pc_fifo[0].pc -'h2)	msb_valid <= 1'b1;
 	else				   	      		msb_valid <= 1'b0;

        


  /*
   * External Interface
   */
  assign biu_stb   = dcflush_rdy & ~if_flush & ~if_stall & ~biu_fifo[1].valid; //TODO when is ~biu_fifo[1] required?
  assign biu_adri  = if_nxt_pc[PHYS_ADDR_SIZE -1:0];
  assign biu_be    = {$bits(biu_be){1'b1}};
  assign biu_lock  = 1'b0;
  assign biu_we    = 1'b0; //no writes
  assign biu_di    =  'h0;
  assign biu_type  = 3'h0; //single access

  //Instruction cache..
  assign biu_is_instruction = 1'b1;
  assign biu_is_cacheable   = is_cacheable;
  assign biu_prv            = st_prv;


  /*
   * FIFO
   */
  always @(posedge clk,negedge rstn)
    if      (!rstn       ) biu_stb_cnt <= 2'h0;
    else if ( if_flush   ) biu_stb_cnt <= 2'h0;
    else if ( biu_stb_ack) biu_stb_cnt <= {1'b1,biu_stb_cnt[1]};


  //valid bits
  always @(posedge clk,negedge rstn)
    if (!rstn)
    begin
        biu_fifo[0].valid <= 1'b0;
        biu_fifo[1].valid <= 1'b0;
        biu_fifo[2].valid <= 1'b0;
    end
    else if (!biu_stb_cnt[0])
    begin
        biu_fifo[0].valid <= 1'b0;
        biu_fifo[1].valid <= 1'b0;
        biu_fifo[2].valid <= 1'b0;
    end
    else
      case ({biu_rack, (if_parcel_valid[0] | if_parcel_valid[1])})// & (biu_rack | biu_fifo[1].valid)})
        2'b00: ;//biu_fifo[0].valid <= biu_fifo[1].valid;
        2'b10:   //FIFO write
               case ({biu_fifo[1].valid,biu_fifo[0].valid})
                 2'b11  : begin
                              //entry 0,1 full. Fill entry2
                              biu_fifo[2].valid <= 1'b1;
                          end
                 2'b01  : begin
                              //entry 0 full. Fill entry1, clear entry2
                              biu_fifo[1].valid <= 1'b1;
                              biu_fifo[2].valid <= 1'b0;
                          end
                 default: begin
                            //Fill entry0, clear entry1,2
                            biu_fifo[0].valid <= 1'b1;
                            biu_fifo[1].valid <= 1'b0;
                            biu_fifo[2].valid <= 1'b0;
                        end
               endcase
        2'b01: begin  //FIFO read
                   biu_fifo[0].valid <= biu_fifo[1].valid;
                   biu_fifo[1].valid <= biu_fifo[2].valid;
                   biu_fifo[2].valid <= 1'b0;
               end
        2'b11: ; //FIFO read/write, no change
      endcase


  //Address & Data
  always @(posedge clk)
    case ({biu_rack,(if_parcel_valid[0] | if_parcel_valid[1]) & (biu_rack | biu_fifo[1].valid)})
        2'b00: ;
        2'b10: case({biu_fifo[1].valid,biu_fifo[0].valid})
                 2'b11 : begin
                             //fill entry2
                             biu_fifo[2].dat <= biu_do;
                             biu_fifo[2].adr <= biu_adro;
                         end
                 2'b01 : begin
                             ////fill entry1
                             biu_fifo[1].dat <= biu_do;
                             biu_fifo[1].adr <= biu_adro;
                         end
                 default:begin
                             //fill entry0
                             biu_fifo[0].dat <= biu_do;
                             biu_fifo[0].adr <= biu_adro;
                         end
               endcase
        2'b01: begin
                   biu_fifo[0].dat <= biu_fifo[1].dat;
                   biu_fifo[0].adr <= biu_fifo[1].adr;
                   biu_fifo[1].dat <= biu_fifo[2].dat;
                   biu_fifo[1].adr <= biu_fifo[2].adr;
                   biu_fifo[2].dat <= 'hx;
                   biu_fifo[2].adr <= 'hx;
               end
        2'b11: casex({biu_fifo[2].valid,biu_fifo[1].valid,biu_fifo[0].valid})
                 3'b1?? : begin
                              //fill entry2
                              biu_fifo[2].dat <= biu_do;
                              biu_fifo[2].adr <= biu_adro;

                              //push other entries
                              biu_fifo[0].dat <= biu_fifo[1].dat;
                              biu_fifo[0].adr <= biu_fifo[1].adr;
                              biu_fifo[1].dat <= biu_fifo[2].dat;
                              biu_fifo[1].adr <= biu_fifo[2].adr;
                          end
                 3'b01? : begin
                              //fill entry1
                              biu_fifo[1].dat <= biu_do;
                              biu_fifo[1].adr <= biu_adro;

                              //push entry0
                              biu_fifo[0].dat <= biu_fifo[1].dat;
                              biu_fifo[0].adr <= biu_fifo[1].adr;

                              //don't care
                              biu_fifo[2].dat <= 'hx;
                              biu_fifo[2].adr <= 'hx;
                         end
                 default:begin
                              //fill entry0
                              biu_fifo[0].dat <= biu_do;
                              biu_fifo[0].adr <= biu_adro;

                              //don't care
                              biu_fifo[1].dat <= 'hx;
                              biu_fifo[1].adr <= 'hx;
                              biu_fifo[2].dat <= 'hx;
                              biu_fifo[2].adr <= 'hx;
                         end
               endcase
      endcase


endmodule



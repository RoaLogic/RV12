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
  input      [XLEN          -1:0] if_nxt_pc,
  output reg [XLEN          -1:0] if_parcel_pc,
  output reg [PARCEL_SIZE   -1:0] if_parcel,
  output reg                      if_parcel_valid,
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


  //////////////////////////////////////////////////////////////////
  //
  // Variables
  //
  logic        is_cacheable;

  logic  [1:0] biu_stb_cnt;
  fifo_struct  biu_fifo[3];
  logic        if_flush_dly;


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
  assign if_parcel_misaligned = |if_nxt_pc[1:0]; //send out together with instruction

  //delay IF-flush
  always @(posedge clk,negedge rstn)
    if (!rstn) if_flush_dly <= 1'b0;
    else       if_flush_dly <= if_flush;


  /*
   * To CPU
   */
  assign if_stall_nxt_pc = ~dcflush_rdy | ~biu_stb_ack | biu_fifo[1].valid;
  assign if_parcel_valid =  dcflush_rdy & ~(if_flush | if_flush_dly) & ~if_stall & biu_fifo[0].valid;
  assign if_parcel_pc    = { {XLEN-PHYS_ADDR_SIZE{1'b0}},biu_fifo[0].adr};
  assign if_parcel       = biu_fifo[0].dat[ if_parcel_pc[$clog2(XLEN/32)+1:1]*16 +: PARCEL_SIZE ];



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
      case ({biu_rack,if_parcel_valid})
        2'b00: ; //no action
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
    case ({biu_rack,if_parcel_valid})
        2'b00: ;
        2'b10: case({biu_fifo[1].valid,biu_fifo[0].valid})
                 2'b11 : begin
                             //fill entry2
                             biu_fifo[2].dat <= biu_do;
                             biu_fifo[2].adr <= biu_adro;
                         end
                 2'b01 : begin
                             //fill entry1
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



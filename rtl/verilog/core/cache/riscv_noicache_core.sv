/////////////////////////////////////////////////////////////////////
//   ,------.                    ,--.                ,--.          //
//   |  .--. ' ,---.  ,--,--.    |  |    ,---. ,---. `--' ,---.    //
//   |  '--'.'| .-. |' ,-.  |    |  |   | .-. | .-. |,--.| .--'    //
//   |  |\  \ ' '-' '\ '-'  |    |  '--.' '-' ' '-' ||  |\ `--.    //
//   `--' '--' `---'  `--`--'    `-----' `---' `-   /`--' `---'    //
//                                             `---'               //
//    RISC-V                                                       //
//    No Instruction Cache Core Logic                              //
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

import biu_constants_pkg::*;
import riscv_state_pkg::*;

module riscv_noicache_core #(
  parameter XLEN        = 32,
  parameter PLEN        = XLEN,
  parameter PARCEL_SIZE = 16,
  parameter HAS_RVC     = 0,
  parameter DEPTH       = 2,        //number of transactions in flight
  parameter BIUTAG_SIZE = $clog2(XLEN/PARCEL_SIZE)
)
(
  input                             rst_ni,
  input                             clk_i,
 
  //CPU side
  input      [XLEN            -1:0] if_nxt_pc_i,
  input                             if_req_i,
  output                            if_ack_o,
  input  biu_prot_t                 if_prot_i,
  input                             if_flush_i,
  output     [XLEN            -1:0] if_parcel_pc_o,
  output     [XLEN            -1:0] if_parcel_o,
  output     [XLEN/PARCEL_SIZE-1:0] if_parcel_valid_o,
  output                            if_parcel_misaligned_o,
  output                            if_parcel_error_o,
  input                             dcflush_rdy_i,
  input      [                 1:0] st_prv_i,

  //To BIU
  output                            biu_stb_o,
  input                             biu_stb_ack_i,
  input                             biu_d_ack_i,
  output     [PLEN            -1:0] biu_adri_o,
  input      [PLEN            -1:0] biu_adro_i,
  output biu_size_t                 biu_size_o,     //transfer size
  output biu_type_t                 biu_type_o,     //burst type -AHB style
  output                            biu_lock_o,
  output                            biu_we_o,
  output biu_prot_t                 biu_prot_o,
  output     [XLEN            -1:0] biu_d_o,
  input      [XLEN            -1:0] biu_q_i,
  input                             biu_ack_i,      //data acknowledge, 1 per data
  input                             biu_err_i,      //data error
  output     [BIUTAG_SIZE     -1:0] biu_tagi_o,
  input      [BIUTAG_SIZE     -1:0] biu_tago_i
);

  //////////////////////////////////////////////////////////////////
  //
  // Variables
  //
  logic if_flush_dly;

  logic [$clog2(DEPTH):0] inflight,
	                  discard;
  

  //////////////////////////////////////////////////////////////////
  //
  // Module Body
  //

  //delay IF-flush
  always @(posedge clk_i, negedge rst_ni)
    if (!rst_ni) if_flush_dly <= 1'b0;
    else         if_flush_dly <= if_flush_i;


  always @(posedge clk_i, negedge rst_ni)
    if      (!rst_ni) inflight <= 'h0;
    else
      unique case ({biu_stb_ack_i, biu_ack_i | biu_err_i})
        2'b01  : inflight <= inflight -1;
        2'b10  : inflight <= inflight +1;
        default: ; //do nothing
      endcase

      
  always @(posedge clk_i, negedge rst_ni)
    if (!rst_ni) discard <= 'h0;
    else if (if_flush_i)
    begin
        if (|inflight && (biu_ack_i | biu_err_i)) discard <= inflight -1;
        else                                      discard <= inflight;
    end
    else if (|discard && (biu_ack_i | biu_err_i)) discard <= discard -1;


  /*
   * To CPU
   */
  assign if_ack_o               = dcflush_rdy_i & biu_stb_ack_i;  //get next parcel address
  assign if_parcel_misaligned_o = (HAS_RVC != 0) ? if_parcel_pc_o[0] : |if_parcel_pc_o[1:0];
  assign if_parcel_error_o      = biu_err_i;
  assign if_parcel_valid_o      = dcflush_rdy_i & ~(if_flush_i | if_flush_dly) & biu_ack_i & ~|discard
                                ? {XLEN/PARCEL_SIZE{1'b1}} << biu_tago_i
                                : {XLEN/PARCEL_SIZE{1'b0}};
  assign if_parcel_pc_o         = { {PLEN - (BIUTAG_SIZE+1) - $bits(biu_tago_i) -1{1'b0}},biu_adro_i[PLEN -1 : BIUTAG_SIZE+1], biu_tago_i, 1'b0};
  assign if_parcel_o            = biu_q_i;


  /*
   * External Interface
   */
  assign biu_stb_o   = dcflush_rdy_i & ~if_flush_i & if_req_i;
  assign biu_adri_o  = if_nxt_pc_i[PLEN -1:0] & (XLEN==64 ? ~'h7 : ~'h3); //Always start at aligned address
  assign biu_tagi_o  = if_nxt_pc_i[1 +: BIUTAG_SIZE];                     //Use TAG to remember offset (actual address LSBs)
  assign biu_size_o  = XLEN==64 ? DWORD : WORD;
  assign biu_lock_o  = 1'b0;
  assign biu_prot_o  = if_prot_i;
  assign biu_we_o    = 1'b0;   //no writes
  assign biu_d_o     =  'h0;
  assign biu_type_o  = INCR;
endmodule



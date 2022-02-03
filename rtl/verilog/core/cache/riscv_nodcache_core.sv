/////////////////////////////////////////////////////////////////////
//   ,------.                    ,--.                ,--.          //
//   |  .--. ' ,---.  ,--,--.    |  |    ,---. ,---. `--' ,---.    //
//   |  '--'.'| .-. |' ,-.  |    |  |   | .-. | .-. |,--.| .--'    //
//   |  |\  \ ' '-' '\ '-'  |    |  '--.' '-' ' '-' ||  |\ `--.    //
//   `--' '--' `---'  `--`--'    `-----' `---' `-   /`--' `---'    //
//                                             `---'               //
//    RISC-V                                                       //
//    No Data Cache Core Logic                                     //
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


module riscv_nodcache_core #(
  parameter XLEN        = 32,
  parameter ALEN        = XLEN,
  parameter DEPTH       = 2 
)
(
  input                  rst_ni,
  input                  clk_i,
 
  //CPU side
  input                  mem_req_i,
  input  biu_size_t      mem_size_i,
  input                  mem_lock_i,
  input      [XLEN -1:0] mem_adr_i,
  input                  mem_we_i,
  input      [XLEN -1:0] mem_d_i,
  output     [XLEN -1:0] mem_q_o,
  output                 mem_ack_o,
  output                 mem_err_o,
  output reg             mem_misaligned_o,
  input      [      1:0] st_prv_i,
  
  //To BIU
  output reg             biu_stb_o,
  output     [ALEN -1:0] biu_adri_o,
  input      [ALEN -1:0] biu_adro_i,
  output biu_size_t      biu_size_o,     //transfer size
  output biu_type_t      biu_type_o,     //burst type -AHB style
  output                 biu_lock_o,
  output                 biu_we_o,
  output biu_prot_t      biu_prot_o,
  output     [XLEN -1:0] biu_d_o,
  input      [XLEN -1:0] biu_q_i,
  input                  biu_stb_ack_i,
  input                  biu_d_ack_i,
  input                  biu_ack_i,      //data acknowledge, 1 per data
  input                  biu_err_i       //data error
);


  //////////////////////////////////////////////////////////////////
  //
  // Variables
  //
  logic                   misaligned;

  logic                   hold_mem_req;
  logic [XLEN       -1:0] hold_mem_adr;
  logic [XLEN       -1:0] hold_mem_d;
  biu_size_t              hold_mem_size;
  biu_type_t              hold_mem_type;
  biu_prot_t              hold_mem_prot;
  logic                   hold_mem_lock;
  logic                   hold_mem_we;

  logic [$clog2(DEPTH):0] inflight,
	                  discard;

  //////////////////////////////////////////////////////////////////
  //
  // Module Body
  //


  /* Misaligned
   */
  always_comb
    unique case (size_i)
      BYTE   : misaligned = 1'b0;
      HWORD  : misaligned =  adr_i[  0];
      WORD   : misaligned = |adr_i[1:0];
      DWORD  : misaligned = |adr_i[2:0];
      default: misaligned = 1'b1;
    endcase


  always @(posedge clk_i)
    mem_misaligned_o <= mem_misaligned;


  /* Statemachine
   */
  always @(posedge clk_i)
    if (mem_req_i)
    begin
        hold_mem_adr  <= mem_adr_i;
        hold_mem_size <= mem_size_i;
        hold_mem_lock <= mem_lock_i;
        hold_mem_we   <= mem_we_i;
        hold_mem_d    <= mem_d_i;
    end


  always @(posedge clk_i)
    if      (!rst_ni                     ) hold_mem_req <= 1'b0;
    else if ( mem_misaligned || mem_err_o) hold_mem_req <= 1'b0;
    else                                   hold_mem_req <= (mem_req_i | hold_mem_req) & ~biu_stb_ack_i;


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
    else if (mem_misaligned || mem_err_o)
    begin
        if (|inflight && (biu_ack_i | biu_err_i)) discard <= inflight -1;
        else                                      discard <= inflight;
    end
    else if (|discard && (biu_ack_i | biu_err_i)) discard <= discard -1;


  /* External Interface
   */
  assign biu_stb_o     = (mem_req_i | hold_mem_req) & ~mem_misaligned;
  assign biu_adri_o    = hold_mem_req ? hold_mem_adr  : mem_adr_i;
  assign biu_size_o    = hold_mem_req ? hold_mem_size : mem_size_i;
  assign biu_lock_o    = hold_mem_req ? hold_mem_lock : mem_lock_i;
  assign biu_prot_o    = biu_prot_t'(PROT_DATA |
                                     st_prv_i == PRV_U ? PROT_USER : PROT_PRIVILEGED);
  assign biu_we_o      = hold_mem_req ? hold_mem_we   : mem_we_i;
  assign biu_d_o       = hold_mem_req ? hold_mem_d    : mem_d_i;
  assign biu_type_o    = SINGLE;

//  assign mem_adr_ack_o = biu_stb_ack_i;
//  assign mem_adr_o     = biu_adro_i;
  assign mem_q_o       = biu_q_i;
  assign mem_ack_o     = |discard ? 1'b0
                                  : |inflight ? biu_ack_i & ~mem_misaligned
                                              : biu_ack_i &  biu_stb_o;
  assign mem_err_o     = |discard ? 1'b0
                                  : |inflight ? biu_err_i & ~mem_misaligned
                                              : biu_err_i & biu_stb_o;

endmodule



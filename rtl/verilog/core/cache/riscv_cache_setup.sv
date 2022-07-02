/////////////////////////////////////////////////////////////////////
//   ,------.                    ,--.                ,--.          //
//   |  .--. ' ,---.  ,--,--.    |  |    ,---. ,---. `--' ,---.    //
//   |  '--'.'| .-. |' ,-.  |    |  |   | .-. | .-. |,--.| .--'    //
//   |  |\  \ ' '-' '\ '-'  |    |  '--.' '-' ' '-' ||  |\ `--.    //
//   `--' '--' `---'  `--`--'    `-----' `---' `-   /`--' `---'    //
//                                             `---'               //
//    RISC-V                                                       //
//    Cache Address Setup Stage                                    //
//                                                                 //
/////////////////////////////////////////////////////////////////////
//                                                                 //
//             Copyright (C) 2021 ROA Logic BV                     //
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

import riscv_cache_pkg::*;
import biu_constants_pkg::*;

module riscv_cache_setup #(
  parameter                    XLEN          = 32,
  parameter                    SIZE          = 64,
  parameter                    BLOCK_SIZE    = XLEN,
  parameter                    WAYS          = 2,

  localparam                   SETS          = no_of_sets             (SIZE, BLOCK_SIZE, WAYS       ),
  localparam                   BLK_OFFS_BITS = no_of_block_offset_bits(BLOCK_SIZE                   ),
  localparam                   IDX_BITS      = no_of_index_bits       (SETS                         )
)
(
  input  logic                 rst_ni,
  input  logic                 clk_i,

  input  logic                 stall_i,
  
  input  logic                 flush_i,
  input  logic                 req_i,
  input  logic [XLEN     -1:0] adr_i,   //virtualy index, physically tagged
  input  biu_size_t            size_i,
  input  logic                 lock_i,
  input  biu_prot_t            prot_i,
  input  logic                 we_i,
  input  logic [XLEN     -1:0] d_i,
  input  logic                 invalidate_i,
                               clean_i,

  output logic                 req_o,
  output logic                 rreq_o,
  output biu_size_t            size_o,
  output logic                 lock_o,
  output biu_prot_t            prot_o,
  output logic                 we_o,
  output logic [XLEN     -1:0] q_o,
  output logic                 invalidate_o,
                               clean_o,

  output logic [IDX_BITS -1:0] idx_o
);

  //////////////////////////////////////////////////////////////////
  //
  // Variables
  //
  logic                flush_dly;

  logic [IDX_BITS-1:0] adr_idx,
                       adr_idx_dly;

  logic                invalidate_hold,
                       clean_hold;

  //////////////////////////////////////////////////////////////////
  //
  // Module Body
  //


  /*delay flush signals
   */
  always @(posedge clk_i)
    flush_dly <= flush_i;


  /* Hold invalidate/clean signals
   */
  always @(posedge clk_i, negedge rst_ni)
    if      (!rst_ni ) invalidate_hold <= 1'b0;
    else if (!stall_i) invalidate_hold <= 1'b0;
    else               invalidate_hold <= invalidate_i | invalidate_hold;


  always @(posedge clk_i, negedge rst_ni)
    if      (!rst_ni ) clean_hold <= 1'b0;
    else if (!stall_i) clean_hold <= 1'b0;
    else               clean_hold <= clean_i | clean_hold;


  /*feed input signals to next stage
   */
  always @(posedge clk_i, negedge rst_ni)
    if      (!rst_ni ) req_o <= 1'b0;
    else if ( flush_i) req_o <= 1'b0;
    else if (!stall_i) req_o <= req_i;


  /* Latch signals
   */
  always @(posedge clk_i)
    if (!stall_i)
    begin
        size_o       <= size_i;
        lock_o       <= lock_i;
        prot_o       <= prot_i;
        we_o         <= we_i;
        q_o          <= d_i;
    end


  always @(posedge clk_i, negedge rst_ni)
    if (!rst_ni)
    begin
        invalidate_o <= 1'b0;
        clean_o      <= 1'b0;
    end
    else if (!stall_i)
    begin
        invalidate_o <= invalidate_i | invalidate_hold;
        clean_o      <= clean_i      | clean_hold;
    end


  /* Read-Request
   * Used to push writebuffer into Cache-memory
   * Same delay as adr_idx
   */
  assign rreq_o = req_i & ~we_i;


  /* TAG and DATA index
   * Output asynchronously, registered by memories
   */
  assign adr_idx = adr_i[BLK_OFFS_BITS +: IDX_BITS];

  always @(posedge clk_i)
    if (!stall_i || flush_dly) adr_idx_dly <= adr_idx;

  assign idx_o = stall_i /*&& !flush_dly*/ ? adr_idx_dly : adr_idx;
endmodule



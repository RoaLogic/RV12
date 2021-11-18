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
  parameter  XLEN          = 32,
  parameter  SIZE          = 64, 
  parameter  BLOCK_SIZE    = XLEN,
  parameter  WAYS          = 2,

  localparam SETS          = no_of_sets(SIZE, BLOCK_SIZE, WAYS),
  localparam BLK_OFFS_BITS = no_of_block_offset_bits(BLOCK_SIZE),
  localparam IDX_BITS      = no_of_index_bits(SETS),
  localparam TAG_BITS      = no_of_tag_bits(XLEN, IDX_BITS, BLK_OFFS_BITS)
)
(
  input  logic                rst_ni,
  input  logic                clk_i,

  input  logic                stall_i,
  
  input  logic                flush_i,
  input  logic                req_i,
  input  logic [XLEN    -1:0] adr_i,   //virtualy index, physically tagged
  input  biu_size_t           size_i,
  input                       lock_i,
  input  biu_prot_t           prot_i,
  input  logic                we_i,
  input  logic [XLEN/8  -1:0] be_i,
  input  logic [XLEN    -1:0] d_i,
  input  logic                is_cacheable_i,
  input  logic                is_misaligned_i,

  output logic                req_o,
  output logic [XLEN    -1:0] adr_o,
  output biu_size_t           size_o,
  output logic                lock_o,
  output biu_prot_t           prot_o,
  output logic                is_cacheable_o,
  output logic                is_misaligned_o,

  output logic [IDX_BITS-1:0] tag_idx_o,
                              dat_idx_o,
  output logic [TAG_BITS-1:0] core_tag_o,

  output logic                writebuffer_we_o,
  output logic [IDX_BITS-1:0] writebuffer_idx_o,
  output logic [XLEN    -1:0] writebuffer_data_o,
  output logic [XLEN/8  -1:0] writebuffer_be_o  
);

  //////////////////////////////////////////////////////////////////
  //
  // Variables
  //
  logic                flush_dly;

  logic [IDX_BITS-1:0] adr_idx,
                       adr_idx_dly;


  //////////////////////////////////////////////////////////////////
  //
  // Module Body
  //


  /*delay flush signals
   */
  always @(posedge clk_i)
    flush_dly <= flush_i;


  /*feed input signals to next stage
   */
  always @(posedge clk_i, negedge rst_ni)
    if      (!rst_ni ) req_o <= 1'b0;
    else if ( flush_i) req_o <= 1'b0;
    else if (!stall_i) req_o <= req_i;


  always @(posedge clk_i)
    if (!stall_i)
    begin
        adr_o           <= adr_i;
        size_o          <= size_i;
        lock_o          <= lock_i;
        prot_o          <= prot_i;
        is_cacheable_o  <= is_cacheable_i;
        is_misaligned_o <= is_misaligned_i;
    end


  /* TAG and DATA index
   * Output asynchronously, registered by memories
   */
  assign adr_idx = adr_i[BLK_OFFS_BITS +: IDX_BITS];

  always @(posedge clk_i)
    if (!stall_i || flush_dly) adr_idx_dly <= adr_idx;

  assign tag_idx_o = stall_i && !flush_dly ? adr_idx_dly : adr_idx;
  assign dat_idx_o = stall_i && !flush_dly ? adr_idx_dly : adr_idx;
//  assign tag_idx_o = adr_idx;
//  assign dat_idx_o = adr_idx;

  /* Core Tag
   */
  always @(posedge clk_i)
    if (!stall_i) core_tag_o <= adr_i[XLEN-1 -: TAG_BITS];


  /* Write Buffer
   */
  always @(posedge clk_i)
    if (!stall_i)
    begin
        writebuffer_we_o   = req_i & we_i;
        writebuffer_idx_o  = adr_idx;
        writebuffer_data_o = d_i;
        writebuffer_be_o   = be_i;
    end

endmodule



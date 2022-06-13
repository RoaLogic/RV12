/////////////////////////////////////////////////////////////////////
//   ,------.                    ,--.                ,--.          //
//   |  .--. ' ,---.  ,--,--.    |  |    ,---. ,---. `--' ,---.    //
//   |  '--'.'| .-. |' ,-.  |    |  |   | .-. | .-. |,--.| .--'    //
//   |  |\  \ ' '-' '\ '-'  |    |  '--.' '-' ' '-' ||  |\ `--.    //
//   `--' '--' `---'  `--`--'    `-----' `---' `-   /`--' `---'    //
//                                             `---'               //
//    RISC-V                                                       //
//    Cache Tag Stage                                              //
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

module riscv_cache_tag #(
  parameter                        XLEN          = 32,
  parameter                        PLEN          = XLEN,
  parameter                        SIZE          = 64,
  parameter                        BLOCK_SIZE    = XLEN,
  parameter                        WAYS          = 2,

  localparam                       SETS          = no_of_sets             (SIZE, BLOCK_SIZE, WAYS       ),
  localparam                       BLK_OFFS_BITS = no_of_block_offset_bits(BLOCK_SIZE                   ),
  localparam                       IDX_BITS      = no_of_index_bits       (SETS                         ),
  localparam                       TAG_BITS      = no_of_tag_bits         (PLEN, IDX_BITS, BLK_OFFS_BITS)
)
(
  input  logic                     rst_ni,
  input  logic                     clk_i,

  input  logic                     stall_i,
  
  input  logic                     flush_i,
  input  logic                     req_i,
  input  logic [PLEN         -1:0] phys_adr_i, //physical address
  input  biu_size_t                size_i,
  input                            lock_i,
  input  biu_prot_t                prot_i,
  input  logic                     we_i,
  input  logic [XLEN         -1:0] d_i,
  input  logic                     invalidate_i,
  input  logic                     clean_i,
  input  logic                     pagefault_i,

  output logic                     req_o,
  output logic                     wreq_o,
  output logic [PLEN         -1:0] adr_o,
  output biu_size_t                size_o,
  output logic                     lock_o,
  output biu_prot_t                prot_o,
  output logic                     we_o,
  output logic [XLEN/8       -1:0] be_o,
  output logic [XLEN         -1:0] q_o,
  output logic                     invalidate_o,
  output logic                     clean_o,
  output logic                     pagefault_o,
  output logic [TAG_BITS     -1:0] core_tag_o
);

  //////////////////////////////////////////////////////////////////
  //
  // Functions
  //   
  function automatic [XLEN/8-1:0] size2be;
    input [     2:0] size;
    input [XLEN-1:0] adr;

    logic [$clog2(XLEN/8)-1:0] adr_lsbs;

    adr_lsbs = adr[$clog2(XLEN/8)-1:0];

    unique case (size)
      BYTE : size2be = 'h1  << adr_lsbs;
      HWORD: size2be = 'h3  << adr_lsbs;
      WORD : size2be = 'hf  << adr_lsbs;
      DWORD: size2be = 'hff << adr_lsbs;
    endcase
  endfunction: size2be


  //////////////////////////////////////////////////////////////////
  //
  // Module Body
  //

  /* Feed input signals to next stage
   * Just a delay while waiting for Hit and Cacheline
   */
  always @(posedge clk_i, negedge rst_ni)
    if      (!rst_ni ) req_o <= 1'b0;
    else if ( flush_i) req_o <= 1'b0;
    else if (!stall_i) req_o <= req_i;


  always @(posedge clk_i, negedge rst_ni)
    if      (!rst_ni ) wreq_o <= 1'b0;
    else if ( flush_i) wreq_o <= 1'b0;
    else if (!stall_i) wreq_o <= req_i & we_i;


  always @(posedge clk_i)
    if (!stall_i)
    begin
        adr_o        <= phys_adr_i;
        size_o       <= size_i;
        lock_o       <= lock_i;
        prot_o       <= prot_i;
        we_o         <= we_i;
        be_o         <= size2be(size_i, phys_adr_i);
        q_o          <= d_i;
        pagefault_o  <= pagefault_i;
    end

  always @(posedge clk_i, negedge rst_ni)
    if (!rst_ni)
    begin
        invalidate_o <= 1'b0;
        clean_o      <= 1'b0;
    end
    else if (!stall_i)
    begin
        invalidate_o <= invalidate_i;
        clean_o      <= clean_i;
    end


  //core-tag
  assign core_tag_o = phys_adr_i[PLEN-1 -: TAG_BITS];
endmodule



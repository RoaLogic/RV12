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
  parameter XLEN = 32,
  parameter PLEN = XLEN
)
(
  input  logic             rst_ni,
  input  logic             clk_i,

  input  logic             stall_i,
  
  input  logic             flush_i,
  input  logic             req_i,
  input  logic [PLEN -1:0] adr_i,
  input  biu_size_t        size_i,
  input                    lock_i,
  input  biu_prot_t        prot_i,
  input  logic             is_cacheable_i,
  input  logic             is_misaligned_i,

  output logic             req_o,
  output logic [PLEN -1:0] adr_o,
  output biu_size_t        size_o,
  output logic             lock_o,
  output biu_prot_t        prot_o,
  output logic             is_cacheable_o,
  output logic             is_misaligned_o
);

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

endmodule



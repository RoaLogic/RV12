/////////////////////////////////////////////////////////////////////
//   ,------.                    ,--.                ,--.          //
//   |  .--. ' ,---.  ,--,--.    |  |    ,---. ,---. `--' ,---.    //
//   |  '--'.'| .-. |' ,-.  |    |  |   | .-. | .-. |,--.| .--'    //
//   |  |\  \ ' '-' '\ '-'  |    |  '--.' '-' ' '-' ||  |\ `--.    //
//   `--' '--' `---'  `--`--'    `-----' `---' `-   /`--' `---'    //
//                                             `---'               //
//    RISC-V                                                       //
//    Memory Management Unit (no)                                  //
//                                                                 //
/////////////////////////////////////////////////////////////////////
//                                                                 //
//             Copyright (C) 2022 ROA Logic BV                     //
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

module riscv_nommu #(
  parameter XLEN    = 32,
  parameter PLEN    = XLEN == 32 ? 34 : 56
)
(
  input  logic            rst_ni,
  input  logic            clk_i,
  input  logic            stall_i,

  //CPU side
  input  logic            flush_i,
  input  logic            req_i,
  input  logic [XLEN-1:0] adr_i,   //virtualy index, physically tagged
  input  biu_size_t       size_i,
  input                   lock_i,
  input  logic            we_i,

  input  logic            cm_clean_i,
  input  logic            cm_invalidate_i,

  //To memory subsystem
  output logic            req_o,
  output logic [PLEN-1:0] adr_o,
  output biu_size_t       size_o,
  output logic            lock_o,
  output logic            we_o,

  output logic            cm_clean_o,
  output logic            cm_invalidate_o,
  
  output logic            pagefault_o
);
  //////////////////////////////////////////////////////////////////
  //
  // Module Body
  //

  /*
   * For now simply delay virtual address one cycle.
   * This assumes 1 clock cyle to translate the address.
   * However most likely this will require 2 cycles
   *
   * Also TLB miss needs to generate it's own memory accesses to fetch new TLB
   * entry. Therefore the whole data-memory signals must be routed through the
   * MMU block
   */

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
        adr_o           <= XLEN == 32 ? {2'h0,adr_i} : adr_i[PLEN-1:0];
        size_o          <= size_i;
        lock_o          <= lock_i;
        we_o            <= we_i;

	cm_clean_o      <= cm_clean_i;
	cm_invalidate_o <= cm_invalidate_i;
    end

  assign pagefault_o = 1'b0;
endmodule


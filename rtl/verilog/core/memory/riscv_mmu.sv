/////////////////////////////////////////////////////////////////////
//   ,------.                    ,--.                ,--.          //
//   |  .--. ' ,---.  ,--,--.    |  |    ,---. ,---. `--' ,---.    //
//   |  '--'.'| .-. |' ,-.  |    |  |   | .-. | .-. |,--.| .--'    //
//   |  |\  \ ' '-' '\ '-'  |    |  '--.' '-' ' '-' ||  |\ `--.    //
//   `--' '--' `---'  `--`--'    `-----' `---' `-   /`--' `---'    //
//                                             `---'               //
//    RISC-V                                                       //
//    Memory Management Unit                                       //
//                                                                 //
/////////////////////////////////////////////////////////////////////
//                                                                 //
//             Copyright (C) 2018 ROA Logic BV                     //
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

/* Placeholder for MMU
 * RISC-V uses 4KB pages
 * SATP-CSR holds: [MODE|ASID|PPN]
 * Mode: rv32   rv64
 * 0     bare   bare (no translation)
 * 1     sv32   reserved
 * 2-7   .      reserved
 * 8     .      sv39
 * 9     .      sv48
 * 10    .      sv57
 * 11    .      sv64
 * 12-15 .      reserved
 */

import biu_constants_pkg::*;

module riscv_mmu #(
  parameter XLEN = 32,
  parameter PLEN = XLEN //
)
(
  input  logic            rst_ni,
  input  logic            clk_i,

  //Mode
//  input  logic [XLEN-1:0] st_satp;

  //CPU side
  input  logic            vreq_i,  //Request from CPU
  input  logic [XLEN-1:0] vadr_i,  //Virtual Memory Address
  input  biu_size_t       vsize_i,
  input  logic            vlock_i,
  input  biu_prot_t       vprot_i,
  input  logic            vwe_i,
  input  logic [XLEN-1:0] vd_i,

  //Memory system side
  output logic            preq_o,
  output logic [PLEN-1:0] padr_o,  //Physical Memory Address
  output biu_size_t       psize_o,
  output logic            plock_o,
  output biu_prot_t       pprot_o,
  output logic            pwe_o,
  output logic [XLEN-1:0] pd_o,
  input  logic [XLEN-1:0] pq_i,
  input  logic            pack_i,

  //Exception
  output logic            page_fault_o
);

  //////////////////////////////////////////////////////////////////
  //
  // Variables
  //


  //////////////////////////////////////////////////////////////////
  //
  // Module Body
  //

  always @(posedge clk_i)
    if (vreq_i) padr_o <= vadr_i; //TODO: actual translation


  //Insert state machine here
  always @(posedge clk_i)
    begin
        preq_o  <= vreq_i;
        psize_o <= vsize_i;
        plock_o <= vlock_i;
        pprot_o <= vprot_i;
        pwe_o   <= vwe_i;
    end


  //MMU does not write data
  always @(posedge clk_i)
    pd_o <= vd_i;


  //No page fault yet
  assign page_fault_o = 1'b0;

endmodule

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
  input  logic            vm_req_i,  //Request from CPU
  input  logic [XLEN-1:0] vm_adr_i,  //Virtual Memory Address
  input  biu_size_t       vm_size_i,
  input  logic            vm_lock_i,
  input  logic            vm_we_i,
  input  logic [XLEN-1:0] vm_d_i,

  //Memory system side
  output logic            pm_req_o,
  output logic [PLEN-1:0] pm_adr_o,  //Physical Memory Address
  output biu_size_t       pm_size_o,
  output logic            pm_lock_o,
  output logic            pm_we_o,
  output logic [XLEN-1:0] pm_d_o,
  input  logic [XLEN-1:0] pm_q_i,
  input  logic            pm_ack_i  
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
    if (vm_req_i) pm_adr_o <= vm_adr_i; //TODO: actual translation


  //Insert state machine here
  always @(posedge clk_i)
    begin
        pm_req_o  <= vm_req_i;
        pm_size_o <= vm_size_i;
        pm_lock_o <= vm_lock_i;
        pm_we_o   <= vm_we_i;
    end


  //MMU does not write data
  always @(posedge clk_i)
    pm_d_o    <= vm_d_i;

endmodule

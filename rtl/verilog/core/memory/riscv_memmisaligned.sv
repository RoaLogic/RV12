/////////////////////////////////////////////////////////////////////
//   ,------.                    ,--.                ,--.          //
//   |  .--. ' ,---.  ,--,--.    |  |    ,---. ,---. `--' ,---.    //
//   |  '--'.'| .-. |' ,-.  |    |  |   | .-. | .-. |,--.| .--'    //
//   |  |\  \ ' '-' '\ '-'  |    |  '--.' '-' ' '-' ||  |\ `--.    //
//   `--' '--' `---'  `--`--'    `-----' `---' `-   /`--' `---'    //
//                                             `---'               //
//    RISC-V                                                       //
//    Misalignment Check                                           //
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
////////////////////////////////////////////////////////////////////

import biu_constants_pkg::*;

module riscv_memmisaligned #(
  parameter PLEN    = 32,
  parameter HAS_RVC = 0
)
(
  input  logic              clk_i,
  input  logic              stall_i,

  //CPU side
  input  logic              instruction_i,
  input  logic [PLEN  -1:0] adr_i,
  input  biu_size_t         size_i,

  //To memory subsystem
  output logic              misaligned_o
);
  //////////////////////////////////////////////////////////////////
  //
  // Module Body
  //
  always @(posedge clk_i)
    if (!stall_i)
      if (instruction_i)
        misaligned_o = (HAS_RVC != 0) ? adr_i[0] : |adr_i[1:0];
      else
        unique case (size_i)
          BYTE   : misaligned_o = 1'b0;
          HWORD  : misaligned_o =  adr_i[  0];
          WORD   : misaligned_o = |adr_i[1:0];
          DWORD  : misaligned_o = |adr_i[2:0];
          default: misaligned_o = 1'b1;
        endcase
endmodule


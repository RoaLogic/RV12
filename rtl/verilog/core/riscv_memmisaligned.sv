/////////////////////////////////////////////////////////////////
//                                                             //
//    ██████╗  ██████╗  █████╗                                 //
//    ██╔══██╗██╔═══██╗██╔══██╗                                //
//    ██████╔╝██║   ██║███████║                                //
//    ██╔══██╗██║   ██║██╔══██║                                //
//    ██║  ██║╚██████╔╝██║  ██║                                //
//    ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═╝                                //
//          ██╗      ██████╗  ██████╗ ██╗ ██████╗              //
//          ██║     ██╔═══██╗██╔════╝ ██║██╔════╝              //
//          ██║     ██║   ██║██║  ███╗██║██║                   //
//          ██║     ██║   ██║██║   ██║██║██║                   //
//          ███████╗╚██████╔╝╚██████╔╝██║╚██████╗              //
//          ╚══════╝ ╚═════╝  ╚═════╝ ╚═╝ ╚═════╝              //
//                                                             //
//    RISC-V                                                   //
//    Check if memory is aligned                               //
//                                                             //
/////////////////////////////////////////////////////////////////
//                                                             //
//             Copyright (C) 2014-2017 ROA Logic BV            //
//             www.roalogic.com                                //
//                                                             //
//    Unless specifically agreed in writing, this software is  //
//  licensed under the RoaLogic Non-Commercial License         //
//  version-1.0 (the "License"), a copy of which is included   //
//  with this file or may be found on the RoaLogic website     //
//  http://www.roalogic.com. You may not use the file except   //
//  in compliance with the License.                            //
//                                                             //
//    THIS SOFTWARE IS PROVIDED "AS IS" AND WITHOUT ANY        //
//  EXPRESS OF IMPLIED WARRANTIES OF ANY KIND.                 //
//  See the License for permissions and limitations under the  //
//  License.                                                   //
//                                                             //
/////////////////////////////////////////////////////////////////

module riscv_memmisaligned #(
  parameter XLEN = 32
)
(
  input                   rstn,
  input                   clk,
 
  //CPU side
  input                   mem_req,
  input      [XLEN  -1:0] mem_adr,
  input      [       2:0] mem_size,
  output reg              mem_misaligned,

  //To Upper layer
  output reg              is_misaligned
);
  //////////////////////////////////////////////////////////////////
  //
  // Module Body
  //
generate
  if (XLEN == 32)
    always_comb
    case (mem_size)
      BYTE   : is_misaligned = 1'b0;
      HWORD  : is_misaligned =  mem_adr[  0];
      WORD   : is_misaligned = |mem_adr[1:0];
      default: is_misaligned = 1'b1;
    endcase

  if (XLEN == 64)
    always_comb
    case (mem_size)
      BYTE   : is_misaligned = 1'b0;
      HWORD  : is_misaligned =  mem_adr[  0];
      WORD   : is_misaligned = |mem_adr[1:0];
      DWORD  : is_misaligned = |mem_adr[2:0];
      default: is_misaligned = 1'b1;
    endcase
endgenerate


  always @(posedge clk)
    if (mem_req) mem_misaligned <= is_misaligned;
    else         mem_misaligned <= 1'b0;
endmodule


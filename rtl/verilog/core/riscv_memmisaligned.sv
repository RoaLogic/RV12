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
  input      [XLEN/8-1:0] mem_be,
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
    case (mem_be)
      4'b0001: is_misaligned = 1'b0;
      4'b0010: is_misaligned = 1'b0;
      4'b0100: is_misaligned = 1'b0;
      4'b1000: is_misaligned = 1'b0;
      4'b0011: is_misaligned =  mem_adr[  0];
      4'b1100: is_misaligned =  mem_adr[  0];
      4'b1111: is_misaligned = |mem_adr[1:0];
      default: is_misaligned = 1'b1;
    endcase

  if (XLEN == 64)
    always_comb
    case (mem_be)
      8'b0000_0001: is_misaligned = 1'b0;
      8'b0000_0010: is_misaligned = 1'b0;
      8'b0000_0100: is_misaligned = 1'b0;
      8'b0000_1000: is_misaligned = 1'b0;
      8'b0001_0000: is_misaligned = 1'b0;
      8'b0010_0000: is_misaligned = 1'b0;
      8'b0100_0000: is_misaligned = 1'b0;
      8'b1000_0000: is_misaligned = 1'b0;
      8'b0000_0011: is_misaligned =  mem_adr[  0];
      8'b0000_1100: is_misaligned =  mem_adr[  0];
      8'b0011_0000: is_misaligned =  mem_adr[  0];
      8'b1100_0000: is_misaligned =  mem_adr[  0];
      8'b0000_1111: is_misaligned = |mem_adr[1:0];
      8'b1111_0000: is_misaligned = |mem_adr[1:0];
      8'b1111_1111: is_misaligned = |mem_adr[2:0];
      default     : is_misaligned = 1'b1;
    endcase
endgenerate


  always @(posedge clk)
    if (mem_req) mem_misaligned <= is_misaligned;
    else         mem_misaligned <= 1'b0;
endmodule


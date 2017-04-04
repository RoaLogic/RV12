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
//    Register FIle                                            //
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

module riscv_rf #(
  parameter XLEN    = 32,
  parameter RDPORTS = 2,
  parameter WRPORTS = 1,


  parameter AR_BITS=5
//  localparam AR_BITS=5
)
(
  input                rstn,
  input                clk,

  //Register File read
  input  [AR_BITS-1:0] rf_src1  [RDPORTS],
  input  [AR_BITS-1:0] rf_src2  [RDPORTS],
  output [XLEN   -1:0] rf_srcv1 [RDPORTS],
  output [XLEN   -1:0] rf_srcv2 [RDPORTS],

  //Register File write
  input  [AR_BITS-1:0] rf_dst   [WRPORTS],
  input  [XLEN   -1:0] rf_dstv  [WRPORTS],
  input  [WRPORTS-1:0] rf_we,

  //Debug Interface
  input                du_stall,
                       du_we_rf,
  input  [XLEN   -1:0] du_dato,   //output from debug unit
  output [XLEN   -1:0] du_dati_rf,
  input  [       11:0] du_addr
);

/////////////////////////////////////////////////////////////////
//
// Variables
//

//Actual register file
logic [XLEN-1:0] rf [32];

//read data from register file
logic            src1_is_x0 [RDPORTS],
                 src2_is_x0 [RDPORTS];
logic [XLEN-1:0] dout1 [RDPORTS],
                 dout2 [RDPORTS];

//variable for generates
genvar i;


/////////////////////////////////////////////////////////////////
//
// Module Body
//


//Reads are asynchronous
generate
  for(i=0; i<RDPORTS; i=i+1)
  begin: xreg_rd
     //per Altera's recommendations. Prevents bypass logic
     always @(posedge clk) dout1[i] <= rf[ rf_src1[i] ];
     always @(posedge clk) dout2[i] <= rf[ rf_src2[i] ];

     //got data from RAM, now handle X0
     always @(posedge clk) src1_is_x0[i] <= ~|rf_src1[i];
     always @(posedge clk) src2_is_x0[i] <= ~|rf_src2[i];

     assign rf_srcv1[i] = src1_is_x0[i] ? {XLEN{1'b0}} : dout1[i];
     assign rf_srcv2[i] = src2_is_x0[i] ? {XLEN{1'b0}} : dout2[i];

  end
endgenerate

//TODO: For the Debug Unit ... mux with port0
assign du_dati_rf = |du_addr[AR_BITS-1:0] ? rf[ du_addr[AR_BITS-1:0] ] : {XLEN{1'b0}};


//Writes are synchronous
generate
  for(i=0; i<WRPORTS; i=i+1)
  begin: xreg_wr
      always @(posedge clk)
        if      ( du_we_rf ) rf[ du_addr[AR_BITS-1:0] ] <= du_dato;
        else if ( rf_we[i] ) rf[ rf_dst[i]            ] <= rf_dstv[i];
  end
endgenerate

endmodule


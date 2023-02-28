/////////////////////////////////////////////////////////////////////
//   ,------.                    ,--.                ,--.          //
//   |  .--. ' ,---.  ,--,--.    |  |    ,---. ,---. `--' ,---.    //
//   |  '--'.'| .-. |' ,-.  |    |  |   | .-. | .-. |,--.| .--'    //
//   |  |\  \ ' '-' '\ '-'  |    |  '--.' '-' ' '-' ||  |\ `--.    //
//   `--' '--' `---'  `--`--'    `-----' `---' `-   /`--' `---'    //
//                                             `---'               //
//    RISC-V                                                       //
//    Register Stage                                               //
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
/////////////////////////////////////////////////////////////////////

module riscv_rf
import riscv_opcodes_pkg::*;
#(
  parameter XLEN      = 32,
  parameter REGOUT    = 0
)
(
  input                      rst_ni,
  input                      clk_i,

  //Register File read
  input        rsd_t         rf_src1_i,
  input        rsd_t         rf_src2_i,
  output logic [XLEN   -1:0] rf_src1_q_o,
  output logic [XLEN   -1:0] rf_src2_q_o,

  //Register File write
  input        rsd_t         rf_dst_i,
  input        [XLEN   -1:0] rf_dst_d_i,
  input                      rf_we_i,
  input                      pd_stall_i,
                             id_stall_i,

  //Debug Interface
  input                      du_re_rf_i,
                             du_we_rf_i,
  input        [XLEN   -1:0] du_d_i,   //output from debug unit
  output logic [XLEN   -1:0] du_rf_q_o,
  input        [       11:0] du_addr_i
);

/////////////////////////////////////////////////////////////////
//
// Variables
//

//Actual register file
//Need to figure out if an array of rsd_t is actually allowed
logic [XLEN-1:0] rf [32];

rsd_t            src1,
                 src2;

//read data from register file
logic [XLEN-1:0] rfout1,
                 rfout2;

//Exceptions
logic            src1_is_x0,
	         src2_is_x0,
                 dst_is_src1,
                 dst_is_src2;
logic [XLEN-1:0] dout1,
                 dout2;

logic            du_re_rf_dly;


/////////////////////////////////////////////////////////////////
//
// Module Body
//

  //delay du_stall signal, to ensure src1 reaches RF before du_stall takes over
  always @(posedge clk_i)
    du_re_rf_dly <= du_re_rf_i;


  //Use traditional registered memory description to ensure that writes to RF
  //during a stall are handled

  //register read port
  always @(posedge clk_i) if      ( du_re_rf_i) src1 <= rsd_t'(du_addr_i[4:0]);
                          else if (!pd_stall_i) src1 <= rf_src1_i;
  always @(posedge clk_i) if      (!pd_stall_i) src2 <= rf_src2_i;


  //RW contention
  assign dst_is_src1 = rf_dst_i == src1;
  assign dst_is_src2 = rf_dst_i == src2;


  //register file access
  assign rfout1 = rf[ src1 ];
  assign rfout2 = rf[ src2 ];

 
  //got data from RAM, now handle X0
  always @(posedge clk_i) if (!pd_stall_i) src1_is_x0  <= ~|rf_src1_i;
  always @(posedge clk_i) if (!pd_stall_i) src2_is_x0  <= ~|rf_src2_i;

  always_comb
    casex (src1_is_x0)
      1'b1: dout1 = {XLEN{1'b0}};
      1'b0: dout1 = rfout1;
    endcase

  always_comb
    casex (src2_is_x0)
      1'b1: dout2 = {XLEN{1'b0}};
      1'b0: dout2 = rfout2;
    endcase


  if (REGOUT > 0)
  begin
      always @(posedge clk_i) if (!id_stall_i) rf_src1_q_o <= dout1;
      always @(posedge clk_i) if (!id_stall_i) rf_src2_q_o <= dout2;
  end
  else
  begin
      assign rf_src1_q_o = dout1;
      assign rf_src2_q_o = dout2;
  end


//Debug Unit output
always @(posedge clk_i)
  if (du_re_rf_dly) du_rf_q_o <= ~|src1 ? 'h0 : rfout1;



//Writes are synchronous
  always @(posedge clk_i)
    if      ( du_we_rf_i ) rf[ du_addr_i[4:0] ] <= du_d_i;
    else if ( rf_we_i    ) rf[ rf_dst_i       ] <= rf_dst_d_i;

endmodule


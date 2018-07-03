/////////////////////////////////////////////////////////////////////
//   ,------.                    ,--.                ,--.          //
//   |  .--. ' ,---.  ,--,--.    |  |    ,---. ,---. `--' ,---.    //
//   |  '--'.'| .-. |' ,-.  |    |  |   | .-. | .-. |,--.| .--'    //
//   |  |\  \ ' '-' '\ '-'  |    |  '--.' '-' ' '-' ||  |\ `--.    //
//   `--' '--' `---'  `--`--'    `-----' `---' `-   /`--' `---'    //
//                                             `---'               //
//    RISC-V                                                       //
//    Data External Access Logic                                   //
//                                                                 //
/////////////////////////////////////////////////////////////////////
//                                                                 //
//             Copyright (C) 2014-2018 ROA Logic BV                //
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

module riscv_dext #(
  parameter XLEN = 32,
  parameter PLEN = XLEN
)
(
  input                  rst_ni,
  input                  clk_i,
 
  //CPU side
  input                  mem_req_i,
  input      [XLEN -1:0] mem_adr_i,
  input  biu_size_t      mem_size_i,
  input  biu_type_t      mem_type_i,
  input                  mem_lock_i,
  input  biu_prot_t      mem_prot_i,
  input                  mem_we_i,
  input      [XLEN -1:0] mem_d_i,
  output reg [XLEN -1:0] mem_q_o,
  output reg             mem_ack_o,
  output reg             mem_err_o,

  //To BIU
  output                 biu_stb_o,
  input                  biu_stb_ack_i,
  output     [PLEN -1:0] biu_adri_o,
  output biu_size_t      biu_size_o,     //transfer size
  output biu_type_t      biu_type_o,     //burst type
  output                 biu_lock_o,
  output biu_prot_t      biu_prot_o,
  output                 biu_we_o,
  output     [XLEN -1:0] biu_d_o,
  input      [XLEN -1:0] biu_q_i,
  input                  biu_ack_i,      //data acknowledge, 1 per data
                         biu_err_i       //data error
);

  //////////////////////////////////////////////////////////////////
  //
  // Constants
  //


  //////////////////////////////////////////////////////////////////
  //
  // Variables
  //
  logic              hold_mem_req;
  logic [XLEN  -1:0] hold_mem_adr,
                     hold_mem_d;
  biu_size_t         hold_mem_size;
  biu_type_t         hold_mem_type;
  biu_prot_t         hold_mem_prot;
  logic              hold_mem_lock;
  logic              hold_mem_we;


  //////////////////////////////////////////////////////////////////
  //
  // Module Body
  //

  /* Statemachine
   */
  always @(posedge clk_i)
    if (mem_req_i)
    begin
        hold_mem_adr  <= mem_adr_i;
        hold_mem_size <= mem_size_i;
        hold_mem_type <= mem_type_i;
        hold_mem_lock <= mem_lock_i;
        hold_mem_we   <= mem_we_i;
        hold_mem_d    <= mem_d_i;
    end


  always @(posedge clk_i)
    if (!rst_ni) hold_mem_req <= 1'b0;
    else         hold_mem_req <= (mem_req_i | hold_mem_req) & ~biu_stb_ack_i;


  /* External Interface
   */
  assign biu_stb_o   = (mem_req_i | hold_mem_req);
  assign biu_adri_o  = hold_mem_req ? hold_mem_adr  : mem_adr_i;
  assign biu_size_o  = hold_mem_req ? hold_mem_size : mem_size_i;
  assign biu_lock_o  = hold_mem_req ? hold_mem_lock : mem_lock_i;
  assign biu_prot_o  = hold_mem_req ? hold_mem_prot : mem_prot_i;
  assign biu_we_o    = hold_mem_req ? hold_mem_we   : mem_we_i;
  assign biu_d_o     = hold_mem_req ? hold_mem_d    : mem_d_i;
  assign biu_type_o  = hold_mem_req ? hold_mem_type : mem_type_i;

  assign mem_q_o   = biu_q_i;
  assign mem_ack_o = biu_ack_i;
  assign mem_err_o = biu_err_i;
endmodule



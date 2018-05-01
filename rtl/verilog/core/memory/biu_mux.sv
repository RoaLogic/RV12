/////////////////////////////////////////////////////////////////////
//   ,------.                    ,--.                ,--.          //
//   |  .--. ' ,---.  ,--,--.    |  |    ,---. ,---. `--' ,---.    //
//   |  '--'.'| .-. |' ,-.  |    |  |   | .-. | .-. |,--.| .--'    //
//   |  |\  \ ' '-' '\ '-'  |    |  '--.' '-' ' '-' ||  |\ `--.    //
//   `--' '--' `---'  `--`--'    `-----' `---' `-   /`--' `---'    //
//                                             `---'               //
//    Simple Bus-Interface-Unit Mux                                //
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

/*
 * Memory Access Multiplexer
 * Switched 'PORTS' input BIUs onto single output BIU
 * Only one input port can be active at the same time
 */

import biu_constants_pkg::*;

module biu_mux #(
  parameter ADDR_SIZE   = 32,
  parameter DATA_SIZE   = 32,
  parameter PORTS       = 2,
  parameter QUEUE_DEPTH = 2
)
(
  input                      rst_ni,
  input                      clk_i,
 
  //Input Ports
  input                      biu_stb_i     [PORTS], //access request strobe
  output                     biu_stb_ack_o [PORTS], //biu access strobe response
  output                     biu_d_ack_o   [PORTS], //biu data request, used for pipelined buses
  input      [ADDR_SIZE-1:0] biu_adri_i    [PORTS], //access start address
  output     [ADDR_SIZE-1:0] biu_adro_o    [PORTS], //biu response address
  input      biu_size_t      biu_size_i    [PORTS], //access data size
  input      biu_type_t      biu_type_i    [PORTS], //access burst type
  input                      biu_lock_i    [PORTS], //access locked access
  input      biu_prot_t      biu_prot_i    [PORTS], //access protection
  input                      biu_we_i      [PORTS], //access write enable
  input      [DATA_SIZE-1:0] biu_d_i       [PORTS], //access write data
  output     [DATA_SIZE-1:0] biu_q_o       [PORTS], //access read data
  output                     biu_ack_o     [PORTS], //transfer acknowledge
                             biu_err_o     [PORTS], //access error

  //Output (to BIU)
  output                     biu_stb_o,             //BIU strobe
  input                      biu_stb_ack_i,         //BIU strobe ackowledge
  input                      biu_d_ack_i,           //BIU requests new data (biu_d_i)
  output     [ADDR_SIZE-1:0] biu_adri_o,            //address into BIU
  input      [ADDR_SIZE-1:0] biu_adro_i,            //biu response address
  output     biu_size_t      biu_size_o,            //transfer size
  output     biu_type_t      biu_type_o,            //burst type
  output                     biu_lock_o,
  output     biu_prot_t      biu_prot_o,
  output                     biu_we_o,
  output     [DATA_SIZE-1:0] biu_d_o,               //data into BIU
  input      [DATA_SIZE-1:0] biu_q_i,               //data from BIU
  input                      biu_ack_i,             //transfer acknowledge
                             biu_err_i              //data error
);

  //////////////////////////////////////////////////////////////////
  //
  // Constants
  //
  localparam PORT_SIZE = PORTS==0 ? 1 : $clog2(PORTS-1);


  //////////////////////////////////////////////////////////////////
  //
  // Functions
  //
  function automatic port_select;
    input req[PORTS];

    //default port
    port_select = 0;

    //check other ports
    for (int n=0; n < PORTS; n++)
      if (req[n]) port_select = n;
  endfunction: port_select


  function automatic bor;
    input a [PORTS];

    bor = 1'b0;

    for (int p=0; p < PORTS; p++)
      bor |= a[p];
  endfunction: bor


  //////////////////////////////////////////////////////////////////
  //
  // Variables
  //
  logic [PORT_SIZE-1:0] access_port,
                        response_port;

  genvar p;


  //////////////////////////////////////////////////////////////////
  //
  // Module Body
  //

//whichever stb is assigned is given access
//biu responds with biu_stb_ack to indicate it can start a new transfer (another one might be in flight)
//store access for response (biu_ack). Response may come simultaneously with stb_ack

  /* Access/response port
   */
  assign access_port = port_select(biu_stb_i);


  always @(posedge clk_i)
    if (biu_stb_o) response_port <= access_port;


  /* basic assignments
   */
  assign biu_stb_o  = bor(biu_stb_i);
  assign biu_adri_o = biu_adri_i [ access_port ];
  assign biu_size_o = biu_size_i [ access_port ];
  assign biu_type_o = biu_type_i [ access_port ];
  assign biu_lock_o = biu_lock_i [ access_port ];
  assign biu_prot_o = biu_prot_i [ access_port ];
  assign biu_we_o   = biu_we_i   [ access_port ];
  assign biu_d_o    = biu_d_i    [ access_port ];


  //generate port signals
generate
  for (p=0; p < PORTS; p++)
  begin: port
      assign biu_stb_ack_o[p] = (p == access_port) & biu_stb_ack_i;
      assign biu_d_ack_o  [p] = (p == access_port) & biu_d_ack_i;
      assign biu_adro_o   [p] = biu_adro_i;
      assign biu_q_o      [p] = biu_q_i;
      assign biu_ack_o    [p] = (p == response_port) & biu_ack_i;
      assign biu_err_o    [p] = (p == response_port) & biu_err_i;
  end
endgenerate

endmodule



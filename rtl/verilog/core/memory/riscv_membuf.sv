/////////////////////////////////////////////////////////////////////
//   ,------.                    ,--.                ,--.          //
//   |  .--. ' ,---.  ,--,--.    |  |    ,---. ,---. `--' ,---.    //
//   |  '--'.'| .-. |' ,-.  |    |  |   | .-. | .-. |,--.| .--'    //
//   |  |\  \ ' '-' '\ '-'  |    |  '--.' '-' ' '-' ||  |\ `--.    //
//   `--' '--' `---'  `--`--'    `-----' `---' `-   /`--' `---'    //
//                                             `---'               //
//    RISC-V                                                       //
//    Memory Access Buffer                                         //
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

/* Buffer memory access
 * Temporary buffer, in case previous access didn't finish yet
 */

import biu_constants_pkg::*;

module riscv_membuf #(
  parameter DEPTH = 2,
  parameter DBITS = 32
)
(
  input  logic             rst_ni,
  input  logic             clk_i,

  input  logic             clr_i,  //clear pending requests
  input  logic             ena_i,

  //CPU side
  input  logic             req_i,
  input  logic [DBITS-1:0] d_i,

  //Memory system side
  output logic             req_o,
  input  logic             ack_i,
  output logic [DBITS-1:0] q_o,

  output logic             empty_o,
                           full_o
);

  //////////////////////////////////////////////////////////////////
  //
  // Variables
  //
  logic [DBITS      -1:0] queue_q;
  logic                   queue_we,
                          queue_re;

  logic [$clog2(DEPTH):0] access_pending;


  //////////////////////////////////////////////////////////////////
  //
  // Module Body
  //

  // Instantiate Queue 
  rl_queue #(
    .DEPTH ( DEPTH ),
    .DBITS ( DBITS )
  )
  rl_queue_inst (
    .rst_ni         ( rst_ni    ),
    .clk_i          ( clk_i     ),
    .clr_i          ( clr_i     ),
    .ena_i          ( ena_i     ),
    .we_i           ( queue_we  ),
    .d_i            ( d_i       ),
    .re_i           ( queue_re  ),
    .q_o            ( queue_q   ),
    .empty_o        ( empty_o   ),
    .full_o         ( full_o    ),
    .almost_empty_o (           ),
    .almost_full_o  (           )
  );


  //control signals
  always @(posedge clk_i, negedge rst_ni)
    if      (!rst_ni) access_pending <= 'h0;
    else if ( clr_i ) access_pending <= 'h0;
    else if ( ena_i )
      unique case ( {req_i,ack_i} )
         2'b01  : access_pending--;
         2'b10  : access_pending++;
         default: ; //do nothing
      endcase


  assign queue_we = |access_pending & (req_i & ~(empty_o & ack_i));
  assign queue_re = ack_i & ~empty_o;


  //queue outputs
  assign req_o = ~|access_pending ?  req_i & ~clr_i
                                  : (req_i | ~empty_o) & ack_i & ena_i & ~clr_i;

  assign q_o = empty_o ? d_i : queue_q;

endmodule

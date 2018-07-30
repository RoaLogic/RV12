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
  parameter XLEN        = 32,
  parameter QUEUE_DEPTH = 2
)
(
  input  logic            rst_ni,
  input  logic            clk_i,

  input  logic            clr_i,  //clear pending requests
  input  logic            ena_i,

  //CPU side
  input  logic            req_i,
  input  logic [XLEN-1:0] adr_i,
  input  biu_size_t       size_i,
  input  logic            lock_i,
  input  logic            we_i,
  input  logic [XLEN-1:0] d_i,


  //Memory system side
  output logic            req_o,
  output logic [XLEN-1:0] adr_o,
  output biu_size_t       size_o,
  output logic            lock_o,
  output logic            we_o,
  output logic [XLEN-1:0] d_o,
  input  logic            ack_i
);

  //////////////////////////////////////////////////////////////////
  //
  // Typedefs
  //
  typedef struct packed {
    logic [XLEN     -1:0] addr;
    biu_size_t            size;
    logic                 lock;
    logic                 we;
    logic [XLEN     -1:0] data;
  } queue_t;


  //////////////////////////////////////////////////////////////////
  //
  // Variables
  //
  queue_t                         queue_d,
                                  queue_q;
  logic                           queue_we,
                                  queue_re,
                                  queue_empty,
                                  queue_full;

  logic [$clog2(QUEUE_DEPTH)  :0] access_pending;


  //////////////////////////////////////////////////////////////////
  //
  // Module Body
  //

  //Queue Input Data
  assign queue_d.addr = adr_i;
  assign queue_d.size = size_i;
  assign queue_d.lock = lock_i;
  assign queue_d.we   = we_i;
  assign queue_d.data = d_i;


  // Instantiate Queue 
  rl_queue #(
    .DEPTH ( QUEUE_DEPTH    ),
    .DBITS ( $bits(queue_d) )
  )
  rl_queue_inst (
    .rst_ni  ( rst_ni      ),
    .clk_i   ( clk_i       ),
    .clr_i   ( clr_i       ),
    .ena_i   ( ena_i       ),
    .we_i    ( queue_we    ),
    .d_i     ( queue_d     ),
    .re_i    ( queue_re    ),
    .q_o     ( queue_q     ),
    .empty_o ( queue_empty ),
    .full_o  ( queue_full  )
  );


  //control signals
  always @(posedge clk_i, negedge rst_ni)
    if      (!rst_ni) access_pending <= 1'b0;
    else if ( clr_i ) access_pending <= 1'b0;
    else if ( ena_i )
      unique case ( {req_i,ack_i} )
         2'b01  : access_pending--;
         2'b10  : access_pending++;
         default: ; //do nothing
      endcase


  assign queue_we = |access_pending & (req_i & ~(queue_empty & ack_i));
  assign queue_re = ack_i & ~queue_empty;


  //queue outputs
  assign req_o = ~|access_pending ?  req_i 
                                  : (req_i | ~queue_empty) & ack_i & ena_i;
  assign adr_o  = queue_empty ? adr_i  : queue_q.addr;
  assign size_o = queue_empty ? size_i : queue_q.size;
  assign lock_o = queue_empty ? lock_i : queue_q.lock;
  assign we_o   = queue_empty ? we_i   : queue_q.we;
  assign d_o    = queue_empty ? d_i    : queue_q.data;

endmodule

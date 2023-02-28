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

module riscv_membuf
import biu_constants_pkg::*;
#(
  parameter DEPTH = 2,
  parameter XLEN  = 32
)
(
  input  logic             rst_ni,
  input  logic             clk_i,

  input  logic             flush_i,  //clear pending requests
  input  logic             stall_i,

  //CPU side
  input  logic             req_i,
  input  logic [XLEN -1:0] adr_i,
  input  biu_size_t        size_i,
  input  logic             lock_i,
  input  biu_prot_t        prot_i,
  input  logic             we_i,
  input  logic [XLEN -1:0] d_i,

  input  logic             cm_clean_i,
  input  logic             cm_invalidate_i,

  //Memory system side
  output logic             req_o,
  input  logic             ack_i,
  output logic [XLEN -1:0] adr_o,
  output biu_size_t        size_o,
  output logic             lock_o,
  output biu_prot_t        prot_o,
  output logic             we_o,
  output logic [XLEN -1:0] q_o,

  output logic             cm_clean_o,
  output logic             cm_invalidate_o,

  output logic             empty_o,
  output logic             full_o
);

  //////////////////////////////////////////////////////////////////
  //
  // Typedefs
  //
  typedef struct packed {
    logic             req;
    logic [XLEN -1:0] adr;
    biu_size_t        size;
    logic             lock;
    biu_prot_t        prot;
    logic             we;
    logic [XLEN -1:0] d;

    logic             cm_clean;
    logic             cm_invalidate;
  } queue_t;


  //////////////////////////////////////////////////////////////////
  //
  // Variables
  //
  queue_t                 queue_d,
                          queue_q;
  logic                   queue_we,
                          queue_re;

  logic [$clog2(DEPTH):0] access_pending;


  //////////////////////////////////////////////////////////////////
  //
  // Module Body
  //

  // Assign queue-data
  assign queue_d.req           = req_i;
  assign queue_d.adr           = adr_i;
  assign queue_d.size          = size_i;
  assign queue_d.lock          = lock_i;
  assign queue_d.prot          = prot_i;
  assign queue_d.we            = we_i;
  assign queue_d.d             = d_i;
  assign queue_d.cm_clean      = cm_clean_i;
  assign queue_d.cm_invalidate = cm_invalidate_i;


  // Instantiate Queue 
  rl_queue #(
    .DEPTH ( DEPTH          ),
    .DBITS ( $bits(queue_t) )
  )
  rl_queue_inst (
    .rst_ni         ( rst_ni    ),
    .clk_i          ( clk_i     ),
    .clr_i          ( flush_i   ),
    .ena_i          ( 1'b1      ),
    .we_i           ( queue_we  ),
    .d_i            ( queue_d   ),
    .re_i           ( queue_re  ),
    .q_o            ( queue_q   ),
    .empty_o        ( empty_o   ),
    .full_o         ( full_o    ),
    .almost_empty_o (           ),
    .almost_full_o  (           )
  );


  //control signals
  always @(posedge clk_i, negedge rst_ni)
    if      (!rst_ni  ) access_pending <= 'h0;
    else if ( flush_i ) access_pending <= 'h0;
    else //if (!stall_i )
      unique case ( {req_i, ~stall_i} )
         2'b01  : access_pending <= |access_pending ? access_pending -1 : 'h0;
         2'b10  : access_pending <= access_pending +1;
         default: ; //do nothing
      endcase


  assign queue_we = (req_i   &  (stall_i | |access_pending)) |
                    cm_clean_i | cm_invalidate_i;
  assign queue_re = ~empty_o & ~stall_i;


  //queue outputs
  assign req_o           = empty_o ? req_i           : queue_q.req;
  assign adr_o           = empty_o ? adr_i           : queue_q.adr;
  assign size_o          = empty_o ? size_i          : queue_q.size;
  assign lock_o          = empty_o ? lock_i          : queue_q.lock;
  assign prot_o          = empty_o ? prot_i          : queue_q.prot;
  assign we_o            = empty_o ? we_i            : queue_q.we;
  assign q_o             = empty_o ? d_i             : queue_q.d;
  assign cm_clean_o      = empty_o ? cm_clean_i      : queue_q.cm_clean;
  assign cm_invalidate_o = empty_o ? cm_invalidate_i : queue_q.cm_invalidate;
endmodule

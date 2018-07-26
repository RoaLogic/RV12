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
  input  logic            ack_i,


  //Control signals
  output logic            empty_o,
                          full_o
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
  queue_t                         queue_data[QUEUE_DEPTH];
  logic [$clog2(QUEUE_DEPTH)-1:0] queue_wadr;
  logic                           queue_we,
                                  queue_re,
                                  queue_empty,
                                  queue_full;

  logic [$clog2(QUEUE_DEPTH)  :0] access_pending;


  //////////////////////////////////////////////////////////////////
  //
  // Module Body
  //

  //----------------------------------------------------------------
  // Queue 
  //----------------------------------------------------------------
  always @(posedge clk_i,negedge rst_ni)
    if      (!rst_ni) queue_wadr <= 'h0;
    else if ( clr_i ) queue_wadr <= 'h0;
    else
      unique case ({queue_we,queue_re})
         2'b01 : queue_wadr <= queue_wadr -1;
         2'b10 : queue_wadr <= queue_wadr +1;
         default: ;
      endcase


  always @(posedge clk_i,negedge rst_ni)
    if (!rst_ni)
      for (int n=0; n<QUEUE_DEPTH; n++) queue_data[n] <= 'h0;
    else if (clr_i)
      for (int n=0; n<QUEUE_DEPTH; n++) queue_data[n] <= 'h0;
    else
    unique case ({queue_we,queue_re})
       2'b01  : begin
                    for (int n=0; n<QUEUE_DEPTH-1; n++)
                      queue_data[n] <= queue_data[n+1];

                    queue_data[QUEUE_DEPTH-1] <= 'h0;
                end

       2'b10  : begin
                    queue_data[queue_wadr].addr <= adr_i;
                    queue_data[queue_wadr].size <= size_i;
                    queue_data[queue_wadr].lock <= lock_i;
                    queue_data[queue_wadr].we   <= we_i;
                    queue_data[queue_wadr].data <= d_i;
                end

       2'b11  : begin
                    for (int n=0; n<QUEUE_DEPTH-1; n++)
                      queue_data[n] <= queue_data[n+1];

                    queue_data[QUEUE_DEPTH-1] <= 'h0;

                    queue_data[queue_wadr-1].addr <= adr_i;
                    queue_data[queue_wadr-1].size <= size_i;
                    queue_data[queue_wadr-1].lock <= lock_i;
                    queue_data[queue_wadr-1].we   <= we_i;
                    queue_data[queue_wadr-1].data <= d_i;
                end
       default: ;
    endcase


  always @(posedge clk_i, negedge rst_ni)
    if      (!rst_ni) queue_full <= 1'b0;
    else if ( clr_i ) queue_full <= 1'b0;
    else
      unique case ({queue_we,queue_re})
         2'b01  : queue_full <= 1'b0;
         2'b10  : queue_full <= (queue_wadr == QUEUE_DEPTH-1); //&queue_wadr;
         default: ;
      endcase

  always @(posedge clk_i, negedge rst_ni)
    if      (!rst_ni) queue_empty <= 1'b1;
    else if ( clr_i ) queue_empty <= 1'b1;
    else
      unique case ({queue_we,queue_re})
         2'b01  : queue_empty <= (queue_wadr == 1);
         2'b10  : queue_empty <= 1'b0;
         default: ;
      endcase


  //control signals
  always @(posedge clk_i, negedge rst_ni)
    if      (!rst_ni) access_pending <= 1'b0;
    else if ( clr_i ) access_pending <= 1'b0;
    else
      unique case ( {req_i,ack_i} )
         2'b01  : access_pending--;
         2'b10  : access_pending++;
         default: ; //do nothing
      endcase


  assign queue_we = |access_pending & (req_i & ~(queue_empty & ack_i));
  assign queue_re = ack_i & ~queue_empty;

  assign empty_o = queue_empty;
  assign full_o  = queue_full;


  //queue outputs
  assign req_o = ~|access_pending ?  req_i 
                                  : (req_i | ~queue_empty) & ack_i;
  assign adr_o  = queue_empty ? adr_i  : queue_data[0].addr;
  assign size_o = queue_empty ? size_i : queue_data[0].size;
  assign lock_o = queue_empty ? lock_i : queue_data[0].lock;
  assign we_o   = queue_empty ? we_i   : queue_data[0].we;
  assign d_o    = queue_empty ? d_i    : queue_data[0].data;

endmodule

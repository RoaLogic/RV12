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
//    Debug Controller Simulation Model                        //
//                                                             //
/////////////////////////////////////////////////////////////////
//                                                             //
//     Copyright (C) 2016 ROA Logic BV                         //
//                                                             //
//    This confidential and proprietary software is provided   //
//  under license. It may only be used as authorised by a      //
//  licensing agreement from ROA Logic BV.                     //
//  No parts may be copied, reproduced, distributed, modified  //
//  or adapted in any form without prior written consent.      //
//  This entire notice must be reproduced on all authorised    //
//  copies.                                                    //
//                                                             //
//    TO THE MAXIMUM EXTENT PERMITTED BY LAW, IN NO EVENT      //
//  SHALL ROA LOGIC BE LIABLE FOR ANY INDIRECT, SPECIAL,       //
//  CONSEQUENTIAL OR INCIDENTAL DAMAGES WHATSOEVER (INCLUDING, //
//  BUT NOT LIMITED TO, DAMAGES FOR LOSS OF PROFIT, BUSINESS   //
//  INTERRUPTIONS OR LOSS OF INFORMATION) ARISING OUT OF THE   //
//  USE OR INABILITY TO USE THE PRODUCT WHETHER BASED ON A     //
//  CLAIM UNDER CONTRACT, TORT OR OTHER LEGAL THEORY, EVEN IF  //
//  ROA LOGIC WAS ADVISED OF THE POSSIBILITY OF SUCH DAMAGES.  //
//  IN NO EVENT WILL ROA LOGIC BE LIABLE TO ANY AGGREGATED     //
//  CLAIMS MADE AGAINST ROA LOGIC GREATER THAN THE FEES PAID   //
//  FOR THE PRODUCT                                            //
//                                                             //
/////////////////////////////////////////////////////////////////

//  CVS Log
//
//  $Id: $
//
//  $Date: $
//  $Revision: $
//  $Author: $
//  $Locker:  $
//  $State: Exp $
//
// Change History:
//   $Log: $
//

module dbg_bfm #(
  parameter ADDR_WIDTH = 16,
  parameter DATA_WIDTH = 32
)
(
  input                       rstn,
  input                       clk,

  input                       cpu_bp_i,

  output                      cpu_stall_o,
  output reg                  cpu_stb_o,
  output reg                  cpu_we_o,
  output reg [ADDR_WIDTH-1:0] cpu_adr_o,
  output reg [DATA_WIDTH-1:0] cpu_dat_o,
  input      [DATA_WIDTH-1:0] cpu_dat_i,
  input                       cpu_ack_i
);
  ////////////////////////////////////////////////////////////////
  //
  // Typedefs
  //

  ////////////////////////////////////////////////////////////////
  //
  // Tasks
  //

  /*
   *
   */
  function is_stalled;
    is_stalled = stall_cpu;
  endfunction

  /*
   * Stall CPU
   */
  task stall;
    @(posedge clk);
    stall_cpu <= 1'b1;
  endtask

  /*
   * Unstall CPU
   */
  task unstall;
    @(posedge clk)
    stall_cpu <= 1'b0;
  endtask

  /*
   * Write to CPU (via DBG interface)
   */
  task write;
    input [ADDR_WIDTH-1:0] addr; //address to write to
    input [DATA_WIDTH-1:0] data; //data to write

    //setup DBG bus
    @(posedge clk);
    cpu_stb_o <= 1'b1;
    cpu_we_o  <= 1'b1;
    cpu_adr_o <= addr;
    cpu_dat_o <= data;

    //wait for ack
    while (!cpu_ack_i) @(posedge clk);

    //clear DBG bus
    cpu_stb_o <= 1'b0;
    cpu_we_o  <= 1'b0;
  endtask;

  /*
   * Read from CPU (via DBG interface)
   */
  task read;
    input  [ADDR_WIDTH-1:0] addr; //address to read from
    output [DATA_WIDTH-1:0] data; //data read from CPU

    //setup DBG bus
    @(posedge clk);
    cpu_stb_o <= 1'b1;
    cpu_we_o  <= 1'b0;
    cpu_adr_o <= addr;

    //wait for ack
    while (!cpu_ack_i) @(posedge clk);
    data = cpu_dat_i;

    //clear DBG bus
    cpu_stb_o <= 1'b0;
    cpu_we_o  <= 1'b0;
  endtask;


  ////////////////////////////////////////////////////////////////
  //
  // Variables
  //
  logic stall_cpu;


  ////////////////////////////////////////////////////////////////
  //
  // Module body
  //
  initial cpu_stb_o = 1'b0;


  assign cpu_stall_o = cpu_bp_i | stall_cpu;

  always @(posedge clk,negedge rstn)
    if      (!rstn    ) stall_cpu <= 1'b0;
    else if ( cpu_bp_i) stall_cpu <= 1'b1; //gets cleared by task unstall_cpu
endmodule

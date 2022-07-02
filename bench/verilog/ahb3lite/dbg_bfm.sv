/////////////////////////////////////////////////////////////////////
//   ,------.                    ,--.                ,--.          //
//   |  .--. ' ,---.  ,--,--.    |  |    ,---. ,---. `--' ,---.    //
//   |  '--'.'| .-. |' ,-.  |    |  |   | .-. | .-. |,--.| .--'    //
//   |  |\  \ ' '-' '\ '-'  |    |  '--.' '-' ' '-' ||  |\ `--.    //
//   `--' '--' `---'  `--`--'    `-----' `---' `-   /`--' `---'    //
//                                             `---'               //
//   Roa Logic RV12 RISC-V CPU                                     //
//   Debug Controller Simulation Model                             //
//                                                                 //
/////////////////////////////////////////////////////////////////////
//                                                                 //
//             Copyright (C) 2016-2021 ROA Logic BV                //
//             www.roalogic.com                                    //
//                                                                 //
//   This source file may be used and distributed without          //
//   restriction provided that this copyright statement is not     //
//   removed from the file and that any derivative work contains   //
//   the original copyright notice and the associated disclaimer.  //
//                                                                 //
//      THIS SOFTWARE IS PROVIDED ``AS IS'' AND WITHOUT ANY        //
//   EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED     //
//   TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS     //
//   FOR A PARTICULAR PURPOSE. IN NO EVENT SHALL THE AUTHOR OR     //
//   CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,  //
//   SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT  //
//   NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;  //
//   LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)      //
//   HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN     //
//   CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR  //
//   OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS          //
//   SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.  //
//                                                                 //
/////////////////////////////////////////////////////////////////////

// Change History:
//   2017-10-06: Changed header, logo, copyright notice
//               Moved stall_cpu declaration. Fixed QuestaSim bug
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
  // Variables
  //
  logic stall_cpu;


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
  // Module body
  //
  initial cpu_stb_o = 1'b0;


  assign cpu_stall_o = cpu_bp_i | stall_cpu;

  always @(posedge clk,negedge rstn)
    if      (!rstn    ) stall_cpu <= 1'b0;
    else if ( cpu_bp_i) stall_cpu <= 1'b1; //gets cleared by task unstall_cpu
endmodule

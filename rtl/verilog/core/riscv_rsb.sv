/////////////////////////////////////////////////////////////////////
//   ,------.                    ,--.                ,--.          //
//   |  .--. ' ,---.  ,--,--.    |  |    ,---. ,---. `--' ,---.    //
//   |  '--'.'| .-. |' ,-.  |    |  |   | .-. | .-. |,--.| .--'    //
//   |  |\  \ ' '-' '\ '-'  |    |  '--.' '-' ' '-' ||  |\ `--.    //
//   `--' '--' `---'  `--`--'    `-----' `---' `-   /`--' `---'    //
//                                             `---'               //
//    RISC-V                                                       //
//    Return Stack Buffer                                          //
//                                                                 //
/////////////////////////////////////////////////////////////////////
//                                                                 //
//             Copyright (C) 2022      ROA Logic BV                //
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


/* Hint are encoded in the 'rd' field; only push/pop RBS when rd=x1/x5
 * 
 * +-------+-------+--------+----------------+
 * |  rd   |  rs1  | rs1=rd | action         |
 * +-------+-------+--------+----------------+
 * | !link | !link |    -   | none           |
 * | !link |  link |    -   | pop            |
 * |  link | !link |    -   | push           |
 * |  link |  link |    0   | pop, then push |
 * |  link |  link |    1   | push           |
 * +-------+-------+--------+----------------+
 */


module riscv_rsb #(
  parameter XLEN  = 32,
  parameter DEPTH = 4
)
(
  input  logic            rst_ni,
  input  logic            clk_i,
  input  logic            ena_i,

  input  logic [XLEN-1:0] d_i,
  output logic [XLEN-1:0] q_o,
  input  logic            push_i,
  input  logic            pop_i,
  output logic            empty_o
);

  ////////////////////////////////////////////////////////////////
  //
  // Variables
  //
  logic [XLEN           -1:0] stack [DEPTH];
  logic [XLEN           -1:0] last_value;
  logic [$clog2(DEPTH+1)-1:0] cnt;


  ////////////////////////////////////////////////////////////////
  //
  // Module Body
  //


  /* Store last written value
   * When RSB is empty, return last written value
   */
  always @(posedge clk_i)
    if (ena_i && push_i) last_value <= d_i;


  /*
   * Store last read value
   */

  /* Actual stack
   */
  always @(posedge clk_i)
    if (ena_i)
    unique case ({push_i, pop_i})
      2'b01: for (int n=0; n < DEPTH-1; n++) stack[n] <= stack[n+1];
      2'b10: begin
                 stack[0] <= d_i;
                 for (int n=1; n < DEPTH; n++) stack[n] <= stack[n-1];
             end
      2'b11: stack[0] <= d_i;
      2'b00: ; //do nothing
    endcase


  /* Assign output
   */ 
  assign q_o = empty_o ? last_value : stack[0];


  /* Empty
   */
  always @(posedge clk_i, negedge rst_ni)
    if (!rst_ni) cnt <= 'h0;
    else if (ena_i)
    unique case ({push_i, pop_i})
      2'b01  : if (!empty_o    ) cnt <= cnt -1;
      2'b10  : if (cnt != DEPTH) cnt <= cnt +1;
      default: ; //do nothing
    endcase


  always @(posedge clk_i, negedge rst_ni)
    if (!rst_ni) empty_o <= 1'b1;
    else if (ena_i)
    unique case ({push_i, pop_i})
      2'b01  : empty_o <= cnt==1;
      2'b10  : empty_o <= 1'b0;
      default: ; //do nothing
    endcase


endmodule

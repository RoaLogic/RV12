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
//    Correlating Branch Prediction Unit                       //
//                                                             //
/////////////////////////////////////////////////////////////////
//                                                             //
//             Copyright (C) 2014-2017 ROA Logic BV            //
//             www.roalogic.com                                //
//                                                             //
//    Unless specifically agreed in writing, this software is  //
//  licensed under the RoaLogic Non-Commercial License         //
//  version-1.0 (the "License"), a copy of which is included   //
//  with this file or may be found on the RoaLogic website     //
//  http://www.roalogic.com. You may not use the file except   //
//  in compliance with the License.                            //
//                                                             //
//    THIS SOFTWARE IS PROVIDED "AS IS" AND WITHOUT ANY        //
//  EXPRESS OF IMPLIED WARRANTIES OF ANY KIND.                 //
//  See the License for permissions and limitations under the  //
//  License.                                                   //
//                                                             //
/////////////////////////////////////////////////////////////////


module riscv_bp #(
  parameter            XLEN              = 32,
  parameter [XLEN-1:0] PC_INIT           = 'h200,
  parameter            HAS_BPU           = 0,

  parameter            BP_GLOBAL_BITS    = 2,
  parameter            BP_LOCAL_BITS     = 10,
  parameter            BP_LOCAL_BITS_LSB = 2,                //LSB of if_nxt_pc to use

  parameter            TECHNOLOGY        = "GENERIC",
  parameter            AVOID_X           = 0
)
(
  input                       rstn,
  input                       clk,
 
  //Read side
  input                       id_stall,
  input  [XLEN          -1:0] if_parcel_pc,
  output [               1:0] bp_bp_predict,


  //Write side
  input  [XLEN          -1:0] ex_pc,
  input  [BP_GLOBAL_BITS-1:0] bu_bp_history,      //branch history
  input  [               1:0] bu_bp_predict,      //prediction bits for branch
  input                       bu_bp_btaken,
  input                       bu_bp_update
);


  //////////////////////////////////////////////////////////////////
  //
  // Variables
  //
  localparam ADR_BITS     = BP_GLOBAL_BITS + BP_LOCAL_BITS;
  localparam MEMORY_DEPTH = 1 << ADR_BITS;

  logic [ADR_BITS-1:0] radr,
                       wadr;

  logic [XLEN    -1:0] if_parcel_pc_dly;

  logic [         1:0] new_prediction;
  bit   [         1:0] old_prediction;


  //////////////////////////////////////////////////////////////////
  //
  // Module Body
  //

  always @(posedge clk,negedge rstn)
    if      (!rstn    ) if_parcel_pc_dly <= PC_INIT;
    else if (!id_stall) if_parcel_pc_dly <= if_parcel_pc;


  assign radr = id_stall ? {bu_bp_history, if_parcel_pc_dly[BP_LOCAL_BITS_LSB +: BP_LOCAL_BITS]}
                         : {bu_bp_history, if_parcel_pc    [BP_LOCAL_BITS_LSB +: BP_LOCAL_BITS]};
  assign wadr = {bu_bp_history, ex_pc[BP_LOCAL_BITS_LSB +: BP_LOCAL_BITS]};


  /*
   *  Calculate new prediction bits
   *
   *  00<-->01<-->11<-->10
   */
  assign new_prediction[0] = bu_bp_predict[1] ^ bu_bp_btaken;
  assign new_prediction[1] = (bu_bp_predict[1] & ~bu_bp_predict[0]) | (bu_bp_btaken & bu_bp_predict[0]);

  /*
   * Hookup 1R1W memory
   */
  rl_ram_1r1w #(
    .ABITS      ( ADR_BITS   ),
    .DBITS      ( 2          ),
    .TECHNOLOGY ( TECHNOLOGY ) )
  bp_ram_inst(
    .rstn  ( rstn            ),
    .clk   ( clk             ),
 
    //Write side
    .waddr ( wadr            ),
    .din   ( new_prediction  ),
    .we    ( bu_bp_update    ),
    .be    ( 1'b1            ),

    //Read side
    .raddr ( radr            ),
    .re    ( 1'b1            ),
    .dout  ( old_prediction  ) );

generate
  //synopsys translate_off
  if (AVOID_X)
     assign bp_bp_predict = (old_prediction == 2'bxx) ? $random : old_prediction;
  else
  //synopsys translate_on
     assign bp_bp_predict = old_prediction;
endgenerate

endmodule



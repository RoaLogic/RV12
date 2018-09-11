/////////////////////////////////////////////////////////////////////
//   ,------.                    ,--.                ,--.          //
//   |  .--. ' ,---.  ,--,--.    |  |    ,---. ,---. `--' ,---.    //
//   |  '--'.'| .-. |' ,-.  |    |  |   | .-. | .-. |,--.| .--'    //
//   |  |\  \ ' '-' '\ '-'  |    |  '--.' '-' ' '-' ||  |\ `--.    //
//   `--' '--' `---'  `--`--'    `-----' `---' `-   /`--' `---'    //
//                                             `---'               //
//    RISC-V                                                       //
//    Correlating Branch Prediction Unit                           //
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
  input                       rst_ni,
  input                       clk_i,
 
  //Read side
  input                       id_stall_i,
  input  [XLEN          -1:0] if_parcel_pc_i,
  output [               1:0] bp_bp_predict_o,


  //Write side
  input  [XLEN          -1:0] ex_pc_i,
  input  [BP_GLOBAL_BITS-1:0] bu_bp_history_i,      //branch history
  input  [               1:0] bu_bp_predict_i,      //prediction bits for branch
  input                       bu_bp_btaken_i,
  input                       bu_bp_update_i
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

  always @(posedge clk_i,negedge rst_ni)
    if      (!rst_ni    ) if_parcel_pc_dly <= PC_INIT;
    else if (!id_stall_i) if_parcel_pc_dly <= if_parcel_pc_i;


  assign radr = id_stall_i ? {bu_bp_history_i, if_parcel_pc_dly[BP_LOCAL_BITS_LSB +: BP_LOCAL_BITS]}
                           : {bu_bp_history_i, if_parcel_pc_i  [BP_LOCAL_BITS_LSB +: BP_LOCAL_BITS]};
  assign wadr = {bu_bp_history_i, ex_pc_i[BP_LOCAL_BITS_LSB +: BP_LOCAL_BITS]};


  /*
   *  Calculate new prediction bits
   *
   *  00<-->01<-->11<-->10
   */
  assign new_prediction[0] = bu_bp_predict_i[1] ^ bu_bp_btaken_i;
  assign new_prediction[1] = (bu_bp_predict_i[1] & ~bu_bp_predict_i[0]) | (bu_bp_btaken_i & bu_bp_predict_i[0]);

  /*
   * Hookup 1R1W memory
   */
  rl_ram_1r1w #(
    .ABITS      ( ADR_BITS   ),
    .DBITS      ( 2          ),
    .TECHNOLOGY ( TECHNOLOGY )
  )
  bp_ram_inst(
    .rst_ni  ( rst_ni         ),
    .clk_i   ( clk_i          ),
 
    //Write side
    .waddr_i ( wadr           ),
    .din_i   ( new_prediction ),
    .we_i    ( bu_bp_update_i ),
    .be_i    ( 1'b1           ),

    //Read side
    .raddr_i ( radr           ),
    .re_i    ( 1'b1           ),
    .dout_o  ( old_prediction )
  );

generate
  //synopsys translate_off
  if (AVOID_X)
     assign bp_bp_predict_o = (old_prediction == 2'bxx) ? $random : old_prediction;
  else
  //synopsys translate_on
     assign bp_bp_predict_o = old_prediction;
endgenerate

endmodule



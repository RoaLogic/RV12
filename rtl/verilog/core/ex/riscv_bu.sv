/////////////////////////////////////////////////////////////////////
//   ,------.                    ,--.                ,--.          //
//   |  .--. ' ,---.  ,--,--.    |  |    ,---. ,---. `--' ,---.    //
//   |  '--'.'| .-. |' ,-.  |    |  |   | .-. | .-. |,--.| .--'    //
//   |  |\  \ ' '-' '\ '-'  |    |  '--.' '-' ' '-' ||  |\ `--.    //
//   `--' '--' `---'  `--`--'    `-----' `---' `-   /`--' `---'    //
//                                             `---'               //
//    RISC-V                                                       //
//    Branch Unit                                                  //
//                                                                 //
/////////////////////////////////////////////////////////////////////
//                                                                 //
//             Copyright (C) 2014-2021 ROA Logic BV                //
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

import riscv_opcodes_pkg::*;
import riscv_state_pkg::*;

module riscv_bu #(
  parameter            XLEN           = 32,
  parameter [XLEN-1:0] PC_INIT        = 'h200,
  parameter            BP_GLOBAL_BITS = 2,
  parameter            HAS_RVC        = 0
)
(
  input                           rst_ni,
  input                           clk_i,

  input                           ex_stall_i,
  input                           st_flush_i,

  //Program counter
  input      [XLEN          -1:0] id_pc_i,
  output reg [XLEN          -1:0] bu_nxt_pc_o,
  output reg                      bu_flush_o,
                                  bu_cacheflush_o,
  input      [               1:0] id_bp_predict_i,
  output reg [               1:0] bu_bp_predict_o,
  output reg [BP_GLOBAL_BITS-1:0] bu_bp_history_o,
  output reg                      bu_bp_btaken_o,
  output reg                      bu_bp_update_o,

  //Instruction
  input  instruction_t            id_insn_i,

  input  exceptions_t             id_exceptions_i,
                                  ex_exceptions_i,
                                  mem_exceptions_i,
                                  wb_exceptions_i,
  output exceptions_t             bu_exceptions_o,

  //from ID
  input      [XLEN          -1:0] opA_i,
                                  opB_i,

  //Debug Unit
  input                           du_stall_i,
                                  du_flush_i,
  input                           du_we_pc_i,
  input      [XLEN          -1:0] du_dato_i,
  input      [              31:0] du_ie_i
);
  ////////////////////////////////////////////////////////////////
  //
  // Variables
  //
  localparam SBITS=$clog2(XLEN);

  opcR_t                   opcR;
  logic                    has_rvc;
  logic                    is_16bit_instruction;
  logic                    misaligned_instruction;

  //Immediates
  immUJ_t                  immUJ;
  immSB_t                  immSB;
  logic [XLEN        -1:0] ext_immUJ,
                           ext_immSB;

  //Branch controls
  logic                    pipeflush,
                           cacheflush,
                           btaken,
                           bp_update;
  logic [BP_GLOBAL_BITS:0] bp_history;
  logic [XLEN        -1:0] nxt_pc,
                           du_nxt_pc;
  logic                    du_we_pc_i_dly,
                           du_wrote_pc;

  ////////////////////////////////////////////////////////////////
  //
  // Module Body
  //

  /*
   * Instruction
   */
  assign opcR    = decode_opcR(id_insn_i.instr);
  assign has_rvc = (HAS_RVC !=  0);
  assign is_16bit_instruction = ~&id_insn_i.instr[1:0];


  /*
   * Exceptions
   */
  always_comb
    casex ( {id_insn_i.bubble,id_insn_i.instr.R.opcode} )
      {1'b0,OPC_JALR  } : misaligned_instruction = id_exceptions_i.misaligned_instruction | has_rvc ? nxt_pc[0] : |nxt_pc[1:0];
      {1'b0,OPC_BRANCH} : misaligned_instruction = id_exceptions_i.misaligned_instruction | has_rvc ? nxt_pc[0] : |nxt_pc[1:0];
      default           : misaligned_instruction = id_exceptions_i.misaligned_instruction;
    endcase


  always @(posedge clk_i, negedge rst_ni)
    if      (!rst_ni    ) bu_exceptions_o    <= 'h0;
    else if (!ex_stall_i)
    begin
        if ( bu_flush_o || st_flush_i || 
             ex_exceptions_i.any || mem_exceptions_i.any || wb_exceptions_i.any  )
        begin
            bu_exceptions_o    <= 'h0;
        end
        else if (!du_stall_i)
        begin
            bu_exceptions_o                        <= id_exceptions_i;
            bu_exceptions_o.misaligned_instruction <= misaligned_instruction;
            bu_exceptions_o.any                    <= id_exceptions_i.any | misaligned_instruction;
        end
    end


  /*
   * Decode Immediates
   */
  assign immUJ = decode_immUJ(id_insn_i.instr);
  assign immSB = decode_immSB(id_insn_i.instr);
  assign ext_immUJ = { {XLEN-$bits(immUJ){immUJ[$left(immUJ,1)]}}, immUJ};
  assign ext_immSB = { {XLEN-$bits(immSB){immSB[$left(immSB,1)]}}, immSB};


  /*
   * Program Counter modifications
   * - Branches/JALR (JAL/JALR results handled by ALU)
   * - Exceptions
   * - Debug Unit NPC access
   */
/*
  always @(posedge clk_i)
    du_we_pc_i_dly <= du_we_pc_i;

  always @(posedge clk_i,negedge rst_ni)
    if (!rst_ni) du_wrote_pc <= 1'b0;
    else         du_wrote_pc <= du_we_pc_i | (du_wrote_pc & du_stall_i);


  always @(posedge clk_i)
    if (du_we_pc_i) du_nxt_pc <= du_dato_i;
*/

  always_comb 
    casex ( {id_insn_i.bubble,opcR} )
      {1'b0,JAL    }: begin //This is really only for the debug unit, such that NPC points to the correct address
                          btaken     = 'b1;
                          bp_update  = 'b0;
                          pipeflush  = ~id_bp_predict_i[1]; //Only flush here if no jump/branch prediction
                          cacheflush = 'b0;
                          nxt_pc     = id_pc_i + ext_immUJ;
                      end
      {1'b0,JALR   }: begin
                          btaken     = 'b1;
                          bp_update  = 'b0;
                          pipeflush  = 'b1;
                          cacheflush = 'b0;
                          nxt_pc     = (opA_i + opB_i) & { {XLEN-1{1'b1}},1'b0 };
                      end
      {1'b0,BEQ    }: begin
                          btaken     = (opA_i == opB_i);
                          bp_update  = 'b1;
                          pipeflush  = btaken ^ id_bp_predict_i[1];
                          cacheflush = 'b0;
                          nxt_pc     = btaken ? id_pc_i + ext_immSB : id_pc_i +(is_16bit_instruction ? 'h2 : 'h4);
                      end
      {1'b0,BNE    }: begin
                          btaken     = (opA_i != opB_i);
                          bp_update  = 'b1;
                          pipeflush  = btaken ^ id_bp_predict_i[1];
                          cacheflush = 'b0;
                          nxt_pc     = btaken ? id_pc_i + ext_immSB : id_pc_i + (is_16bit_instruction ? 'h2 : 'h4);
                       end
      {1'b0,BLTU    }: begin
                           btaken     = (opA_i < opB_i);
                           bp_update  = 'b1;
                           pipeflush  = btaken ^ id_bp_predict_i[1];
                           cacheflush = 'b0;
                           nxt_pc     = btaken ? id_pc_i + ext_immSB : id_pc_i + 'h4;
                      end
      {1'b0,BGEU   }: begin
                          btaken     = (opA_i >= opB_i);
                          bp_update  = 'b1;
                          pipeflush  = btaken ^ id_bp_predict_i[1];
                          cacheflush = 'b0;
                          nxt_pc     = btaken ? id_pc_i + ext_immSB : id_pc_i +'h4;
                     end
      {1'b0,BLT   }: begin
                         btaken     = $signed(opA_i) <  $signed(opB_i); 
                         bp_update  = 'b1;
                         pipeflush  = btaken ^ id_bp_predict_i[1];
                         cacheflush = 'b0;
                         nxt_pc     = btaken ? id_pc_i + ext_immSB : id_pc_i + 'h4;
                      end
      {1'b0,BGE    }: begin
                          btaken     = $signed(opA_i) >= $signed(opB_i);
                          bp_update  = 'b1;
                          pipeflush  = btaken ^ id_bp_predict_i[1];
                          cacheflush = 'b0;
                          nxt_pc     = btaken ? id_pc_i + ext_immSB : id_pc_i + 'h4;
                      end
      {1'b0,MISCMEM}: case (id_insn_i.instr)
                         FENCE_I: begin
                                      btaken     = 'b0;
                                      bp_update  = 'b0;
                                      pipeflush  = 'b1;
                                      cacheflush = 'b1;
                                      nxt_pc     = id_pc_i +'h4;
                                  end
                         default: begin
                                      btaken     = 'b0;
                                      bp_update  = 'b0;
                                      pipeflush  = 'b0;
                                      cacheflush = 'b0;
                                      nxt_pc     = id_pc_i + 'h4;
                                   end
                      endcase
      default       : begin
                          btaken     = 'b0;
                          bp_update  = 'b0;
                          pipeflush  = 'b0;
                          cacheflush = 'b0;
                          nxt_pc     = id_pc_i + (is_16bit_instruction ? 'h2 : 'h4);
                      end
    endcase



  /*
   * Program Counter modifications (Branches/JALR)
   */
  always @(posedge clk_i, negedge rst_ni)
    if (!rst_ni)
    begin
        bu_flush_o      <= 'b1;
        bu_cacheflush_o <= 'b0;
//        bu_nxt_pc_o     <= PC_INIT;

        bu_bp_predict_o <= 'b00;
        bu_bp_btaken_o  <= 'b0;
        bu_bp_update_o  <= 'b0;
        bp_history      <= 'h0;
    end
/*
    else if (du_wrote_pc)
    begin
        bu_flush_o      <= du_we_pc_i_dly;
        bu_cacheflush_o <= 1'b0;
//        bu_nxt_pc_o     <= du_nxt_pc;

        bu_bp_predict_o <= 'b00;
        bu_bp_btaken_o  <= 'b0;
        bu_bp_update_o  <= 'b0;
    end
*/
    else
    begin
        bu_flush_o      <= pipeflush; //(pipeflush & ~du_stall_i & ~du_flush_i);
        bu_cacheflush_o <= cacheflush;
//        bu_nxt_pc_o     <= nxt_pc;

        bu_bp_predict_o <= id_bp_predict_i;
        bu_bp_btaken_o  <= btaken;
        bu_bp_update_o  <= bp_update;

	//Branch History is a simple shift register
        if (bp_update) bp_history <= {bp_history[BP_GLOBAL_BITS-1:0],btaken};
    end



  always @(posedge clk_i, negedge rst_ni)
   if      (!rst_ni     ) bu_nxt_pc_o <= PC_INIT;
//   else if ( du_wrote_pc) bu_nxt_pc_o <= du_nxt_pc;
   else if (!ex_stall_i ) bu_nxt_pc_o <= nxt_pc;


  //don't take myself (current branch) into account when updating branch history
  assign bu_bp_history_o = bp_history[BP_GLOBAL_BITS:1];

endmodule 

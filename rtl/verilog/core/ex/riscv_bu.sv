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


module riscv_bu
import riscv_opcodes_pkg::*;
import riscv_state_pkg::*;
#(
  parameter int        XLEN           = 32,
  parameter [XLEN-1:0] PC_INIT        = 'h200,
  parameter int        BP_GLOBAL_BITS = 2,
  parameter int        RSB_DEPTH      = 0,
  parameter int        HAS_RVC        = 0
)
(
  input                           rst_ni,
  input                           clk_i,

  input                           ex_stall_i,
  input                           st_flush_i,

  output reg                      bu_bubble_o,

  //Program counter
  input      [XLEN          -1:0] id_pc_i,
                                  id_rsb_pc_i,
  output reg [XLEN          -1:0] bu_nxt_pc_o,
  output reg                      bu_flush_o,
                                  cm_ic_invalidate_o,
                                  cm_dc_invalidate_o,
                                  cm_dc_clean_o,
  input      [               1:0] id_bp_predict_i,
  output reg [               1:0] bu_bp_predict_o,
  input      [BP_GLOBAL_BITS-1:0] id_bp_history_i,
  output reg [BP_GLOBAL_BITS-1:0] bu_bp_history_update_o,
                                  bu_bp_history_o,
  output reg                      bu_bp_btaken_o,
  output reg                      bu_bp_update_o,

  //Instruction
  input  instruction_t            id_insn_i,

  input  interrupts_exceptions_t  id_exceptions_i,
                                  ex_exceptions_i,
                                  mem_exceptions_i,
                                  wb_exceptions_i,
  output interrupts_exceptions_t  bu_exceptions_o,

  //from ID
  input      [XLEN          -1:0] opA_i,
                                  opB_i
);
  ////////////////////////////////////////////////////////////////
  //
  // Variables
  //
  localparam SBITS=$clog2(XLEN);

  logic                    has_rvc;
  logic                    has_rsb;
  logic                    is_16bit_instruction;
  opcR_t                   opcR;
  rsd_t                    rs1;
  logic                    is_ret;
  logic                    misaligned_instruction;

  //Immediates
  immUJ_t                  immUJ;
  immSB_t                  immSB;
  logic [XLEN        -1:0] ext_immUJ,
                           ext_immSB;

  //Branch controls
  logic                    bu_bubble;
  logic                    pipeflush,
                           ic_invalidate,
                           dc_invalidate,
                           dc_clean,
                           cacheflush,
                           btaken,
                           bp_update;
  logic [BP_GLOBAL_BITS:0] bp_history;
  logic [XLEN        -1:0] nxt_pc;


  ////////////////////////////////////////////////////////////////
  //
  // Module Body
  //

  /*
   * Instruction
   */
  assign has_rvc = (HAS_RVC !=  0);
  assign has_rsb = (RSB_DEPTH > 0);
  assign is_16bit_instruction = ~&id_insn_i.instr[1:0];
  assign opcR    = decode_opcR(id_insn_i.instr);
  assign rs1     = decode_rs1 (id_insn_i.instr);
  assign is_ret  = (rs1 == 1) | (rs1 == 5);

  /*
   * Exceptions
   */
  always_comb
    casex ( {id_insn_i.bubble,id_insn_i.instr.R.opcode} )
      {1'b0,OPC_JALR  } : misaligned_instruction = id_exceptions_i.exceptions.misaligned_instruction | has_rvc ? nxt_pc[0] : |nxt_pc[1:0];
      {1'b0,OPC_BRANCH} : misaligned_instruction = id_exceptions_i.exceptions.misaligned_instruction | has_rvc ? nxt_pc[0] : |nxt_pc[1:0];
      default           : misaligned_instruction = id_exceptions_i.exceptions.misaligned_instruction;
    endcase


  always @(posedge clk_i, negedge rst_ni)
    if      (!rst_ni    ) bu_exceptions_o <= 'h0;
    else if (!ex_stall_i)
    begin
        if ( bu_flush_o || st_flush_i || 
             ex_exceptions_i.any || mem_exceptions_i.any || wb_exceptions_i.any  )
        begin
            bu_exceptions_o <= 'h0;
        end
        else
        begin
            bu_exceptions_o                                   <= id_exceptions_i;
            bu_exceptions_o.exceptions.misaligned_instruction <= misaligned_instruction;
            bu_exceptions_o.any                               <= id_exceptions_i.any | misaligned_instruction;
        end
    end


  /*
   * Decode Immediates
   */
  assign immUJ     = decode_immUJ(id_insn_i.instr);
  assign immSB     = decode_immSB(id_insn_i.instr);
  assign ext_immUJ = { {XLEN-$bits(immUJ){immUJ[$left(immUJ,1)]}}, immUJ};
  assign ext_immSB = { {XLEN-$bits(immSB){immSB[$left(immSB,1)]}}, immSB};


  /*
   * Program Counter modifications
   * - Branches/JALR (JAL/JALR results handled by ALU)
   * - Exceptions
   */
  always_comb 
    casex ( {id_insn_i.bubble,opcR} )
      {1'b0,JAL    }: begin //This is really only for the debug unit, such that NPC points to the correct address
                          bu_bubble     = 1'b0;
                          btaken        = 1'b1;
                          bp_update     = 1'b0;
                          pipeflush     = ~id_bp_predict_i[1]; //Only flush here if no jump/branch prediction
                          cacheflush    = 1'b0;
                          ic_invalidate = 1'b0;
                          dc_invalidate = 1'b0;
                          dc_clean      = 1'b0;
                          nxt_pc        = id_pc_i + ext_immUJ;
                      end
      {1'b0,JALR   }: if (has_rsb)
                      begin
                          bu_bubble     = 1'b0;
                          btaken        = 1'b1;
                          bp_update     = 1'b0;
                          cacheflush    = 1'b0;
                          ic_invalidate = 1'b0;
                          dc_invalidate = 1'b0;
                          dc_clean      = 1'b0;
                          nxt_pc        = (opA_i + opB_i) & { {XLEN-1{1'b1}},1'b0 };
                          pipeflush     = is_ret ?  (nxt_pc[XLEN-1:1] != id_rsb_pc_i[XLEN-1:1]) : 1'b1;
                      end
                      else
                      begin
                          bu_bubble     = 1'b0;
                          btaken        = 1'b1;
                          bp_update     = 1'b0;
                          pipeflush     = 1'b1;
                          cacheflush    = 1'b0;
                          ic_invalidate = 1'b0;
                          dc_invalidate = 1'b0;
                          dc_clean      = 1'b0;
                          nxt_pc        = (opA_i + opB_i) & { {XLEN-1{1'b1}},1'b0 };
                      end
      {1'b0,BEQ    }: begin
                          bu_bubble     = 1'b0;
                          btaken        = (opA_i == opB_i);
                          bp_update     = 1'b1;
                          pipeflush     = btaken ^ id_bp_predict_i[1];
                          cacheflush    = 1'b0;
                          ic_invalidate = 1'b0;
                          dc_invalidate = 1'b0;
                          dc_clean      = 1'b0;
                          nxt_pc        = btaken ? id_pc_i + ext_immSB : id_pc_i + ('h2 << id_insn_i.instr.SB.size);
                      end
      {1'b0,BNE    }: begin
                          bu_bubble     = 1'b0;
                          btaken        = (opA_i != opB_i);
                          bp_update     = 1'b1;
                          pipeflush     = btaken ^ id_bp_predict_i[1];
                          cacheflush    = 1'b0;
                          ic_invalidate = 1'b0;
                          dc_invalidate = 1'b0;
                          dc_clean      = 1'b0;
                          nxt_pc        = btaken ? id_pc_i + ext_immSB : id_pc_i + ('h2 << id_insn_i.instr.SB.size);
                       end
      {1'b0,BLTU   }: begin
                          bu_bubble     = 1'b0;
                          btaken        = (opA_i < opB_i);
                          bp_update     = 1'b1;
                          pipeflush     = btaken ^ id_bp_predict_i[1];
                          cacheflush    = 1'b0;
                          ic_invalidate = 1'b0;
                          dc_invalidate = 1'b0;
                          dc_clean      = 1'b0;
                          nxt_pc        = btaken ? id_pc_i + ext_immSB : id_pc_i + ('h2 << id_insn_i.instr.SB.size);
                      end
      {1'b0,BGEU   }: begin
                          bu_bubble     = 1'b0;
                          btaken        = (opA_i >= opB_i);
                          bp_update     = 1'b1;
                          pipeflush     = btaken ^ id_bp_predict_i[1];
                          cacheflush    = 1'b0;
                          ic_invalidate = 1'b0;
                          dc_invalidate = 1'b0;
                          dc_clean      = 1'b0;
                          nxt_pc        = btaken ? id_pc_i + ext_immSB : id_pc_i + ('h2 << id_insn_i.instr.SB.size);
                      end
      {1'b0,BLT    }: begin
                          bu_bubble     = 1'b0;
                          btaken        = $signed(opA_i) <  $signed(opB_i); 
                          bp_update     = 1'b1;
                          pipeflush     = btaken ^ id_bp_predict_i[1];
                          cacheflush    = 1'b0;
                          ic_invalidate = 1'b0;
                          dc_invalidate = 1'b0;
                          dc_clean      = 1'b0;
                          nxt_pc        = btaken ? id_pc_i + ext_immSB : id_pc_i + ('h2 << id_insn_i.instr.SB.size);
                      end
      {1'b0,BGE    }: begin
                          bu_bubble     = 1'b0;
                          btaken        = $signed(opA_i) >= $signed(opB_i);
                          bp_update     = 1'b1;
                          pipeflush     = btaken ^ id_bp_predict_i[1];
                          cacheflush    = 1'b0;
                          ic_invalidate = 1'b0;
                          dc_invalidate = 1'b0;
                          dc_clean      = 1'b0;
                          nxt_pc        = btaken ? id_pc_i + ext_immSB : id_pc_i + ('h2 << id_insn_i.instr.SB.size);
                      end
      {1'b0,MISCMEM}: case (id_insn_i.instr)
                         FENCE_I: begin
                                      bu_bubble     = 1'b0;
                                      btaken        = 1'b0;
                                      bp_update     = 1'b0;
                                      pipeflush     = 1'b1;
                                      cacheflush    = 1'b1;
                                      ic_invalidate = 1'b1;
                                      dc_invalidate = 1'b0;
                                      dc_clean      = 1'b1;
                                      nxt_pc        = id_pc_i + ('h2 << id_insn_i.instr.SB.size);
                                  end
                         default: begin
                                      bu_bubble     = 1'b1;
                                      btaken        = 1'b0;
                                      bp_update     = 1'b0;
                                      pipeflush     = 1'b0;
                                      cacheflush    = 1'b0;
                                      ic_invalidate = 1'b0;
                                      dc_invalidate = 1'b0;
                                      dc_clean      = 1'b0;
                                      nxt_pc        = id_pc_i + ('h2 << id_insn_i.instr.SB.size);
                                   end
                      endcase
      default       : begin
                          bu_bubble     = 1'b1;
                          btaken        = 1'b0;
                          bp_update     = 1'b0;
                          pipeflush     = 1'b0;
                          cacheflush    = 1'b0;
                          ic_invalidate = 1'b0;
                          dc_invalidate = 1'b0;
                          dc_clean      = 1'b0;
                          nxt_pc        = id_pc_i + ('h2 << id_insn_i.instr.SB.size);
                      end
    endcase


  /*
   * Program Counter modifications (Branches/JALR)
   */
  always @(posedge clk_i, negedge rst_ni)
    if      (!rst_ni                ) bu_bubble_o <= 1'b1;
    else if ( ex_exceptions_i.any  ||
              mem_exceptions_i.any ||
              wb_exceptions_i.any   ) bu_bubble_o <= 1'b1;
    else if (!ex_stall_i            ) bu_bubble_o <= bu_bubble;


  always @(posedge clk_i, negedge rst_ni)
    if (!rst_ni)
    begin
        bu_flush_o                <= 1'b1;
	cm_ic_invalidate_o        <= 1'b0;
	cm_dc_invalidate_o        <= 1'b0;
	cm_dc_clean_o             <= 1'b0;

        bu_bp_predict_o           <= 2'b00;
        bu_bp_btaken_o            <= 1'b0;
        bu_bp_update_o            <= 1'b0;
	bu_bp_history_update_o    <= 'h0;
        bp_history                <= 'h0;
    end
    else
    begin
        bu_flush_o                <= (pipeflush === 1'b1);
        cm_ic_invalidate_o        <= ic_invalidate;
        cm_dc_invalidate_o        <= dc_invalidate;
        cm_dc_clean_o             <= dc_clean;

        bu_bp_predict_o           <= id_bp_predict_i;
        bu_bp_btaken_o            <= btaken;
        bu_bp_update_o            <= bp_update;
	bu_bp_history_update_o    <= id_bp_history_i;

	//Branch History is a simple shift register
        if (bp_update) bp_history <= {bp_history[BP_GLOBAL_BITS-1:0],btaken};
    end



  always @(posedge clk_i, negedge rst_ni)
   if      (!rst_ni     ) bu_nxt_pc_o <= PC_INIT;
   else if (!ex_stall_i ) bu_nxt_pc_o <= nxt_pc;


  //don't take myself (current branch) into account when updating branch history
  assign bu_bp_history_o = bp_history[BP_GLOBAL_BITS:1];

endmodule 

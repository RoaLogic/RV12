/////////////////////////////////////////////////////////////////////
//   ,------.                    ,--.                ,--.          //
//   |  .--. ' ,---.  ,--,--.    |  |    ,---. ,---. `--' ,---.    //
//   |  '--'.'| .-. |' ,-.  |    |  |   | .-. | .-. |,--.| .--'    //
//   |  |\  \ ' '-' '\ '-'  |    |  '--.' '-' ' '-' ||  |\ `--.    //
//   `--' '--' `---'  `--`--'    `-----' `---' `-   /`--' `---'    //
//                                             `---'               //
//    RISC-V                                                       //
//    Execution Units (EX Stage)                                   //
//                                                                 //
/////////////////////////////////////////////////////////////////////
//                                                                 //
//             Copyright (C) 2017-2021 ROA Logic BV                //
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
import biu_constants_pkg::*;

module riscv_ex #(
  parameter int        XLEN           = 32,
  parameter [XLEN-1:0] PC_INIT        = 'h200,
  parameter int        BP_GLOBAL_BITS = 2,
  parameter int        HAS_RVC        = 0,
  parameter int        HAS_RVA        = 0,
  parameter int        HAS_RVM        = 0,
  parameter int        MULT_LATENCY   = 0,
  parameter int        RSB_DEPTH      = 0
)
(
  input                           rst_ni,
  input                           clk_i,

  input                           mem_stall_i,
  output                          ex_stall_o,

  //Program counter
  input      [XLEN          -1:0] id_pc_i,
                                  id_rsb_pc_i,
  output reg [XLEN          -1:0] ex_pc_o,
                                  bu_nxt_pc_o,
  output                          bu_flush_o,
                                  cm_ic_invalidate_o,
                                  cm_dc_invalidate_o,
                                  cm_dc_clean_o,
  input      [               1:0] id_bp_predict_i,
  output     [               1:0] bu_bp_predict_o,
  input      [BP_GLOBAL_BITS-1:0] id_bp_history_i,
  output     [BP_GLOBAL_BITS-1:0] bu_bp_history_update_o,
                                  bu_bp_history_o,
  output                          bu_bp_btaken_o,
  output                          bu_bp_update_o,

  //Instruction
  input  instruction_t            id_insn_i,
  output instruction_t            ex_insn_o,

  input  interrupts_exceptions_t  id_exceptions_i,
  output interrupts_exceptions_t  ex_exceptions_o,
  input  interrupts_exceptions_t  mem_exceptions_i,
                                  wb_exceptions_i,

  //from ID
  input                           id_userf_opA_i,
                                  id_userf_opB_i,
                                  id_bypex_opA_i,
                                  id_bypex_opB_i,
  input      [XLEN          -1:0] id_opA_i,
                                  id_opB_i,

  //from RF
  input      [XLEN          -1:0] rf_srcv1_i,
                                  rf_srcv2_i,

  //to MEM
  output reg [XLEN          -1:0] ex_r_o,

  //To State
  output     [              11:0] ex_csr_reg_o,
  output     [XLEN          -1:0] ex_csr_wval_o,
  output                          ex_csr_we_o,

  //From State
  input      [               1:0] st_xlen_i,
  input                           st_flush_i,
  input      [XLEN          -1:0] st_csr_rval_i, //TODO: read during ID

  //To DCACHE/Memory
  output                          dmem_req_o,
  output                          dmem_lock_o,
  output     [XLEN          -1:0] dmem_adr_o,
  output     biu_size_t           dmem_size_o,
  output                          dmem_we_o,
  output     [XLEN          -1:0] dmem_d_o,
  input      [XLEN          -1:0] dmem_q_i,
  input                           dmem_ack_i,
                                  dmem_misaligned_i,
                                  dmem_page_fault_i
);


  ////////////////////////////////////////////////////////////////
  //
  // Variables
  //

  //Operand generation
  logic [XLEN          -1:0] opA,opB,
                             hold_opA, hold_opB;

  logic [XLEN          -1:0] alu_r,
                             lsu_r,
                             mul_r,
                             div_r;

  //Pipeline Bubbles
  logic                      alu_bubble,
                             lsu_bubble,
                             mul_bubble,
                             div_bubble;

  //Pipeline stalls
  logic                      lsu_stall,
                             mul_stall,
                             div_stall;

  //Exceptions
  logic [EXCEPTION_SIZE-1:0] bu_exception;
  interrupts_exceptions_t    lsu_exceptions;


  ////////////////////////////////////////////////////////////////
  //
  // Module Body
  //

  /*
   * Program Counter
   */
  always @(posedge clk_i, negedge rst_ni)
    if      (!rst_ni    ) ex_pc_o <= PC_INIT;
    else if (!ex_stall_o) ex_pc_o <= id_pc_i;


  /*
   * Instruction
   */
  always @(posedge clk_i)
    if (!ex_stall_o) ex_insn_o.instr <= id_insn_i.instr;


  /*
   * Bypasses
   */
  always_comb
    casex ( {id_userf_opA_i, id_bypex_opA_i})
      2'b?1  : opA = ex_r_o;
      2'b10  : opA = rf_srcv1_i;
      default: opA = id_opA_i;
    endcase

  always_comb
    casex ( {id_userf_opB_i, id_bypex_opB_i})
      2'b?1  : opB = ex_r_o;
      2'b10  : opB = rf_srcv2_i;
      default: opB = id_opB_i;
    endcase


  /*
   * Execution Units
   */
  riscv_alu #(
    .XLEN             ( XLEN             ),
    .HAS_RVC          ( HAS_RVC          ))
  alu (
    .rst_ni           ( rst_ni           ),
    .clk_i            ( clk_i            ),

    .ex_stall_i       ( ex_stall_o       ),

    .id_pc_i          ( id_pc_i          ),
    .id_insn_i        ( id_insn_i        ),

    .opA_i            ( opA              ),
    .opB_i            ( opB              ),

    .ex_exceptions_i  ( ex_exceptions_o  ),
    .mem_exceptions_i ( mem_exceptions_i ),
    .wb_exceptions_i  ( wb_exceptions_i  ),

    .alu_bubble_o     ( alu_bubble       ),
    .alu_r_o          ( alu_r            ),

    .ex_csr_reg_o     ( ex_csr_reg_o     ),
    .ex_csr_wval_o    ( ex_csr_wval_o    ),
    .ex_csr_we_o      ( ex_csr_we_o      ),

    .st_csr_rval_i    ( st_csr_rval_i    ),
    .st_xlen_i        ( st_xlen_i        ) );


  // Load-Store Unit
  riscv_lsu #(
    .XLEN              ( XLEN              ) )
  lsu (
    .rst_ni            ( rst_ni            ),
    .clk_i             ( clk_i             ),

    .ex_stall_i        ( ex_stall_o        ),
    .lsu_stall_o       ( lsu_stall         ),

    .id_insn_i         ( id_insn_i         ),

    .lsu_bubble_o      ( lsu_bubble        ),
    .lsu_r_o           ( lsu_r             ),

    .id_exceptions_i   ( id_exceptions_i   ),
    .ex_exceptions_i   ( ex_exceptions_o   ),
    .mem_exceptions_i  ( mem_exceptions_i  ),
    .wb_exceptions_i   ( wb_exceptions_i   ),
    .lsu_exceptions_o  ( lsu_exceptions    ),


    .opA_i             ( opA               ),
    .opB_i             ( opB               ),

    .st_xlen_i         ( st_xlen_i         ),

    .dmem_req_o        ( dmem_req_o        ),
    .dmem_lock_o       ( dmem_lock_o       ),
    .dmem_we_o         ( dmem_we_o         ),
    .dmem_size_o       ( dmem_size_o       ),
    .dmem_adr_o        ( dmem_adr_o        ),
    .dmem_d_o          ( dmem_d_o          ),
    .dmem_q_i          ( dmem_q_i          ),
    .dmem_ack_i        ( dmem_ack_i        ),
    .dmem_misaligned_i ( dmem_misaligned_i ),
    .dmem_page_fault_i ( dmem_page_fault_i ) );


  // Branch Unit
  riscv_bu #(
    .XLEN                   ( XLEN                   ),
    .HAS_RVC                ( HAS_RVC                ),
    .PC_INIT                ( PC_INIT                ),
    .BP_GLOBAL_BITS         ( BP_GLOBAL_BITS         ),
    .RSB_DEPTH              ( RSB_DEPTH              ) )
  bu (
    .rst_ni                 ( rst_ni                 ),
    .clk_i                  ( clk_i                  ),

    .ex_stall_i             ( ex_stall_o             ),
    .st_flush_i             ( st_flush_i             ),

    .id_pc_i                ( id_pc_i                ),
    .id_insn_i              ( id_insn_i              ),
    .id_rsb_pc_i            ( id_rsb_pc_i            ),
    .bu_nxt_pc_o            ( bu_nxt_pc_o            ),
    .bu_flush_o             ( bu_flush_o             ),
    .cm_ic_invalidate_o     ( cm_ic_invalidate_o     ),
    .cm_dc_invalidate_o     ( cm_dc_invalidate_o     ),
    .cm_dc_clean_o          ( cm_dc_clean_o          ),

    .id_bp_predict_i        ( id_bp_predict_i        ),
    .bu_bp_predict_o        ( bu_bp_predict_o        ),
    .id_bp_history_i        ( id_bp_history_i        ),
    .bu_bp_history_update_o ( bu_bp_history_update_o ),
    .bu_bp_history_o        ( bu_bp_history_o        ),
    .bu_bp_btaken_o         ( bu_bp_btaken_o         ),
    .bu_bp_update_o         ( bu_bp_update_o         ),

    .id_exceptions_i        ( id_exceptions_i        ),
    .ex_exceptions_i        ( ex_exceptions_o        ),
    .mem_exceptions_i       ( mem_exceptions_i       ),
    .wb_exceptions_i        ( wb_exceptions_i        ),
    .bu_exceptions_o        ( ex_exceptions_o        ),

    .opA_i                  ( opA                    ),
    .opB_i                  ( opB                    ) );


generate
  if (HAS_RVM)
  begin
      riscv_mul #(
        .XLEN         ( XLEN         ),
        .MULT_LATENCY ( MULT_LATENCY ) )
      mul (
        .rst_ni       ( rst_ni       ),
        .clk_i        ( clk_i        ),

        .ex_stall_i   ( ex_stall_o   ),
        .mul_stall_o  ( mul_stall    ),

        .id_insn_i    ( id_insn_i    ),

        .opA_i        ( opA          ),
        .opB_i        ( opB          ),

        .st_xlen_i    ( st_xlen_i    ),

        .mul_bubble_o ( mul_bubble   ),
        .mul_r_o      ( mul_r        ) );


      riscv_div #(
        .XLEN         ( XLEN       ) )
      div (
        .rst_ni       ( rst_ni     ),
        .clk_i        ( clk_i      ),

        .ex_stall_i   ( ex_stall_o ),
        .div_stall_o  ( div_stall  ),

        .id_insn_i    (id_insn_i   ),

        .opA_i        ( opA        ),
        .opB_i        ( opB        ),

        .st_xlen_i    ( st_xlen_i  ),

        .div_bubble_o ( div_bubble ),
        .div_r_o      ( div_r      ) );
  end
  else
  begin
      assign mul_bubble = 1'b1;
      assign mul_r      =  'h0;
      assign mul_stall  = 1'b0;

      assign div_bubble = 1'b1;
      assign div_r      =  'h0;
      assign div_stall  = 1'b0;
  end
endgenerate


  /*
   * Combine outputs into 1 single EX output
   */

  assign ex_insn_o.bubble = alu_bubble & lsu_bubble & mul_bubble & div_bubble;
  assign ex_stall_o       = mem_stall_i | lsu_stall | mul_stall | div_stall;

  //result
  always_comb
    unique casex ( {mul_bubble,div_bubble,lsu_bubble} )
      3'b110 : ex_r_o = lsu_r;
      3'b101 : ex_r_o = div_r;
      3'b011 : ex_r_o = mul_r;
      default: ex_r_o = alu_r;
    endcase

endmodule 

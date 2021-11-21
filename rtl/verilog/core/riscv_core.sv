/////////////////////////////////////////////////////////////////////
//   ,------.                    ,--.                ,--.          //
//   |  .--. ' ,---.  ,--,--.    |  |    ,---. ,---. `--' ,---.    //
//   |  '--'.'| .-. |' ,-.  |    |  |   | .-. | .-. |,--.| .--'    //
//   |  |\  \ ' '-' '\ '-'  |    |  '--.' '-' ' '-' ||  |\ `--.    //
//   `--' '--' `---'  `--`--'    `-----' `---' `-   /`--' `---'    //
//                                             `---'               //
//    RISC-V                                                       //
//    CPU Core                                                     //
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

/*
  Changelog: 2017-12-15: Added MEM stage to improve memory access performance
*/

import riscv_du_pkg::*;
import riscv_state_pkg::*;
import riscv_opcodes_pkg::*;
import biu_constants_pkg::*;

module riscv_core #(
  parameter            XLEN                  = 32,
  parameter [XLEN-1:0] PC_INIT               = 'h200,
  parameter            HAS_USER              = 0,
  parameter            HAS_SUPER             = 0,
  parameter            HAS_HYPER             = 0,
  parameter            HAS_BPU               = 1,
  parameter            HAS_FPU               = 0,
  parameter            HAS_MMU               = 0,
  parameter            HAS_RVA               = 0,
  parameter            HAS_RVM               = 0,
  parameter            HAS_RVC               = 0,
  parameter            IS_RV32E              = 0,

  parameter            RF_REGOUT             = 1,
  parameter            MULT_LATENCY          = 1,

  parameter            BREAKPOINTS           = 3,
  parameter            PMP_CNT               = 16,

  parameter            BP_GLOBAL_BITS        = 2,
  parameter            BP_LOCAL_BITS         = 10,

  parameter            TECHNOLOGY            = "GENERIC",

  parameter            MNMIVEC_DEFAULT       = PC_INIT -'h004,
  parameter            MTVEC_DEFAULT         = PC_INIT -'h040,
  parameter            HTVEC_DEFAULT         = PC_INIT -'h080,
  parameter            STVEC_DEFAULT         = PC_INIT -'h0C0,
  parameter            UTVEC_DEFAULT         = PC_INIT -'h100,

  parameter            JEDEC_BANK            = 10,
  parameter            JEDEC_MANUFACTURER_ID = 'h6e,

  parameter            HARTID                = 0,

  parameter            PARCEL_SIZE           = 16
)
(
  input                                  rst_ni,   //Reset
  input                                  clk_i,    //Clock

  //Instruction Memory Access bus
  output          [XLEN            -1:0] imem_adr_o,
  output                                 imem_req_o,
  input                                  imem_ack_i,
  output                                 imem_flush_o,
  input           [XLEN            -1:0] imem_parcel_i,
  input           [XLEN/PARCEL_SIZE-1:0] imem_parcel_valid_i,
  input                                  imem_parcel_misaligned_i,
  input                                  imem_parcel_page_fault_i,
  input                                  imem_parcel_error_i,

  //Data memory Access  bus
  output          [XLEN            -1:0] dmem_adr_o,
                                         dmem_d_o,
  input           [XLEN            -1:0] dmem_q_i,
  output                                 dmem_we_o,
  output biu_size_t                      dmem_size_o,
  output                                 dmem_lock_o,
  output                                 dmem_req_o,
  input                                  dmem_ack_i,
                                         dmem_err_i,
                                         dmem_misaligned_i,
                                         dmem_page_fault_i,

  //cpu state
  output          [                 1:0] st_prv_o,
  output pmpcfg_t [                15:0] st_pmpcfg_o,
  output [   15:0][XLEN            -1:0] st_pmpaddr_o,

  output                                 cacheflush_o,

  //Interrupts
  input                                  ext_nmi_i,
                                         ext_tint_i,
                                         ext_sint_i,
  input           [                 3:0] ext_int_i,

  //Debug Interface
  input                                  dbg_stall_i,
  input                                  dbg_strb_i,
  input                                  dbg_we_i,
  input           [DBG_ADDR_SIZE   -1:0] dbg_addr_i,
  input           [XLEN            -1:0] dbg_dati_i,
  output          [XLEN            -1:0] dbg_dato_o,
  output                                 dbg_ack_o,
  output                                 dbg_bp_o
);


  ////////////////////////////////////////////////////////////////
  //
  // Variables
  //
  logic [XLEN          -1:0] pd_nxt_pc,
                             bu_nxt_pc,
                             st_nxt_pc,
			     if_predict_pc,
                             if_nxt_pc,
			     if_pc,
                             pd_pc,
                             id_pc,
                             ex_pc,
                             mem_pc,
                             wb_pc;

  instruction_t              if_nxt_insn,
                             if_insn,
                             pd_insn,
                             id_insn,
                             ex_insn,
                             mem_insn,
                             wb_insn,
                             dwb_insn;

  logic                      bu_flush,
                             st_flush,
                             du_flush,
                             bu_cacheflush;

  logic                      id_stall,
                             pd_stall,
                             ex_stall,
                             mem_stall,
                             wb_stall,
                             du_stall,
                             du_stall_if;

  //Branch Prediction
  logic [               1:0] bp_bp_predict,
                             pd_bp_predict,
                             id_bp_predict,
                             bu_bp_predict;

  logic                      pd_latch_nxt_pc;      //Yes, this is needed.

  logic [BP_GLOBAL_BITS-1:0] bu_bp_history,        //Global BP history from BU
                             if_predict_history,   //Global history to BP (read)
                             if_bp_history,        //Global history to PD
                             pd_bp_history,
                             id_bp_history,
                             bu_bp_history_update; //Global history to BP (write)
  logic                      bu_bp_btaken,
                             bu_bp_update;

  //Exceptions
  exceptions_t               if_exceptions,
                             pd_exceptions,
	                     id_exceptions,
			     ex_exceptions,
			     mem_exceptions,
			     wb_exceptions;

  //RF access
  rsd_t                      pd_rs1, 
                             pd_rs2, 
                             id_rs1,
                             id_rs2;
  rsd_t                      rf_src1,
                             rf_src2;
  logic [XLEN          -1:0] rf_srcv1,
                             rf_srcv2;


  //ALU signals
  logic [XLEN          -1:0] id_opA,
                             id_opB,
                             ex_r,
                             mem_r,
                             mem_memadr,
                             wb_r,
			     wb_memq,
                             dwb_r;

  logic                      id_userf_opA,
                             id_userf_opB,
                             id_bypex_opA,
                             id_bypex_opB;

  //CPU state
  logic [               1:0] st_xlen;
  logic                      st_tvm,
                             st_tw,
                             st_tsr;
  logic [XLEN          -1:0] st_mcounteren,
                             st_scounteren;
  logic [              11:0] pd_csr_reg,
	                     ex_csr_reg;
  logic [XLEN          -1:0] ex_csr_wval,
                             st_csr_rval,
                             du_csr_rval;
  logic                      ex_csr_we;

  //Write back
  rsd_t                      wb_dst;
  logic [               0:0] wb_we;
  logic [XLEN          -1:0] wb_badaddr;

  //Debug
  logic                      du_latch_nxt_pc;
  logic                      du_we_rf,
                             du_we_frf,
                             du_re_csr,
                             du_we_csr,
                             du_we_pc;
  logic [DU_ADDR_SIZE  -1:0] du_addr;
  logic [XLEN          -1:0] du_dato,
                             du_dati_rf,
                             du_dati_frf;
  logic [              31:0] du_ie,
                             du_exceptions;


  ////////////////////////////////////////////////////////////////
  //
  // Module Body
  //

  assign cacheflush_o = du_flush | bu_cacheflush;


  /*
   * Instruction pipeline
   * insn (instruction + bubble) and exceptions move down
   * stalls move up
   */

  /*
   * Instruction Fetch
   *
   * Calculate next Program Counter
   * Fetch next instruction
   */
  riscv_if #(
    .XLEN                     ( XLEN                     ),
    .PC_INIT                  ( PC_INIT                  ),
    .HAS_RVC                  ( HAS_RVC                  ),
    .BP_GLOBAL_BITS           ( BP_GLOBAL_BITS           ) )
  if_unit (
    .rst_ni                   ( rst_ni                   ),   //Reset
    .clk_i                    ( clk_i                    ),   //Clock

    //To Instruction Memory
    .imem_adr_o               ( imem_adr_o               ),   //next Program Counter
    .imem_req_o               ( imem_req_o               ),   //request new parcel from BIU (cache/bus-interface)
    .imem_ack_i               ( imem_ack_i               ),   //BIU acknowledge
    .imem_flush_o             ( imem_flush_o             ),   //flush instruction fetch BIU (cache/bus-interface)

    .imem_parcel_i            ( imem_parcel_i            ),
    .imem_parcel_valid_i      ( imem_parcel_valid_i      ),
    .imem_parcel_misaligned_i ( imem_parcel_misaligned_i ),
    .imem_parcel_page_fault_i ( imem_parcel_page_fault_i ),
    .imem_parcel_error_i      ( imem_parcel_error_i      ),

    .bu_bp_history_i          ( bu_bp_history            ),
    .if_predict_history_o     ( if_predict_history       ),
    .if_bp_history_o          ( if_bp_history            ),

    .if_predict_pc_o          ( if_predict_pc            ),
    .if_nxt_pc_o              ( if_nxt_pc                ),   //Program Counter for Branch Prediction
    .if_nxt_insn_o            ( if_nxt_insn              ),
    .if_pc_o                  ( if_pc                    ),   //Program Counter
    .if_insn_o                ( if_insn                  ),   //Instruction out
    .if_exceptions_o          ( if_exceptions            ),   //Exceptions
    .pd_exceptions_i          ( pd_exceptions            ),
    .id_exceptions_i          ( id_exceptions            ),
    .ex_exceptions_i          ( ex_exceptions            ),
    .mem_exceptions_i         ( mem_exceptions           ),
    .wb_exceptions_i          ( wb_exceptions            ),

    .pd_pc_i                  ( pd_pc                    ),
    .pd_stall_i               ( pd_stall                 ),
    .pd_flush_i               ( pd_flush                 ),

    .bu_flush_i               ( bu_flush                 ),   //flush pipe & load new program counter
    .st_flush_i               ( st_flush                 ),
    .du_stall_i               ( du_stall_if              ),
    .du_flush_i               ( du_flush                 ),
    .du_we_pc_i               ( du_we_pc                 ),
    .du_dato_i                ( du_dato                  ),
    .du_latch_nxt_pc_i        ( du_latch_nxt_pc          ),
    .pd_latch_nxt_pc_i        ( pd_latch_nxt_pc          ),
    
    .pd_nxt_pc_i              ( pd_nxt_pc                ),   //Branch Prediction Next Program Counter    
    .bu_nxt_pc_i              ( bu_nxt_pc                ),   //Branch Unit Next Program Counter
    .st_nxt_pc_i              ( st_nxt_pc                ),   //State Next Program Counter

    .st_xlen_i                ( st_xlen                  ) );


  /*
   * Pre-Decoder
   */
  riscv_pd #(
    .XLEN              ( XLEN            ),
    .PC_INIT           ( PC_INIT         ),
    .HAS_RVC           ( HAS_RVC         ),
    .HAS_BPU           ( HAS_BPU         ),
    .BP_GLOBAL_BITS    ( BP_GLOBAL_BITS  ) )
  pd_unit (
    .rst_ni            ( rst_ni          ),
    .clk_i             ( clk_i           ),
    
    .id_stall_i        ( id_stall        ),
    .pd_stall_o        ( pd_stall        ),
    .du_mode_i         ( du_stall_if     ),
    
    .bu_flush_i        ( bu_flush        ),
    .st_flush_i        ( st_flush        ),
    .pd_flush_o        ( pd_flush        ),

    .pd_rs1_o          ( pd_rs1          ),
    .pd_rs2_o          ( pd_rs2          ),

    .pd_csr_reg_o      ( pd_csr_reg      ),
  
    .if_bp_history_i   ( if_bp_history   ),
    .pd_bp_history_o   ( pd_bp_history   ),
    .bp_bp_predict_i   ( bp_bp_predict   ),
    .pd_bp_predict_o   ( pd_bp_predict   ),
    .pd_latch_nxt_pc_o ( pd_latch_nxt_pc ),

    .bu_nxt_pc_i       ( bu_nxt_pc       ),
    .st_nxt_pc_i       ( st_nxt_pc       ),
    .pd_nxt_pc_o       ( pd_nxt_pc       ),

    .if_pc_i           ( if_pc           ),
    .if_insn_i         ( if_insn         ),

    .pd_pc_o           ( pd_pc           ),
    .pd_insn_o         ( pd_insn         ),

    .if_exceptions_i   ( if_exceptions   ),
    .pd_exceptions_o   ( pd_exceptions   ),
    .id_exceptions_i   ( id_exceptions   ),
    .ex_exceptions_i   ( ex_exceptions   ),
    .mem_exceptions_i  ( mem_exceptions  ),
    .wb_exceptions_i   ( wb_exceptions   ) );
 

  /*
   * Instruction Decoder
   *
   * Data from RF/ROB is available here
   */
  riscv_id #(
    .XLEN             ( XLEN            ),
    .PC_INIT          ( PC_INIT         ),
    .HAS_USER         ( HAS_USER        ),
    .HAS_SUPER        ( HAS_SUPER       ),
    .HAS_HYPER        ( HAS_HYPER       ),
    .HAS_RVA          ( HAS_RVA         ),
    .HAS_RVM          ( HAS_RVM         ),
    .HAS_RVC          ( HAS_RVC         ),
    .MULT_LATENCY     ( MULT_LATENCY    ),
    .RF_REGOUT        ( RF_REGOUT       ),
    .BP_GLOBAL_BITS   ( BP_GLOBAL_BITS  ) )
  id_unit (
    .rst_ni           ( rst_ni          ),
    .clk_i            ( clk_i           ),

    .id_stall_o       ( id_stall        ),
    .ex_stall_i       ( ex_stall        ),
    .du_stall_i       ( du_stall        ),

    .bu_flush_i       ( bu_flush        ),
    .st_flush_i       ( st_flush        ),
    .du_flush_i       ( du_flush        ),

    .bu_nxt_pc_i      ( bu_nxt_pc       ),
    .st_nxt_pc_i      ( st_nxt_pc       ),


    .pd_pc_i          ( pd_pc           ),
    .id_pc_o          ( id_pc           ),

    .pd_bp_history_i  ( pd_bp_history   ),
    .id_bp_history_o  ( id_bp_history   ),
    .pd_bp_predict_i  ( pd_bp_predict   ),
    .id_bp_predict_o  ( id_bp_predict   ),


    .pd_insn_i        ( pd_insn         ),
    .id_insn_o        ( id_insn         ),
    .ex_insn_i        ( ex_insn         ),
    .mem_insn_i       ( mem_insn        ),
    .wb_insn_i        ( wb_insn         ),
    .dwb_insn_i       ( dwb_insn        ),

    .pd_exceptions_i  ( pd_exceptions   ),
    .id_exceptions_o  ( id_exceptions   ),
    .ex_exceptions_i  ( ex_exceptions   ),
    .mem_exceptions_i ( mem_exceptions  ),
    .wb_exceptions_i  ( wb_exceptions   ),

    .st_prv_i         ( st_prv_o        ),
    .st_xlen_i        ( st_xlen         ),
    .st_tvm_i         ( st_tvm          ),
    .st_tw_i          ( st_tw           ),
    .st_tsr_i         ( st_tsr          ),
    .st_mcounteren_i  ( st_mcounteren   ),
    .st_scounteren_i  ( st_scounteren   ),

    .id_rs1_o         ( id_rs1          ),
    .id_rs2_o         ( id_rs2          ),

    .id_opA_o         ( id_opA          ),
    .id_opB_o         ( id_opB          ),
    .id_userf_opA_o   ( id_userf_opA    ),
    .id_userf_opB_o   ( id_userf_opB    ),
    .id_bypex_opA_o   ( id_bypex_opA    ),
    .id_bypex_opB_o   ( id_bypex_opB    ),

    .ex_r_i           ( ex_r            ),
    .mem_r_i          ( mem_r           ),
    .wb_r_i           ( wb_r            ),
    .wb_memq_i        ( wb_memq         ),
    .dwb_r_i          ( dwb_r           ) );


  /*
   * Execution units
   */
  riscv_ex #(
    .XLEN                   ( XLEN                 ),
    .PC_INIT                ( PC_INIT              ),
    .HAS_RVC                ( HAS_RVC              ),
    .HAS_RVA                ( HAS_RVA              ),
    .HAS_RVM                ( HAS_RVM              ),
    .MULT_LATENCY           ( MULT_LATENCY         ),
    .BP_GLOBAL_BITS         ( BP_GLOBAL_BITS       ) )
  ex_units (
    .rst_ni                 ( rst_ni               ),
    .clk_i                  ( clk_i                ),

    .mem_stall_i            ( mem_stall            ),
    .ex_stall_o             ( ex_stall             ),

    .id_pc_i                ( id_pc                ),
    .ex_pc_o                ( ex_pc                ),
    .bu_nxt_pc_o            ( bu_nxt_pc            ),
    .bu_flush_o             ( bu_flush             ),
    .bu_cacheflush_o        ( bu_cacheflush        ),
    .id_bp_predict_i        ( id_bp_predict        ),
    .bu_bp_predict_o        ( bu_bp_predict        ),
    .id_bp_history_i        ( id_bp_history        ),
    .bu_bp_history_update_o ( bu_bp_history_update ),
    .bu_bp_history_o        ( bu_bp_history        ),
    .bu_bp_btaken_o         ( bu_bp_btaken         ),
    .bu_bp_update_o         ( bu_bp_update         ),

    .id_insn_i              ( id_insn              ),
    .ex_insn_o              ( ex_insn              ),

    .id_exceptions_i        ( id_exceptions        ),
    .ex_exceptions_o        ( ex_exceptions        ),
    .mem_exceptions_i       ( mem_exceptions       ),
    .wb_exceptions_i        ( wb_exceptions        ),

    .id_userf_opA_i         ( id_userf_opA         ),
    .id_userf_opB_i         ( id_userf_opB         ),
    .id_bypex_opA_i         ( id_bypex_opA         ),
    .id_bypex_opB_i         ( id_bypex_opB         ),
    .id_opA_i               ( id_opA               ),
    .id_opB_i               ( id_opB               ),

    .rf_srcv1_i             ( rf_srcv1             ),
    .rf_srcv2_i             ( rf_srcv2             ),

    .ex_r_o                 ( ex_r                 ),

    .ex_csr_reg_o           ( ex_csr_reg           ),
    .ex_csr_wval_o          ( ex_csr_wval          ),
    .ex_csr_we_o            ( ex_csr_we            ),
    .st_xlen_i              ( st_xlen              ),
    .st_flush_i             ( st_flush             ),
    .st_csr_rval_i          ( st_csr_rval          ),

    .dmem_req_o             ( dmem_req_o           ),
    .dmem_lock_o            ( dmem_lock_o          ),
    .dmem_adr_o             ( dmem_adr_o           ),
    .dmem_size_o            ( dmem_size_o          ),
    .dmem_we_o              ( dmem_we_o            ),
    .dmem_d_o               ( dmem_d_o             ),
    .dmem_q_i               ( dmem_q_i             ),
    .dmem_ack_i             ( dmem_ack_i           ),
    .dmem_misaligned_i      ( dmem_misaligned_i    ),
    .dmem_page_fault_i      ( dmem_page_fault_i    ) );


  /*
   * Memory access
   */
  riscv_mem #(
    .XLEN             ( XLEN           ),
    .PC_INIT          ( PC_INIT        ) )
  mem_unit   (
    .rst_ni           ( rst_ni         ),
    .clk_i            ( clk_i          ),

    .wb_stall_i       ( wb_stall       ),
    .mem_stall_o      ( mem_stall      ),

    .ex_pc_i          ( ex_pc          ),
    .mem_pc_o         ( mem_pc         ),
    .ex_insn_i        ( ex_insn        ),
    .mem_insn_o       ( mem_insn       ),

    .ex_exceptions_i  ( ex_exceptions  ),
    .mem_exceptions_o ( mem_exceptions ),
    .wb_exceptions_i  ( wb_exceptions  ),

    .ex_r_i           ( ex_r           ),
    .dmem_adr_i       ( dmem_adr_o     ),
    .mem_r_o          ( mem_r          ),
    .mem_memadr_o     ( mem_memadr     ) );


  /*
   * Memory acknowledge + Write Back unit
   */
  riscv_wb #(
    .XLEN              ( XLEN              ),
    .PC_INIT           ( PC_INIT           ) )
  wb_unit   (
    .rst_ni            ( rst_ni            ),
    .clk_i             ( clk_i             ),
    .mem_pc_i          ( mem_pc            ),
    .mem_insn_i        ( mem_insn          ),
    .mem_r_i           ( mem_r             ),
    .mem_exceptions_i  ( mem_exceptions    ),
    .mem_memadr_i      ( mem_memadr        ),
    .wb_pc_o           ( wb_pc             ),
    .wb_stall_o        ( wb_stall          ),
    .wb_insn_o         ( wb_insn           ),
    .wb_exceptions_o   ( wb_exceptions     ),
    .wb_badaddr_o      ( wb_badaddr        ),
    .dmem_ack_i        ( dmem_ack_i        ),
    .dmem_q_i          ( dmem_q_i          ),
    .dmem_misaligned_i ( dmem_misaligned_i ),
    .dmem_page_fault_i ( dmem_page_fault_i ),
    .dmem_err_i        ( dmem_err_i        ),
    .wb_dst_o          ( wb_dst            ),
    .wb_r_o            ( wb_r              ),
    .wb_memq_o         ( wb_memq           ),
    .wb_we_o           ( wb_we             ) );


  /*
  * Additional stage for RF_REGOUT=1
  * Simply delays WB outputs purely for bypass purposes
  */
  riscv_dwb #(
    .XLEN       ( XLEN       ),
    .PC_INIT    ( PC_INIT    ) )
  dwb_unit (
    .rst_ni     ( rst_ni     ),
    .clk_i      ( clk_i      ),
    .wb_insn_i  ( wb_insn    ),
    .wb_we_i    ( wb_we      ),
    .wb_r_i     ( wb_r       ),
    .dwb_insn_o ( dwb_insn   ),
    .dwb_r_o    ( dwb_r      ) );


  /*
   * Thread state
   */
  riscv_state1_10 #(
    .XLEN                  ( XLEN                  ),
    .PC_INIT               ( PC_INIT               ),
    .HAS_FPU               ( HAS_FPU               ),
    .HAS_MMU               ( HAS_MMU               ),
    .HAS_USER              ( HAS_USER              ),
    .HAS_SUPER             ( HAS_SUPER             ),
    .HAS_HYPER             ( HAS_HYPER             ),

    .MNMIVEC_DEFAULT       ( MNMIVEC_DEFAULT       ),
    .MTVEC_DEFAULT         ( MTVEC_DEFAULT         ),
    .HTVEC_DEFAULT         ( HTVEC_DEFAULT         ),
    .STVEC_DEFAULT         ( STVEC_DEFAULT         ),
    .UTVEC_DEFAULT         ( UTVEC_DEFAULT         ),

    .JEDEC_BANK            ( JEDEC_BANK            ),
    .JEDEC_MANUFACTURER_ID ( JEDEC_MANUFACTURER_ID ),

    .PMP_CNT               ( PMP_CNT               ),
    .HARTID                ( HARTID                ) )
  cpu_state    (
    .rst_ni          ( rst_ni        ),
    .clk_i           ( clk_i         ),

    .id_pc_i         ( id_pc         ),
    .id_insn_i       ( id_insn       ),

    .bu_flush_i      ( bu_flush      ),
    .bu_nxt_pc_i     ( bu_nxt_pc     ),
    .st_flush_o      ( st_flush      ),
    .st_nxt_pc_o     ( st_nxt_pc     ),

    .wb_pc_i         ( wb_pc         ),
    .wb_insn_i       ( wb_insn       ),
    .wb_exceptions_i ( wb_exceptions ),
    .wb_badaddr_i    ( wb_badaddr    ),

    .st_interrupt_o  (               ),
    .st_prv_o        ( st_prv_o      ),
    .st_xlen_o       ( st_xlen       ),
    .st_tvm_o        ( st_tvm        ),
    .st_tw_o         ( st_tw         ),
    .st_tsr_o        ( st_tsr        ),
    .st_mcounteren_o ( st_mcounteren ),
    .st_scounteren_o ( st_scounteren ),
    .st_pmpcfg_o     ( st_pmpcfg_o   ),
    .st_pmpaddr_o    ( st_pmpaddr_o  ),

    .ext_int_i       ( ext_int_i     ),
    .ext_tint_i      ( ext_tint_i    ),
    .ext_sint_i      ( ext_sint_i    ),
    .ext_nmi_i       ( ext_nmi_i     ),

    .pd_stall_i      ( pd_stall      ),
    .pd_csr_reg_i    ( pd_csr_reg    ),
    .ex_csr_reg_i    ( ex_csr_reg    ),
    .ex_csr_we_i     ( ex_csr_we     ),
    .ex_csr_wval_i   ( ex_csr_wval   ),
    .st_csr_rval_o   ( st_csr_rval   ),

    .du_stall_i      ( du_stall      ),
    .du_flush_i      ( du_flush      ),
    .du_re_csr_i     ( du_re_csr     ),
    .du_we_csr_i     ( du_we_csr     ),
    .du_csr_rval_o   ( du_csr_rval   ),
    .du_dato_i       ( du_dato       ),
    .du_addr_i       ( du_addr       ),
    .du_ie_i         ( du_ie         ),
    .du_exceptions_o ( du_exceptions ) );


  /*
   *  Integer Register File
   */
  assign rf_src1 = (RF_REGOUT > 0) ? pd_rs1 : id_rs1;
  assign rf_src2 = (RF_REGOUT > 0) ? pd_rs2 : id_rs2;

  riscv_rf #(
    .XLEN        ( XLEN       ),
    .REGOUT      ( RF_REGOUT  ) )
  int_rf (
    .rst_ni      ( rst_ni     ),
    .clk_i       ( clk_i      ),

    .rf_src1_i   ( rf_src1    ),
    .rf_src2_i   ( rf_src2    ),
    .rf_src1_q_o ( rf_srcv1   ),
    .rf_src2_q_o ( rf_srcv2   ),

    .rf_dst_i    ( wb_dst     ),
    .rf_dst_d_i  ( wb_r       ),
    .rf_we_i     ( wb_we      ),
    .stall_i     ( pd_stall   ),

    .du_stall_i  ( du_stall   ),
    .du_we_rf_i  ( du_we_rf   ),
    .du_d_i      ( du_dato    ),
    .du_rf_q_o   ( du_dati_rf ),
    .du_addr_i   ( du_addr    ) );


  /*
   * Branch Prediction Unit
   *
   * Get Branch Prediction for Next Program Counter
   */
generate
  if (HAS_BPU == 0)
  begin
      assign bp_bp_predict = 2'b00;
  end
  else
    riscv_bp #(
      .XLEN                   ( XLEN                 ),
      .PC_INIT                ( PC_INIT              ),
      .HAS_RVC                ( HAS_RVC              ),
      .BP_GLOBAL_BITS         ( BP_GLOBAL_BITS       ),
      .BP_LOCAL_BITS          ( BP_LOCAL_BITS        ),
      .BP_LOCAL_BITS_LSB      ( 2                    ), 
      .TECHNOLOGY             ( TECHNOLOGY           ) )
    bp_unit(
      .rst_ni                 ( rst_ni               ),
      .clk_i                  ( clk_i                ),

      //read branch prediciton
      .id_stall_i             ( id_stall             ),
      .if_parcel_bp_history_i ( if_predict_history   ),
      .if_parcel_pc_i         ( if_predict_pc        ),
      .bp_bp_predict_o        ( bp_bp_predict        ),

      //update branch prediction
      .ex_pc_i                ( ex_pc                ),
      .bu_bp_history_i        ( bu_bp_history_update ),
      .bu_bp_predict_i        ( bu_bp_predict        ),
      .bu_bp_btaken_i         ( bu_bp_btaken         ),
      .bu_bp_update_i         ( bu_bp_update         ) );
endgenerate


  /*
   * Debug Unit
   */
  riscv_du #(
    .XLEN              ( XLEN            ),
    .BREAKPOINTS       ( BREAKPOINTS     ) )
  du_unit (
    .rst_ni            ( rst_ni          ),
    .clk_i             ( clk_i           ),

    .dbg_stall_i       ( dbg_stall_i     ),
    .dbg_strb_i        ( dbg_strb_i      ),
    .dbg_we_i          ( dbg_we_i        ),
    .dbg_addr_i        ( dbg_addr_i      ),
    .dbg_d_i           ( dbg_dati_i      ),
    .dbg_q_o           ( dbg_dato_o      ),
    .dbg_ack_o         ( dbg_ack_o       ),
    .dbg_bp_o          ( dbg_bp_o        ),

    .du_dbg_mode_o     (),  
    .du_stall_o        ( du_stall        ),
    .du_stall_if_o     ( du_stall_if     ),

    .du_latch_nxt_pc_o ( du_latch_nxt_pc ),
    .du_flush_o        ( du_flush        ),
    .du_we_rf_o        ( du_we_rf        ),
    .du_we_frf_o       ( du_we_frf       ),
    .du_re_csr_o       ( du_re_csr       ),
    .du_we_csr_o       ( du_we_csr       ),
    .du_we_pc_o        ( du_we_pc        ),
    .du_addr_o         ( du_addr         ),
    .du_d_o            ( du_dato         ),
    .du_ie_o           ( du_ie           ),
    .du_rf_q_i         ( du_dati_rf      ),
    .du_frf_q_i        ( {XLEN{1'b0}}    ), //du_dati_frf     ),
    .st_csr_q_i        ( du_csr_rval     ),
    .if_nxt_pc_i       ( if_nxt_pc       ),
    .if_pc_i           ( if_pc           ),
    .pd_pc_i           ( pd_pc           ),
    .id_pc_i           ( id_pc           ),
    .ex_pc_i           ( ex_pc           ),
    .wb_pc_i           ( wb_pc           ),
    .bu_flush_i        ( bu_flush        ),
    .st_flush_i        ( st_flush        ),

    .if_nxt_insn_i     ( if_nxt_insn     ),
    .if_insn_i         ( if_insn         ),
    .pd_insn_i         ( pd_insn         ),
    .mem_insn_i        ( mem_insn        ),
    .mem_exceptions_i  ( mem_exceptions  ),
    .mem_memadr_i      ( mem_memadr      ),
    .dmem_ack_i        ( dmem_ack_i      ),
    .ex_stall_i        ( ex_stall        ),

    .du_exceptions_i   ( du_exceptions   ) );

endmodule


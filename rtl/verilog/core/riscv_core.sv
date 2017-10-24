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
//    Core                                                     //
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

module riscv_core #(
  parameter            XLEN            = 32,
  parameter [XLEN-1:0] PC_INIT         = 'h200,
  parameter            HAS_USER        = 0,
  parameter            HAS_SUPER       = 0,
  parameter            HAS_HYPER       = 0,
  parameter            HAS_BPU         = 1,
  parameter            HAS_FPU         = 0,
  parameter            HAS_MMU         = 0,
  parameter            HAS_MULDIV      = 0,
  parameter            HAS_AMO         = 0,
  parameter            HAS_RVC         = 1,
  parameter            IS_RV32E        = 0,

  parameter            MULT_LATENCY    = 0,

  parameter            BREAKPOINTS     = 3,

  parameter            BP_GLOBAL_BITS  = 2,
  parameter            BP_LOCAL_BITS   = 10,

  parameter            TECHNOLOGY      = "GENERIC",

  parameter            MNMIVEC_DEFAULT = PC_INIT -'h004,
  parameter            MTVEC_DEFAULT   = PC_INIT -'h040,
  parameter            HTVEC_DEFAULT   = PC_INIT -'h080,
  parameter            STVEC_DEFAULT   = PC_INIT -'h0C0,
  parameter            UTVEC_DEFAULT   = PC_INIT -'h100,

  parameter            VENDORID        = 16'h0001,
  parameter            ARCHID          = (1<<XLEN) | 12,
  parameter            REVMAJOR        = 4'h0,
  parameter            REVMINOR        = 4'h0,

  parameter            HARTID          = 0,

  parameter            PARCEL_SIZE     = 32,
  parameter            INSTR_SIZE      = 32
)
(
  input                      rstn,   //Reset
  input                      clk,    //Clock


  //Instruction Memory Access bus
  input                      if_stall_nxt_pc,
  output [XLEN         -1:0] if_nxt_pc,
  output                     if_stall,
                             if_flush,
  output		     if_out_order,
  input  [PARCEL_SIZE  -1:0] if_parcel,
  input  [XLEN         -1:0] if_parcel_pc,
  input  [ 		1:0] if_parcel_valid,
  input                      if_parcel_misaligned,
  input                      if_parcel_page_fault,

  //Data Memory Access bus
  output [XLEN         -1:0] mem_adr,
                             mem_d,
  input  [XLEN         -1:0] mem_q,
  output                     mem_we,
  output [XLEN/8       -1:0] mem_be,
  output                     mem_req,
  input                      mem_ack,
                             mem_misaligned,
                             mem_page_fault,

  //cpu state
  output [              1:0] st_prv,
  output                     bu_cacheflush,

  //Interrupts
  input                      ext_nmi,
                             ext_tint,
                             ext_sint,
  input  [              3:0] ext_int,


  //Debug Interface
  input                      dbg_stall,
  input                      dbg_strb,
  input                      dbg_we,
  input  [riscv_du_pkg::DBG_ADDR_SIZE-1:0] dbg_addr,
  input  [XLEN         -1:0] dbg_dati,
  output [XLEN         -1:0] dbg_dato,
  output                     dbg_ack,
  output                     dbg_bp
);


  ////////////////////////////////////////////////////////////////
  //
  // Variables
  //
  import riscv_pkg::*;
  import riscv_du_pkg::*;


  logic [XLEN          -1:0] bu_nxt_pc,
                             st_nxt_pc,
			     branch_pc,
                             if_pc,
			     pd_pc,
                             id_pc,
                             ex_pc,
                             wb_pc;			     

  logic [INSTR_SIZE    -1:0] if_instr,
			     pd_instr,
                             id_instr,
                             ex_instr,
                             wb_instr;

  logic                      if_bubble,
			     pd_bubble,
                             id_bubble,
                             ex_bubble,
                             wb_bubble;

  logic                      bu_flush,
                             st_flush,
                             du_flush;

  logic                      id_stall,
                             ex_stall,
                             wb_stall,
                             du_stall,
                             du_stall_dly;

  //Branch Prediction
  logic [               1:0] bp_bp_predict,
                             pd_bp_predict,
                             id_bp_predict,
                             bu_bp_predict;

  logic [BP_GLOBAL_BITS-1:0] bu_bp_history;
  logic                      bu_bp_btaken,
                             bu_bp_update;


  //Exceptions
  logic [EXCEPTION_SIZE-1:0] if_exception,
			     pd_exception,
                             id_exception,
                             ex_exception,
                             wb_exception;

  //RF access
  logic [XLEN          -1:0] id_srcv2;
  logic [               4:0] rf_src1 [1],
                             rf_src2 [1],
                             rf_dst  [1];
  logic [XLEN          -1:0] rf_srcv1[1],
                             rf_srcv2[1],
                             rf_dstv [1];
  logic [               0:0] rf_we;           


  //ALU signals
  logic [XLEN          -1:0] id_opA,
                             id_opB,
                             ex_r,
                             ex_memadr,
                             mem_r;

  logic                      id_userf_opA,
                             id_userf_opB,
                             id_bypex_opA,
                             id_bypex_opB,
                             id_bypwb_opA,
                             id_bypwb_opB;

  //CPU state
  logic                      st_interrupt;
  logic [              11:0] ex_csr_reg;
  logic [XLEN          -1:0] ex_csr_wval,
                             st_csr_rval;
  logic                      ex_csr_we;

  //Write back
  logic [               4:0] wb_dst;
  logic [XLEN          -1:0] wb_r;
  logic [               0:0] wb_we;
  logic [XLEN          -1:0] wb_badaddr;

  //Debug
  logic                      du_we_rf,
                             du_we_frf,
                             du_we_csr,
                             du_we_pc;
  logic [DU_ADDR_SIZE  -1:0] du_addr;
  logic [XLEN          -1:0] du_dato,
                             du_dati_rf,
                             du_dati_frf,
                             du_dati_csr;
  logic [              31:0] du_ie,
                             du_exceptions;

  logic 		     is_16bit_instruction,
			     is_32bit_instruction;

  logic			     branch_taken;
    
  ////////////////////////////////////////////////////////////////
  //
  // Module Body
  //

  /*
   * Instruction Fetch
   *
   * Calculate next Program Counter
   * Fetch next instruction
   */
  riscv_if #(
    .XLEN           ( XLEN           ),
    .PC_INIT        ( PC_INIT        ),
    .INSTR_SIZE     ( INSTR_SIZE     ),
    .PARCEL_SIZE    ( PARCEL_SIZE    ),
    .EXCEPTION_SIZE ( EXCEPTION_SIZE ),
    .HAS_BPU        ( HAS_BPU        ) )
  if_unit ( .* );

  riscv_pd #(
    .XLEN           ( XLEN           ),
    .PC_INIT        ( PC_INIT        ),
    .INSTR_SIZE     ( INSTR_SIZE     ),
    .PARCEL_SIZE    ( PARCEL_SIZE    ),
    .EXCEPTION_SIZE ( EXCEPTION_SIZE ),
    .HAS_BPU        ( HAS_BPU        ) )
  pd_unit ( .* );



  /*
   * Instruction Decoder
   *
   * Data from RF/ROB is available here
   */
  riscv_id #(
    .XLEN           ( XLEN           ),
    .PC_INIT        ( PC_INIT        ),
    .INSTR_SIZE     ( INSTR_SIZE     ),
    .EXCEPTION_SIZE ( EXCEPTION_SIZE ),
    .HAS_USER       ( HAS_USER       ),
    .HAS_SUPER      ( HAS_SUPER      ),
    .HAS_HYPER      ( HAS_HYPER      ),
    .HAS_MULDIV     ( HAS_MULDIV     ) )
  id_unit (
    .id_src1  ( rf_src1[0]  ),
    .id_src2  ( rf_src2[0]  ),
    .*
  );


  /*
   * Execution units
   */
  riscv_ex #(
    .XLEN           ( XLEN           ),
    .PC_INIT        ( PC_INIT        ),
    .INSTR_SIZE     ( INSTR_SIZE     ),
    .EXCEPTION_SIZE ( EXCEPTION_SIZE ),
    .HAS_RVC        ( HAS_RVC        ),
    .HAS_AMO        ( HAS_AMO        ),
    .HAS_MULDIV     ( HAS_MULDIV     ),
    .MULT_LATENCY   ( MULT_LATENCY   ) )
  ex_units (
    .rf_srcv1 ( rf_srcv1[0] ),
    .rf_srcv2 ( rf_srcv2[0] ),
    .*
  );

 
  /*
   * Memory + Write Back unit
   */
  riscv_memwb #(
    .XLEN           ( XLEN           ),
    .PC_INIT        ( PC_INIT        ),
    .INSTR_SIZE     ( INSTR_SIZE     ),
    .EXCEPTION_SIZE ( EXCEPTION_SIZE ) )
  memwb_unit   (
    .wb_dst ( rf_dst[0]  ),
    .wb_we  ( rf_we[0]   ),
    .*
  );
 assign rf_dstv[0] = wb_r;


  /*
   * Thread state
   */
  riscv_state1_9 #(
    .XLEN            ( XLEN            ),
    .PC_INIT         ( PC_INIT         ),
    .INSTR_SIZE      ( INSTR_SIZE      ),
    .HAS_FPU         ( HAS_FPU         ),
    .HAS_MMU         ( HAS_MMU         ),
    .EXCEPTION_SIZE  ( EXCEPTION_SIZE  ),
    .HAS_USER        ( HAS_USER        ),
    .HAS_SUPER       ( HAS_SUPER       ),
    .HAS_HYPER       ( HAS_HYPER       ),

    .MNMIVEC_DEFAULT ( MNMIVEC_DEFAULT ),
    .MTVEC_DEFAULT   ( MTVEC_DEFAULT   ),
    .HTVEC_DEFAULT   ( HTVEC_DEFAULT   ),
    .STVEC_DEFAULT   ( STVEC_DEFAULT   ),
    .UTVEC_DEFAULT   ( UTVEC_DEFAULT   ),

    .VENDORID        ( VENDORID        ),
    .ARCHID          ( ARCHID          ),
    .REVMAJOR        ( REVMAJOR        ),
    .REVMINOR        ( REVMINOR        ),

    .HARTID          ( HARTID          ) )
  cpu_state    ( .* );


  /*
   *  Integer Register File
   */
  riscv_rf #(
    .XLEN    ( XLEN ),
    .RDPORTS ( 1    ),
    .WRPORTS ( 1    ) )
  int_rf    ( .* );


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
      .XLEN              ( XLEN           ),
      .PC_INIT           ( PC_INIT        ),
      .BP_GLOBAL_BITS    ( BP_GLOBAL_BITS ),
      .BP_LOCAL_BITS     ( BP_LOCAL_BITS  ),
      .BP_LOCAL_BITS_LSB ( 2              ), 
      .TECHNOLOGY        ( TECHNOLOGY     ) )
    bp_unit( .* );
endgenerate


  /*
   * MMU
   */
generate
  if (HAS_MMU == 0)
  begin
//      assign if_parcel_page_fault = 1'b0;
//      assign mem_page_fault = 1'b0;
  end
  else
    riscv_mmu
    mmu ( );
endgenerate


  /*
   * Debug Unit
   */
  riscv_du #(
    .XLEN           ( XLEN           ),
    .INSTR_SIZE     ( INSTR_SIZE     ),
    .BREAKPOINTS    ( BREAKPOINTS    ),
    .EXCEPTION_SIZE ( EXCEPTION_SIZE )
  )
  du_unit ( .* );

endmodule


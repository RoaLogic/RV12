/////////////////////////////////////////////////////////////////////
//   ,------.                    ,--.                ,--.          //
//   |  .--. ' ,---.  ,--,--.    |  |    ,---. ,---. `--' ,---.    //
//   |  '--'.'| .-. |' ,-.  |    |  |   | .-. | .-. |,--.| .--'    //
//   |  |\  \ ' '-' '\ '-'  |    |  '--.' '-' ' '-' ||  |\ `--.    //
//   `--' '--' `---'  `--`--'    `-----' `---' `-   /`--' `---'    //
//                                             `---'               //
//    RISC-V                                                       //
//    (Thread) State (priv spec 1.10)                              //
//                                                                 //
/////////////////////////////////////////////////////////////////////
//                                                                 //
//             Copyright (C) 2018-2021 Roa Logic BV                //
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

import riscv_rvl_pkg::*;
import riscv_opcodes_pkg::*;
import riscv_state_pkg::*;

module riscv_state1_10 #(
  parameter            XLEN            = 32,
  parameter            FLEN            = 64,    // Floating Point Data length
  parameter [XLEN-1:0] PC_INIT         = 'h200,

  parameter            IS_RV32E        = 0,
  parameter            HAS_RVN         = 0,
  parameter            HAS_RVC         = 0,
  parameter            HAS_FPU         = 0,
  parameter            HAS_MMU         = 0,
  parameter            HAS_RVM         = 0,
  parameter            HAS_RVA         = 0,
  parameter            HAS_RVB         = 0,
  parameter            HAS_RVT         = 0,
  parameter            HAS_RVP         = 0,
  parameter            HAS_EXT         = 0,

  parameter            HAS_USER        = 1,
  parameter            HAS_SUPER       = 1,
  parameter            HAS_HYPER       = 0,

  parameter            MNMIVEC_DEFAULT = PC_INIT -'h004,
  parameter            MTVEC_DEFAULT   = PC_INIT -'h040,
  parameter            HTVEC_DEFAULT   = PC_INIT -'h080,
  parameter            STVEC_DEFAULT   = PC_INIT -'h0C0,
  parameter            UTVEC_DEFAULT   = PC_INIT -'h100,

  parameter            JEDEC_BANK            = 9,
  parameter            JEDEC_MANUFACTURER_ID = 'h8a,

  parameter            PMP_CNT               = 16,    //number of PMP CSR blocks (max.16)
  parameter            HARTID                = 0      //hardware thread-id
)
(
  input                             rst_ni,
  input                             clk_i,

  input               [XLEN   -1:0] id_pc_i,
  input  instruction_t              id_insn_i,

  input                             bu_flush_i,
  input               [XLEN   -1:0] bu_nxt_pc_i,
  output reg                        st_flush_o,
  output reg          [XLEN   -1:0] st_nxt_pc_o,

  input               [XLEN   -1:0] wb_pc_i,
  input  instruction_t              wb_insn_i,
  input  interrupts_exceptions_t    wb_exceptions_i,
  input               [XLEN   -1:0] wb_badaddr_i,

  output reg          [        1:0] st_prv_o,        //Privilege level
  output reg          [        1:0] st_xlen_o,       //Active Architecture
  output                            st_tvm_o,        //trap on satp access or SFENCE.VMA
                                    st_tw_o,         //trap on WFI (after time >=0)
                                    st_tsr_o,        //trap SRET
  output              [XLEN   -1:0] st_mcounteren_o,
                                    st_scounteren_o,
  output pmpcfg_t     [       15:0] st_pmpcfg_o,
  output [       15:0][XLEN   -1:0] st_pmpaddr_o,


  //interrupts (3=M-mode, 0=U-mode)
  input               [        3:0] int_external_i,  //external interrupt (per privilege mode; determined by PIC)
  input                             int_timer_i,     //machine timer interrupt
                                    int_software_i,  //machine software interrupt (for ipi)
  output interrupts_t               st_int_o,

  
  //CSR interface
  input                             pd_stall_i,
  input                             id_stall_i,
  input               [       11:0] pd_csr_reg_i,
  input               [       11:0] ex_csr_reg_i,
  input                             ex_csr_we_i,
  input               [XLEN   -1:0] ex_csr_wval_i,
  output reg          [XLEN   -1:0] st_csr_rval_o,

  //Debug interface
  input                             du_stall_i,
                                    du_flush_i,
                                    du_re_csr_i,
                                    du_we_csr_i,
  output reg           [XLEN  -1:0] du_csr_rval_o,
  input                [XLEN  -1:0] du_dato_i,       //output from debug unit
  input                [      11:0] du_addr_i,
  input                [      31:0] du_ie_i,
  output               [      31:0] du_exceptions_o
);
  ////////////////////////////////////////////////////////////////
  //
  // Constants
  //
  localparam EXT_XLEN = (XLEN > 32) ? XLEN-32 : 32;


  ////////////////////////////////////////////////////////////////
  //
  // Functions
  //
  function [3:0] get_trap_cause;
    input [EXCEPTION_SIZE-1:0] exception;
    integer n;

    get_trap_cause = 0;

    for (n=0; n < EXCEPTION_SIZE; n++)
     if (exception[n]) get_trap_cause = n;
  endfunction : get_trap_cause


  ////////////////////////////////////////////////////////////////
  //
  // Variables
  //

  /*
   * CSRs
   */
  typedef struct packed {
    /*
     * User
     */
    //Floating point registers
    fcsr_struct        fcsr;

    //User trap setup
    logic  [XLEN -1:0] utvec;

    //User trap handler
    logic  [XLEN -1:0] uscratch;   //scratch register
    logic  [XLEN -1:0] uepc;       //exception program counter
    logic  [XLEN -1:0] ucause;     //trap cause
    logic  [XLEN -1:0] utval;      //bad address


    /*
     * Supervisor
     */
    //Supervisor trap setup
    logic  [XLEN -1:0] stvec;      //trap handler base address
    logic  [XLEN -1:0] scounteren; //Enable performance counters for lower privilege level
    logic  [XLEN -1:0] sedeleg;    //trap delegation register

    //Supervisor trap handler
    logic  [XLEN -1:0] sscratch;   //scratch register
    logic  [XLEN -1:0] sepc;       //exception program counter
    logic  [XLEN -1:0] scause;     //trap cause
    logic  [XLEN -1:0] stval;      //bad address

    //Supervisor protection and Translation
    logic  [XLEN -1:0] satp;       //Address translation & protection


    /*
     * Hypervisor
    //Hypervisor Trap Setup
    logic  [XLEN-1:0] htvec;    //trap handler base address
    logic  [XLEN-1:0] hedeleg;  //trap delegation register

    //Hypervisor trap handler
    logic  [XLEN-1:0] hscratch; //scratch register
    logic  [XLEN-1:0] hepc;     //exception program counter
    logic  [XLEN-1:0] hcause;   //trap cause
    logic  [XLEN-1:0] htval;    //bad address

    //Hypervisor protection and Translation
    //TBD per spec v1.7, somewhat defined in 1.9, removed in 1.10
    */

    /*
     * Machine
     */
    mvendorid_struct   mvendorid;  //Vendor-ID
    logic  [XLEN -1:0] marchid,    //Architecture ID
                       mimpid;     //Revision number
    logic  [XLEN -1:0] mhartid;    //Hardware Thread ID

    //Machine Trap Setup
    mstatus_struct     mstatus;    //status
    misa_struct        misa;       //Machine ISA
    logic  [XLEN -1:0] mnmivec;    //ROALOGIC NMI handler base address
    logic  [XLEN -1:0] mtvec;      //trap handler base address
    logic  [XLEN -1:0] mcounteren; //Enable performance counters for lower level
    logic  [XLEN -1:0] medeleg,    //Exception delegation
                       mideleg;    //Interrupt delegation
    mie_struct         mie;        //interrupt enable

    //Machine trap handler
    logic  [XLEN -1:0] mscratch;   //scratch register
    logic  [XLEN -1:0] mepc;       //exception program counter
    logic  [XLEN -1:0] mcause;     //trap cause
    logic  [XLEN -1:0] mtval;      //bad address
    mip_struct         mip;        //interrupt pending

    //Machine protection and Translation
    pmpcfg_t [15:0]            pmpcfg;
    logic    [15:0][XLEN -1:0] pmpaddr;

    //Machine counters/Timers
    timer_struct       mcycle,     //timer for MCYCLE
                       minstret;   //instruction retire count for MINSTRET
  } csr_struct;
  csr_struct csr;


  logic             is_rv32,
                    is_rv32e,
                    is_rv64,
                    is_rv128,
                    has_rvc,
                    has_fpu, has_fpud, has_fpuq,
                    has_decfpu,
                    has_mmu,
                    has_muldiv,
                    has_amo,
                    has_bm,
                    has_tmem,
                    has_simd,
                    has_n,
                    has_u,
                    has_s,
                    has_h,
                    has_ext;

  logic [    127:0] mstatus;      //mstatus is special (can be larger than 32bits)
  logic [      1:0] uxl_wval,     //u/sxl are taken from bits 35:32
                    sxl_wval;     //and can only have limited values

  logic             soft_seip,    //software supervisor-external-interrupt
                    soft_ueip;    //software user-external-interrupt

  logic             take_interrupt;

  logic [      3:0] interrupt_cause,
                    trap_cause;


  //CSR access
  logic [     11:0] csr_raddr;    //CSR read address
  logic [XLEN -1:0] csr_rval;     //CSR read value
  logic [XLEN -1:0] csr_wval;     //CSR write value


  ////////////////////////////////////////////////////////////////
  //
  // Module Body
  //
  assign is_rv32   = (XLEN       ==  32);
  assign is_rv64   = (XLEN       ==  64);
  assign is_rv128  = (XLEN       == 128);
  assign is_rv32e  = (IS_RV32E   !=   0) & is_rv32;
  assign has_n     = (HAS_RVN    !=   0) & has_u;
  assign has_u     = (HAS_USER   !=   0);
  assign has_s     = (HAS_SUPER  !=   0) & has_u;
  assign has_h     = 1'b0;  //(HAS_HYPER  !=   0) & has_s;   //No Hypervisor

  assign has_rvc   = (HAS_RVC    !=   0);
  assign has_fpu   = (HAS_FPU    !=   0);
  assign has_fpuq  = (FLEN       == 128) & has_fpu;
  assign has_fpud  =((FLEN       ==  64) & has_fpu) | has_fpuq;
  assign has_decfpu= 1'b0;
  assign has_mmu   = (HAS_MMU    !=   0) & has_s;
  assign has_muldiv= (HAS_RVM    !=   0);
  assign has_amo   = (HAS_RVA    !=   0);
  assign has_bm    = (HAS_RVB    !=   0);
  assign has_tmem  = (HAS_RVT    !=   0);
  assign has_simd  = (HAS_RVP    !=   0);
  assign has_ext   = (HAS_EXT    !=   0);

  //Mux address/data for Debug-Unit access
  always @(posedge clk_i)
	  if      ( du_re_csr_i) csr_raddr <= du_addr_i;
	  else if (!pd_stall_i ) csr_raddr <= pd_csr_reg_i;

  assign csr_wval  = du_we_csr_i ? du_dato_i : ex_csr_wval_i;



  /*
   * Priviliged Control Registers
   */
  //mstatus has different values for RV32 and RV64/RV128
  //treat it here as though it is a 128bit register
  assign mstatus = {csr.mstatus.sd,
                    {128-37{1'b0}},
                    csr.mstatus.sxl,
                    csr.mstatus.uxl,
                    {9{1'b0}},
                    csr.mstatus.tsr,
                    csr.mstatus.tw,
                    csr.mstatus.tvm,
                    csr.mstatus.mxr,
                    csr.mstatus.sum,
                    csr.mstatus.mprv,
                    csr.mstatus.xs,
                    csr.mstatus.fs,
                    csr.mstatus.mpp,
                    2'b00,
                    csr.mstatus.spp,
                    csr.mstatus.mpie,
                    1'b0,
                    csr.mstatus.spie,
                    csr.mstatus.upie,
                    csr.mstatus.mie,
                    1'b0,
                    csr.mstatus.sie,
                    csr.mstatus.uie};

  
  //Read
  always_comb
    unique case (csr_raddr)
      //User
      USTATUS   : csr_rval = {mstatus[127],mstatus[XLEN-2:0]} & 'h11;
      UIE       : csr_rval = has_n ? csr.mie & 12'h111               : 'h0;
      UTVEC     : csr_rval = has_n ? csr.utvec                       : 'h0;
      USCRATCH  : csr_rval = has_n ? csr.uscratch                    : 'h0;
      UEPC      : csr_rval = has_n ? csr.uepc                        : 'h0;
      UCAUSE    : csr_rval = has_n ? csr.ucause                      : 'h0;
      UTVAL     : csr_rval = has_n ? csr.utval                       : 'h0;
      UIP       : csr_rval = has_n ? csr.mip & csr.mideleg & 12'h111 : 'h0;

      FFLAGS    : csr_rval = has_fpu ? { {XLEN-$bits(csr.fcsr.flags){1'b0}},csr.fcsr.flags } : 'h0;
      FRM       : csr_rval = has_fpu ? { {XLEN-$bits(csr.fcsr.rm   ){1'b0}},csr.fcsr.rm    } : 'h0;
      FCSR      : csr_rval = has_fpu ? { {XLEN-$bits(csr.fcsr      ){1'b0}},csr.fcsr       } : 'h0;
      CYCLE     : csr_rval = csr.mcycle[XLEN-1:0];
//      TIME      : csr_rval = csr.timer[XLEN-1:0];
      INSTRET   : csr_rval = csr.minstret[XLEN-1:0];
      CYCLEH    : csr_rval = is_rv32 ? csr.mcycle.h   : 'h0;
//      TIMEH     : csr_rval = is_rv32 ? csr.timer.h   : 'h0;
      INSTRETH  : csr_rval = is_rv32 ? csr.minstret.h : 'h0;

      //Supervisor
      SSTATUS   : csr_rval = {mstatus[127],mstatus[XLEN-2:0]} & (1 << XLEN-1 | 2'b11 << 32 | 'hde133);
      STVEC     : csr_rval = has_s            ? csr.stvec                       : 'h0;
      SCOUNTEREN: csr_rval = has_s            ? csr.scounteren                  : 'h0;
      SIE       : csr_rval = has_s            ? csr.mie               & 12'h333 : 'h0;
      SEDELEG   : csr_rval = has_s            ? csr.sedeleg                     : 'h0;
      SIDELEG   : csr_rval = has_s            ? csr.mideleg           & 12'h111 : 'h0;
      SSCRATCH  : csr_rval = has_s            ? csr.sscratch                    : 'h0;
      SEPC      : csr_rval = has_s            ? csr.sepc                        : 'h0;
      SCAUSE    : csr_rval = has_s            ? csr.scause                      : 'h0;
      STVAL     : csr_rval = has_s            ? csr.stval                       : 'h0;
      SIP       : csr_rval = has_s            ? csr.mip & csr.mideleg & 12'h333 : 'h0;
      SATP      : csr_rval = has_s && has_mmu ? csr.satp                        : 'h0;
/*
      //Hypervisor
      HSTATUS   : csr_rval = {mstatus[127],mstatus[XLEN-2:0] & (1 << XLEN-1 | 2'b11 << 32 | 'hde133);
      HTVEC     : csr_rval = has_h ? csr.htvec                       : 'h0;
      HIE       : csr_rval = has_h ? csr.mie & 12'h777               : 'h0;
      HEDELEG   : csr_rval = has_h ? csr.hedeleg                     : 'h0;
      HIDELEG   : csr_rval = has_h ? csr.mideleg & 12'h333           : 'h0;
      HSCRATCH  : csr_rval = has_h ? csr.hscratch                    : 'h0;
      HEPC      : csr_rval = has_h ? csr.hepc                        : 'h0;
      HCAUSE    : csr_rval = has_h ? csr.hcause                      : 'h0;
      HTVAL     : csr_rval = has_h ? csr.htval                       : 'h0;
      HIP       : csr_rval = has_h ? csr.mip & csr.mideleg & 12'h777 : 'h0;
*/
      //Machine
      MISA      : csr_rval = {csr.misa.base, {XLEN-$bits(csr.misa){1'b0}}, csr.misa.extensions};
      MVENDORID : csr_rval = {{XLEN-$bits(csr.mvendorid){1'b0}}, csr.mvendorid};
      MARCHID   : csr_rval = csr.marchid;
      MIMPID    : csr_rval = is_rv32 ? csr.mimpid : { {XLEN-$bits(csr.mimpid){1'b0}}, csr.mimpid };
      MHARTID   : csr_rval = csr.mhartid;
      MSTATUS   : csr_rval = {mstatus[127],mstatus[XLEN-2:0]};
      MTVEC     : csr_rval = csr.mtvec;
      MCOUNTEREN: csr_rval = csr.mcounteren;
      MNMIVEC   : csr_rval = csr.mnmivec;
      MEDELEG   : csr_rval = csr.medeleg;
      MIDELEG   : csr_rval = csr.mideleg;
      MIE       : csr_rval = csr.mie & 12'hFFF;
      MSCRATCH  : csr_rval = csr.mscratch;
      MEPC      : csr_rval = csr.mepc;
      MCAUSE    : csr_rval = csr.mcause;
      MTVAL     : csr_rval = csr.mtval;
      MIP       : csr_rval = csr.mip;
      PMPCFG0   : csr_rval =            csr.pmpcfg[ 0 +: XLEN/8];
      PMPCFG1   : csr_rval = is_rv32  ? csr.pmpcfg[ 4 +: XLEN/8] : 'h0;
      PMPCFG2   : csr_rval =~is_rv128 ? csr.pmpcfg[ 8 +: XLEN/8] : 'h0;
      PMPCFG3   : csr_rval = is_rv32  ? csr.pmpcfg[12 +: XLEN/8] : 'h0;
      PMPADDR0  : csr_rval = csr.pmpaddr[0];
      PMPADDR1  : csr_rval = csr.pmpaddr[1];
      PMPADDR2  : csr_rval = csr.pmpaddr[2];
      PMPADDR3  : csr_rval = csr.pmpaddr[3];
      PMPADDR4  : csr_rval = csr.pmpaddr[4];
      PMPADDR5  : csr_rval = csr.pmpaddr[5];
      PMPADDR6  : csr_rval = csr.pmpaddr[6];
      PMPADDR7  : csr_rval = csr.pmpaddr[7];
      PMPADDR8  : csr_rval = csr.pmpaddr[8];
      PMPADDR9  : csr_rval = csr.pmpaddr[9];
      PMPADDR10 : csr_rval = csr.pmpaddr[10];
      PMPADDR11 : csr_rval = csr.pmpaddr[11];
      PMPADDR12 : csr_rval = csr.pmpaddr[12];
      PMPADDR13 : csr_rval = csr.pmpaddr[13];
      PMPADDR14 : csr_rval = csr.pmpaddr[14];
      PMPADDR15 : csr_rval = csr.pmpaddr[15];
      MCYCLE    : csr_rval = csr.mcycle[XLEN-1:0];
      MINSTRET  : csr_rval = csr.minstret[XLEN-1:0];
      MCYCLEH   : csr_rval = is_rv32 ? csr.mcycle.h   : 'h0;
      MINSTRETH : csr_rval = is_rv32 ? csr.minstret.h : 'h0;

      default   : csr_rval = 32'h0;
    endcase


  //output CSR read value; bypass a write
  always @(posedge clk_i)
    if (!id_stall_i) st_csr_rval_o <= csr_rval;

  always @(posedge clk_i)
    du_csr_rval_o <= csr_rval;



  ////////////////////////////////////////////////////////////////
  // Machine registers
  //
  assign csr.misa.base       = is_rv128 ? RV128I : is_rv64 ? RV64I : RV32I;
  assign csr.misa.extensions =  '{z: 1'b0,       //reserved
                                  y: 1'b0,       //reserved
                                  x: has_ext,    
                                  w: 1'b0,       //reserved
                                  v: 1'b0,       //reserved for vector extensions
                                  u: has_u,      //user mode supported
                                  t: has_tmem,
                                  s: has_s,      //supervisor mode supported
                                  r: 1'b0,       //reserved
                                  q: has_fpuq,
                                  p: has_simd,
                                  o: 1'b0,       //reserved
                                  n: has_n,
                                  m: has_muldiv,
                                  l: has_decfpu,
                                  k: 1'b0,       //reserved
                                  j: 1'b0,       //reserved for JIT
                                  i: ~is_rv32e,
                                  h: 1'b0,       //reserved
                                  g: 1'b0,       //additional extensions
                                  f: has_fpu,
                                  e: is_rv32e,
                                  d: has_fpud,
                                  c: has_rvc,
                                  b: has_bm,
                                  a: has_amo,
                                  default : 1'b0};

  assign csr.mvendorid.bank    = JEDEC_BANK -1;
  assign csr.mvendorid.offset  = JEDEC_MANUFACTURER_ID[6:0];
  assign csr.marchid           = (1 << (XLEN-1)) | ARCHID;
  assign csr.mimpid[    31:24] = REVPRV_MAJOR;
  assign csr.mimpid[    23:16] = REVPRV_MINOR;
  assign csr.mimpid[    15: 8] = REVUSR_MAJOR;
  assign csr.mimpid[     7: 0] = REVUSR_MINOR;
  assign csr.mhartid           = HARTID;

  //mstatus
  assign csr.mstatus.sd = &csr.mstatus.fs | &csr.mstatus.xs;

  assign st_tvm_o = csr.mstatus.tvm;
  assign st_tw_o  = csr.mstatus.tw;
  assign st_tsr_o = csr.mstatus.tsr;

generate
  if (XLEN == 128)
  begin
      assign sxl_wval = |csr_wval[35:34] ? csr_wval[35:34] : csr.mstatus.sxl;
      assign uxl_wval = |csr_wval[33:32] ? csr_wval[33:32] : csr.mstatus.uxl;
  end
  else if (XLEN == 64)
  begin
      assign sxl_wval = csr_wval[35:34]==RV32I || csr_wval[35:34]==RV64I ? csr_wval[35:34] : csr.mstatus.sxl;
      assign uxl_wval = csr_wval[33:32]==RV32I || csr_wval[33:32]==RV64I ? csr_wval[33:32] : csr.mstatus.uxl;
  end
  else
  begin
      assign sxl_wval = 2'b00;
      assign uxl_wval = 2'b00;
  end
endgenerate


  always_comb
    case (st_prv_o)
      PRV_S  : st_xlen_o = has_s ? csr.mstatus.sxl : csr.misa.base;
      PRV_U  : st_xlen_o = has_u ? csr.mstatus.uxl : csr.misa.base;
      default: st_xlen_o = csr.misa.base;
    endcase


  always @(posedge clk_i,negedge rst_ni)
    if (!rst_ni)
    begin
        st_prv_o           <= PRV_M;    //start in machine mode
        st_nxt_pc_o        <= PC_INIT;
        st_flush_o         <= 1'b1;     //flush CPU(heart) upon reset exit

//        csr.mstatus.vm   <= VM_MBARE;
        csr.mstatus.sxl  <= has_s ? csr.misa.base : 2'b00;
        csr.mstatus.uxl  <= has_u ? csr.misa.base : 2'b00;
        csr.mstatus.tsr  <= 1'b0;
        csr.mstatus.tw   <= 1'b0;
        csr.mstatus.tvm  <= 1'b0;
        csr.mstatus.mxr  <= 1'b0;
        csr.mstatus.sum  <= 1'b0;
        csr.mstatus.mprv <= 1'b0;
        csr.mstatus.xs   <= {2{has_ext}};
        csr.mstatus.fs   <= 2'b00;

        csr.mstatus.mpp  <= PRV_M;
        csr.mstatus.hpp  <= 2'h0;  //reserved
        csr.mstatus.spp  <= has_s;
        csr.mstatus.mpie <= 1'b0;
        csr.mstatus.hpie <= 1'b0;  //reserved
        csr.mstatus.spie <= 1'b0;
        csr.mstatus.upie <= 1'b0;
        csr.mstatus.mie  <= 1'b0;
        csr.mstatus.hie  <= 1'b0;  //reserved
        csr.mstatus.sie  <= 1'b0;
        csr.mstatus.uie  <= 1'b0;
    end
    else
    begin
        st_flush_o <= 1'b0;

        //write from EX, Machine Mode
        if ( (ex_csr_we_i && ex_csr_reg_i == MSTATUS && st_prv_o == PRV_M) ||
             (du_we_csr_i && du_addr_i    == MSTATUS)                     )
        begin
//            csr.mstatus.vm    <= csr_wval[28:24];
            csr.mstatus.sxl   <= has_s && XLEN > 32 ? sxl_wval        : 2'b00;
            csr.mstatus.uxl   <= has_u && XLEN > 32 ? uxl_wval        : 2'b00;
            csr.mstatus.tsr   <= has_s              ? csr_wval[22]    : 1'b0;
            csr.mstatus.tw    <= has_s              ? csr_wval[21]    : 1'b0;
            csr.mstatus.tvm   <= has_s              ? csr_wval[20]    : 1'b0;
            csr.mstatus.mxr   <= has_s              ? csr_wval[19]    : 1'b0;
            csr.mstatus.sum   <= has_s              ? csr_wval[18]    : 1'b0;
            csr.mstatus.mprv  <= has_u              ? csr_wval[17]    : 1'b0;
            csr.mstatus.xs    <= has_ext            ? csr_wval[16:15] : 2'b00; //TODO
            csr.mstatus.fs    <= has_s && has_fpu   ? csr_wval[14:13] : 2'b00; //TODO

	    case (csr_wval[12:11])
              PRV_M: csr.mstatus.mpp <=         PRV_M;
              PRV_H: csr.mstatus.mpp <= has_h ? PRV_H : csr.mstatus.mpp;
              PRV_S: csr.mstatus.mpp <= has_s ? PRV_S : csr.mstatus.mpp;
              PRV_U: csr.mstatus.mpp <= has_u ? PRV_U : csr.mstatus.mpp;
            endcase
            csr.mstatus.hpp   <= 2'h0;                              //reserved
            csr.mstatus.spp   <= has_s ? csr_wval[   8] : 1'b0;
            csr.mstatus.mpie  <=         csr_wval[   7];
            csr.mstatus.hpie  <= 1'b0;                              //reserved
            csr.mstatus.spie  <= has_s ? csr_wval[   5] : 1'b0;
            csr.mstatus.upie  <= has_n ? csr_wval[   4] : 1'b0;
            csr.mstatus.mie   <=         csr_wval[   3];
            csr.mstatus.hie   <= 1'b0;                              //reserved
            csr.mstatus.sie   <= has_s ? csr_wval[   1] : 1'b0;
            csr.mstatus.uie   <= has_n ? csr_wval[   0] : 1'b0;
        end

        //Supervisor Mode access
        if (has_s)
        begin
            if ( (ex_csr_we_i && ex_csr_reg_i == SSTATUS && st_prv_o >= PRV_S) ||
                 (du_we_csr_i && du_addr_i    == SSTATUS)                     )
            begin
                csr.mstatus.uxl  <= uxl_wval;
                csr.mstatus.mxr  <= csr_wval[19];
                csr.mstatus.sum  <= csr_wval[18]; 
                csr.mstatus.xs   <= has_ext ? csr_wval[16:15] : 2'b00; //TODO
                csr.mstatus.fs   <= has_fpu ? csr_wval[14:13] : 2'b00; //TODO

                csr.mstatus.spp  <= csr_wval[7];
                csr.mstatus.spie <= csr_wval[5];
                csr.mstatus.upie <= has_n ? csr_wval[4] : 1'b0;
                csr.mstatus.sie  <= csr_wval[1];
                csr.mstatus.uie  <= csr_wval[0];
            end
        end

        //MRET,HRET,SRET,URET
        if (!id_insn_i.bubble && !bu_flush_i)
        begin
            case (id_insn_i.instr)
              //pop privilege stack
              MRET : begin
                         //set privilege level
                         st_prv_o    <= csr.mstatus.mpp;
                         st_nxt_pc_o <= csr.mepc;
                         st_flush_o  <= 1'b1;

                         //set MIE
                         csr.mstatus.mie  <= csr.mstatus.mpie;
                         csr.mstatus.mpie <= 1'b1;
                         csr.mstatus.mpp  <= has_u ? PRV_U : PRV_M;
                     end
/*
              HRET : begin
                         //set privilege level
                         st_prv_o    <= csr.mstatus.hpp;
                         st_nxt_pc_o <= csr.hepc;
                         st_flush_o  <= 1'b1;

                         //set HIE
                         csr.mstatus.hie  <= csr.mstatus.hpie;
                         csr.mstatus.hpie <= 1'b1;
                         csr.mstatus.hpp  <= has_u ? PRV_U : PRV_M;
                     end
*/
              SRET : begin
                         //set privilege level
                         st_prv_o    <= {1'b0,csr.mstatus.spp};
                         st_nxt_pc_o <= csr.sepc;
                         st_flush_o  <= 1'b1;

                         //set SIE
                         csr.mstatus.sie  <= csr.mstatus.spie;
                         csr.mstatus.spie <= 1'b1;
                         csr.mstatus.spp  <= 1'b0; //Must have User-mode. SPP is only 1 bit
                     end
              URET : begin
                         //set privilege level
                         st_prv_o    <= PRV_U;
                         st_nxt_pc_o <= csr.uepc;
                         st_flush_o  <= 1'b1;

                         //set UIE
                         csr.mstatus.uie  <= csr.mstatus.upie;
                         csr.mstatus.upie <= 1'b1;
                     end
            endcase
        end

        //push privilege stack
        if (wb_exceptions_i.nmi)
        begin
$display ("NMI");
            //NMI always at Machine-mode
            st_prv_o    <= PRV_M;
            st_nxt_pc_o <= csr.mnmivec;
            st_flush_o  <= 1'b1;

            //store current state
            csr.mstatus.mpie <= csr.mstatus.mie;
            csr.mstatus.mie  <= 1'b0;
            csr.mstatus.mpp  <= st_prv_o;
        end
        else if (take_interrupt && !du_stall_i && !du_flush_i)
        begin
$display ("take_interrupt");
            st_flush_o  <= 1'b1;

            //Check if interrupts are delegated
            if (has_n && st_prv_o == PRV_U && ( wb_exceptions_i.interrupts & csr.mideleg & 12'h111) )
            begin
                st_prv_o    <= PRV_U;
                st_nxt_pc_o <= csr.utvec & ~'h3 + (csr.utvec[0] ? interrupt_cause << 2 : 0);

                csr.mstatus.upie <= csr.mstatus.uie;
                csr.mstatus.uie  <= 1'b0;
            end
            else if (has_s && st_prv_o >= PRV_S && (wb_exceptions_i.interrupts & csr.mideleg & 12'h333) )
            begin
                st_prv_o    <= PRV_S;
                st_nxt_pc_o <= csr.stvec & ~'h3 + (csr.stvec[0] ? interrupt_cause << 2 : 0);

                csr.mstatus.spie <= csr.mstatus.sie;
                csr.mstatus.sie  <= 1'b0;
                csr.mstatus.spp  <= st_prv_o[0];
            end
/*
            else if (has_h && st_prv_o >= PRV_H && (st_int & csr.mideleg & 12'h777) )
            begin
                st_prv_o    <= PRV_H;
                st_nxt_pc_o <= csr.htvec;

                csr.mstatus.hpie <= csr.mstatus.hie;
                csr.mstatus.hie  <= 1'b0;
                csr.mstatus.hpp  <= st_prv_o;
            end
*/
            else
            begin
                st_prv_o    <= PRV_M;
                st_nxt_pc_o <= csr.mtvec & ~'h3 + (csr.mtvec[0] ? interrupt_cause << 2 : 0);

                csr.mstatus.mpie <= csr.mstatus.mie;
                csr.mstatus.mie  <= 1'b0;
                csr.mstatus.mpp  <= st_prv_o;
            end
        end
        else if ( |(wb_exceptions_i.exceptions & ~du_ie_i[15:0]) )
        begin
            st_flush_o  <= 1'b1;

            if (has_n && st_prv_o == PRV_U && |(wb_exceptions_i.exceptions & csr.medeleg))
            begin
                st_prv_o    <= PRV_U;
                st_nxt_pc_o <= csr.utvec;

                csr.mstatus.upie <= csr.mstatus.uie;
                csr.mstatus.uie  <= 1'b0;
            end
            else if (has_s && st_prv_o >= PRV_S && |(wb_exceptions_i.exceptions & csr.medeleg))
            begin
                st_prv_o    <= PRV_S;
                st_nxt_pc_o <= csr.stvec;

                csr.mstatus.spie <= csr.mstatus.sie;
                csr.mstatus.sie  <= 1'b0;
                csr.mstatus.spp  <= st_prv_o[0];

            end
/*
            else if (has_h && st_prv_o >= PRV_H && |(wb_exception_i.exceptions & csr.medeleg))
            begin
                st_prv_o    <= PRV_H;
                st_nxt_pc_o <= csr.htvec;

                csr.mstatus.hpie <= csr.mstatus.hie;
                csr.mstatus.hie  <= 1'b0;
                csr.mstatus.hpp  <= st_prv_o;
            end
*/
            else
            begin
                st_prv_o    <= PRV_M;
                st_nxt_pc_o <= csr.mtvec & ~'h3;

                csr.mstatus.mpie <= csr.mstatus.mie;
                csr.mstatus.mie  <= 1'b0;
                csr.mstatus.mpp  <= st_prv_o;
            end
        end
    end


  /*
   * mcycle, minstret
   */
generate
  if (XLEN==32)
  begin
      always @(posedge clk_i,negedge rst_ni)
      if (!rst_ni)
      begin
          csr.mcycle   <= 'h0;
          csr.minstret <= 'h0;
      end
      else
      begin
          //cycle always counts (thread active time)
          if      ( (ex_csr_we_i && ex_csr_reg_i == MCYCLE  && st_prv_o == PRV_M) ||
                    (du_we_csr_i && du_addr_i    == MCYCLE)  )
            csr.mcycle.l <= csr_wval;
          else if ( (ex_csr_we_i && ex_csr_reg_i == MCYCLEH && st_prv_o == PRV_M) ||
                    (du_we_csr_i && du_addr_i    == MCYCLEH)  )
            csr.mcycle.h <= csr_wval;
          else
            csr.mcycle <= csr.mcycle + 'h1;

          //instruction retire counter
          if      ( (ex_csr_we_i && ex_csr_reg_i == MINSTRET  && st_prv_o == PRV_M) ||
                    (du_we_csr_i && du_addr_i    == MINSTRET)  )
            csr.minstret.l <= csr_wval;
          else if ( (ex_csr_we_i && ex_csr_reg_i == MINSTRETH && st_prv_o == PRV_M) ||
                    (du_we_csr_i && du_addr_i    == MINSTRETH)  )
            csr.minstret.h <= csr_wval;
          else if   (!wb_insn_i.bubble)
            csr.minstret <= csr.minstret + 'h1;
      end
  end
  else //(XLEN > 32)
  begin
      always @(posedge clk_i,negedge rst_ni)
      if (!rst_ni)
      begin
          csr.mcycle   <= 'h0;
          csr.minstret <= 'h0;
      end
      else
      begin
          //cycle always counts (thread active time)
          if ( (ex_csr_we_i && ex_csr_reg_i == MCYCLE && st_prv_o == PRV_M) ||
               (du_we_csr_i && du_addr_i    == MCYCLE)  )
            csr.mcycle <= csr_wval[63:0];
          else
            csr.mcycle <= csr.mcycle + 'h1;

          //instruction retire counter
          if ( (ex_csr_we_i && ex_csr_reg_i == MINSTRET && st_prv_o == PRV_M) ||
               (du_we_csr_i && du_addr_i    == MINSTRET)  )
            csr.minstret <= csr_wval[63:0];
          else if (!wb_insn_i.bubble)
            csr.minstret <= csr.minstret + 'h1;
      end
  end
endgenerate


  /*
   * mnmivec - RoaLogic Extension
   */
  always @(posedge clk_i,negedge rst_ni)
    if (!rst_ni)
      csr.mnmivec <= MNMIVEC_DEFAULT;
    else if ( (ex_csr_we_i && ex_csr_reg_i == MNMIVEC && st_prv_o == PRV_M) ||
              (du_we_csr_i && du_addr_i    == MNMIVEC)                     )
      csr.mnmivec <= {csr_wval[XLEN-1:2],2'b00};


  /*
   * mtvec
   */
  always @(posedge clk_i,negedge rst_ni)
    if (!rst_ni)
      csr.mtvec <= MTVEC_DEFAULT;
    else if ( (ex_csr_we_i && ex_csr_reg_i == MTVEC && st_prv_o == PRV_M) ||
              (du_we_csr_i && du_addr_i    == MTVEC)                     )
      csr.mtvec <= csr_wval & ~'h2;


  /*
   * mcounteren
   */
  always @(posedge clk_i,negedge rst_ni)
    if (!rst_ni)
      csr.mcounteren <= 'h0;
    else if ( (ex_csr_we_i && ex_csr_reg_i == MCOUNTEREN && st_prv_o == PRV_M) ||
              (du_we_csr_i && du_addr_i    == MCOUNTEREN)                     )
      csr.mcounteren <= csr_wval & 'h7;

  assign st_mcounteren_o = csr.mcounteren;


  /*
   * medeleg, mideleg
   */
generate
  if (!HAS_HYPER && !HAS_SUPER && !HAS_USER)
  begin
      assign csr.medeleg = 0;
      assign csr.mideleg = 0;
  end
  else
  begin
      //medeleg
      always @(posedge clk_i,negedge rst_ni)
        if (!rst_ni)
          csr.medeleg <= 'h0;
        else if ( (ex_csr_we_i && ex_csr_reg_i == MEDELEG && st_prv_o == PRV_M) ||
                  (du_we_csr_i && du_addr_i    == MEDELEG)                     )
          csr.medeleg <= csr_wval & {EXCEPTION_SIZE{1'b1}};

      //mideleg
      always @(posedge clk_i,negedge rst_ni)
        if (!rst_ni)
          csr.mideleg <= 'h0;
        else if ( (ex_csr_we_i && ex_csr_reg_i == MIDELEG && st_prv_o == PRV_M) ||
                  (du_we_csr_i && du_addr_i    == MIDELEG)                )
        begin
            csr.mideleg[SSI] <= has_s & csr_wval[SSI];
            csr.mideleg[USI] <= has_n & csr_wval[USI];
        end
/*
        else if (has_h)
        begin
            if ( (ex_csr_we_i && ex_csr_reg_i == HIDELEG && st_prv_o >= PRV_H) ||
                 (du_we_csr_i && du_addr_i    == HIDELEG)                )
            begin
                csr.mideleg[SSI] <= has_s & csr_wval[SSI];
                csr.mideleg[USI] <= has_n & csr_wval[USI];
            end
        end
*/
        else if (has_s)
        begin
            if ( (ex_csr_we_i && ex_csr_reg_i == SIDELEG && st_prv_o >= PRV_S) ||
                 (du_we_csr_i && du_addr_i    == SIDELEG)                )
            begin
                csr.mideleg[USI] <= has_n & csr_wval[USI];
            end
        end
  end
endgenerate


  /*
   * mip
   */
  always @(posedge clk_i,negedge rst_ni)
    if (!rst_ni)
    begin
        csr.mip   <= 'h0;
        soft_seip <= 1'b0;
        soft_ueip <= 1'b0;
    end
    else
    begin
        //external interrupts
        csr.mip.meip <=          int_external_i[PRV_M]; 
        csr.mip.heip <= has_h &  int_external_i[PRV_H];
        csr.mip.seip <= has_s & (int_external_i[PRV_S] | soft_seip);
        csr.mip.ueip <= has_n & (int_external_i[PRV_U] | soft_ueip);

        //may only be written by M-mode
        if ( (ex_csr_we_i & ex_csr_reg_i == MIP & st_prv_o == PRV_M) ||
             (du_we_csr_i & du_addr_i    == MIP)                  )
        begin
            soft_seip <= csr_wval[SEI] & has_s;
            soft_ueip <= csr_wval[UEI] & has_n;
        end
 

        //timer interrupts
        csr.mip.mtip <= int_timer_i;

        //may only be written by M-mode
        if ( (ex_csr_we_i & ex_csr_reg_i == MIP & st_prv_o == PRV_M) ||
             (du_we_csr_i & du_addr_i    == MIP)                  )
        begin
            csr.mip.htip <= csr_wval[HTI] & has_h;
            csr.mip.stip <= csr_wval[STI] & has_s;
            csr.mip.utip <= csr_wval[UTI] & has_n;
        end


        //software interrupts
        csr.mip.msip <= int_software_i;
        //Machine Mode write
        if ( (ex_csr_we_i && ex_csr_reg_i == MIP && st_prv_o == PRV_M) ||
             (du_we_csr_i && du_addr_i    == MIP)                   )
        begin
            csr.mip.hsip <= csr_wval[HSI] & has_h;
            csr.mip.ssip <= csr_wval[SSI] & has_s;
            csr.mip.usip <= csr_wval[USI] & has_n;
        end
/*
        else if (has_h)
        begin
            //Hypervisor Mode write
            if ( (ex_csr_we_i && ex_csr_reg_i == HIP && st_prv_o >= PRV_H) ||
                 (du_we_csr_i && du_addr_i    == HIP)                   )
            begin
                csr.mip.hsip <= csr_wval[HSI] & csr.mideleg[HSI];
                csr.mip.ssip <= csr_wval[SSI] & csr.mideleg[SSI] & has_s;
                csr.mip.usip <= csr_wval[USI] & csr.mideleg[USI] & has_n;
            end
        end
*/
        else if (has_s)
        begin
            //Supervisor Mode write
            if ( (ex_csr_we_i && ex_csr_reg_i == SIP && st_prv_o >= PRV_S) ||
                 (du_we_csr_i && du_addr_i    == SIP)                   )
            begin
                csr.mip.ssip <= csr_wval[SSI] & csr.mideleg[SSI];
                csr.mip.usip <= csr_wval[USI] & csr.mideleg[USI] & has_n;
            end
        end
        else if (has_n)
        begin
            //User Mode write
            if ( (ex_csr_we_i && ex_csr_reg_i == UIP) ||
                 (du_we_csr_i && du_addr_i    == UIP)  )
            begin
                csr.mip.usip <= csr_wval[USI] & csr.mideleg[USI];
            end
        end
    end


  /*
   * mie
   */
  always @(posedge clk_i,negedge rst_ni)
    if (!rst_ni)
      csr.mie <= 'h0;
    else if ( (ex_csr_we_i && ex_csr_reg_i == MIE && st_prv_o == PRV_M) ||
              (du_we_csr_i && du_addr_i    == MIE)                   )
    begin
        csr.mie.meie <= csr_wval[MEI];
        csr.mie.heie <= csr_wval[HEI] & has_h;
        csr.mie.seie <= csr_wval[SEI] & has_s;
        csr.mie.ueie <= csr_wval[UEI] & has_n;
        csr.mie.mtie <= csr_wval[MTI];
        csr.mie.htie <= csr_wval[HTI] & has_h;
        csr.mie.stie <= csr_wval[STI] & has_s;
        csr.mie.utie <= csr_wval[UTI] & has_n;
        csr.mie.msie <= csr_wval[MSI];
        csr.mie.hsie <= csr_wval[HSI] & has_h;
        csr.mie.ssie <= csr_wval[SSI] & has_s;
        csr.mie.usie <= csr_wval[USI] & has_n;
    end
/*
    else if (has_h)
    begin
        if ( (ex_csr_we_i && ex_csr_reg_i == HIE && st_prv_o >= PRV_H) ||
             (du_we_csr_i && du_addr_i    == HIE)                   )
        begin
            csr.mie.heie <= csr_wval[HEI];
            csr.mie.seie <= csr_wval[SEI] & has_s;
            csr.mie.ueie <= csr_wval[UEI] & has_n;
            csr.mie.htie <= csr_wval[HTI];
            csr.mie.stie <= csr_wval[STI] & has_s;
            csr.mie.utie <= csr_wval[UTI] & has_n;
            csr.mie.hsie <= csr_wval[HSI];
            csr.mie.ssie <= csr_wval[SSI] & has_s;
            csr.mie.usie <= csr_wval[USI] & has_n;
        end
    end
*/
    else if (has_s)
    begin
        if ( (ex_csr_we_i && ex_csr_reg_i == SIE && st_prv_o >= PRV_S) ||
             (du_we_csr_i && du_addr_i    == SIE)                   )
        begin
            csr.mie.seie <= csr_wval[SEI];
            csr.mie.ueie <= csr_wval[UEI] & has_n;
            csr.mie.stie <= csr_wval[STI];
            csr.mie.utie <= csr_wval[UTI] & has_n;
            csr.mie.ssie <= csr_wval[SSI];
            csr.mie.usie <= csr_wval[USI] & has_n;
        end
    end
   else if (has_n)
    begin
        if ( (ex_csr_we_i && ex_csr_reg_i == UIE) ||
             (du_we_csr_i && du_addr_i    == UIE)  )
        begin
            csr.mie.ueie <= csr_wval[UEI];
            csr.mie.utie <= csr_wval[UTI];
            csr.mie.usie <= csr_wval[USI];
        end
    end


  /*
   * mscratch
   */
  always @(posedge clk_i,negedge rst_ni)
    if      (!rst_ni)
      csr.mscratch <= 'h0;
    else if ( (ex_csr_we_i && ex_csr_reg_i == MSCRATCH && st_prv_o == PRV_M) ||
              (du_we_csr_i && du_addr_i    == MSCRATCH                   ) )
      csr.mscratch <= csr_wval;


  assign trap_cause = get_trap_cause( wb_exceptions_i.exceptions & ~du_ie_i[15:0]);


  //decode interrupts
  //priority external, software, timer
  //st_int_o goes into ID, where the interrupts are synchronized
  //with the CPU pipeline
  assign st_int_o.external[PRV_M] = ( ((st_prv_o < PRV_M) | (st_prv_o == PRV_M & csr.mstatus.mie)) & (csr.mip.meip & csr.mie.meie) );
  assign st_int_o.external[PRV_H] = ( ((st_prv_o < PRV_H) | (st_prv_o == PRV_H & csr.mstatus.hie)) & (csr.mip.heip & csr.mie.heie) );
  assign st_int_o.external[PRV_S] = ( ((st_prv_o < PRV_S) | (st_prv_o == PRV_S & csr.mstatus.sie)) & (csr.mip.seip & csr.mie.seie) );
  assign st_int_o.external[PRV_U] = (                       (st_prv_o == PRV_U & csr.mstatus.uie)  & (csr.mip.ueip & csr.mie.ueie) );

  assign st_int_o.software[PRV_M] = ( ((st_prv_o < PRV_M) | (st_prv_o == PRV_M & csr.mstatus.mie)) & (csr.mip.msip & csr.mie.msie) ) &
                                   ~st_int_o.external[PRV_M];
  assign st_int_o.software[PRV_H] = ( ((st_prv_o < PRV_H) | (st_prv_o == PRV_H & csr.mstatus.hie)) & (csr.mip.hsip & csr.mie.hsie) ) &
                                   ~st_int_o.external[PRV_H];
  assign st_int_o.software[PRV_S] = ( ((st_prv_o < PRV_S) | (st_prv_o == PRV_S & csr.mstatus.sie)) & (csr.mip.ssip & csr.mie.ssie) ) &
                                   ~st_int_o.external[PRV_S];
  assign st_int_o.software[PRV_U] = (                       (st_prv_o == PRV_U & csr.mstatus.uie)  & (csr.mip.usip & csr.mie.usie) ) &
                                   ~st_int_o.external[PRV_U];

  assign st_int_o.timer   [PRV_M] = ( ((st_prv_o < PRV_M) | (st_prv_o == PRV_M & csr.mstatus.mie)) & (csr.mip.mtip & csr.mie.mtie) ) &
                                   ~(st_int_o.external[PRV_M] | st_int_o.software[PRV_M]);
  assign st_int_o.timer   [PRV_H] = ( ((st_prv_o < PRV_H) | (st_prv_o == PRV_H & csr.mstatus.hie)) & (csr.mip.htip & csr.mie.htie) ) &
                                   ~(st_int_o.external[PRV_H] | st_int_o.software[PRV_H]);
  assign st_int_o.timer   [PRV_S] = ( ((st_prv_o < PRV_S) | (st_prv_o == PRV_S & csr.mstatus.sie)) & (csr.mip.stip & csr.mie.stie) ) &
                                   ~(st_int_o.external[PRV_S] | st_int_o.software[PRV_S]);
  assign st_int_o.timer   [PRV_U] = (                       (st_prv_o == PRV_U & csr.mstatus.uie)  & (csr.mip.utip & csr.mie.utie) ) &
                                   ~(st_int_o.external[PRV_U] | st_int_o.software[PRV_U]);


  //interrupt cause priority
  always_comb
    casex (wb_exceptions_i.interrupts & ~du_ie_i[31:16])
       12'h??1 : interrupt_cause = 0;
       12'h??2 : interrupt_cause = 1;
       12'h??4 : interrupt_cause = 2;
       12'h??8 : interrupt_cause = 3;
       12'h?10 : interrupt_cause = 4;
       12'h?20 : interrupt_cause = 5;
       12'h?40 : interrupt_cause = 6;
       12'h?80 : interrupt_cause = 7;
       12'h100 : interrupt_cause = 8;
       12'h200 : interrupt_cause = 9;
       12'h400 : interrupt_cause =10;
       12'h800 : interrupt_cause =11;
       default : interrupt_cause = 0;
    endcase

  assign take_interrupt = |(wb_exceptions_i.interrupts & ~du_ie_i[31:16]);


  //for Debug Unit
  assign du_exceptions_o = du_ie_i & { {16-$bits(wb_exceptions_i.interrupts){1'b0}}, wb_exceptions_i.interrupts,
                                       {16-$bits(wb_exceptions_i.exceptions){1'b0}}, wb_exceptions_i.exceptions };


  //Update mepc and mcause
  always @(posedge clk_i,negedge rst_ni)
    if (!rst_ni)
    begin
        csr.mepc     <= 'h0;
//        csr.hepc     <= 'h0;
        csr.sepc     <= 'h0;
        csr.uepc     <= 'h0;

        csr.mcause   <= 'h0;
//        csr.hcause   <= 'h0;
        csr.scause   <= 'h0;
        csr.ucause   <= 'h0;

        csr.mtval    <= 'h0;
//        csr.htval    <= 'h0;
        csr.stval    <= 'h0;
        csr.utval    <= 'h0;
    end
    else
    begin
        //Write access to regs (lowest priority)
        if ( (ex_csr_we_i && ex_csr_reg_i == MEPC && st_prv_o == PRV_M) ||
             (du_we_csr_i && du_addr_i    == MEPC)                  )
          csr.mepc <= {csr_wval[XLEN-1:2], csr_wval[1] & has_rvc, 1'b0};
/*
        if ( (ex_csr_we_i && ex_csr_reg_i == HEPC && st_prv_o >= PRV_H) ||
             (du_we_csr_i && du_addr_i    == HEPC)                  )
          csr.hepc <= {csr_wval[XLEN-1:2], csr_wval[1] & has_rvc, 1'b0};
*/
        if ( (ex_csr_we_i && ex_csr_reg_i == SEPC && st_prv_o >= PRV_S) ||
             (du_we_csr_i && du_addr_i    == SEPC)                  )
          csr.sepc <= {csr_wval[XLEN-1:2], csr_wval[1] & has_rvc, 1'b0};

        if ( (ex_csr_we_i && ex_csr_reg_i == UEPC && st_prv_o >= PRV_U) ||
             (du_we_csr_i && du_addr_i    == UEPC)                  )
          csr.uepc <= {csr_wval[XLEN-1:2], csr_wval[1] & has_rvc, 1'b0};


        if ( (ex_csr_we_i && ex_csr_reg_i == MCAUSE && st_prv_o == PRV_M) ||
             (du_we_csr_i && du_addr_i    == MCAUSE)                  )
          csr.mcause <= csr_wval;
/*
        if ( (ex_csr_we_i && ex_csr_reg_i == HCAUSE && st_prv_o >= PRV_H) ||
             (du_we_csr_i && du_addr_i    == HCAUSE)                  )
          csr.hcause <= csr_wval;
*/
        if ( (ex_csr_we_i && ex_csr_reg_i == SCAUSE && st_prv_o >= PRV_S) ||
             (du_we_csr_i && du_addr_i    == SCAUSE)                  )
          csr.scause <= csr_wval;

        if ( (ex_csr_we_i && ex_csr_reg_i == UCAUSE && st_prv_o >= PRV_U) ||
             (du_we_csr_i && du_addr_i    == UCAUSE)                  )
          csr.ucause <= csr_wval;


        if ( (ex_csr_we_i && ex_csr_reg_i == MTVAL && st_prv_o == PRV_M) ||
             (du_we_csr_i && du_addr_i    == MTVAL)                  )
          csr.mtval <= csr_wval;
/*
        if ( (ex_csr_we_i && ex_csr_reg_i == HTVAL && st_prv_o >= PRV_H) ||
             (du_we_csr_i && du_addr_i    == HTVAL)                  )
          csr.htval <= csr_wval;
*/
        if ( (ex_csr_we_i && ex_csr_reg_i == STVAL && st_prv_o >= PRV_S) ||
             (du_we_csr_i && du_addr_i    == STVAL)                  )
          csr.stval <= csr_wval;

        if ( (ex_csr_we_i && ex_csr_reg_i == UTVAL && st_prv_o >= PRV_U) ||
             (du_we_csr_i && du_addr_i    == UTVAL)                  )
          csr.utval <= csr_wval;


        /*
         * Handle exceptions
         */
        //priority external interrupts, software interrupts, timer interrupts, traps
        if (wb_exceptions_i.nmi) //TODO: doesn't this cause a deadlock? Need to hold of NMI once handled
        begin
            //NMI always at Machine Level
            csr.mepc     <= bu_flush_i ? bu_nxt_pc_i : wb_pc_i;
            csr.mcause   <= (1 << (XLEN-1)) | 'h0; //Implementation dependent. '0' indicates 'unknown cause'
        end
        else if (take_interrupt)
        begin
            //Check if interrupts are delegated
            if (has_n && st_prv_o == PRV_U && ( wb_exceptions_i.interrupts & csr.mideleg & 12'h111) )
            begin
                csr.ucause <= (1 << (XLEN-1)) | interrupt_cause;

		//don't update application return address if state caused a flush (ISR exit)
		if (!st_flush_o) csr.uepc <= wb_pc_i;
            end
            else if (has_s && st_prv_o >= PRV_S && (wb_exceptions_i.interrupts & csr.mideleg & 12'h333) )
            begin
                csr.scause <= (1 << (XLEN-1)) | interrupt_cause;
		
		//don't update application return address if state caused a flush (ISR exit)
                if (!st_flush_o) csr.sepc <= wb_pc_i;
            end
/*
            else if (has_h && st_prv_o >= PRV_H && (st_int & csr.mideleg & 12'h777) )
            begin
                csr.hcause <= (1 << (XLEN-1)) | interrupt_cause;;
                csr.hepc   <= id_pc_i;
            end
*/
            else
            begin
                csr.mcause <= (1 << (XLEN-1)) | interrupt_cause;;

		//don't update application return address if state caused a flush (ISR exit)
                if (!st_flush_o) csr.mepc <= wb_pc_i;
            end
        end
        else if (|(wb_exceptions_i.exceptions & ~du_ie_i[15:0]))
        begin
            //Trap
            if (has_n && st_prv_o == PRV_U && |(wb_exceptions_i.exceptions & csr.medeleg))
            begin
                csr.uepc   <= wb_pc_i;
                csr.ucause <= trap_cause;
                csr.utval  <= wb_badaddr_i;
            end
            else if (has_s && st_prv_o >= PRV_S && |(wb_exceptions_i.exceptions & csr.medeleg))
            begin
                csr.sepc   <= wb_pc_i;
                csr.scause <= trap_cause;

                if (wb_exceptions_i.exceptions.illegal_instruction)
                  csr.stval <= wb_insn_i.instr;
/*	  
                else if (wb_exceptions_i.exceptions.misaligned_instruction   ||
                         wb_exceptions_i.exceptions.instruction_access_fault ||
                         wb_exceptions_i.exceptions.instruction_page_fault   ||
                         wb_exceptions_i.exceptions.misaligned_load          ||
                         wb_exceptions_i.exceptions.load_access_fault        ||
                         wb_exceptions_i.exceptions.load_page_fault          ||
                         wb_exceptions_i.exceptions.misaligned_store         ||
                         wb_exceptions_i.exceptions.store_access_fault       ||
                         wb_exceptions_i.exceptions.store_page_fault         )
*/
                else			 
                  csr.stval <= wb_badaddr_i;
            end
/*
            else if (has_h && st_prv_o >= PRV_H && |(wb_exception & csr.medeleg))
            begin
                csr.hepc   <= wb_pc_i;
                csr.hcause <= trap_cause;

                if (wb_exception[CAUSE_ILLEGAL_INSTRUCTION])
                  csr.htval <= wb_insn_i.instr;
                else if (wb_exception[CAUSE_MISALIGNED_INSTRUCTION] || wb_exception[CAUSE_INSTRUCTION_ACCESS_FAULT] || wb_exception[CAUSE_INSTRUCTION_PAGE_FAULT] ||
                         wb_exception[CAUSE_MISALIGNED_LOAD       ] || wb_exception[CAUSE_LOAD_ACCESS_FAULT       ] || wb_exception[CAUSE_LOAD_PAGE_FAULT       ] ||
                         wb_exception[CAUSE_MISALIGNED_STORE      ] || wb_exception[CAUSE_STORE_ACCESS_FAULT      ] || wb_exception[CAUSE_STORE_PAGE_FAULT      ] )
                  csr.htval <= wb_badaddr_i;
            end
*/
            else
            begin
                csr.mepc   <= wb_pc_i;
                csr.mcause <= trap_cause;

                if (wb_exceptions_i.exceptions.illegal_instruction)
                  csr.mtval <= wb_insn_i.instr;
/*	  
                else if (wb_exceptions_i.exceptions.misaligned_instruction   ||
                         wb_exceptions_i.exceptions.instruction_access_fault ||
                         wb_exceptions_i.exceptions.instruction_page_fault   ||
                         wb_exceptions_i.exceptions.misaligned_load          ||
                         wb_exceptions_i.exceptions.load_access_fault        ||
                         wb_exceptions_i.exceptions.load_page_fault          ||
                         wb_exceptions_i.exceptions.misaligned_store         ||
                         wb_exceptions_i.exceptions.store_access_fault       ||
                         wb_exceptions_i.exceptions.store_page_fault         )
*/
                else
                  csr.mtval <= wb_badaddr_i;
            end
        end
     end


  /*
   * Physical Memory Protection & Translation registers
   */
generate
  genvar idx; //a-z are used by 'misa'

  if (XLEN > 64)      //RV128
  begin
      for (idx=0; idx<16; idx++)
      begin: gen_pmpcfg0
          if (idx < PMP_CNT)
          begin
              always @(posedge clk_i,negedge rst_ni)
                if (!rst_ni) csr.pmpcfg[idx] <= 'h0;
                else if ( (ex_csr_we_i && ex_csr_reg_i == PMPCFG0 && st_prv_o == PRV_M) ||
                          (du_we_csr_i && du_addr_i    == PMPCFG0                     ) )
                  if (!csr.pmpcfg[idx].l) csr.pmpcfg[idx] <= csr_wval[idx*8 +: 8] & PMPCFG_MASK;
          end
          else
            assign csr.pmpcfg[idx] = 'h0;
      end //next idx

        //pmpaddr not defined for RV128 yet
  end
  else if (XLEN > 32) //RV64
  begin
      for (idx=0; idx<8; idx++)
      begin: gen_pmpcfg0
	  if (idx < PMP_CNT)
          begin
              always @(posedge clk_i,negedge rst_ni)
                if (!rst_ni) csr.pmpcfg[idx] <= 'h0;
                else if ( (ex_csr_we_i && ex_csr_reg_i == PMPCFG0 && st_prv_o == PRV_M) ||
                          (du_we_csr_i && du_addr_i    == PMPCFG0                     ) )
                  if (!csr.pmpcfg[idx].l) csr.pmpcfg[idx] <= csr_wval[0 + idx*8 +: 8] & PMPCFG_MASK;
          end
          else
            assign csr.pmpcfg[idx] = 'h0;
      end //next idx

      for (idx=8; idx<16; idx++)
      begin: gen_pmpcfg2
          if (idx < PMP_CNT)
          begin
              always @(posedge clk_i,negedge rst_ni)
                if (!rst_ni) csr.pmpcfg[idx] <= 'h0;
                else if ( (ex_csr_we_i && ex_csr_reg_i == PMPCFG2 && st_prv_o == PRV_M) ||
                          (du_we_csr_i && du_addr_i    == PMPCFG2                     ) )
                  if (!csr.pmpcfg[idx].l) csr.pmpcfg[idx] <= csr_wval[(idx-8)*8 +:8] & PMPCFG_MASK;
           end
           else
             assign csr.pmpcfg[idx] = 'h0;
      end //next idx


      for (idx=0; idx < 16; idx++)
      begin: gen_pmpaddr
          if (idx < PMP_CNT)
          begin
              if (idx == 15)
              begin
                  always @(posedge clk_i,negedge rst_ni)
                    if (!rst_ni) csr.pmpaddr[idx] <= 'h0;
                    else if ( (ex_csr_we_i && ex_csr_reg_i == (PMPADDR0 +idx) && st_prv_o == PRV_M &&
                               !csr.pmpcfg[idx].l                                                 ) ||
                              (du_we_csr_i && du_addr_i    == (PMPADDR0 +idx)                     ) )
                      csr.pmpaddr[idx] <= {10'h0,csr_wval[53:0]};
              end
              else
              begin
                  always @(posedge clk_i,negedge rst_ni)
                    if (!rst_ni) csr.pmpaddr[idx] <= 'h0;
                    else if ( (ex_csr_we_i && ex_csr_reg_i == (PMPADDR0 +idx) && st_prv_o == PRV_M &&
                               !csr.pmpcfg[idx].l && !(csr.pmpcfg[idx+1].a==TOR && csr.pmpcfg[idx+1].l) ) ||
                              (du_we_csr_i && du_addr_i    == (PMPADDR0 +idx)                           ) )
                      csr.pmpaddr[idx] <= {10'h0,csr_wval[53:0]};
              end
          end
          else
            assign csr.pmpaddr[idx] = 'h0;
      end //next idx
  end
  else //RV32
  begin
      for (idx=0; idx<4; idx++)
      begin: gen_pmpcfg0
          if (idx < PMP_CNT)
          begin
              always @(posedge clk_i,negedge rst_ni)
                if (!rst_ni) csr.pmpcfg[idx] <= 'h0;
                else if ( (ex_csr_we_i && ex_csr_reg_i == PMPCFG0 && st_prv_o == PRV_M) ||
                          (du_we_csr_i && du_addr_i    == PMPCFG0                     ) )
                  if (!csr.pmpcfg[idx].l) csr.pmpcfg[idx] <= csr_wval[idx*8 +:8] & PMPCFG_MASK;
          end
          else
            assign csr.pmpcfg[idx] = 'h0;
      end //next idx


      for (idx=4; idx<8; idx++)
      begin: gen_pmpcfg1
          if (idx < PMP_CNT)
          begin
              always @(posedge clk_i,negedge rst_ni)
                if (!rst_ni) csr.pmpcfg[idx] <= 'h0;
                else if ( (ex_csr_we_i && ex_csr_reg_i == PMPCFG1 && st_prv_o == PRV_M) ||
                          (du_we_csr_i && du_addr_i    == PMPCFG1                     ) )
                  if (!csr.pmpcfg[idx].l) csr.pmpcfg[idx] <= csr_wval[(idx-4)*8 +:8] & PMPCFG_MASK;
          end
          else
            assign csr.pmpcfg[idx] = 'h0;
      end //next idx


      for (idx=8; idx<12; idx++)
      begin: gen_pmpcfg2
          if (idx < PMP_CNT)
          begin
              always @(posedge clk_i,negedge rst_ni)
                if (!rst_ni) csr.pmpcfg[idx] <= 'h0;
                  else if ( (ex_csr_we_i && ex_csr_reg_i == PMPCFG2 && st_prv_o == PRV_M) ||
                            (du_we_csr_i && du_addr_i    == PMPCFG2                     ) )
                  if (!csr.pmpcfg[idx].l) csr.pmpcfg[idx] <= csr_wval[(idx-8)*8 +:8] & PMPCFG_MASK;
          end
          else
            assign csr.pmpcfg[idx] = 'h0;
      end //next idx


      for (idx=12; idx<16; idx++)
      begin: gen_pmpcfg3
          if (idx < PMP_CNT)
          begin
              always @(posedge clk_i,negedge rst_ni)
                if (!rst_ni) csr.pmpcfg[idx] <= 'h0;
                else if ( (ex_csr_we_i && ex_csr_reg_i == PMPCFG3 && st_prv_o == PRV_M) ||
                          (du_we_csr_i && du_addr_i    == PMPCFG3                     ) )
                  if (idx < PMP_CNT && !csr.pmpcfg[idx].l)
                    csr.pmpcfg[idx] <= csr_wval[(idx-12)*8 +:8] & PMPCFG_MASK;
          end
          else
            assign csr.pmpcfg[idx] = 'h0;
      end //next idx


      for (idx=0; idx < 16; idx++)
      begin: gen_pmpaddr
         if (idx < PMP_CNT)
          begin
              if (idx == 15)
              begin
                  always @(posedge clk_i,negedge rst_ni)
                    if (!rst_ni) csr.pmpaddr[idx] <= 'h0;
                    else if ( (ex_csr_we_i && ex_csr_reg_i == (PMPADDR0 +idx) && st_prv_o == PRV_M &&
                               !csr.pmpcfg[idx].l                                                ) ||
                              (du_we_csr_i && du_addr_i    == (PMPADDR0 +idx)                    ) )
                      csr.pmpaddr[idx] <= csr_wval;
              end
              else
              begin
                  always @(posedge clk_i,negedge rst_ni)
                    if (!rst_ni) csr.pmpaddr[idx] <= 'h0;
                    else if ( (ex_csr_we_i && ex_csr_reg_i == (PMPADDR0 +idx) && st_prv_o == PRV_M &&
                               !csr.pmpcfg[idx].l && !(csr.pmpcfg[idx+1].a==TOR && csr.pmpcfg[idx+1].l) ) ||
                              (du_we_csr_i && du_addr_i    == (PMPADDR0 +idx)                           ) )
                      csr.pmpaddr[idx] <= csr_wval;
              end
          end
          else
            assign csr.pmpaddr[idx] = 'h0;
      end //next idx

  end
endgenerate


  assign st_pmpcfg_o  = csr.pmpcfg;
  assign st_pmpaddr_o = csr.pmpaddr;



  ////////////////////////////////////////////////////////////////
  //
  // Supervisor Registers
  //
generate
  if (HAS_SUPER)
  begin
      //stvec
      always @(posedge clk_i,negedge rst_ni)
        if      (!rst_ni)
          csr.stvec <= STVEC_DEFAULT;
        else if ( (ex_csr_we_i && ex_csr_reg_i == STVEC && st_prv_o >= PRV_S) ||
                  (du_we_csr_i && du_addr_i    == STVEC                   ) )
          csr.stvec <= csr_wval & ~'h2;


      //scounteren
      always @(posedge clk_i,negedge rst_ni)
        if (!rst_ni)
          csr.scounteren <= 'h0;
        else if ( (ex_csr_we_i && ex_csr_reg_i == SCOUNTEREN && st_prv_o == PRV_M) ||
                  (du_we_csr_i && du_addr_i    == SCOUNTEREN                   ) )
          csr.scounteren <= csr_wval & 'h7;


      //sedeleg
      always @(posedge clk_i,negedge rst_ni)
        if      (!rst_ni)
          csr.sedeleg <= 'h0;
        else if ( (ex_csr_we_i && ex_csr_reg_i == SEDELEG && st_prv_o >= PRV_S) ||
                  (du_we_csr_i && du_addr_i    == SEDELEG                   ) )
          csr.sedeleg <= csr_wval & ((1<<CAUSE_UMODE_ECALL) | (1<<CAUSE_SMODE_ECALL));


      //sscratch
      always @(posedge clk_i,negedge rst_ni)
        if      (!rst_ni)
          csr.sscratch <= 'h0;
        else if ( (ex_csr_we_i && ex_csr_reg_i == SSCRATCH && st_prv_o >= PRV_S) ||
                  (du_we_csr_i && du_addr_i    == SSCRATCH                   ) )
          csr.sscratch <= csr_wval;


      //satp
      always @(posedge clk_i,negedge rst_ni)
        if      (!rst_ni)
          csr.satp <= 'h0;
        else if ( (ex_csr_we_i && ex_csr_reg_i == SATP && st_prv_o >= PRV_S) ||
                  (du_we_csr_i && du_addr_i    == SATP                   ) )
          csr.satp <= ex_csr_wval_i;
  end
  else //NO SUPERVISOR MODE
  begin
      assign csr.stvec      = 'h0;
      assign csr.scounteren = 'h0;
      assign csr.sedeleg    = 'h0;
      assign csr.sscratch   = 'h0;
      assign csr.satp       = 'h0;
  end
endgenerate

  assign st_scounteren_o = csr.scounteren;


  ////////////////////////////////////////////////////////////////
  //User Registers
  //
generate
  if (HAS_USER)
  begin
      //utvec
      always @(posedge clk_i,negedge rst_ni)
        if      (!rst_ni)
          csr.utvec <= UTVEC_DEFAULT;
        else if ( (ex_csr_we_i && ex_csr_reg_i == UTVEC) ||
                  (du_we_csr_i && du_addr_i    == UTVEC)  )
          csr.utvec <= {csr_wval[XLEN-1:2],2'b00};

      //uscratch
      always @(posedge clk_i,negedge rst_ni)
        if      (!rst_ni)
          csr.uscratch <= 'h0;
        else if ( (ex_csr_we_i && ex_csr_reg_i == USCRATCH) ||
                  (du_we_csr_i && du_addr_i    == USCRATCH)  )
          csr.uscratch <= csr_wval;

      //Floating point registers
      if (HAS_FPU)
      begin
          //TODO
      end
  end
  else //NO USER MODE
  begin
      assign csr.utvec    = 'h0;
      assign csr.uscratch = 'h0;
      assign csr.fcsr     = 'h0;
  end
endgenerate


endmodule 

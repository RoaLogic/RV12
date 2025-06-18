/////////////////////////////////////////////////////////////////////
//   ,------.                    ,--.                ,--.          //
//   |  .--. ' ,---.  ,--,--.    |  |    ,---. ,---. `--' ,---.    //
//   |  '--'.'| .-. |' ,-.  |    |  |   | .-. | .-. |,--.| .--'    //
//   |  |\  \ ' '-' '\ '-'  |    |  '--.' '-' ' '-' ||  |\ `--.    //
//   `--' '--' `---'  `--`--'    `-----' `---' `-   /`--' `---'    //
//                                             `---'               //
//    RISC-V                                                       //
//    (Thread) State (priv spec 2024-04-11)                        //
//                                                                 //
/////////////////////////////////////////////////////////////////////
//                                                                 //
//             Copyright (C) 2018-2024 Roa Logic BV                //
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


module riscv_state1_10
import riscv_rv12_pkg::*;
import riscv_opcodes_pkg::*;
import riscv_state_pkg::*;
#(
  parameter int         MXLEN           = 32,
  parameter int         FLEN            = 64,    // Floating Point Data length
  parameter [MXLEN-1:0] PC_INIT         = 'h200,

  parameter bit         IS_RV32E        = 0,
  parameter bit         HAS_FPU         = 0,
  parameter bit         HAS_MMU         = 0,
  parameter bit         HAS_RVA         = 0,
  parameter bit         HAS_RVB         = 0,
  parameter bit         HAS_RVC         = 0,
  parameter bit         HAS_RVM         = 0,
  parameter bit         HAS_RVN         = 0,
  parameter bit         HAS_RVP         = 0,
  parameter bit         HAS_RVT         = 0,
  parameter bit         HAS_EXT         = 0,

  parameter bit         HAS_USER        = 1,
  parameter bit         HAS_SUPER       = 1,
  parameter bit         HAS_HYPER       = 0,

  parameter [MXLEN-1:0] MCONFIGPTR_VAL  = {MXLEN{1'b0}},

  parameter [MXLEN-1:0] MNMIVEC_DEFAULT = PC_INIT -'h004,
  parameter [MXLEN-1:0] MTVEC_DEFAULT   = PC_INIT -'h040,
  parameter [MXLEN-1:0] HTVEC_DEFAULT   = PC_INIT -'h080,
  parameter [MXLEN-1:0] STVEC_DEFAULT   = PC_INIT -'h0C0,

  parameter [      7:0] JEDEC_BANK            = 9,
  parameter [      6:0] JEDEC_MANUFACTURER_ID = 'h8a,

  parameter int         PMP_CNT               = 16,    //number of PMP CSR blocks (max.16)
  parameter [MXLEN-1:0] HARTID                = 0      //hardware thread-id
)
(
  input                             rst_ni,
  input                             clk_i,

  input               [MXLEN  -1:0] id_pc_i,
  input  instruction_t              id_insn_i,

  input                             bu_flush_i,
  input               [MXLEN  -1:0] bu_nxt_pc_i,
  output reg                        st_flush_o,
  output reg          [MXLEN  -1:0] st_nxt_pc_o,

  input               [MXLEN  -1:0] wb_pc_i,
  input  instruction_t              wb_insn_i,
  input  interrupts_exceptions_t    wb_exceptions_i,
  input               [MXLEN  -1:0] wb_badaddr_i,

  output reg          [        1:0] st_prv_o,        //Privilege level
  output reg          [        1:0] st_xlen_o,       //Active Architecture
  output reg                        st_be_o,         //Big/Little Endian
  output                            st_tvm_o,        //trap on satp access or SFENCE.VMA
                                    st_tw_o,         //trap on WFI (after time >=0)
                                    st_tsr_o,        //trap SRET
  output              [MXLEN  -1:0] st_mcounteren_o,
                                    st_scounteren_o,
  output pmpcfg_t     [       15:0] st_pmpcfg_o,
  output [       15:0][MXLEN  -1:0] st_pmpaddr_o,


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
  input               [MXLEN  -1:0] ex_csr_wval_i,
  output reg          [MXLEN  -1:0] st_csr_rval_o,

  //Debug interface
  input                             du_stall_i,
                                    du_flush_i,
                                    du_re_csr_i,
                                    du_we_csr_i,
  output reg           [MXLEN -1:0] du_csr_rval_o,
  input                [MXLEN -1:0] du_dato_i,       //output from debug unit
  input                [      11:0] du_addr_i,
  input                [MXLEN -1:0] du_ie_i,
  input                [      63:0] du_ee_i,
  output               [MXLEN -1:0] du_interrupts_o,
  output               [      63:0] du_exceptions_o
);

  ////////////////////////////////////////////////////////////////
  //
  // Functions
  //

  //find first one, starting at lsb(!!)
  function automatic [MXLEN-1:0] find_first_one(input [MXLEN-1:0] a);
    find_first_one = 0;

    for (int n=0; n < MXLEN; n++)
      if (a[n]) return n;
  endfunction : find_first_one


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
    fcsr_struct                 fcsr;

    timer_struct                cycle,
                                utime,         //actually time, but that's a reserved keyword
                                instret;
    //timer_struct hpmcounter[31:3];

    /*
     * Supervisor
     */
    //Supervisor Trap Setup
    logic          [MXLEN -1:0] sstatus;       //status
    logic          [MXLEN -1:0] sie;           //interrupt enable
    logic          [MXLEN -1:0] stvec;         //trap handler base address
    logic          [MXLEN -1:0] scounteren;    //counter enable

    //Supervisor configuration
    logic          [MXLEN -1:0] senvcfg;       //environment configuration

    //Supervisor Counter Setup
    logic          [MXLEN -1:0] scountinhibit; //counter inhibit

    //Supervisor Trap Handler
    logic          [MXLEN -1:0] sscratch;      //scratch register
    logic          [MXLEN -1:0] sepc;          //exception program counter
    logic          [MXLEN -1:0] scause;        //trap cause
    logic          [MXLEN -1:0] stval;         //bad address
    logic          [MXLEN -1:0] sip;           //interrupt pending
    logic          [MXLEN -1:0] scountovf;     //count overflow

    //Supervisor Protection and Translation
    logic          [MXLEN -1:0] satp;          //Address translation & protection

    //Debug/Trace
    logic          [MXLEN -1:0] scontext;      //context register

    //State Enable
    logic          [MXLEN -1:0] sstateen0,
                                sstateen1,
                                sstateen2,
                                sstateen3;

    /*
     * Hypervisor
     */
    //Hypervisor Trap Setup
    logic          [MXLEN -1:0] hstatus;       //status
    logic          [MXLEN -1:0] hedeleg;       //exception delegation
    logic          [MXLEN -1:0] hideleg;       //interrupt delegation
    logic          [MXLEN -1:0] hie;           //interrupt enable
    logic          [MXLEN -1:0] hcounteren;    //counter enable
    logic          [MXLEN -1:0] hgeie;         //guest external interrupt enable

    //Hypervisor Trap Handler
    logic          [MXLEN -1:0] htval;         //bad guest address
    logic          [MXLEN -1:0] hip;           //interrupt pending
    logic          [MXLEN -1:0] hvip;          //virtual interrupt pending
    logic          [MXLEN -1:0] htinst;        //trap instruction (transformed)
    logic          [MXLEN -1:0] hgeip;         //guest external interrupt pending

    //Hypervisor Configuration
    logic          [MXLEN -1:0] henvcfg;       //configuration

    //Hypervisor protection and Translation
    logic          [MXLEN -1:0] hgatp;         //guest address translation and protection

    //Hypervisor Debug/Trace
    logic          [MXLEN -1:0] hcontext;      //context

    //Hypervisor Counter/Timer Virtualisation
    logic          [MXLEN -1:0] htimedelta;    //delta for VS/VU-mode timer

    //Hypervisor State Enable
    logic          [MXLEN -1:0] hstateen0,
                                hstateen1,
                                hstateen2,
                                hstateen3;

    //Virtual Supervisor
    logic          [MXLEN -1:0] vsstatus;      //virtual supervisor status
    logic          [MXLEN -1:0] vsie;          //virtual supervisor interrupt enable
    logic          [MXLEN -1:0] vstvec;        //virtual supervisor trap handler base address
    logic          [MXLEN -1:0] vsscratch;     //virtual supervisor scratchpad
    logic          [MXLEN -1:0] vsepc;         //virtual supervisor exception program counter
    logic          [MXLEN -1:0] vscause;       //virtual supervisor trap cause
    logic          [MXLEN -1:0] vstval;        //virtual supervisor bad address or instruction
    logic          [MXLEN -1:0] vsip;          //virtual supervisor interrupt pending
    logic          [MXLEN -1:0] vsatp;         //virtual supervisor address translation and protection

    /*
     * Machine
     */
    mvendorid_struct            mvendorid;     //Vendor-ID
    logic          [MXLEN -1:0] marchid;       //Architecture ID
    logic          [MXLEN -1:0] mimpid;        //Revision number
    logic          [MXLEN -1:0] mhartid;       //Hardware Thread ID
    logic          [MXLEN -1:0] mconfigptr;    //Pointer to configuration data structure

    //Machine Trap Setup
    mstatus_struct              mstatus;       //status
    misa_struct                 misa;          //Machine ISA extensions
    logic          [      63:0] medeleg;       //Machine excepton delegation
    logic          [MXLEN -1:0] mideleg;       //Machine interrupt delegation
    mie_t                       mie;           //Machine interrupt enable
    logic          [MXLEN -1:0] mtvec;         //trap handler base address
    logic          [MXLEN -1:0] mcounteren;    //counter enable

    //Machine Trap Handler
    logic          [MXLEN -1:0] mscratch;      //scratch register
    logic          [MXLEN -1:0] mepc;          //exception program counter
    logic          [MXLEN -1:0] mcause;        //trap cause
    logic          [MXLEN -1:0] mtval;         //bad address or instruction
    mip_t                       mip;           //interrupt pending
    logic          [MXLEN -1:0] mtinst;        //trap instruction (transformed)
    logic          [MXLEN -1:0] mtval2;        //bad guest physical address

    //Machine Configuration
    logic          [63		 :0] menvcfg;       //environment configuration CHANGED BY TIM
    logic          [63      :0] mseccfg;        //security configuration CHANGED BY TIM

    //Machine Memory Protection
    pmpcfg_t [15:0]             pmpcfg;        //physical memory protection configuration
    logic    [15:0][MXLEN -1:0] pmpaddr;       //physical memory protection address

    //Machine State Enable
    logic          [MXLEN -1:0] mstateen0,
                                mstateen1,
                                mstateen2,
                                mstateen3;

    //Machine Non-Maskable Interrupt Hanlding
    logic          [MXLEN -1:0] mnmivec;       //RoaLogic NMI trap handler address
    logic          [MXLEN -1:0] mnscratch;     //resumable NMI scratchpad
    logic          [MXLEN -1:0] mnepc;         //resumable NMI program counter
    logic          [MXLEN -1:0] mncause;       //resumable NMI cause
    logic          [MXLEN -1:0] mnstatus;      //resumable NMI status

    //Machine counters/Timers
    timer_struct                mcycle,        //timer for MCYCLE
                                minstret;      //instruction retire count for MINSTRET
    //mhpmcounter[31:3];

    //Machine Counter Setup
    logic          [MXLEN -1:0] mcountinhibit; //counter inhibit
//    logic          [MXLEN -1:0] mhpmevent[31:3]

    //Debug/Trace
    logic          [MXLEN -1:0] tselect;       //Debug/Trace trigger select
    logic          [MXLEN -1:0] tdata1,        //Debug/Trace data
                                tdata2,
                                tdata3;
    logic          [MXLEN -1:0] mcontext;


    //Debug Mode
    logic          [MXLEN -1:0] dcsr;          //Debug control and status
    logic          [MXLEN -1:0] dpc;           //Debug program counter
    logic          [MXLEN -1:0] dscratch0,     //Debug scratchpad
                                dscratch1;

  } csr_struct;
  csr_struct csr;


  logic             is_rv32,
                    is_rv32e,
                    is_rv64,
                    is_rv128,
                    has_rvc,
                    has_fpu, has_fpud, has_fpuq,
                    has_mmu,
                    has_muldiv,
                    has_amo,
                    has_b,
                    has_tmem,
                    has_simd,
                    has_u,
                    has_s,
                    has_h,
                    has_ext;

  logic [     63:0] mstatus;      //mstatus is special (can be larger than 32bits)
  logic [      1:0] uxl_wval,     //u/sxl are taken from bits 35:32
                    sxl_wval;     //and can only have limited values

  logic             soft_seip,    //software supervisor-external-interrupt
                    soft_ueip;    //software user-external-interrupt

  logic             take_interrupt;

  logic [      3:0] interrupt_cause,
                    trap_cause;


  //CSR access
  logic [      11:0] csr_raddr;    //CSR read address
  logic [MXLEN -1:0] csr_rval;     //CSR read value
  logic [MXLEN -1:0] csr_wval;     //CSR write value


  ////////////////////////////////////////////////////////////////
  //
  // Module Body
  //
  assign is_rv32   = (MXLEN      ==  32);
  assign is_rv64   = (MXLEN      ==  64);
  assign is_rv128  = (MXLEN      == 128);
  assign is_rv32e  = (IS_RV32E   !=   0) & is_rv32;
  assign has_u     = (HAS_USER   !=   0);
  assign has_s     = (HAS_SUPER  !=   0) & has_u;
  assign has_h     = 1'b0;  //(HAS_HYPER  !=   0) & has_s;   //No Hypervisor

  assign has_rvc   = (HAS_RVC    !=   0);
  assign has_fpu   = (HAS_FPU    !=   0);
  assign has_fpuq  = (FLEN       == 128) & has_fpu;
  assign has_fpud  =((FLEN       ==  64) & has_fpu) | has_fpuq;
  assign has_mmu   = (HAS_MMU    !=   0) & has_s;
  assign has_muldiv= (HAS_RVM    !=   0);
  assign has_amo   = (HAS_RVA    !=   0);
  assign has_b     = (HAS_RVB    !=   0);
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
  //mstatus has different values for RV32 and RV64
  //treat it here as though it is a 64bit register
  assign mstatus = {csr.mstatus.sd,
                    {63-34{1'b0}},
                    csr.mstatus.mbe,
                    csr.mstatus.sbe,
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
                    csr.mstatus.vs,
                    csr.mstatus.spp,
                    csr.mstatus.mpie,
                    csr.mstatus.ube,
                    csr.mstatus.spie,
                    1'b0,
                    csr.mstatus.mie,
                    1'b0,
                    csr.mstatus.sie,
                    1'b0};

  
  //Read
  always_comb
    unique case (csr_raddr)
      //User
      FFLAGS    : csr_rval = has_fpu ? { {MXLEN-$bits(csr.fcsr.flags){1'b0}},csr.fcsr.flags } : 'h0;
      FRM       : csr_rval = has_fpu ? { {MXLEN-$bits(csr.fcsr.rm   ){1'b0}},csr.fcsr.rm    } : 'h0;
      FCSR      : csr_rval = has_fpu ? { {MXLEN-$bits(csr.fcsr      ){1'b0}},csr.fcsr       } : 'h0;
      CYCLE     : csr_rval = csr.mcycle[MXLEN-1:0];
//      TIME      : csr_rval = csr.timer[MXLEN-1:0];
      INSTRET   : csr_rval = csr.minstret[MXLEN-1:0];
      CYCLEH    : csr_rval = is_rv32 ? csr.mcycle.h   : 'h0;
//      TIMEH     : csr_rval = is_rv32 ? csr.timer.h   : 'h0;
      INSTRETH  : csr_rval = is_rv32 ? csr.minstret.h : 'h0;

      //Supervisor
      SSTATUS   : csr_rval = {mstatus[63],mstatus[MXLEN-2:0]} & (1 << MXLEN-1 | 2'b11 << 32 | 'hde133); // CHANGED BY TIM
      SIE       : csr_rval = has_s            ? csr.mie               & 12'h333 : 'h0;
      STVEC     : csr_rval = has_s            ? csr.stvec                       : 'h0;
      SCOUNTEREN: csr_rval = has_s            ? csr.scounteren                  : 'h0;
      SSCRATCH  : csr_rval = has_s            ? csr.sscratch                    : 'h0;
      SEPC      : csr_rval = has_s            ? csr.sepc                        : 'h0;
      SCAUSE    : csr_rval = has_s            ? csr.scause                      : 'h0;
      STVAL     : csr_rval = has_s            ? csr.stval                       : 'h0;
      SIP       : csr_rval = has_s            ? csr.mip & csr.mideleg & 12'h333 : 'h0;
      SATP      : csr_rval = has_s && has_mmu ? csr.satp                        : 'h0;
/*
      //Hypervisor
      HSTATUS   : csr_rval = {mstatus[127],mstatus[MXLEN-2:0] & (1 << MXLEN-1 | 2'b11 << 32 | 'hde133);
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
      MISA      : csr_rval = {csr.misa.mxl, {MXLEN-$bits(csr.misa){1'b0}}, csr.misa.extensions};
      MVENDORID : csr_rval = {{MXLEN-$bits(csr.mvendorid){1'b0}}, csr.mvendorid};
      MARCHID   : csr_rval = csr.marchid;
      MIMPID    : csr_rval = is_rv32 ? csr.mimpid : { {MXLEN-$bits(csr.mimpid){1'b0}}, csr.mimpid };
      MHARTID   : csr_rval = csr.mhartid;
      MSTATUS   : csr_rval = {mstatus[63],mstatus[MXLEN-2:0]};
      MSTATUSH  : csr_rval = is_rv32 ? { {MXLEN-6{1'b0}}, csr.mstatus.mbe, csr.mstatus.sbe, 4'h0} : 'h0;
      MCONFIGPTR: csr_rval = {MXLEN{1'b0}} | MCONFIGPTR_VAL;
      MTVEC     : csr_rval = csr.mtvec;
      MCOUNTEREN: csr_rval = csr.mcounteren;
      MNMIVEC   : csr_rval = csr.mnmivec;
      MEDELEG   : csr_rval = csr.medeleg[MXLEN-1:0];
      MEDELEGH  : csr_rval = is_rv32 ? csr.medeleg[63:32] : 'h0;
      MIDELEG   : csr_rval = csr.mideleg;
      MIE       : csr_rval = csr.mie & 12'hFFF;
      MSCRATCH  : csr_rval = csr.mscratch;
      MEPC      : csr_rval = csr.mepc;
      MCAUSE    : csr_rval = csr.mcause;
      MTVAL     : csr_rval = csr.mtval;
      MIP       : csr_rval = csr.mip;
      MTINST    : csr_rval = {MXLEN{1'b0}};
      MTVAL2    : csr_rval = {MXLEN{1'b0}}; //For guest-page-faults
      MENVCFG   : csr_rval = csr.menvcfg[MXLEN-1:0];
      MENVCFGH  : csr_rval = is_rv32 ? csr.menvcfg[63:32] : 'h0;
//    MSECCFG
//    MSECCFGH
      PMPCFG0   : csr_rval =            csr.pmpcfg[ 0 +: MXLEN/8];
      PMPCFG1   : csr_rval = is_rv32  ? csr.pmpcfg[ 7  :       4] : 'h0;
      PMPCFG2   : csr_rval =~is_rv128 ? csr.pmpcfg[ 8 +: MXLEN/8] : 'h0;
      PMPCFG3   : csr_rval = is_rv32  ? csr.pmpcfg[15  :      12] : 'h0;
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
      MCYCLE    : csr_rval = csr.mcycle[MXLEN-1:0];
      MINSTRET  : csr_rval = csr.minstret[MXLEN-1:0];
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
  assign csr.misa.mxl        = is_rv128 ? RV128I : is_rv64 ? RV64I : RV32I;
  assign csr.misa.extensions =  '{z: 1'b0,       //reserved
                                  y: 1'b0,       //reserved
                                  x: has_ext,
                                  w: 1'b0,       //reserved
                                  v: 1'b0,       //reserved for vector extensions
                                  u: has_u,      //user mode supported
                                  t: 1'b0,       //reserved
                                  s: has_s,      //supervisor mode supported
                                  r: 1'b0,       //reserved
                                  q: has_fpuq,
                                  p: has_simd,
                                  o: 1'b0,       //reserved
                                  n: 1'b0,       //reserved (for user lvl interrupts)
                                  m: has_muldiv,
                                  l: 1'b0,       //reserved
                                  k: 1'b0,       //reserved
                                  j: 1'b0,       //reserved for JIT
                                  i: ~is_rv32e,
                                  h: 1'b0,       //hypervisor extensions
                                  g: 1'b0,       //additional extensions
                                  f: has_fpu,
                                  e: is_rv32e,
                                  d: has_fpud,
                                  c: has_rvc,
                                  b: has_b,
                                  a: has_amo,
                                  default : 1'b0};

  assign csr.mvendorid.bank    = JEDEC_BANK -1;
  assign csr.mvendorid.offset  = JEDEC_MANUFACTURER_ID[6:0];
  assign csr.marchid           = (1 << (MXLEN-1)) | ARCHID;
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
  if (MXLEN == 128)
  begin
      assign sxl_wval = |csr_wval[35:34] ? csr_wval[35:34] : csr.mstatus.sxl;
      assign uxl_wval = |csr_wval[33:32] ? csr_wval[33:32] : csr.mstatus.uxl;
  end
  else if (MXLEN == 64)
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
      PRV_S  : begin
                   st_xlen_o = has_s ? csr.mstatus.sxl : csr.misa.mxl;
                   st_be_o   = has_s ? csr.mstatus.sbe : csr.mstatus.mbe;
               end
      PRV_U  : begin
                   st_xlen_o = has_u ? csr.mstatus.uxl : csr.misa.mxl;
                   st_be_o   = has_u ? csr.mstatus.ube : csr.mstatus.mbe;
               end
      default: begin
                   st_xlen_o = csr.misa.mxl;
                   st_be_o   = csr.mstatus.mbe;
               end
    endcase


  always @(posedge clk_i,negedge rst_ni)
    if (!rst_ni)
    begin
        st_prv_o         <= PRV_M;    //start in machine mode
        st_nxt_pc_o      <= PC_INIT;
        st_flush_o       <= 1'b1;     //flush CPU(heart) upon reset exit

        csr.mstatus.mbe  <= 1'b0;
        csr.mstatus.sbe  <= 1'b0;
        csr.mstatus.sxl  <= has_s ? csr.misa.mxl : 2'b00;
        csr.mstatus.uxl  <= has_u ? csr.misa.mxl : 2'b00;
        csr.mstatus.tsr  <= 1'b0;
        csr.mstatus.tw   <= 1'b0;
        csr.mstatus.tvm  <= 1'b0;
        csr.mstatus.mxr  <= 1'b0;
        csr.mstatus.sum  <= 1'b0;
        csr.mstatus.mprv <= 1'b0;
        csr.mstatus.xs   <= {2{has_ext}};
        csr.mstatus.fs   <= 2'b00;

        csr.mstatus.mpp  <= PRV_M;
        csr.mstatus.vs   <= 2'b00; //for V-extension
        csr.mstatus.spp  <= has_s;
        csr.mstatus.mpie <= 1'b0;
        csr.mstatus.ube  <= 1'b0;
        csr.mstatus.spie <= 1'b0;
        csr.mstatus.mie  <= 1'b0;
        csr.mstatus.sie  <= 1'b0;
    end
    else
    begin
        st_flush_o <= 1'b0;

        //write from EX, Machine Mode
        if ( (ex_csr_we_i && ex_csr_reg_i == MSTATUS && st_prv_o == PRV_M) ||
             (du_we_csr_i && du_addr_i    == MSTATUS)                     )
        begin
//            csr.mstatus.vm    <= csr_wval[28:24];
            csr.mstatus.sxl   <= has_s && MXLEN > 32 ? sxl_wval        : 2'b00;
            csr.mstatus.uxl   <= has_u && MXLEN > 32 ? uxl_wval        : 2'b00;
            csr.mstatus.tsr   <= has_s               ? csr_wval[22]    : 1'b0;
            csr.mstatus.tw    <= has_s               ? csr_wval[21]    : 1'b0;
            csr.mstatus.tvm   <= has_s               ? csr_wval[20]    : 1'b0;
            csr.mstatus.mxr   <= has_s               ? csr_wval[19]    : 1'b0;
            csr.mstatus.sum   <= has_s               ? csr_wval[18]    : 1'b0;
            csr.mstatus.mprv  <= has_u               ? csr_wval[17]    : 1'b0;
            csr.mstatus.xs    <= has_ext             ? csr_wval[16:15] : 2'b00; //TODO
            csr.mstatus.fs    <= has_s && has_fpu    ? csr_wval[14:13] : 2'b00; //TODO

	    case (csr_wval[12:11])
              PRV_M: csr.mstatus.mpp <=         PRV_M;
              PRV_H: csr.mstatus.mpp <= has_h ? PRV_H : csr.mstatus.mpp;
              PRV_S: csr.mstatus.mpp <= has_s ? PRV_S : csr.mstatus.mpp;
              PRV_U: csr.mstatus.mpp <= has_u ? PRV_U : csr.mstatus.mpp;
            endcase
            csr.mstatus.vs    <=         csr_wval[10:9];
            csr.mstatus.spp   <= has_s ? csr_wval[   8] : 1'b0;
            csr.mstatus.mpie  <=         csr_wval[   7];
            csr.mstatus.ube   <=         csr_wval[   6];
            csr.mstatus.spie  <= has_s ? csr_wval[   5] : 1'b0;
            csr.mstatus.mie   <=         csr_wval[   3];
            csr.mstatus.sie   <= has_s ? csr_wval[   1] : 1'b0;
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
                csr.mstatus.sie  <= csr_wval[1];
            end
        end

        //MRET,SRET
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
            endcase
        end

        //push privilege stack
        if (wb_exceptions_i.nmi)
        begin
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
            st_flush_o  <= 1'b1;

            //Check if interrupts are delegated
            if (has_s && st_prv_o >= PRV_S && (wb_exceptions_i.interrupts & csr.mideleg & 12'h333) )
            begin
                st_prv_o    <= PRV_S;
                st_nxt_pc_o <= csr.stvec & ~'h3 + (csr.stvec[0] ? interrupt_cause << 2 : 0);

                csr.mstatus.spie <= csr.mstatus.sie;
                csr.mstatus.sie  <= 1'b0;
                csr.mstatus.spp  <= st_prv_o[0];
            end
            else
            begin
                st_prv_o    <= PRV_M;
                st_nxt_pc_o <= csr.mtvec & ~'h3 + (csr.mtvec[0] ? interrupt_cause << 2 : 0);

                csr.mstatus.mpie <= csr.mstatus.mie;
                csr.mstatus.mie  <= 1'b0;
                csr.mstatus.mpp  <= st_prv_o;
            end
        end
        else if ( |(wb_exceptions_i.exceptions & ~du_ee_i) )
        begin
            st_flush_o  <= 1'b1;

            if (has_s && st_prv_o >= PRV_S && |(wb_exceptions_i.exceptions & csr.medeleg))
            begin
                st_prv_o    <= PRV_S;
                st_nxt_pc_o <= csr.stvec;

                csr.mstatus.spie <= csr.mstatus.sie;
                csr.mstatus.sie  <= 1'b0;
                csr.mstatus.spp  <= st_prv_o[0];

            end
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
  if (MXLEN==32)
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
          else
            csr.minstret <= csr.minstret + wb_insn_i.retired;
      end
  end
  else //(MXLEN > 32)
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
          else
            csr.minstret <= csr.minstret + wb_insn_i.retired;
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
      csr.mnmivec <= {csr_wval[MXLEN-1:2],2'b00};


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
   * medeleg
   */
generate
  if (!HAS_SUPER)
  begin
      assign csr.medeleg = 0;
  end
  else
  if (MXLEN==32)
  begin
  end
  else //MXLEN > 32
  begin
      always @(posedge clk_i,negedge rst_ni)
        if (!rst_ni)
          csr.medeleg <= 'h0;
        else if ( (ex_csr_we_i && ex_csr_reg_i == MEDELEG && st_prv_o == PRV_M) ||
                  (du_we_csr_i && du_addr_i    == MEDELEG)                      )
        begin
            csr.medeleg[31:0] <= csr_wval;
            csr.medeleg[CAUSE_MMODE_ECALL] = 1'b0;
        end

      always @(posedge clk_i,negedge rst_ni)
        if (!rst_ni)
          csr.medeleg <= 'h0;
        else if ( (ex_csr_we_i && ex_csr_reg_i == MEDELEGH && st_prv_o == PRV_M) ||
                  (du_we_csr_i && du_addr_i    == MEDELEGH)                      )
        begin
            csr.medeleg[63:32] <= csr_wval;
        end
  end
endgenerate


  /*
   * mideleg
   */
generate
  if (!HAS_SUPER)
  begin
      assign csr.mideleg = 'h0;
  end
  else
  begin
      always @(posedge clk_i,negedge rst_ni)
        if (!rst_ni)
          csr.mideleg <= 'h0;
        else if ( (ex_csr_we_i && ex_csr_reg_i == MIDELEG && st_prv_o == PRV_M) ||
                  (du_we_csr_i && du_addr_i    == MIDELEG)                      )
          csr.mideleg <= csr_wval;
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
        csr.mip.seip <= has_s & (int_external_i[PRV_S] | soft_seip);

        //may only be written by M-mode
        if ( (ex_csr_we_i & ex_csr_reg_i == MIP & st_prv_o == PRV_M) ||
             (du_we_csr_i & du_addr_i    == MIP)                  )
        begin
            soft_seip <= csr_wval[SEI] & has_s;
        end
 

        //timer interrupts
        csr.mip.mtip <= int_timer_i;

        //may only be written by M-mode
        if ( (ex_csr_we_i & ex_csr_reg_i == MIP & st_prv_o == PRV_M) ||
             (du_we_csr_i & du_addr_i    == MIP)                  )
        begin
            csr.mip.stip <= csr_wval[STI] & has_s;
        end


        //software interrupts
        csr.mip.msip <= int_software_i;
        //Machine Mode write
        if ( (ex_csr_we_i && ex_csr_reg_i == MIP && st_prv_o == PRV_M) ||
             (du_we_csr_i && du_addr_i    == MIP)                   )
        begin
            csr.mip.ssip <= csr_wval[SSI] & has_s;
        end
        else if (has_s)
        begin
            //Supervisor Mode write
            if ( (ex_csr_we_i && ex_csr_reg_i == SIP && st_prv_o >= PRV_S) ||
                 (du_we_csr_i && du_addr_i    == SIP)                   )
            begin
                csr.mip.ssip <= csr_wval[SSI] & csr.mideleg[SSI];
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
        csr.mie.meie   <= csr_wval[MEI];
        csr.mie.seie   <= csr_wval[SEI] & has_s;
        csr.mie.mtie   <= csr_wval[MTI];
        csr.mie.stie   <= csr_wval[STI] & has_s;
        csr.mie.msie   <= csr_wval[MSI];
        csr.mie.ssie   <= csr_wval[SSI] & has_s;
        csr.mie.lcofie <= csr_wval[CNT_OVF];
    end
    else if (has_s)
    begin
        if ( (ex_csr_we_i && ex_csr_reg_i == SIE && st_prv_o >= PRV_S) ||
             (du_we_csr_i && du_addr_i    == SIE)                   )
        begin
            csr.mie.seie <= csr_wval[SEI];
            csr.mie.stie <= csr_wval[STI];
            csr.mie.ssie <= csr_wval[SSI];
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



  //decode interrupts
  //priority external, software, timer
  //st_int_o goes into ID, where the interrupts are synchronized
  //with the CPU pipeline
  // CHANGED BY TIM
  assign st_int_o.external[PRV_M[1]] = ( ((st_prv_o < PRV_M) | (st_prv_o == PRV_M & csr.mstatus.mie)) & (csr.mip.meip & csr.mie.meie) );
  assign st_int_o.external[PRV_S[1]] = ( ((st_prv_o < PRV_S) | (st_prv_o == PRV_S & csr.mstatus.sie)) & (csr.mip.seip & csr.mie.seie) );

  assign st_int_o.software[PRV_M[1]] = ( ((st_prv_o < PRV_M) | (st_prv_o == PRV_M & csr.mstatus.mie)) & (csr.mip.msip & csr.mie.msie) ) &
                                   ~st_int_o.external[PRV_M[1]];
  assign st_int_o.software[PRV_S[1]] = ( ((st_prv_o < PRV_S) | (st_prv_o == PRV_S & csr.mstatus.sie)) & (csr.mip.ssip & csr.mie.ssie) ) &
                                   ~st_int_o.external[PRV_S[1]];

  assign st_int_o.timer   [PRV_M[1]] = ( ((st_prv_o < PRV_M) | (st_prv_o == PRV_M & csr.mstatus.mie)) & (csr.mip.mtip & csr.mie.mtie) ) &
                                   ~(st_int_o.external[PRV_M[1]] | st_int_o.software[PRV_M[1]]);
  assign st_int_o.timer   [PRV_S[1]] = ( ((st_prv_o < PRV_S) | (st_prv_o == PRV_S & csr.mstatus.sie)) & (csr.mip.stip & csr.mie.stie) ) &
                                   ~(st_int_o.external[PRV_S[1]] | st_int_o.software[PRV_S[1]]);


  //exception/interrupt cause priority
  assign trap_cause      = find_first_one(wb_exceptions_i.exceptions & ~du_ee_i);
  assign interrupt_cause = find_first_one(wb_exceptions_i.interrupts & ~du_ie_i);
  assign take_interrupt  =              |(wb_exceptions_i.interrupts & ~du_ie_i);

  //for Debug Unit
  assign du_exceptions_o = du_ee_i & wb_exceptions_i.exceptions;
  assign du_interrupts_o = du_ie_i & wb_exceptions_i.interrupts;


  //Update mepc and mcause
  always @(posedge clk_i,negedge rst_ni)
    if (!rst_ni)
    begin
        csr.mepc     <= 'h0;
        csr.sepc     <= 'h0;

        csr.mcause   <= 'h0;
        csr.scause   <= 'h0;

        csr.mtval    <= 'h0;
        csr.stval    <= 'h0;
    end
    else
    begin
        //Write access to regs (lowest priority)
        if ( (ex_csr_we_i && ex_csr_reg_i == MEPC && st_prv_o == PRV_M) ||
             (du_we_csr_i && du_addr_i    == MEPC)                      )
          csr.mepc <= {csr_wval[MXLEN-1:2], csr_wval[1] & has_rvc, 1'b0};

        if ( (ex_csr_we_i && ex_csr_reg_i == SEPC && st_prv_o >= PRV_S) ||
             (du_we_csr_i && du_addr_i    == SEPC)                      )
          csr.sepc <= {csr_wval[MXLEN-1:2], csr_wval[1] & has_rvc, 1'b0};

        if ( (ex_csr_we_i && ex_csr_reg_i == MCAUSE && st_prv_o == PRV_M) ||
             (du_we_csr_i && du_addr_i    == MCAUSE)                      )
          csr.mcause <= csr_wval;

        if ( (ex_csr_we_i && ex_csr_reg_i == SCAUSE && st_prv_o >= PRV_S) ||
             (du_we_csr_i && du_addr_i    == SCAUSE)                      )
          csr.scause <= csr_wval;

        if ( (ex_csr_we_i && ex_csr_reg_i == MTVAL && st_prv_o == PRV_M) ||
             (du_we_csr_i && du_addr_i    == MTVAL)                      )
          csr.mtval <= csr_wval;

        if ( (ex_csr_we_i && ex_csr_reg_i == STVAL && st_prv_o >= PRV_S) ||
             (du_we_csr_i && du_addr_i    == STVAL)                      )
          csr.stval <= csr_wval;


        /*
         * Handle exceptions
         */
        //priority external interrupts, software interrupts, timer interrupts, traps
        if (wb_exceptions_i.nmi) //TODO: doesn't this cause a deadlock? Need to hold of NMI once handled
        begin
            //NMI always at Machine Level
            csr.mepc     <= bu_flush_i ? bu_nxt_pc_i : wb_pc_i;
            csr.mcause   <= (1 << (MXLEN-1)) | 'h0; //Implementation dependent. '0' indicates 'unknown cause'
        end
        else if (take_interrupt)
        begin
            //Check if interrupts are delegated
            if (has_s && st_prv_o >= PRV_S && (wb_exceptions_i.interrupts & csr.mideleg & 12'h333) )
            begin
                csr.scause <= (1 << (MXLEN-1)) | interrupt_cause;
		
		//don't update application return address if state caused a flush (ISR exit)
                if (!st_flush_o) csr.sepc <= wb_pc_i;
            end
            else
            begin
                csr.mcause <= (1 << (MXLEN-1)) | interrupt_cause;;

		//don't update application return address if state caused a flush (ISR exit)
                if (!st_flush_o) csr.mepc <= wb_pc_i;
            end
        end
        else if (|(wb_exceptions_i.exceptions & ~du_ee_i))
        begin
            //Trap
            if (has_s && st_prv_o >= PRV_S && |(wb_exceptions_i.exceptions & csr.medeleg))
            begin
                csr.sepc   <= wb_pc_i;
                csr.scause <= trap_cause;

                if (wb_exceptions_i.exceptions.illegal_instruction)
                  csr.stval <= wb_insn_i.instr;
                else			 
                  csr.stval <= wb_badaddr_i;
            end
            else
            begin
                csr.mepc   <= wb_pc_i;
                csr.mcause <= trap_cause;

                if (wb_exceptions_i.exceptions.illegal_instruction)
                  csr.mtval <= wb_insn_i.instr;
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

  if (MXLEN > 64)      //RV128
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
  else if (MXLEN > 32) //RV64
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
      assign csr.sscratch   = 'h0;
      assign csr.satp       = 'h0;
  end
endgenerate

  assign st_scounteren_o = csr.scounteren;


  ////////////////////////////////////////////////////////////////
  //User Mode Registers
  //
generate
  if (HAS_USER)
  begin
      //Floating point registers
      if (HAS_FPU)
      begin
          //TODO
      end
  end
  else //NO USER MODE
  begin
      assign csr.fcsr     = 'h0;
      assign csr.menvcfg  = 'h0;
  end
endgenerate


endmodule 

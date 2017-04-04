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
//    (Thread) State (priv spec 1.9.1)                         //
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

module riscv_state1_9 #(
  parameter            XLEN            = 32,
  parameter            FLEN            = 64, //floating point data length
  parameter [XLEN-1:0] PC_INIT         = 'h200,
  parameter            INSTR_SIZE      = 32,
  parameter            EXCEPTION_SIZE  = 12,

  parameter            IS_RV32E        = 0,
  parameter            HAS_N           = 0,
  parameter            HAS_RVC         = 0,
  parameter            HAS_FPU         = 0,
  parameter            HAS_DFPU        = 0,
  parameter            HAS_QFPU        = 0,
  parameter            HAS_MMU         = 0,
  parameter            HAS_MULDIV      = 0,
  parameter            HAS_AMO         = 0,
  parameter            HAS_BM          = 0,
  parameter            HAS_TMEM        = 0,
  parameter            HAS_SIMD        = 0,
  parameter            HAS_EXT         = 0,

  parameter            HAS_USER        = 1,
  parameter            HAS_SUPER       = 1,
  parameter            HAS_HYPER       = 0,

  parameter            MNMIVEC_DEFAULT = PC_INIT -'h004,
  parameter            MTVEC_DEFAULT   = PC_INIT -'h040,
  parameter            HTVEC_DEFAULT   = PC_INIT -'h080,
  parameter            STVEC_DEFAULT   = PC_INIT -'h0C0,
  parameter            UTVEC_DEFAULT   = PC_INIT -'h100,

  parameter            VENDORID        = 16'h0001,
  parameter            ARCHID          = (1<<XLEN) | 12,
  parameter            REVMAJOR        = 4'h0,
  parameter            REVMINOR        = 4'h0,

  parameter            HARTID          = 0      //hardware thread-id
)
(
  input                           rstn,
  input                           clk,

  input      [XLEN          -1:0] id_pc,
  input                           id_bubble,
  input      [INSTR_SIZE    -1:0] id_instr,
  input                           id_stall,

  input                           bu_flush,
  input      [XLEN          -1:0] bu_nxt_pc,
  output reg                      st_flush,
  output reg [XLEN          -1:0] st_nxt_pc,

  input      [XLEN          -1:0] wb_pc,
  input      [EXCEPTION_SIZE-1:0] wb_exception,
  input      [XLEN          -1:0] wb_badaddr,

  output reg                      st_interrupt,
  output reg [               1:0] st_prv,

  //interrupts (3=M-mode, 0=U-mode)
  input      [               3:0] ext_int,  //external interrupt (per privilege mode; determined by PIC)
  input                           ext_tint, //machine timer interrupt
                                  ext_sint, //machine software interrupt (for ipi)
  input                           ext_nmi,  //non-maskable interrupt

  //CSR interface
  input      [              11:0] ex_csr_reg,
  input                           ex_csr_we,
  input      [XLEN          -1:0] ex_csr_wval,
  output reg [XLEN          -1:0] st_csr_rval,

  //Debug interface
  input                           du_stall,
                                  du_flush,
                                  du_we_csr,
  input      [XLEN          -1:0] du_dato,   //output from debug unit
  input      [              11:0] du_addr,
  input      [              31:0] du_ie,
  output     [              31:0] du_exceptions
);

  ////////////////////////////////////////////////////////////////
  //
  // Variables
  //
  import riscv_pkg::*;
  import riscv_state_pkg::*;

  /*
   * CSRs
   */
  typedef struct packed {
    /*
     * User
     */
    //Floating point registers
    fcsr_struct fcsr;

    //User Counter/Timers
    timer_struct      cycle,   //timer for RDCYCLE
                      timer,   //timer for RDTIME
                      instret; //instruction retire count for RDINSTRET

    //User trap setup
    logic  [XLEN-1:0] utvec;

    //User trap handler
    logic  [XLEN-1:0] uscratch; //scratch register
    logic  [XLEN-1:0] uepc;     //exception program counter
    logic  [XLEN-1:0] ucause;   //trap cause
    logic  [XLEN-1:0] ubadaddr; //bad address


    /*
     * Supervisor
     */
    //Supervisor trap setup
    logic  [XLEN-1:0] stvec;    //trap handler base address
    logic  [XLEN-1:0] sedeleg;  //trap delegation register

    //Supervisor trap handler
    logic  [XLEN-1:0] sscratch; //scratch register
    logic  [XLEN-1:0] sepc;     //exception program counter
    logic  [XLEN-1:0] scause;   //trap cause
    logic  [XLEN-1:0] sbadaddr; //bad address

    //Supervisor protection and Translation
    logic  [XLEN-1:0] sptbr;    //Page-table base address


    /*
     * Hypervisor
     */
    //Hypervisor Trap Setup
    logic  [XLEN-1:0] htvec;    //trap handler base address
    logic  [XLEN-1:0] hedeleg;  //trap delegation register

    //Hypervisor trap handler
    logic  [XLEN-1:0] hscratch; //scratch register
    logic  [XLEN-1:0] hepc;     //exception program counter
    logic  [XLEN-1:0] hcause;   //trap cause
    logic  [XLEN-1:0] hbadaddr; //bad address

    //Hypervisor protection and Translation
    //TBD per spec v1.7, somewhat defined in 1.9, removed in 1.10?
      

    /*
     * Machine
     */
    logic  [XLEN-1:0] mvendorid, //Vendor-ID
                      marchid,   //Architecture ID
                      mimpid;    //Revision number
    logic  [XLEN-1:0] mhartid;   //Hardware Thread ID

    //Machine Trap Setup
    mstatus_struct    mstatus;  //status
    misa_struct       misa;     //Machine ISA
    logic  [XLEN-1:0] mnmivec;  //ROALOGIC NMI handler base address
    logic  [XLEN-1:0] mtvec;    //trap handler base address
    logic  [XLEN-1:0] medeleg,  //Exception delegation
                      mideleg;  //Interrupt delegation
    mie_struct        mie;      //interrupt enable

    //Machine trap handler
    logic  [XLEN-1:0] mscratch; //scratch register
    logic  [XLEN-1:0] mepc;     //exception program counter
    logic  [XLEN-1:0] mcause;   //trap cause
    logic  [XLEN-1:0] mbadaddr; //bad address
    mip_struct        mip;      //interrupt pending

    //Machine protection and Translation
    logic  [XLEN-1:0] mbase;    //Base
    logic  [XLEN-1:0] mbound;   //Bound
    logic  [XLEN-1:0] mibase;   //Instruction base
    logic  [XLEN-1:0] mibound;  //Instruction bound
    logic  [XLEN-1:0] mdbase;   //Data base
    logic  [XLEN-1:0] mdbound;  //Data bound
  } csr_struct;
  csr_struct csr;


  logic                      is_rv32,
                             is_rv32e,
                             is_rv64,
                             has_rvc,
                             has_fpu, has_dfpu, has_qfpu,
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

  logic [XLEN          -1:0] mip,
                             mie,
                             mideleg,
                             medeleg;

  logic                      take_interrupt;

  logic [              11:0] st_exceptions;
  logic [              11:0] st_int;
  logic [               3:0] interrupt_cause,
                             trap_cause;

  //Mux for debug-unit
  logic [              11:0] csr_raddr; //CSR read address
  logic [XLEN          -1:0] csr_wval; //CSR write value



  ////////////////////////////////////////////////////////////////
  //
  // Module Body
  //
  assign is_rv32   = (XLEN       ==  32);
  assign is_rv64   = (XLEN       ==  64);
  assign is_rv32e  = (IS_RV32E   !=   0) & is_rv32;
  assign has_n     = (HAS_N      !=   0) & has_u;
  assign has_u     = (HAS_USER   !=   0);
  assign has_s     = (HAS_SUPER  !=   0) & has_u;
  assign has_h     = (HAS_HYPER  !=   0) & has_s;

  assign has_rvc   = (HAS_RVC    !=   0);
  assign has_fpu   = (HAS_FPU    !=   0);
  assign has_qfpu  = (FLEN       == 128) & has_fpu;
  assign has_dfpu  =((FLEN       ==  64) & has_fpu) | has_qfpu;
  assign has_decfpu= 1'b0;
  assign has_mmu   = (HAS_MMU    !=   0) & has_s;
  assign has_muldiv= (HAS_MULDIV !=   0);
  assign has_amo   = (HAS_AMO    !=   0);
  assign has_bm    = (HAS_BM     !=   0);
  assign has_tmem  = (HAS_TMEM   !=   0);
  assign has_simd  = (HAS_SIMD   !=   0);
  assign has_ext   = (HAS_EXT    !=   0);

  //Mux address/data for Debug-Unit access
  assign csr_raddr = du_stall ? du_addr : ex_csr_reg;
  assign csr_wval  = du_stall ? du_dato : ex_csr_wval;



  /*
   * Priviliged Control Registers
   */
  
  //Read
  always_comb
    (* synthesis,parallel_case *)
    case (csr_raddr)
      //User
      USTATUS   : st_csr_rval = {{XLEN-5{1'b0}},
                                  csr.mstatus.upie,
                                  3'h0,
                                  csr.mstatus.uie};
      UIE       : st_csr_rval = has_n ? csr.mie & 12'h111               : 'h0;
      UTVEC     : st_csr_rval = has_n ? csr.utvec                       : 'h0;
      USCRATCH  : st_csr_rval = has_n ? csr.uscratch                    : 'h0;
      UEPC      : st_csr_rval = has_n ? csr.uepc                        : 'h0;
      UCAUSE    : st_csr_rval = has_n ? csr.ucause                      : 'h0;
      UBADADDR  : st_csr_rval = has_n ? csr.ubadaddr                    : 'h0;
      UIP       : st_csr_rval = has_n ? csr.mip & csr.mideleg & 12'h111 : 'h0;

      FFLAGS    : st_csr_rval = has_fpu ? { {XLEN-$bits(csr.fcsr.flags){1'b0}},csr.fcsr.flags } : 'h0;
      FRM       : st_csr_rval = has_fpu ? { {XLEN-$bits(csr.fcsr.rm   ){1'b0}},csr.fcsr.rm    } : 'h0;
      FCSR      : st_csr_rval = has_fpu ? { {XLEN-$bits(csr.fcsr      ){1'b0}},csr.fcsr       } : 'h0;
      CYCLE     : st_csr_rval = csr.cycle[XLEN-1:0];
      TIME      : st_csr_rval = csr.timer[XLEN-1:0];
      INSTRET   : st_csr_rval = csr.instret[XLEN-1:0];
      CYCLEH    : st_csr_rval = is_rv32 ? csr.cycle.h   : 'h0;
      TIMEH     : st_csr_rval = is_rv32 ? csr.timer.h   : 'h0;
      INSTRETH  : st_csr_rval = is_rv32 ? csr.instret.h : 'h0;

      //Supervisor
      SSTATUS   : st_csr_rval = { csr.mstatus.sd,
                                  {XLEN-20{1'b0}},
                                  csr.mstatus.pum,
                                  1'b0,
                                  csr.mstatus.xs,
                                  csr.mstatus.fs,
                                  4'h0,
                                  csr.mstatus.spp,
                                  2'h0,
                                  csr.mstatus.spie,
                                  csr.mstatus.upie,
                                  2'h0,
                                  csr.mstatus.sie,
                                  csr.mstatus.uie};
      STVEC     : st_csr_rval = has_s ? csr.stvec                       : 'h0;
      SIE       : st_csr_rval = has_s ? csr.mie & 12'h333               : 'h0;
      SEDELEG   : st_csr_rval = has_s ? csr.sedeleg                     : 'h0;
      SIDELEG   : st_csr_rval = has_s ? csr.mideleg & 12'h111           : 'h0;
      SSCRATCH  : st_csr_rval = has_s ? csr.sscratch                    : 'h0;
      SEPC      : st_csr_rval = has_s ? csr.sepc                        : 'h0;
      SCAUSE    : st_csr_rval = has_s ? csr.scause                      : 'h0;
      SBADADDR  : st_csr_rval = has_s ? csr.sbadaddr                    : 'h0;
      SIP       : st_csr_rval = has_s ? csr.mip & csr.mideleg & 12'h333 : 'h0;
      SPTBR     : st_csr_rval = has_s ? has_mmu ? csr.sptbr : 'h0       : 'h0;

      //Hypervisor
      HSTATUS   : st_csr_rval = { csr.mstatus.sd,
                                  {XLEN-20{1'b0}},
                                  csr.mstatus.pum,
                                  1'b0,
                                  csr.mstatus.xs,
                                  csr.mstatus.fs,
                                  2'h0,
                                  csr.mstatus.hpp,
                                  csr.mstatus.spp,
                                  1'h0,
                                  csr.mstatus.hpie,
                                  csr.mstatus.spie,
                                  csr.mstatus.upie,
                                  1'h0,
                                  csr.mstatus.hie,
                                  csr.mstatus.sie,
                                  csr.mstatus.uie};
      HTVEC     : st_csr_rval = has_h ? csr.htvec                       : 'h0;
      HIE       : st_csr_rval = has_h ? csr.mie & 12'h777               : 'h0;
      HEDELEG   : st_csr_rval = has_h ? csr.hedeleg                     : 'h0;
      HIDELEG   : st_csr_rval = has_h ? csr.mideleg & 12'h333           : 'h0;
      HSCRATCH  : st_csr_rval = has_h ? csr.hscratch                    : 'h0;
      HEPC      : st_csr_rval = has_h ? csr.hepc                        : 'h0;
      HCAUSE    : st_csr_rval = has_h ? csr.hcause                      : 'h0;
      HBADADDR  : st_csr_rval = has_h ? csr.hbadaddr                    : 'h0;
      HIP       : st_csr_rval = has_h ? csr.mip & csr.mideleg & 12'h777 : 'h0;

      //Machine
      MISA      : st_csr_rval = {csr.misa.base, {XLEN-$bits(csr.misa){1'b0}}, csr.misa.extensions};
      MVENDORID : st_csr_rval = csr.mvendorid;
      MARCHID   : st_csr_rval = csr.marchid;
      MIMPID    : st_csr_rval = is_rv32 ? csr.mimpid : { {XLEN-$bits(csr.mimpid){1'b0}}, csr.mimpid };
      MHARTID   : st_csr_rval = csr.mhartid;
      MSTATUS   : st_csr_rval = {csr.mstatus.sd,
                                 {XLEN-30{1'b0}},
                                 csr.mstatus.vm,
                                 4'h0,
                                 csr.mstatus.mxr,
                                 csr.mstatus.pum,
                                 csr.mstatus.mprv,
                                 csr.mstatus.xs,
                                 csr.mstatus.fs,
                                 csr.mstatus.mpp,
                                 csr.mstatus.hpp,
                                 csr.mstatus.spp,
                                 csr.mstatus.mpie,
                                 csr.mstatus.hpie,
                                 csr.mstatus.spie,
                                 csr.mstatus.upie,
                                 csr.mstatus.mie,
                                 csr.mstatus.hie,
                                 csr.mstatus.sie,
                                 csr.mstatus.uie};
      MTVEC     : st_csr_rval = csr.mtvec;
      MNMIVEC   : st_csr_rval = csr.mnmivec;
      MEDELEG   : st_csr_rval = csr.medeleg;
      MIDELEG   : st_csr_rval = csr.mideleg;
      MIE       : st_csr_rval = csr.mie & 12'hFFF;
      MSCRATCH  : st_csr_rval = csr.mscratch;
      MEPC      : st_csr_rval = csr.mepc;
      MCAUSE    : st_csr_rval = csr.mcause;
      MBADADDR  : st_csr_rval = csr.mbadaddr;
      MIP       : st_csr_rval = csr.mip;
      MBASE     : st_csr_rval = csr.mbase;
      MBOUND    : st_csr_rval = csr.mbound;
      MIBASE    : st_csr_rval = csr.mibase;
      MIBOUND   : st_csr_rval = csr.mibound;
      MDBASE    : st_csr_rval = csr.mdbase;
      MDBOUND   : st_csr_rval = csr.mdbound;
      MCYCLE    : st_csr_rval = csr.cycle[XLEN-1:0];
      MINSTRET  : st_csr_rval = csr.instret[XLEN-1:0];
      MCYCLEH   : st_csr_rval = is_rv32 ? csr.cycle.h   : 'h0;
      MINSTRETH : st_csr_rval = is_rv32 ? csr.instret.h : 'h0;

      default   : st_csr_rval = 32'h0;
    endcase


  ////////////////////////////////////////////////////////////////
  // Machine registers
  //
  assign csr.misa.base       = is_rv64 ? RV64I : RV32I;
  assign csr.misa.extensions =  '{u: has_u,      //supports user mode
                                  s: has_s,      //supports supervisor mode
                                  h: has_h,      //supports hypervisor mode
                                  x: has_ext,
                                  t: has_tmem,
                                  p: has_simd,
                                  n: has_n,
                                  m: has_muldiv,
                                  l: has_decfpu,
                                  i: ~is_rv32e,
                                  e: is_rv32e, 
                                  f: has_fpu,
                                  d: has_dfpu,
                                  q: has_qfpu,
                                  c: has_rvc,
                                  b: has_bm,
                                  a: has_amo,
                                  default : 1'b0};

  assign csr.mvendorid    = VENDORID;
  assign csr.marchid      = ARCHID;
  assign csr.mimpid[XLEN-1:16] = 'h0;
  assign csr.mimpid[15:8] = REVMAJOR;
  assign csr.mimpid[ 7:0] = REVMINOR;
  assign csr.mhartid      = HARTID;

  //mstatus
  assign csr.mstatus.sd = &csr.mstatus.fs | &csr.mstatus.xs;

  always @(posedge clk,negedge rstn)
    if (!rstn)
    begin
        st_prv           <= PRV_M;    //start in machine mode
        st_nxt_pc        <= PC_INIT;
        st_flush         <= 1'b1;

        csr.mstatus.vm   <= VM_MBARE;
        csr.mstatus.mxr  <= 1'b0;
        csr.mstatus.pum  <= 1'b0;
        csr.mstatus.mprv <= 1'b0;
        csr.mstatus.xs   <= {2{has_ext}};
        csr.mstatus.fs   <= 2'b00;

        csr.mstatus.mpp  <= 2'h3;
        csr.mstatus.hpp  <= {2{has_h}};
        csr.mstatus.spp  <= has_s;
        csr.mstatus.mpie <= 1'b0;
        csr.mstatus.hpie <= 1'b0;
        csr.mstatus.spie <= 1'b0;
        csr.mstatus.upie <= 1'b0;
        csr.mstatus.mie  <= 1'b0;
        csr.mstatus.hie  <= 1'b0;
        csr.mstatus.sie  <= 1'b0;
        csr.mstatus.uie  <= 1'b0;
    end
    else
    begin
        st_flush <= 1'b0;

        //write from ID, Machine Mode
        if ( (ex_csr_we && ex_csr_reg == MSTATUS && st_prv == PRV_M) ||
             (du_we_csr && du_addr    == MSTATUS)                     )
        begin
            csr.mstatus.vm    <= csr_wval[28:24];
            csr.mstatus.mxr   <= csr_wval[19];
            csr.mstatus.pum   <= csr_wval[18];
            csr.mstatus.mprv  <= csr_wval[17];
            csr.mstatus.xs    <= has_ext ? csr_wval[16:15] : 2'b00; //TODO
            csr.mstatus.fs    <= has_fpu ? csr_wval[14:13] : 2'b00; //TODO

            csr.mstatus.mpp   <=         csr_wval[12:11];
            csr.mstatus.hpp   <= has_h ? csr_wval[10:9] : 2'h0;
            csr.mstatus.spp   <= has_s ? csr_wval[   8] : 1'b0;
            csr.mstatus.mpie  <=         csr_wval[   7];
            csr.mstatus.hpie  <= has_h ? csr_wval[   6] : 1'b0;
            csr.mstatus.spie  <= has_s ? csr_wval[   5] : 1'b0;
            csr.mstatus.upie  <= has_n ? csr_wval[   4] : 1'b0;
            csr.mstatus.mie   <=         csr_wval[   3];
            csr.mstatus.hie   <= has_h ? csr_wval[   2] : 1'b0;
            csr.mstatus.sie   <= has_s ? csr_wval[   1] : 1'b0;
            csr.mstatus.uie   <= has_n ? csr_wval[   0] : 1'b0;
        end

        //Supervisor Mode access
        if (has_s)
        begin
            if ( (ex_csr_we && ex_csr_reg == SSTATUS && st_prv >= PRV_S) ||
                 (du_we_csr && du_addr    == SSTATUS)                     )
            begin
                csr.mstatus.pum  <= csr_wval[18]; 
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
        if (!id_bubble && !bu_flush && !du_stall)
        begin
            case (id_instr)
              //pop privilege stack
              MRET : begin
                         //set privilege level
                         st_prv    <= csr.mstatus.mpp;
                         st_nxt_pc <= csr.mepc;
                         st_flush  <= 1'b1;

                         //set yIE
//                         csr.mstatus[csr.mstatus.mpp] <= csr.mstatus.mpie; <<<Quartus 16.1.2 barfs on this construct
                         case (csr.mstatus.hpp)
                           3: csr.mstatus[3] <= csr.mstatus.mpie;
                           2: csr.mstatus[2] <= csr.mstatus.mpie;
                           1: csr.mstatus[1] <= csr.mstatus.mpie;
                           0: csr.mstatus[0] <= csr.mstatus.mpie;
                         endcase

                         csr.mstatus.mpie <= 1'b1;
                         csr.mstatus.mpp  <= has_u ? PRV_U : PRV_M;
                     end
              HRET : begin
                         //set privilege level
                         st_prv    <= csr.mstatus.hpp;
                         st_nxt_pc <= csr.hepc;
                         st_flush  <= 1'b1;

                         //set yIE
//                         csr.mstatus[csr.mstatus.hpp] <= csr.mstatus.hpie; <<<Quartus 16.1.2 barfs on this construct
                         case (csr.mstatus.hpp)
                           3: csr.mstatus[3] <= csr.mstatus.hpie;
                           2: csr.mstatus[2] <= csr.mstatus.hpie;
                           1: csr.mstatus[1] <= csr.mstatus.hpie;
                           0: csr.mstatus[0] <= csr.mstatus.hpie;
                         endcase

                         csr.mstatus.hpie <= 1'b1;
                         csr.mstatus.hpp  <= has_u ? PRV_U : PRV_M;
                     end
              SRET : begin
                         //set privilege level
                         st_prv    <= {1'b0,csr.mstatus.spp};
                         st_nxt_pc <= csr.sepc;
                         st_flush  <= 1'b1;

                         //set yIE
//                         csr.mstatus[csr.mstatus.spp] <= csr.mstatus.spie; <<<Quartus 16.1.2 barfs on this construct
                         case(csr.mstatus.spp)
                            1: csr.mstatus[1] <= csr.mstatus.spie;
                            0: csr.mstatus[0] <= csr.mstatus.spie;
                         endcase

                         csr.mstatus.spie <= 1'b1;
                         csr.mstatus.spp  <= 1'b0; //has_u ? PRV_U : PRV_M; >>>Must have User-mode. SPP is only 1 bit
                     end
              URET : begin
                         //set privilege level
                         st_prv    <= PRV_U;
                         st_nxt_pc <= csr.uepc;
                         st_flush  <= 1'b1;

                         //set yIE
                         csr.mstatus.uie  <= csr.mstatus.upie; //little bit silly ... should always be '1'

                         csr.mstatus.upie <= 1'b1;
                     end
            endcase
        end

        //push privilege stack
        if (ext_nmi)
        begin
$display ("NMI");
            //NMI always at Machine-mode
            st_prv    <= PRV_M;
            st_nxt_pc <= csr.mnmivec;
            st_flush  <= 1'b1;

            //store current state
            csr.mstatus.mpie <= csr.mstatus[st_prv];
            csr.mstatus.mie  <= 1'b0;
            csr.mstatus.mpp  <= st_prv;
        end
        else if (take_interrupt)
        begin
$display ("take_interrupt");
            st_flush  <= ~du_stall & ~du_flush;

            //Check if interrupts are delegated
            if (has_n && st_prv == PRV_U && ( st_int & csr.mideleg & 12'h111) )
            begin
                st_prv    <= PRV_U;
                st_nxt_pc <= csr.utvec;

                csr.mstatus.upie <= csr.mstatus[st_prv];
                csr.mstatus.uie  <= 1'b0;
            end
            else if (has_s && st_prv >= PRV_S && (st_int & csr.mideleg & 12'h333) )
            begin
                st_prv    <= PRV_S;
                st_nxt_pc <= csr.stvec;

                csr.mstatus.spie <= csr.mstatus[st_prv];
                csr.mstatus.sie  <= 1'b0;
                csr.mstatus.spp  <= st_prv[0];
            end
            else if (has_h && st_prv >= PRV_H && (st_int & csr.mideleg & 12'h777) )
            begin
                st_prv    <= PRV_H;
                st_nxt_pc <= csr.htvec;

                csr.mstatus.hpie <= csr.mstatus[st_prv];
                csr.mstatus.hie  <= 1'b0;
                csr.mstatus.hpp  <= st_prv;
            end
            else
            begin
                st_prv    <= PRV_M;
                st_nxt_pc <= csr.mtvec;

                csr.mstatus.mpie <= csr.mstatus[st_prv];
                csr.mstatus.mie  <= 1'b0;
                csr.mstatus.mpp  <= st_prv;
            end
        end
        else if ( |(wb_exception & ~du_ie[15:0]) ) //NOT st_exceptions ... ebreak/ecall handled below
        begin
$display("exception");
            st_flush  <= ~du_stall & ~du_flush;

            if (has_n && st_prv == PRV_U && |(wb_exception & csr.medeleg))
            begin
                st_prv    <= PRV_U;
                st_nxt_pc <= csr.utvec;

                csr.mstatus.upie <= csr.mstatus[st_prv];
                csr.mstatus.uie  <= 1'b0;
            end
            else if (has_s && st_prv >= PRV_S && |(wb_exception & csr.medeleg))
            begin
                st_prv    <= PRV_S;
                st_nxt_pc <= csr.stvec;

                csr.mstatus.spie <= csr.mstatus[st_prv];
                csr.mstatus.sie  <= 1'b0;
                csr.mstatus.spp  <= st_prv[0];

            end
            else if (has_h && st_prv >= PRV_H && |(wb_exception & csr.medeleg))
            begin
                st_prv    <= PRV_H;
                st_nxt_pc <= csr.htvec;

                csr.mstatus.hpie <= csr.mstatus[st_prv];
                csr.mstatus.hie  <= 1'b0;
                csr.mstatus.hpp  <= st_prv;
            end
            else
            begin
                st_prv    <= PRV_M;
                st_nxt_pc <= csr.mtvec;

                csr.mstatus.mpie <= csr.mstatus[st_prv];
                csr.mstatus.mie  <= 1'b0;
                csr.mstatus.mpp  <= st_prv;
            end
        end
        else if (st_exceptions[CAUSE_BREAKPOINT] & ~du_ie[CAUSE_BREAKPOINT])
        begin
$display("BREAKPOINT");
            st_flush  <= ~du_stall & ~du_flush;

            if (has_n && st_prv == PRV_U && csr.medeleg[CAUSE_BREAKPOINT])
            begin
                st_prv    <= PRV_U;
                st_nxt_pc <= csr.utvec;

                csr.mstatus.upie <= csr.mstatus[st_prv];
                csr.mstatus.uie  <= 1'b0;
            end
            else if (has_s && st_prv >= PRV_S && csr.medeleg[CAUSE_BREAKPOINT])
            begin
                st_prv    <= PRV_S;
                st_nxt_pc <= csr.stvec;

                csr.mstatus.spie <= csr.mstatus[st_prv];
                csr.mstatus.sie  <= 1'b0;
                csr.mstatus.spp  <= st_prv[0];

            end
            else if (has_h && st_prv >= PRV_H && csr.medeleg[CAUSE_BREAKPOINT])
            begin
                st_prv    <= PRV_H;
                st_nxt_pc <= csr.htvec;

                csr.mstatus.hpie <= csr.mstatus[st_prv];
                csr.mstatus.hie  <= 1'b0;
                csr.mstatus.hpp  <= st_prv;
            end
            else
            begin
                st_prv    <= PRV_M;
                st_nxt_pc <= csr.mtvec;

                csr.mstatus.mpie <= csr.mstatus[st_prv];
                csr.mstatus.mie  <= 1'b0;
                csr.mstatus.mpp  <= st_prv;
            end
        end
        else if (!id_bubble && id_instr == ECALL && !bu_flush && !du_stall)
        begin
$display("ECALL");
            st_flush  <= 1'b1;

            //ECALL
            if (has_n && st_prv == PRV_U && csr.medeleg[CAUSE_UMODE_ECALL])
            begin
                st_prv    <= PRV_U;
                st_nxt_pc <= csr.utvec;

                csr.mstatus.upie <= csr.mstatus[st_prv];
                csr.mstatus.uie  <= 1'b0;
            end
            else if (has_s && st_prv >= PRV_S && csr.medeleg[CAUSE_SMODE_ECALL])
            begin
                st_prv    <= PRV_S;
                st_nxt_pc <= csr.stvec;

                csr.mstatus.spie <= csr.mstatus[st_prv];
                csr.mstatus.sie  <= 1'b0;
                csr.mstatus.spp  <= st_prv[0];
            end
            else if (has_h && st_prv >= PRV_H && csr.medeleg[CAUSE_HMODE_ECALL])
            begin
                st_prv    <= PRV_H;
                st_nxt_pc <= csr.htvec;

                csr.mstatus.hpie <= csr.mstatus[st_prv];
                csr.mstatus.hie  <= 1'b0;
                csr.mstatus.hpp  <= st_prv;
            end
            else
            begin
                st_prv    <= PRV_M;
                st_nxt_pc <= csr.mtvec;

                csr.mstatus.mpie <= csr.mstatus[st_prv];
                csr.mstatus.mie  <= 1'b0;
                csr.mstatus.mpp  <= st_prv;
            end
        end
    end


  //mnmivec
  always @(posedge clk,negedge rstn)
    if (!rstn)
      csr.mnmivec <= MNMIVEC_DEFAULT;
    else if ( (ex_csr_we && ex_csr_reg == MNMIVEC && st_prv == PRV_M) ||
              (du_we_csr && du_addr    == MNMIVEC)                     )
      csr.mnmivec <= {csr_wval[XLEN-1:2],2'b00};


  //mtvec
  always @(posedge clk,negedge rstn)
    if (!rstn)
      csr.mtvec <= MTVEC_DEFAULT;
    else if ( (ex_csr_we && ex_csr_reg == MTVEC && st_prv == PRV_M) ||
              (du_we_csr && du_addr    == MTVEC)                     )
      csr.mtvec <= {csr_wval[XLEN-1:2],2'b00};


  //medeleg, mideleg
generate
  if (!HAS_HYPER && !HAS_SUPER && !HAS_USER)
  begin
      assign csr.medeleg = 0;
      assign csr.mideleg = 0;
  end
  else
  begin
      //medeleg
      always @(posedge clk,negedge rstn)
        if (!rstn)
          csr.medeleg <= 'h0;
        else if ( (ex_csr_we && ex_csr_reg == MEDELEG && st_prv == PRV_M) ||
                  (du_we_csr && du_addr    == MEDELEG)                     )
          csr.medeleg <= csr_wval & 12'hFFF;

      //mideleg
      always @(posedge clk,negedge rstn)
        if (!rstn)
          csr.mideleg <= 'h0;
        else if ( (ex_csr_we && ex_csr_reg == MIDELEG && st_prv == PRV_M) ||
                  (du_we_csr && du_addr    == MIDELEG)                )
          csr.mideleg <= csr_wval & 12'h777;
        else if (has_h)
        begin
            if ( (ex_csr_we && ex_csr_reg == HIDELEG && st_prv >= PRV_H) ||
                 (du_we_csr && du_addr    == HIDELEG)                )
            begin
                csr.mideleg[SSI] <= has_s & csr_wval[SSI];
                csr.mideleg[USI] <= has_n & csr_wval[USI];
            end
        end
        else if (has_s)
        begin
            if ( (ex_csr_we && ex_csr_reg == SIDELEG && st_prv >= PRV_S) ||
                 (du_we_csr && du_addr    == SIDELEG)                )
            begin
                csr.mideleg[USI] <= has_n & csr_wval[USI];
            end
        end
  end
endgenerate


  /*
   * MIP
   */
  always @(posedge clk,negedge rstn)
    if (!rstn)
      csr.mip <= 'h0;
    else
    begin
        //external interrupts
        csr.mip.meip <= ext_int[PRV_M]; 
        csr.mip.heip <= ext_int[PRV_H] & has_h;
        csr.mip.seip <= ext_int[PRV_S] & has_s;
        csr.mip.ueip <= ext_int[PRV_U] & has_n;
 

        //timer interrupts
        csr.mip.mtip <= ext_tint;
        //may only be written by M-mode
        if ( (ex_csr_we & ex_csr_reg == MIP & st_prv == PRV_M) ||
             (du_we_csr & du_addr    == MIP)                  )
        begin
            csr.mip.htip <= csr_wval[HTI] & has_h;
            csr.mip.stip <= csr_wval[STI] & has_s;
            csr.mip.utip <= csr_wval[UTI] & has_n;
        end


        //software interrupts
        csr.mip.msip <= ext_sint;
        //Machine Mode write
        if ( (ex_csr_we && ex_csr_reg == MIP && st_prv == PRV_M) ||
             (du_we_csr && du_addr    == MIP)                   )
        begin
            csr.mip.hsip <= csr_wval[HSI] & has_h;
            csr.mip.ssip <= csr_wval[SSI] & has_s;
            csr.mip.usip <= csr_wval[USI] & has_n;
        end
        else if (has_h)
        begin
            //Hypervisor Mode write
            if ( (ex_csr_we && ex_csr_reg == HIP && st_prv >= PRV_H) ||
                 (du_we_csr && du_addr    == HIP)                   )
            begin
                csr.mip.hsip <= csr_wval[HSI] & csr.mideleg[HSI];
                csr.mip.ssip <= csr_wval[SSI] & csr.mideleg[SSI] & has_s;
                csr.mip.usip <= csr_wval[USI] & csr.mideleg[USI] & has_n;
            end
        end
        else if (has_s)
        begin
            //Supervisor Mode write
            if ( (ex_csr_we && ex_csr_reg == SIP && st_prv >= PRV_S) ||
                 (du_we_csr && du_addr    == SIP)                   )
            begin
                csr.mip.ssip <= csr_wval[SSI] & csr.mideleg[SSI];
                csr.mip.usip <= csr_wval[USI] & csr.mideleg[USI] & has_n;
            end
        end
        else if (has_n)
        begin
            //User Mode write
            if ( (ex_csr_we && ex_csr_reg == UIP) ||
                 (du_we_csr && du_addr    == UIP)  )
            begin
                csr.mip.usip <= csr_wval[USI] & csr.mideleg[USI];
            end
        end
    end


  /* MIE */
  always @(posedge clk,negedge rstn)
    if (!rstn)
      csr.mie <= 'h0;
    else if ( (ex_csr_we && ex_csr_reg == MIE && st_prv == PRV_M) ||
              (du_we_csr && du_addr    == MIE)                   )
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
    else if (has_h)
    begin
        if ( (ex_csr_we && ex_csr_reg == HIE && st_prv >= PRV_H) ||
             (du_we_csr && du_addr    == HIE)                   )
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
    else if (has_s)
    begin
        if ( (ex_csr_we && ex_csr_reg == SIE && st_prv >= PRV_S) ||
             (du_we_csr && du_addr    == HIE)                   )
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
        if ( (ex_csr_we && ex_csr_reg == UIE) ||
             (du_we_csr && du_addr    == UIE)  )
        begin
            csr.mie.ueie <= csr_wval[UEI];
            csr.mie.utie <= csr_wval[UTI];
            csr.mie.usie <= csr_wval[USI];
        end
    end


  //mscratch
  always @(posedge clk,negedge rstn)
    if      (!rstn)                                                    csr.mscratch <= 'h0;
    else if ( (ex_csr_we && ex_csr_reg == MSCRATCH && st_prv == PRV_M) ||
              (du_we_csr && du_addr    == MSCRATCH)                  ) csr.mscratch <= csr_wval;


  //decode exceptions
  always_comb
  begin
      st_exceptions = 'h0;
      st_exceptions[EXCEPTION_SIZE-1:0] = wb_exception;

      //Breakpoints
      st_exceptions[CAUSE_BREAKPOINT ] = (~id_bubble & id_instr == EBREAK & ~bu_flush & ~du_stall);

      //UMODE, SMODE, HMODE, MMODE
      st_exceptions[CAUSE_UMODE_ECALL] = has_u & st_prv==PRV_U & (~id_bubble & id_instr == ECALL & ~bu_flush & ~du_stall);
      st_exceptions[CAUSE_SMODE_ECALL] = has_s & st_prv==PRV_S & (~id_bubble & id_instr == ECALL & ~bu_flush & ~du_stall);
      st_exceptions[CAUSE_HMODE_ECALL] = has_h & st_prv==PRV_H & (~id_bubble & id_instr == ECALL & ~bu_flush & ~du_stall);
      st_exceptions[CAUSE_MMODE_ECALL] =                         (~id_bubble & id_instr == ECALL & ~bu_flush & ~du_stall);
  end

  always_comb
    casex (st_exceptions & ~du_ie[15:0])
      12'b????_????_???1: trap_cause =  0;
      12'b????_????_??10: trap_cause =  1;
      12'b????_????_?100: trap_cause =  2;
      12'b????_????_1000: trap_cause =  3;
      12'b????_???1_0000: trap_cause =  4;
      12'b????_??10_0000: trap_cause =  5;
      12'b????_?100_0000: trap_cause =  6;
      12'b????_1000_0000: trap_cause =  7;
      12'b???1_0000_0000: trap_cause =  8;
      12'b??10_0000_0000: trap_cause =  9;
      12'b?100_0000_0000: trap_cause = 10;
      12'b1000_0000_0000: trap_cause = 11;
      default           : trap_cause =  0;
    endcase


  //decode interrupts
  //priority external, software, timer
  assign st_int[CAUSE_MEINT] = ( ((st_prv < PRV_M) | (st_prv == PRV_M & csr.mstatus.mie)) & (csr.mip.meip & csr.mie.meie) );
  assign st_int[CAUSE_HEINT] = ( ((st_prv < PRV_H) | (st_prv == PRV_H & csr.mstatus.hie)) & (csr.mip.heip & csr.mie.heie) );
  assign st_int[CAUSE_SEINT] = ( ((st_prv < PRV_S) | (st_prv == PRV_S & csr.mstatus.sie)) & (csr.mip.seip & csr.mie.seie) );
  assign st_int[CAUSE_UEINT] = (                     (st_prv == PRV_U & csr.mstatus.uie)  & (csr.mip.ueip & csr.mie.ueie) );

  assign st_int[CAUSE_MSINT] = ( ((st_prv < PRV_M) | (st_prv == PRV_M & csr.mstatus.mie)) & (csr.mip.msip & csr.mie.msie) ) & ~st_int[CAUSE_MEINT];
  assign st_int[CAUSE_HSINT] = ( ((st_prv < PRV_H) | (st_prv == PRV_H & csr.mstatus.hie)) & (csr.mip.hsip & csr.mie.hsie) ) & ~st_int[CAUSE_HEINT];
  assign st_int[CAUSE_SSINT] = ( ((st_prv < PRV_S) | (st_prv == PRV_S & csr.mstatus.sie)) & (csr.mip.ssip & csr.mie.ssie) ) & ~st_int[CAUSE_SEINT];
  assign st_int[CAUSE_USINT] = (                     (st_prv == PRV_U & csr.mstatus.uie)  & (csr.mip.usip & csr.mie.usie) ) & ~st_int[CAUSE_UEINT];

  assign st_int[CAUSE_MTINT] = ( ((st_prv < PRV_M) | (st_prv == PRV_M & csr.mstatus.mie)) & (csr.mip.mtip & csr.mie.mtie) ) & ~(st_int[CAUSE_MEINT] | st_int[CAUSE_MSINT]);
  assign st_int[CAUSE_HTINT] = ( ((st_prv < PRV_H) | (st_prv == PRV_H & csr.mstatus.hie)) & (csr.mip.htip & csr.mie.htie) ) & ~(st_int[CAUSE_HEINT] | st_int[CAUSE_HSINT]);
  assign st_int[CAUSE_STINT] = ( ((st_prv < PRV_S) | (st_prv == PRV_S & csr.mstatus.sie)) & (csr.mip.stip & csr.mie.stie) ) & ~(st_int[CAUSE_SEINT] | st_int[CAUSE_SSINT]);
  assign st_int[CAUSE_UTINT] = (                     (st_prv == PRV_U & csr.mstatus.uie)  & (csr.mip.utip & csr.mie.utie) ) & ~(st_int[CAUSE_UEINT] | st_int[CAUSE_USINT]);


  //interrupt cause priority
  always_comb
    casex (st_int & ~du_ie[31:16])
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

  assign take_interrupt = |(st_int & ~du_ie[31:16]);


  //for Debug Unit
  assign du_exceptions = { {16-$bits(st_int){1'b0}}, st_int, {16-$bits(st_exceptions){1'b0}}, st_exceptions} & du_ie;


  //Update mepc and mcause
  always @(posedge clk,negedge rstn)
    if (!rstn)
    begin
        st_interrupt <= 'b0;

        csr.mepc     <= 'h0;
        csr.hepc     <= 'h0;
        csr.sepc     <= 'h0;
        csr.uepc     <= 'h0;

        csr.mcause   <= 'h0;
        csr.hcause   <= 'h0;
        csr.scause   <= 'h0;
        csr.ucause   <= 'h0;

        csr.mbadaddr <= 'h0;
        csr.hbadaddr <= 'h0;
        csr.sbadaddr <= 'h0;
        csr.ubadaddr <= 'h0;
    end
    else
    begin
        //Write access to regs (lowest priority)
        if ( (ex_csr_we && ex_csr_reg == MEPC && st_prv == PRV_M) ||
             (du_we_csr && du_addr    == MEPC)                  )
          csr.mepc <= {csr_wval[XLEN-1:2], csr_wval[1] & has_rvc, 1'b0};

        if ( (ex_csr_we && ex_csr_reg == HEPC && st_prv >= PRV_H) ||
             (du_we_csr && du_addr    == HEPC)                  )
          csr.hepc <= {csr_wval[XLEN-1:2], csr_wval[1] & has_rvc, 1'b0};

        if ( (ex_csr_we && ex_csr_reg == SEPC && st_prv >= PRV_S) ||
             (du_we_csr && du_addr    == SEPC)                  )
          csr.sepc <= {csr_wval[XLEN-1:2], csr_wval[1] & has_rvc, 1'b0};

        if ( (ex_csr_we && ex_csr_reg == UEPC && st_prv >= PRV_U) ||
             (du_we_csr && du_addr    == UEPC)                  )
          csr.uepc <= {csr_wval[XLEN-1:2], csr_wval[1] & has_rvc, 1'b0};


        if ( (ex_csr_we && ex_csr_reg == MCAUSE && st_prv == PRV_M) ||
             (du_we_csr && du_addr    == MCAUSE)                  )
          csr.mcause <= csr_wval;

        if ( (ex_csr_we && ex_csr_reg == HCAUSE && st_prv >= PRV_H) ||
             (du_we_csr && du_addr    == HCAUSE)                  )
          csr.hcause <= csr_wval;

        if ( (ex_csr_we && ex_csr_reg == SCAUSE && st_prv >= PRV_S) ||
             (du_we_csr && du_addr    == SCAUSE)                  )
          csr.scause <= csr_wval;

        if ( (ex_csr_we && ex_csr_reg == UCAUSE && st_prv >= PRV_U) ||
             (du_we_csr && du_addr    == UCAUSE)                  )
          csr.ucause <= csr_wval;


        if ( (ex_csr_we && ex_csr_reg == MBADADDR && st_prv == PRV_M) ||
             (du_we_csr && du_addr    == MBADADDR)                  )
          csr.mbadaddr <= csr_wval;

        if ( (ex_csr_we && ex_csr_reg == HBADADDR && st_prv >= PRV_H) ||
             (du_we_csr && du_addr    == HBADADDR)                  )
          csr.hbadaddr <= csr_wval;

        if ( (ex_csr_we && ex_csr_reg == SBADADDR && st_prv >= PRV_S) ||
             (du_we_csr && du_addr    == SBADADDR)                  )
          csr.sbadaddr <= csr_wval;

        if ( (ex_csr_we && ex_csr_reg == UBADADDR && st_prv >= PRV_U) ||
             (du_we_csr && du_addr    == UBADADDR)                  )
          csr.ubadaddr <= csr_wval;


        /*
         * Handle exceptions
         */
        st_interrupt <= 1'b0;

        //priority external interrupts, software interrupts, timer interrupts, traps
        if (ext_nmi) //TODO: doesn't this cause a deadlock? Need to hold of NMI once handled
        begin
            //NMI always at Machine Level
            st_interrupt <= 1'b1;
            csr.mepc     <= bu_flush ? bu_nxt_pc : id_pc;
            csr.mcause   <= (1 << (XLEN-1)) | 'h0; //Implementation dependent. '0' indicates 'unknown cause'
        end
        else if (take_interrupt)
        begin
            st_interrupt <= 1'b1;

            //Check if interrupts are delegated
            if (has_n && st_prv == PRV_U && ( st_int & csr.mideleg & 12'h111) )
            begin
                csr.ucause <= (1 << (XLEN-1)) | interrupt_cause;
                csr.uepc   <= id_pc;
            end
            else if (has_s && st_prv >= PRV_S && (st_int & csr.mideleg & 12'h333) )
            begin
                csr.scause <= (1 << (XLEN-1)) | interrupt_cause;;
                csr.sepc   <= id_pc;
            end
            else if (has_h && st_prv >= PRV_H && (st_int & csr.mideleg & 12'h777) )
            begin
                csr.hcause <= (1 << (XLEN-1)) | interrupt_cause;;
                csr.hepc   <= id_pc;
            end
            else
            begin
                csr.mcause <= (1 << (XLEN-1)) | interrupt_cause;;
                csr.mepc   <= id_pc;
            end
        end
        else if (|(wb_exception & ~du_ie[15:0])) //NOT st_exceptions ... ebreak/ecall handled below
        begin
            //Trap
            if (has_n && st_prv == PRV_U && |(wb_exception & csr.medeleg))
            begin
                csr.uepc   <= wb_pc;
                csr.ucause <= trap_cause;
            end
            else if (has_s && st_prv >= PRV_S && |(wb_exception & csr.medeleg))
            begin
                csr.sepc   <= wb_pc;
                csr.scause <= trap_cause;
                if (wb_exception[CAUSE_MISALIGNED_INSTRUCTION] || wb_exception[CAUSE_INSTRUCTION_ACCESS_FAULT] ||
                                                                  wb_exception[CAUSE_LOAD_ACCESS_FAULT       ] ||
                    wb_exception[CAUSE_MISALIGNED_STORE      ] || wb_exception[CAUSE_STORE_ACCESS_FAULT      ])
                csr.sbadaddr <= wb_badaddr;
            end
            else if (has_h && st_prv >= PRV_H && |(wb_exception & csr.medeleg))
            begin
                csr.hepc   <= wb_pc;
                csr.hcause <= trap_cause;

                if (wb_exception[CAUSE_MISALIGNED_INSTRUCTION] || wb_exception[CAUSE_INSTRUCTION_ACCESS_FAULT] ||
                    wb_exception[CAUSE_MISALIGNED_LOAD       ] || wb_exception[CAUSE_LOAD_ACCESS_FAULT       ] ||
                    wb_exception[CAUSE_MISALIGNED_STORE      ] || wb_exception[CAUSE_STORE_ACCESS_FAULT      ])
                csr.hbadaddr <= wb_badaddr;
            end
            else
            begin
                csr.mepc   <= wb_pc;
                csr.mcause <= trap_cause;

                if (wb_exception[CAUSE_MISALIGNED_INSTRUCTION] || wb_exception[CAUSE_INSTRUCTION_ACCESS_FAULT] ||
                    wb_exception[CAUSE_MISALIGNED_LOAD       ] || wb_exception[CAUSE_LOAD_ACCESS_FAULT       ] ||
                    wb_exception[CAUSE_MISALIGNED_STORE      ] || wb_exception[CAUSE_STORE_ACCESS_FAULT      ])
                csr.mbadaddr <= wb_badaddr;
            end
        end
        else if (st_exceptions[CAUSE_BREAKPOINT] & ~du_ie[CAUSE_BREAKPOINT])
        begin
            //BREAKPOINT
            if (has_n && st_prv == PRV_U && csr.medeleg[CAUSE_BREAKPOINT])
            begin
                csr.uepc     <= id_pc;
                csr.ucause   <= CAUSE_BREAKPOINT;
                csr.ubadaddr <= id_pc; //Should this be the address which triggers an 'access' breakpoint?
            end
            else if (has_s && st_prv >= PRV_S && csr.medeleg[CAUSE_BREAKPOINT])
            begin
                csr.sepc     <= id_pc;
                csr.scause   <= CAUSE_BREAKPOINT;
                csr.sbadaddr <= id_pc;
            end
            else if (has_h && st_prv >= PRV_H && csr.medeleg[CAUSE_BREAKPOINT])
            begin
                csr.hepc     <= id_pc;
                csr.hcause   <= CAUSE_BREAKPOINT;
                csr.hbadaddr <= id_pc;
            end
            else
            begin
                csr.mepc     <= id_pc;
                csr.mcause   <= CAUSE_BREAKPOINT;
                csr.mbadaddr <= id_pc;
            end
        end
        else if (~id_bubble & id_instr == ECALL & ~bu_flush & ~du_stall)
        begin
            //ECALL
            if (has_n && st_prv == PRV_U && csr.medeleg[CAUSE_UMODE_ECALL])
            begin
                csr.uepc   <= id_pc;
                csr.ucause <= trap_cause;
            end
            else if (has_s && st_prv >= PRV_S && csr.medeleg[CAUSE_SMODE_ECALL])
            begin
                csr.sepc   <= id_pc;
                csr.scause <= trap_cause;
            end
            else if (has_h && st_prv >= PRV_H && csr.medeleg[CAUSE_HMODE_ECALL])
            begin
                csr.hepc   <= id_pc;
                csr.hcause <= trap_cause;
            end
            else
            begin
                csr.mepc   <= id_pc;
                csr.mcause <= trap_cause;
            end
        end
     end



  ////////////////////////////////////////////////////////////////
  //Supervisor Registers
  //
generate
  if (HAS_SUPER)
  begin
      //stvec
      always @(posedge clk,negedge rstn)
        if      (!rstn)
          csr.stvec <= STVEC_DEFAULT;
        else if ( (ex_csr_we && ex_csr_reg == STVEC && st_prv >= PRV_S) ||
                  (du_we_csr && du_addr    == STVEC)                     )
          csr.stvec <= {csr_wval[XLEN-1:2],2'b00};

      //sedeleg
      always @(posedge clk,negedge rstn)
        if      (!rstn)
          csr.sedeleg <= 'h0;
        else if ( (ex_csr_we && ex_csr_reg == SEDELEG && st_prv >= PRV_S) ||
                  (du_we_csr && du_addr    == SEDELEG)                     )
          csr.sedeleg <= csr_wval & ((1<<CAUSE_UMODE_ECALL) | (1<<CAUSE_SMODE_ECALL));

      //sscratch
      always @(posedge clk,negedge rstn)
        if      (!rstn)
          csr.sscratch <= 'h0;
        else if ( (ex_csr_we && ex_csr_reg == SSCRATCH && st_prv >= PRV_S) ||
                  (du_we_csr && du_addr    == SSCRATCH)                     )
          csr.sscratch <= csr_wval;

      //sptbr
      always @(posedge clk,negedge rstn)
        if      (!rstn)
          csr.sptbr <= 'h0;
        else if ( (ex_csr_we && ex_csr_reg == SPTBR && st_prv >= PRV_S) ||
                  (du_we_csr && du_addr    == SPTBR)                     )
          csr.sptbr <= ex_csr_wval;
  end
  else //NO SUPERVISOR MODE
  begin
      assign csr.stvec    = 'h0;
      assign csr.sedeleg  = 'h0;
      assign csr.sscratch = 'h0;
      assign csr.sptbr    = 'h0;
  end
endgenerate


  ////////////////////////////////////////////////////////////////
  //User Registers
  //
generate
  //Cycle, Time, Instret are always available (even if no User Mode)
  if (XLEN==32)
  begin
      always @(posedge clk,negedge rstn)
      if (!rstn)
      begin
          csr.cycle    <= 'h0;
          csr.timer    <= 'h0;
          csr.instret  <= 'h0;
      end
      else
      begin
          //timer always counts (Wall time)
          if      ( (ex_csr_we && ex_csr_reg == TIME) ||
                    (du_we_csr && du_addr    == TIME)  )
            csr.timer.l <= csr_wval;
          else if ( (ex_csr_we && ex_csr_reg == TIMEH) ||
                    (du_we_csr && du_addr    == TIMEH)  )
            csr.timer.h <= csr_wval;
          else
            csr.timer   <= csr.timer + 'h1;

          //cycle always counts (thread active time)
          if      ( (ex_csr_we && ex_csr_reg == CYCLE) ||
                    (du_we_csr && du_addr    == CYCLE)  )
            csr.cycle.l <= csr_wval;
          else if ( (ex_csr_we && ex_csr_reg == CYCLEH) ||
                    (du_we_csr && du_addr    == CYCLEH)  )
            csr.cycle.h <= csr_wval;
          else
            csr.cycle <= csr.cycle + 'h1;

          //User Mode instruction retire counter
          if      ( (ex_csr_we && ex_csr_reg == INSTRET) ||
                    (du_we_csr && du_addr    == INSTRET)  )
            csr.instret.l <= csr_wval;
          else if ( (ex_csr_we && ex_csr_reg == INSTRETH) ||
                    (du_we_csr && du_addr    == INSTRETH)  )
            csr.instret.h <= csr_wval;
          else if   (!id_stall && !bu_flush && !du_stall && st_prv == PRV_U)
            csr.instret <= csr.instret + 'h1;
      end
  end
  else //(XLEN > 32)
  begin
      always @(posedge clk,negedge rstn)
      if (!rstn)
      begin
          csr.cycle    <= 'h0;
          csr.timer    <= 'h0;
          csr.instret  <= 'h0;
      end
      else
      begin
          //timer always counts (Wall time)
          if ( (ex_csr_we && ex_csr_reg == TIME) ||
               (du_we_csr && du_addr    == TIME)  )
            csr.timer <= csr_wval;
          else
            csr.timer <= csr.timer + 'h1;

          //cycle always counts (thread active time)
          if ( (ex_csr_we && ex_csr_reg == TIME) ||
               (du_we_csr && du_addr    == TIME)  )
            csr.cycle <= csr_wval;
          else
            csr.cycle <= csr.cycle + 'h1;

          //User Mode instruction retire counter
          if ( (ex_csr_we && ex_csr_reg == INSTRET) ||
               (du_we_csr && du_addr    == INSTRET)  )
            csr.instret <= csr_wval;
          else if (!id_stall && !bu_flush && !du_stall && st_prv == PRV_U)
            csr.instret <= csr.instret + 'h1;
      end
  end


  if (HAS_USER)
  begin
      //utvec
      always @(posedge clk,negedge rstn)
        if      (!rstn)
          csr.utvec <= UTVEC_DEFAULT;
        else if ( (ex_csr_we && ex_csr_reg == UTVEC) ||
                  (du_we_csr && du_addr    == UTVEC)  )
          csr.utvec <= {csr_wval[XLEN-1:2],2'b00};

      //uscratch
      always @(posedge clk,negedge rstn)
        if      (!rstn)
          csr.uscratch <= 'h0;
        else if ( (ex_csr_we && ex_csr_reg == USCRATCH) ||
                  (du_we_csr && du_addr    == USCRATCH)  )
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

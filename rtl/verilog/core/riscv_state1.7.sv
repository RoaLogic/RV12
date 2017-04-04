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
//    (Thread) State (1.7)                                     //
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

module riscv_state #(
  parameter            XLEN           = 32,
  parameter            FLEN           = 64, //floating point data length
  parameter [XLEN-1:0] PC_INIT        = 'h200,
  parameter            INSTR_SIZE     = 32,
  parameter            EXCEPTION_SIZE = 12,

  parameter            HAS_RVC        = 0,
  parameter            HAS_FPU        = 0,
  parameter            HAS_DFPU       = 0,
  parameter            HAS_QFPU       = 0,
  parameter            HAS_MMU        = 0,
  parameter            HAS_MULDIV     = 0,
  parameter            HAS_AMO        = 0,
  parameter            HAS_BM         = 0,
  parameter            HAS_TMEM       = 0,
  parameter            HAS_SIMD       = 0,

  parameter            HAS_USER       = 1,
  parameter            HAS_SUPER      = 1,
  parameter            HAS_HYPER      = 0,

  parameter            VENDORID       = 16'h0001,
  parameter            REVMINOR       = 4'h0,
  parameter            REVMAJOR       = 4'h0,
  parameter            CPUIDMINOR     = 4'h2,
  parameter            CPUIDMAJOR     = 4'h1,

  parameter            HARTID         = 0      //hardware thread-id
)
(
  input                           rstn,
  input                           clk,

  input      [XLEN          -1:0] id_pc,
  input                           id_bubble,
  input      [INSTR_SIZE    -1:0] id_instr,
  input                           id_stall,

  input                           ex_flush,
  input      [XLEN          -1:0] ex_nxt_pc,

  input      [XLEN          -1:0] wb_pc,
  input      [EXCEPTION_SIZE-1:0] wb_exception,
  input      [XLEN          -1:0] wb_badaddr,

  output reg                      st_interrupt,
                                  st_nmi,
  output     [               1:0] st_priv,
  output     [XLEN          -1:0] csr_mtvec,
                                  csr_htvec,
                                  csr_stvec,
                                  csr_mepc,
                                  csr_hepc,
                                  csr_sepc,

  //interrupts
  input                           ext_int,
  input                           ext_nmi,

  //CSR interface
  input      [              11:0] ex_csr_reg,
  input                           ex_csr_we,
  input      [XLEN          -1:0] ex_csr_wval,
  output reg [XLEN          -1:0] st_csr_rval,

  //Debug interface
  input                           du_stall,
                                  du_we_csr,
  input      [XLEN          -1:0] du_dato,   //output from debug unit
  input      [              11:0] du_addr,
  input      [              31:0] du_ie,
  output     [              31:0] du_exceptions,

  //Host interface
  input                           host_csr_req,
  output reg                      host_csr_ack,
  input                           host_csr_we,
  input      [XLEN          -1:0] host_csr_fromhost,
  output     [XLEN          -1:0] host_csr_tohost
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
    //User Floating Point CSRs
    fcsr_struct fcsr;

    //User Counter/Timers
    timer_struct      cycle,   //timer for RDCYCLE
                      timer,   //timer for RDTIME
                      instret; //instruction retire count for RDINSTRET


    //Supervisor Trap Setup
//    sstatus_struct    sstatus;  //status -- Restricted view of MSTATUS
    logic  [XLEN-1:0] stvec;    //trap handler base address
//    logic  [XLEN-1:0] sie;      //interrupt enable reg -- Restricted view/access of MIE
    logic  [    31:0] stimecmp; //Wall-clock timer compare

    //Supervisor Timer
//    timer_struct      stime; //--same as timer

    //Supervisor trap handler
    logic  [XLEN-1:0] sscratch; //scratch register
    logic  [XLEN-1:0] sepc;     //exception program counter
    logic  [XLEN-1:0] scause;   //trap cause
    logic  [XLEN-1:0] sbadaddr; //bad address
//    logic  [XLEN-1:0] sip;      //interrupt pending -- Restricted view/access of MIP

    //Supervisor protection and Translation
    logic  [XLEN-1:0] sptbr;    //Page-table base address
    logic  [XLEN-1:0] sasid;    //Address-space ID

    //Hypervisor Trap Setup
//TBD      hstatus_struct    hstatus;  //status
    logic  [XLEN-1:0] htvec;    //trap handler base address
    logic  [XLEN-1:0] htdeleg;  //trap delegation reg
    logic  [    31:0] htimecmp; //Wall-clock timer compare

    //Hypervisor Timer
    timer_struct      htime;

    //Hypervisor trap handler
    logic  [XLEN-1:0] hscratch; //scratch register
    logic  [XLEN-1:0] hepc;     //exception program counter
    logic  [XLEN-1:0] hcause;   //trap cause
    logic  [XLEN-1:0] hbadaddr; //bad address

    //Hypervisor protection and Translation
    //TBD per spec v1.7
      

    //Machine Information Register
    mcpuid_struct     mcpuid;  //CPU description
    mimpid_struct     mimpid;  //Vendor-ID and version number
    logic  [XLEN-1:0] mhartid; //Hardware Thread ID

    //Machine Trap Setup
    mstatus_struct    mstatus;  //status
    logic  [XLEN-1:0] mtvec;    //trap handler base address
    logic  [XLEN-1:0] mtdeleg;  //Trap delegation reg
    mie_struct        mie;      //interrupt enable reg
    logic  [    31:0] mtimecmp; //Wall-clock timer compare

    //Machine Timer
    timer_struct      mtime;

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
 

    //Berkely Extensions
    logic  [XLEN-1:0] mtohost,
                      mfromhost;
  } csr_struct;
  csr_struct csr;


  logic                      is_rv32,
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
                             has_u,
                             has_s,
                             has_h;

  logic [               1:0] priv;
  logic                      ie;

  logic                      take_trap,
                             take_interrupt,
                             handle_exception,
                             software_interrupt,
                             timer_interrupt,
                             host_interrupt,
                             ext_interrupt;

  logic [              15:0] st_exceptions;
  logic [              15:0] st_interrupts;
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


  assign st_priv    = priv;
  assign csr_mtvec  = csr.mtvec;
  assign csr_htvec  = csr.htvec;
  assign csr_stvec  = csr.stvec;
  assign csr_mepc   = csr.mepc;
  assign csr_hepc   = csr.hepc;
  assign csr_sepc   = csr.sepc;


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
                                  {XLEN-18{1'b0}},
                                  csr.mstatus.mprv,
                                  csr.mstatus.xs,
                                  csr.mstatus.fs,
                                  7'h0,
                                 |csr.mstatus.prv[1].prv,
                                  csr.mstatus.prv[1].ie,
                                  2'h0,
                                  csr.mstatus.prv[0].ie};
      STVEC     : st_csr_rval = csr.stvec;
      SIE       : st_csr_rval = {{XLEN-6{1'b0}},
                                 csr.mie.stie,
                                 3'h0,
                                 csr.mie.ssie,
                                 1'b0};
      STIMECMP  : st_csr_rval = csr.stimecmp;
      STIME     : st_csr_rval = csr.timer[XLEN-1:0];
      STIMEH    : st_csr_rval = is_rv32 ? csr.timer.h : 'h0;
      SSCRATCH  : st_csr_rval = csr.sscratch;
      SEPC      : st_csr_rval = csr.sepc;
      SCAUSE    : st_csr_rval = csr.scause;
      SBADADDR  : st_csr_rval = csr.sbadaddr;
      SIP       : st_csr_rval = {{XLEN-6{1'b0}},
                                 csr.mip.stip,
                                 3'h0,
                                 csr.mip.ssip,
                                 1'b0};
      SPTBR     : st_csr_rval = has_mmu ? csr.sptbr : 'h0;
      SASID     : st_csr_rval = csr.sasid;
      CYCLEW    : st_csr_rval = csr.cycle[XLEN-1:0];
      TIMEW     : st_csr_rval = csr.timer[XLEN-1:0];
      INSTRETW  : st_csr_rval = csr.instret[XLEN-1:0];
      CYCLEHW   : st_csr_rval = is_rv32 ? csr.cycle.h   : 'h0;
      TIMEHW    : st_csr_rval = is_rv32 ? csr.timer.h   : 'h0;
      INSTRETHW : st_csr_rval = is_rv32 ? csr.instret.h : 'h0;

      //Hypervisor
//      HSTATUS   : st_csr_rval = hstatus;
      HTVEC     : st_csr_rval = csr.htvec;
      HTDELEG   : st_csr_rval = csr.htdeleg;
      HTIMECMP  : st_csr_rval = csr.htimecmp;
      HTIME     : st_csr_rval = csr.htime[XLEN-1:0];
      HTIMEH    : st_csr_rval = is_rv32 ? csr.htime.h : 'h0;
      HSCRATCH  : st_csr_rval = csr.hscratch;
      HEPC      : st_csr_rval = csr.hepc;
      HCAUSE    : st_csr_rval = csr.hcause;
      HBADADDR  : st_csr_rval = csr.hbadaddr;
      STIMEW    : st_csr_rval = csr.mtime[XLEN-1:0];
      STIMEHW   : st_csr_rval = is_rv32 ? csr.mtime.h : 'h0;

      //Machine
      MCPUID    : st_csr_rval = {csr.mcpuid.base, {XLEN-$bits(csr.mcpuid){1'b0}}, csr.mcpuid.extensions};
      MIMPID    : st_csr_rval = is_rv32 ? csr.mimpid : { {XLEN-$bits(csr.mimpid){1'b0}}, csr.mimpid };
      MHARTID   : st_csr_rval = csr.mhartid;
      MSTATUS   : st_csr_rval = {csr.mstatus.sd,
                                 {XLEN-$bits(csr.mstatus){1'b0}},
                                 csr.mstatus.vm,
                                 csr.mstatus.mprv,
                                 csr.mstatus.xs,
                                 csr.mstatus.fs,
                                 csr.mstatus.prv};
      MTVEC     : st_csr_rval = csr.mtvec;
      MTDELEG   : st_csr_rval = csr.mtdeleg;
      MIE       : st_csr_rval = {{XLEN-8{1'b0}},
                                 csr.mie.mtie,
                                 csr.mie.htie,
                                 csr.mie.stie,
                                 1'b0,
                                 csr.mie.msie,
                                 csr.mie.hsie,
                                 csr.mie.ssie,
                                 1'b0};
      MTIMECMP  : st_csr_rval = { {XLEN-32{1'b0}},csr.mtimecmp };
      MTIME     : st_csr_rval = csr.mtime[XLEN-1:0];
      MTIMEH    : st_csr_rval = is_rv32 ? csr.mtime.h : 'h0;
      MSCRATCH  : st_csr_rval = csr.mscratch;
      MEPC      : st_csr_rval = csr.mepc;
      MCAUSE    : st_csr_rval = csr.mcause;
      MBADADDR  : st_csr_rval = csr.mbadaddr;
      MIP       : st_csr_rval = {{XLEN-8{1'b0}},
                                 csr.mip.mtip,
                                 csr.mip.htip,
                                 csr.mip.stip,
                                 1'b0,
                                 csr.mip.msip,
                                 csr.mip.hsip,
                                 csr.mip.ssip,
                                 1'b0};
      MBASE     : st_csr_rval = csr.mbase;
      MBOUND    : st_csr_rval = csr.mbound;
      MIBASE    : st_csr_rval = csr.mibase;
      MIBOUND   : st_csr_rval = csr.mibound;
      MDBASE    : st_csr_rval = csr.mdbase;
      MDBOUND   : st_csr_rval = csr.mdbound;
      HTIMEW    : st_csr_rval = csr.htime[XLEN-1:0];
      HTIMEHW   : st_csr_rval = is_rv32 ? csr.htime.h : 'h0;

      //Berkeley
      MTOHOST   : st_csr_rval = csr.mtohost;
      MFROMHOST : st_csr_rval = csr.mfromhost;

      default   : st_csr_rval = 32'h0;
    endcase


  ////////////////////////////////////////////////////////////////
  // Machine registers
  //
  assign csr.mcpuid.base       = is_rv64 ? RV64I : RV32I;
  assign csr.mcpuid.extensions =  '{u: has_u,      //supports user mode
                                    s: has_s,      //supports supervisor mode
                                    h: has_h,      //supports hypervisor mode
                                    t: has_tmem,
                                    p: has_simd,
                                    m: has_muldiv,
                                    l: has_decfpu,
                                    i: csr.mcpuid.base != RV32E,
                                    e: csr.mcpuid.base == RV32E, 
                                    f: has_fpu,
                                    d: has_dfpu,
                                    q: has_qfpu,
                                    c: has_rvc,
                                    b: has_bm,
                                    a: has_amo,
                                    default : 1'b0};

  assign csr.mimpid.source     = VENDORID;
  assign csr.mimpid.revmajor   = REVMAJOR;
  assign csr.mimpid.revminor   = REVMINOR;
  assign csr.mimpid.cpuidmajor = CPUIDMAJOR;
  assign csr.mimpid.cpuidminor = CPUIDMINOR;

  assign csr.mhartid = HARTID;

  //mstatus
  assign csr.mstatus.sd = &csr.mstatus.fs | &csr.mstatus.xs;
  assign csr.mstatus.xs = 2'b00; //no user extensions

  always @(posedge clk,negedge rstn)
    if (!rstn)
    begin
        csr.mstatus.mprv       <= 1'b0;
        csr.mstatus.fs         <= 2'b00;
        csr.mstatus.prv[3].prv <= PRV_U;
        csr.mstatus.prv[3].ie  <= has_h;
        csr.mstatus.prv[2].prv <= PRV_U;
        csr.mstatus.prv[2].ie  <= has_s;
        csr.mstatus.prv[1].prv <= has_u ? PRV_U : PRV_M;
        csr.mstatus.prv[1].ie  <= 'b1;
        csr.mstatus.prv[0].prv <= PRV_M;
        csr.mstatus.prv[0].ie  <= 'b1;
    end
    else
    begin
        //write from ID, Machine Mode
        if ( (ex_csr_we && ex_csr_reg == MSTATUS && priv == PRV_M) ||
             (du_we_csr && du_addr    == MSTATUS)                  )
        begin
            csr.mstatus.vm     <= csr_wval[21:17]; //TODO
            csr.mstatus.mprv   <= csr_wval[26];
            csr.mstatus.fs     <= has_fpu ? 2'b00 : 2'b00; //TODO

            csr.mstatus.prv[3].prv <= has_h ? csr_wval[11:10] : PRV_U;
            csr.mstatus.prv[3].ie  <= has_h ? csr_wval[    9] : 1'b0;
            csr.mstatus.prv[2].prv <= has_s ? csr_wval[ 8: 7] : PRV_U;
            csr.mstatus.prv[2].ie  <= has_s ? csr_wval[    6] : 1'b0;
            csr.mstatus.prv[1].prv <= has_u ? csr_wval[ 5: 4] : PRV_M;
            csr.mstatus.prv[1].ie  <= has_u ? csr_wval[    3] : 1'b1;
            csr.mstatus.prv[0].prv <= has_u ? csr_wval[ 2: 1] : PRV_M;
            csr.mstatus.prv[0].ie  <= has_u ? csr_wval[    0] : 1'b1;
        end

        //Supervisor Mode
        if ( (ex_csr_we && ex_csr_reg == SSTATUS && priv > PRV_U) ||
             (du_we_csr && du_addr    == SSTATUS)                 )
        begin
            csr.mstatus.mprv   <= ex_csr_wval[26];
            csr.mstatus.fs     <= has_fpu ? 2'b00 : 2'b00; //TODO

            csr.mstatus.prv[1].prv <= {1'b0,csr_wval[4]};
            csr.mstatus.prv[1].ie  <=       csr_wval[3];
            csr.mstatus.prv[0].ie  <=       csr_wval[0];
        end

        if (!ex_flush && !du_stall)
          case ({id_bubble, id_instr})
            //pop privilege stack
            {1'b0,ERET} : begin
                              csr.mstatus.prv[3].prv <= PRV_U;
                              csr.mstatus.prv[3].ie  <= has_h;
                              csr.mstatus.prv[2].prv <= has_h ? csr.mstatus.prv[3].prv : PRV_U; 
                              csr.mstatus.prv[2].ie  <= has_h ? csr.mstatus.prv[3].ie  : has_s;
                              csr.mstatus.prv[1].prv <= has_s ? csr.mstatus.prv[2].prv : has_u ? PRV_U : PRV_M; 
                              csr.mstatus.prv[1].ie  <= has_s ? csr.mstatus.prv[2].ie  : 1'b1;
                              csr.mstatus.prv[0].prv <= has_u ? csr.mstatus.prv[1].prv : PRV_M;
                              csr.mstatus.prv[0].ie  <= has_u ? csr.mstatus.prv[1].ie  : 1'b1;
                           end

            //set privilege to Supervisor
            {1'b0,MRTS} : csr.mstatus.prv[0].prv <= PRV_S;

            //set privilege to hypervisor
            {1'b0,MRTH} : csr.mstatus.prv[0].prv <= PRV_H;
          endcase

        //push privilege stack
        if (handle_exception)
        begin
            csr.mstatus.mprv   <= 1'b0;

            csr.mstatus.prv[3].prv <= has_h ? csr.mstatus.prv[2].prv : PRV_U;
            csr.mstatus.prv[3].ie  <= has_h ? csr.mstatus.prv[2].ie  : 1'b0;
            csr.mstatus.prv[2].prv <= has_s ? csr.mstatus.prv[1].prv : PRV_U;
            csr.mstatus.prv[2].ie  <= has_s ? csr.mstatus.prv[1].ie  : 1'b0;
            csr.mstatus.prv[1].prv <= has_u ? csr.mstatus.prv[0].prv : PRV_M;
            csr.mstatus.prv[1].ie  <= has_u ? csr.mstatus.prv[0].ie  : 1'b1;
            csr.mstatus.prv[0].prv <=                                  PRV_M;
            csr.mstatus.prv[0].ie  <= has_u ? 1'b0                   : 1'b1;
         end
    end

  assign priv = csr.mstatus.prv[0].prv;
  assign ie   = csr.mstatus.prv[0].ie;


  //mtvec
  always @(posedge clk,negedge rstn)
    if (!rstn)
      csr.mtvec <= PC_INIT -'h100;
    else if ( (ex_csr_we && ex_csr_reg == MTVEC && priv == PRV_M) ||
              (du_we_csr && du_addr    == MTVEC)                  )
      csr.mtvec <= {csr_wval[XLEN-1:2],2'b00};


  //mtdeleg
generate
  if (!HAS_HYPER && !HAS_SUPER)
     assign csr.mtdeleg = 0;
  else
     assign csr.mtdeleg = 0; //TODO
endgenerate


  //mip, mie
  always @(posedge clk,negedge rstn)
    if (!rstn)
      csr.mip <= 'h0;
    else
    begin
        csr.mip.mtip <= (csr.mip.mtip | csr.mtime.l == csr.mtimecmp) &
                       ~( (ex_csr_we & ex_csr_reg == MTIMECMP & priv == PRV_M) ||
                          (du_we_csr & du_addr    == MTIMECMP)                 );
        csr.mip.htip <= (csr.mip.htip | csr.htime.l == csr.htimecmp) &
                       ~( (ex_csr_we & ex_csr_reg == HTIMECMP   &
                           ( priv == PRV_M |
                             priv == PRV_H  )                    ) ||
                          (du_we_csr & du_addr == HTIMECMP)        ) &
                        has_h;
        csr.mip.stip <= (csr.mip.stip | csr.mtime.l == csr.stimecmp) &
                       ~( (ex_csr_we & ex_csr_reg == STIMECMP   &
                           ( priv == PRV_M |
                             priv == PRV_H |
                             priv == PRV_S  )                    ) ||
                          (du_we_csr & du_addr == STIMECMP)        ) &
                        has_s;

        //Machine Mode write
        if ( (ex_csr_we && ex_csr_reg == MIP && priv == PRV_M) ||
             (du_we_csr && du_addr    == MIP)                  )
        begin
            csr.mip.msip <= csr_wval[MSI];
            csr.mip.hsip <= csr_wval[HSI] & has_h;
            csr.mip.ssip <= csr_wval[SSI] & has_s;
        end

        //Supervisor Mode write
        if ( (ex_csr_we && ex_csr_reg == SIP && priv > PRV_U) ||
             (du_we_csr && du_addr    == SIP)                 )
        begin
            csr.mip.ssip <= csr_wval[SSI];
        end
    end

  always @(posedge clk,negedge rstn)
    if (!rstn)
      csr.mie <= 'h0;
    else if ( (ex_csr_we && ex_csr_reg == MIE && priv == PRV_M) ||
              (du_we_csr && du_addr    == MIE)                  )
    begin
      csr.mie.mtie <= csr_wval[MTI];
      csr.mie.htie <= csr_wval[HTI] & has_h;
      csr.mie.stie <= csr_wval[STI] & has_s;
      csr.mie.msie <= csr_wval[MSI];
      csr.mie.hsie <= csr_wval[HSI] & has_h;
      csr.mie.ssie <= csr_wval[SSI] & has_s;
    end


  //mtime
generate
  if (XLEN==32)
  begin
      always @(posedge clk,negedge rstn)
        if      (!rstn)                                                  csr.mtime   <= 'h0;
        else if ( (ex_csr_we && ex_csr_reg == MTIME  && priv == PRV_M) ||
                  (du_we_csr && du_addr    == MTIME)                   ) csr.mtime.l <= csr_wval;
        else if ( (ex_csr_we && ex_csr_reg == MTIMEH && priv == PRV_M) ||
                  (du_we_csr && du_addr    == MTIMEH)                  ) csr.mtime.h <= csr_wval;
        else                                                             csr.mtime   <= csr.mtime + 'h1;
  end
  else //!RV32
  begin
      always @(posedge clk,negedge rstn)
        if      (!rstn)                                                 csr.mtime <= 'h0;
        else if ( (ex_csr_we && ex_csr_reg == MTIME && priv == PRV_M) ||
                  (du_we_csr && du_addr    == MTIME)                  ) csr.mtime <= csr_wval;
        else                                                            csr.mtime <= csr.mtime + 'h1;
  end
endgenerate


  //mtimecmp
  always @(posedge clk,negedge rstn)
    if      (!rstn)                                                    csr.mtimecmp <= 'h0;
    else if ( (ex_csr_we && ex_csr_reg == MTIMECMP && priv == PRV_M) ||
              (du_we_csr && du_addr    == MTIMECMP)                  ) csr.mtimecmp <= csr_wval[31:0];


  //mscratch
  always @(posedge clk,negedge rstn)
    if      (!rstn)                                                    csr.mscratch <= 'h0;
    else if ( (ex_csr_we && ex_csr_reg == MSCRATCH && priv == PRV_M) ||
              (du_we_csr && du_addr    == MSCRATCH)                  ) csr.mscratch <= csr_wval;



  //decode exceptions
  always_comb
  begin
      st_exceptions = 'h0;
      st_exceptions[EXCEPTION_SIZE-1:0] = wb_exception;

      //Breakpoints
      st_exceptions[CAUSE_BREAKPOINT ] = (~id_bubble & id_instr == EBREAK & ~ex_flush & ~du_stall);

      //UMODE, SMODE, MMODE, ... doesn't really matter. Just pick a bit
      st_exceptions[CAUSE_UMODE_ECALL] = (~id_bubble & id_instr == ECALL & ~ex_flush & ~du_stall);
  end

  always_comb
    casex (st_exceptions & ~du_ie[15:0])
      8'b????_???1: trap_cause =  0;
      8'b????_??10: trap_cause =  1;
      8'b????_?100: trap_cause =  2;
      8'b????_1000: trap_cause =  3;
      8'b???1_0000: trap_cause =  4;
      8'b??10_0000: trap_cause =  5;
      8'b?100_0000: trap_cause =  6;
      8'b1000_0000: trap_cause =  7;
      default     : trap_cause =  0;
    endcase

  assign take_trap = |(st_exceptions & ~du_ie[15:0]); //such that PRIV is set correctly


  //decode interrupts
  assign software_interrupt = ( ((priv < PRV_M) | (priv == PRV_M & ie)) & (csr.mip.msip & csr.mie.msie) ) |
                              ( ((priv < PRV_H) | (priv == PRV_H & ie)) & (csr.mip.hsip & csr.mie.hsie) ) |
                              ( ((priv < PRV_S) | (priv == PRV_S & ie)) & (csr.mip.ssip & csr.mie.ssie) );

  assign timer_interrupt    = ( ((priv < PRV_M) | (priv == PRV_M & ie)) & (csr.mip.mtip & csr.mie.mtie) ) |
                              ( ((priv < PRV_H) | (priv == PRV_H & ie)) & (csr.mip.htip & csr.mie.htie) ) |
                              ( ((priv < PRV_S) | (priv == PRV_S & ie)) & (csr.mip.stip & csr.mie.stie) );

  assign ext_interrupt      = ext_int & ( ((priv < PRV_M) | (priv == PRV_M & ie)) |
                                          ((priv < PRV_H) | (priv == PRV_H & ie)) |
                                          ((priv < PRV_S) | (priv == PRV_S & ie)) );

  assign st_interrupts = { 13'h0, ext_interrupt,timer_interrupt,software_interrupt};
  always_comb
    casex ( st_interrupts & ~du_ie[31:16])
       16'h???1 : interrupt_cause = 0;
       16'h???2 : interrupt_cause = 1;
       16'h???4 : interrupt_cause = 2;
       16'h???8 : interrupt_cause = 3;
       16'h??10 : interrupt_cause = 4;
       16'h??20 : interrupt_cause = 5;
       16'h??40 : interrupt_cause = 6;
       16'h??80 : interrupt_cause = 7;
       16'h?100 : interrupt_cause = 8;
       16'h?200 : interrupt_cause = 9;
       16'h?400 : interrupt_cause =10;
       16'h?800 : interrupt_cause =11;
       16'h1000 : interrupt_cause =12;
       16'h2000 : interrupt_cause =13;
       16'h4000 : interrupt_cause =14;
       16'h8000 : interrupt_cause =15;
       default  : interrupt_cause = 0;
    endcase

  assign take_interrupt = |(st_interrupts & ~du_ie[31:16]);


  //for Debug Unit
  assign du_exceptions = {st_interrupts, { {16-EXCEPTION_SIZE{1'b0}}, st_exceptions }} & du_ie;


  //traps & interrupts
  assign handle_exception = (ext_nmi | take_trap | take_interrupt);

  //store NMI (NMI has highest priority)
  always @(posedge clk) st_nmi <= ext_nmi;

  //Update epc and cause
  always @(posedge clk,negedge rstn)
    if (!rstn)
    begin
        st_interrupt <= 'b0;
        csr.mepc     <= 'h0;
        csr.mcause   <= 'h0;
    end
    else
    begin
        //Write access to regs (lowest priority)
        if ( (ex_csr_we && ex_csr_reg == MEPC && priv == PRV_M) ||
             (du_we_csr && du_addr    == MEPC)                  )
          csr.mepc <= {csr_wval[XLEN-1:2], csr_wval[1] & has_rvc, 1'b0};

        if ( (ex_csr_we && ex_csr_reg == MCAUSE && priv == PRV_M) ||
             (du_we_csr && du_addr    == MCAUSE)                  )
          csr.mcause <= csr_wval;


        //handle exceptions
        st_interrupt <= 1'b0;
        if (|(wb_exception & ~du_ie[15:0])) //NOT st_exceptions ... ebreak/ecall handled below
        begin
            //Trap
            csr.mepc   <= wb_pc;
            csr.mcause <= trap_cause;
        end
        else if (st_exceptions[CAUSE_BREAKPOINT] & ~du_ie[CAUSE_BREAKPOINT]) //breakpoint before interrupt, because interrupts can generate breakpoints
        begin
            csr.mepc   <= id_pc;
            csr.mcause <= CAUSE_BREAKPOINT;
        end
        else if (ext_nmi | take_interrupt)
	begin
	    //external causes
            st_interrupt <= 1'b1;
	    csr.mepc     <= ex_flush ? ex_nxt_pc : id_pc;
	    csr.mcause   <= (1<<(XLEN-1)) | interrupt_cause;
	end
        else
        begin
            //Privileged instructions
            if (st_exceptions[CAUSE_UMODE_ECALL] & ~du_ie[CAUSE_UMODE_ECALL])
            begin
                csr.mepc   <= id_pc;
                csr.mcause <= CAUSE_UMODE_ECALL + priv;
            end
        end
     end


  //mbadaddr
  always @(posedge clk,negedge rstn)
    if      (!rstn        ) csr.mbadaddr <= 'h0;
    else if (|wb_exception) csr.mbadaddr <= wb_badaddr;


  //
  // Berkely Host Interface
  //
  always @(posedge clk,negedge rstn)
    if (!rstn)
    begin
        csr.mtohost   <= 'h0;
        csr.mfromhost <= 'h0;
    end
    else
    begin
        //from host
        if (host_csr_req && !host_csr_we) csr.mtohost   <= 'h0;
        if (host_csr_req &&  host_csr_we) csr.mfromhost <= host_csr_fromhost;

        //from CPU
        if ( (ex_csr_we && ex_csr_reg == MTOHOST && priv == PRV_M) ||
             (du_we_csr && du_addr    == MTOHOST)                  )
          csr.mtohost <= csr_wval;
    end


  //Host Interface
  assign host_csr_tohost = csr.mtohost;

  always @(posedge clk,negedge rstn)
    if (!rstn) host_csr_ack <= 'b0;
    else       host_csr_ack <= host_csr_req & ~host_csr_ack;


  ////////////////////////////////////////////////////////////////
  //Supervisor Registers
  //
generate
  //User Shadow Registers
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
          if      ( (ex_csr_we && ex_csr_reg == TIMEW  && priv > PRV_U) ||
                    (du_we_csr && du_addr    == TIMEW)                  )
            csr.timer.l <= csr_wval;
          else if ( (ex_csr_we && ex_csr_reg == TIMEHW && priv > PRV_U) ||
                    (du_we_csr && du_addr    == TIMEHW)                 )
            csr.timer.h <= csr_wval;
          else
            csr.timer   <= csr.timer + 'h1;

          //cycle always counts (thread active time)
          if      ( (ex_csr_we && ex_csr_reg == CYCLEW  && priv > PRV_U) ||
                    (du_we_csr && du_addr    == CYCLEW)                  )
            csr.cycle.l <= csr_wval;
          else if ( (ex_csr_we && ex_csr_reg == CYCLEHW && priv > PRV_U) ||
                    (du_we_csr && du_addr    == CYCLEHW)                 )
            csr.cycle.h <= csr_wval;
          else
            csr.cycle <= csr.cycle + 'h1;

          //User Mode instruction retire counter
          if      ( (ex_csr_we && ex_csr_reg == INSTRETW  && priv >  PRV_U) ||
                    (du_we_csr && du_addr    == INSTRETW)                   )
            csr.instret.l <= csr_wval;
          else if ( (ex_csr_we && ex_csr_reg == INSTRETHW && priv >  PRV_U) ||
                    (du_we_csr && du_addr    == INSTRETHW)                  )
            csr.instret.h <= csr_wval;
          else if   (!id_stall && !ex_flush && !du_stall && priv == PRV_U)
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
          if ( (ex_csr_we && ex_csr_reg == TIMEW && priv > PRV_U) ||
               (du_we_csr && du_addr    == TIMEW)                 )
            csr.timer <= csr_wval;
          else
            csr.timer <= csr.timer + 'h1;

          //cycle always counts (thread active time)
          if ( (ex_csr_we && ex_csr_reg == TIMEW && priv > PRV_U) ||
               (du_we_csr && du_addr    == TIMEW)                 )
            csr.cycle <= csr_wval;
          else
            csr.cycle <= csr.cycle + 'h1;

          //User Mode instruction retire counter
          if ( (ex_csr_we && ex_csr_reg == INSTRETW && priv > PRV_U) ||
               (du_we_csr && du_addr    == INSTRETW)                 )
            csr.instret <= csr_wval;
          else if (!id_stall && !ex_flush && !du_stall && priv == PRV_U)
            csr.instret <= csr.instret + 'h1;
      end
  end


  if (HAS_SUPER)
  begin
      //stvec
      always @(posedge clk,negedge rstn)
        if      (!rstn)                                                csr.stvec <= PC_INIT -'h100;
        else if ( (ex_csr_we && ex_csr_reg == STVEC && priv > PRV_U) ||
                  (du_we_csr && du_addr    == STVEC)                 ) csr.stvec <= {csr_wval[XLEN-1:2],2'b00};

      //stimecmp
      always @(posedge clk,negedge rstn)
        if      (!rstn)                                                   csr.stimecmp <= 'h0;
        else if ( (ex_csr_we && ex_csr_reg == STIMECMP && priv > PRV_U) ||
                  (du_we_csr && du_addr    == STIMECMP)                 ) csr.stimecmp <= csr_wval[31:0];

      //sscratch
      always @(posedge clk,negedge rstn)
        if      (!rstn)                                                   csr.sscratch <= 'h0;
        else if ( (ex_csr_we && ex_csr_reg == SSCRATCH && priv > PRV_U) ||
                  (du_we_csr && du_addr    == SSCRATCH)                 ) csr.sscratch <= csr_wval;

      //sepc
      always @(posedge clk)
        if      ( (ex_csr_we && ex_csr_reg == SEPC && priv > PRV_U) ||
                  (du_we_csr && du_addr    == SEPC)                 )      csr.sepc <= csr_wval;
        else if (!ex_flush && !du_stall && !id_bubble && id_instr == MRTS) csr.sepc <= csr.mepc;

      //scause
      always @(posedge clk)
        if (!ex_flush && !du_stall && !id_bubble && id_instr == MRTS) csr.scause <= csr.mcause;

      //sbadaddr
      always @(posedge clk)
        if (!ex_flush && !du_stall && !id_bubble && id_instr == MRTS) csr.sbadaddr <= csr.mbadaddr;

      //sptbr
      always @(posedge clk,negedge rstn)
        if      (!rstn)                                                csr.sptbr <= 'h0;
        else if ( (ex_csr_we && ex_csr_reg == SPTBR && priv > PRV_U) ||
                  (du_we_csr && du_addr    == SPTBR)                 ) csr.sptbr <= ex_csr_wval;

      //sasid
      always @(posedge clk,negedge rstn)
        if      (!rstn)                                                csr.sasid <= 'h0;
        else if ( (ex_csr_we && ex_csr_reg == SASID && priv > PRV_U) ||
                  (du_we_csr && du_addr    == SASID)                 ) csr.sasid <= ex_csr_wval;
  end
  else //NO SUPERVISOR MODE
  begin
      assign csr.stvec    = 'h0;
      assign csr.stimecmp = 'h0;
      assign csr.sscratch = 'h0;
      assign csr.sepc     = 'h0;
      assign csr.scause   = 'h0;
      assign csr.sbadaddr = 'h0;
      assign csr.sptbr    = 'h0;
      assign csr.sasid    = 'h0;
  end
endgenerate


  ////////////////////////////////////////////////////////////////
  //User Registers
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
  else
  begin
      assign csr.fcsr    = 'h0;
  end
endgenerate


endmodule 

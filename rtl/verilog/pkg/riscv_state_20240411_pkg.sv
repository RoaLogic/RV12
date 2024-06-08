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
//             Copyright (C) 2018 ROA Logic BV                     //
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

package riscv_state_pkg;
  /*
   *  Per Supervisor Spec 20240411
   *
   */

  //MCPUID mapping
  typedef struct packed {
    logic z,y,x,w,v,u,t,s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a;
  } misa_extensions_struct;

  typedef struct packed {
    logic [ 1:0] mxl;
    misa_extensions_struct extensions;
  } misa_struct;


  typedef struct packed {
    logic [ 7:0] bank;
    logic [ 6:0] offset;
  } mvendorid_struct;


  //MSTATUS mapping
  typedef struct packed {
    logic       sd;

    logic       mbe, sbe;            //m-mode/s-mode endianness
    logic [1:0] sxl, uxl;

    logic       tsr,
                tw,
                tvm,
                mxr,
                sum,
                mprv;                //memory privilege

    logic [1:0] xs;                  //user extension status
    logic [1:0] fs;                  //floating point status

    logic [1:0] mpp;                 //previous privilege levels
    logic [1:0] vs;
    logic       spp;                 //supervisor previous privilege level
    logic       mpie, ube, spie;     //previous interrupt enable bits
    logic       mie, sie;            //interrupt enable bits (per privilege level)
  } mstatus_struct;


  typedef struct packed {
    logic reserved15,
          reserved14,
          lcofip,
          reserved12,
          meip, 
          reserved10,
          seip,
          reserved8,
          mtip,
          reserved6,
          stip,
          reserved4,
          msip,
          reserved2,
          ssip,
          reserved0;
  } mip_t;

  typedef struct packed {
    logic reserved15,
          reserved14,
          lcofie,
          reserved12,
          meie, 
          reserved10,
          seie,
          reserved8,
          mtie,
          reserved6,
          stie,
          reserved4,
          msie,
          reserved2,
          ssie,
          reserved0;
  } mie_t;

  typedef struct packed {
    logic        stce,         //for future Sstc
                 pbmte,        //Svpmbte implemented?
                 adue,         //For Svadu
                 cde;          //Smcdeleg? Delegate Zicntr/Zihpm 
    logic [25:0] reserved59_33;
    logic [ 1:0] pmm;          //for future Smnpm
    logic [23:0] reserved30_8;
    logic        cbze,         //for future Zicboz
                 cbcfe,        //for future Zicbom
                 cbie,         //for future Zicbom
                 fiom;         //Fence of IO implies Memory
  } menvcfg_t;


//PMP-CFG register
  typedef enum logic [1:0] {
    OFF   = 2'd0,
    TOR   = 2'd1,
    NA4   = 2'd2,
    NAPOT = 2'd3
  } pmpcfg_a_t;

  typedef struct packed {
    logic       l;
    logic [1:0] reserved;
    pmpcfg_a_t  a;
    logic       x,
                w,
                r;
  } pmpcfg_t;

  localparam PMPCFG_MASK = 8'h9F;


// Timer
  typedef struct packed {
    logic [31:0] h,l;
  } timer_struct; //mtime, htime, stime


//user FCR mapping
  typedef struct packed {
    logic [2:0] rm;
    logic [4:0] flags;
  } fcsr_struct;


//CSR mapping
//bits[11:10] indicate rw 00/01/10=read/write, 11=read-only
//bits[ 9: 8] indicate lowest privileged level
localparam[11:0] //User
	   //User Floating-Point CSRs
	   FFLAGS        = 'h001,
	   FRM           = 'h002,
	   FCSR          = 'h003,
	   //User Counters/Timers
	   CYCLE         = 'hC00,
	   TIME          = 'hC01,
	   INSTRET       = 'hC02,
	   HPMCOUNTER3   = 'hC03, //until HPMCOUNTER31='hC1F
	   CYCLEH        = 'hC80,
	   TIMEH         = 'hC81,
	   INSTRETH      = 'hC82,
	   HPMCOUNTER3H  = 'hC83, //until HPMCONTER31='hC9F

	   //Supervisor
	   //Supervisor Trap Setup
	   SSTATUS       = 'h100,
	   SIE           = 'h104,
	   STVEC         = 'h105,
	   SCOUNTEREN    = 'h106,
	   //Supervisor Configuration
	   SENVCFG       = 'h10A,
	   //Supervisor Counter Setup
	   SCOUNTINHIBIT = 'h120,
	   //Supervisor Trap Handling
	   SSCRATCH      = 'h140,
	   SEPC          = 'h141,
	   SCAUSE        = 'h142,
	   STVAL         = 'h143,
	   SIP           = 'h144,
	   SCOUNTOVF     = 'hDA0,
	   //Supervisor Protection and Translation
	   SATP          = 'h180,
	   //Debug/Trace
	   SCONTEXT      = 'h5A8,
	   //Supervisor State Enable Registers
	   SSTATEEN0     = 'h10C,
	   SSTATEEN1     = 'h10D,
	   SSTATEEN2     = 'h10E,
	   SSTATEEN3     = 'h10F,

	   //Hypervisor
	   //Hypervisor Trap Setup
	   HSTATUS       = 'h600,
	   HEDELEG       = 'h602,
	   HIDELEG       = 'h603,
	   HIE           = 'h604,
	   HCOUNTEREN    = 'h606,
	   HGEIE         = 'h607,
	   HEDELEGH      = 'h612,
	   //Hypervisor Trap Handling
	   HTVAL         = 'h643,
	   HIP           = 'h644,
	   HVIP          = 'h645,
	   HTINST        = 'h64A,
	   HGEIP         = 'hE12,
	   //Hypervisor Configuration
	   HENVCFG       = 'h60A,
	   HENVCFGH      = 'h61A,
	   //Hypervisor Protection and Translation
	   HGATP         = 'h680,
	   //Debug/Trace
	   HCONTEXT      = 'h6A8,
	   //Hypervisor Counter/Timer Virtualisation Registers
	   HTIMEDELTA    = 'h605,
	   HTIMEDELTAH   = 'h615,
	   //Hypervisor State Enable Registers
	   HSTATEEN0     = 'h60C,
	   HSTATEEN1     = 'h60D,
	   HSTATEEN2     = 'h60E,
	   HSTATEEN3     = 'h60F,
	   HSTATEEN0H    = 'h61C,
	   HSTATEEN1H    = 'h61D,
	   HSTATEEN2H    = 'h61E,
	   HSTATEEN3H    = 'h61F,
	   //Virtual Supervisor Registers
	   VSSTATUS      = 'h200,
	   VSIE          = 'h204,
	   VSTVEC        = 'h205,
	   VSSCRATCH     = 'h240,
	   VSEPC         = 'h241,
	   VSCAUSE       = 'h242,
	   VSTVAL        = 'h243,
	   VSIP          = 'h244,
	   VSATP         = 'h280,

	   //Machine
	   //Machine Information
	   MVENDORID     = 'hF11,
	   MARCHID       = 'hF12,
	   MIMPID        = 'hF13,
	   MHARTID       = 'hF14,
	   MCONFIGPTR    = 'hF15,
	   //Machine Trap Setup
	   MSTATUS       = 'h300,
	   MISA          = 'h301,
	   MEDELEG       = 'h302,
	   MIDELEG       = 'h303,
	   MIE           = 'h304,
	   MNMIVEC       = 'h7C0, //ROALOGIC NMI Vector
	   MTVEC         = 'h305,
	   MCOUNTEREN    = 'h306,
	   MSTATUSH      = 'h310, //RV32 only
	   MEDELEGH      = 'h312, //RV32 only
	   //Machine Trap Handling
	   MSCRATCH      = 'h340,
	   MEPC          = 'h341,
	   MCAUSE        = 'h342,
	   MTVAL         = 'h343,
	   MIP           = 'h344,
	   MTINST        = 'h34A,
	   MTVAL2        = 'h34B,
	   //Machine configuration
	   MENVCFG       = 'h30A,
	   MENVCFGH      = 'h31A, //RV32 only
	   MSECCFG       = 'h747,
	   MSECCFGH      = 'h757, //RV32 only
	   //Machine Protection
	   PMPCFG0       = 'h3A0,
	   PMPCFG1       = 'h3A1, //RV32 only
	   PMPCFG2       = 'h3A2,
	   PMPCFG3       = 'h3A3, //RV32 only
	   PMPCFG4       = 'h3A4,
	   PMPCFG5       = 'h3A5,
	   PMPCFG6       = 'h3A6,
	   PMPCFG7       = 'h3A7,
	   PMPCFG8       = 'h3A8,
	   PMPCFG9       = 'h3A9,
	   PMPCFG10      = 'h3AA,
	   PMPCFG11      = 'h3AB,
	   PMPCFG12      = 'h3AC,
	   PMPCFG13      = 'h3AD,
	   PMPCFG14      = 'h3AE,
	   PMPCFG15      = 'h3AF,
	   PMPADDR0      = 'h3B0,
	   PMPADDR1      = 'h3B1,
	   PMPADDR2      = 'h3B2,
	   PMPADDR3      = 'h3B3,
	   PMPADDR4      = 'h3B4,
	   PMPADDR5      = 'h3B5,
	   PMPADDR6      = 'h3B6,
	   PMPADDR7      = 'h3B7,
	   PMPADDR8      = 'h3B8,
	   PMPADDR9      = 'h3B9,
	   PMPADDR10     = 'h3BA,
	   PMPADDR11     = 'h3BB,
	   PMPADDR12     = 'h3BC,
	   PMPADDR13     = 'h3BD,
	   PMPADDR14     = 'h3BE,
	   PMPADDR15     = 'h3BF, //until pmpaddr63
	   //Machine State Enable Registers
	   MSTATEEN0     = 'h30C,
	   MSTATEEN1     = 'h30D,
	   MSTATEEN2     = 'h30E,
	   MSTATEEN3     = 'h30F,
	   MSTATEEN0H    = 'h31C,
	   MSTATEEN1H    = 'h31D,
	   MSTATEEN2H    = 'h31E,
	   MSTATEEN3H    = 'h31F,
	   //Machine Non-Maskable Interrupt Handling
	   MNSCRATCH     = 'h740,
	   MNEPC         = 'h741,
	   MNCAUSE       = 'h742,
	   MNSTATUS      = 'h744,
	   //Machine Counters/Timers
	   MCYCLE        = 'hB00,
	   MINSTRET      = 'hB02,
	   MHPMCOUNTER3  = 'hB03, //until MHPMCOUNTER31='hB1F
	   MCYCLEH       = 'hB80,
	   MINSTRETH     = 'hB82,
	   MHPMCOUNTER3H = 'hB83, //until MHPMCOUNTER31H='hB9F
	   //Machine Counter Setup
	   MCOUNTINHIBIT = 'h320,
	   MHPMEVENT3    = 'h323,   //until MHPMEVENT31 = 'h33f

	   //Debug/Trace
	   TSELECT       = 'h7A0,
	   TDATA1        = 'h7A1,
	   TDATA2        = 'h7A2,
	   TDATA3        = 'h7A3,
	   MCONTEXT      = 'h7AB,
	   //Debug Mode Register
	   DCSR          = 'h7B0,
	   DPC           = 'h7B1,
	   DSCRATCH0     = 'h7B2,
	   DSCRATCH1     = 'h7B3;


  //MXL mapping
  localparam [1:0] RV32I  = 2'b01,
                   RV32E  = 2'b01,
                   RV64I  = 2'b10,
                   RV128I = 2'b11;


  //Privilege levels
  localparam [1:0] PRV_M = 2'b11,
                   PRV_H = 2'b10,
                   PRV_S = 2'b01,
                   PRV_U = 2'b00;

  //Virtualisation
  localparam [3:0] VM_MBARE = 4'd0,
                   VM_SV32  = 4'd1,
                   VM_SV39  = 4'd8,
                   VM_SV48  = 4'd9,
                   VM_SV57  = 4'd10,
                   VM_SV64  = 4'd11;

  //MIE MIP
  localparam CNT_OVF = 13,
             MEI     = 11,
             SEI     = 9,
             MTI     = 7,
             STI     = 5,
             MSI     = 3,
             SSI     = 1;

  //Performance counters
  localparam CY = 0,
             TM = 1,
             IR = 2;




  //Interrupts and Exceptions
  typedef struct packed {
  logic [1:0] external,
              timer,
              software;
  } interrupts_t;

typedef struct packed {
  logic hardware_error,                //19 (corrupted/uncorrectable data)
        software_check,                //18
        reserved17,                    //17
        reserved16,                    //16
        store_page_fault,              //15
        res14,                         //14
        load_page_fault,               //13
        instruction_page_fault,        //12
        mmode_ecall,                   //11
        reserved10,                    //10
        smode_ecall,                   //9
        umode_ecall,                   //8
        store_access_fault,            //7
        misaligned_store,              //6
        load_access_fault,             //5
        misaligned_load,               //4
        breakpoint,                    //3
        illegal_instruction,           //2
        instruction_access_fault,      //1
        misaligned_instruction;        //0
  } exceptions_t;

  typedef struct packed {
    logic any;                 //OR of all interrupts and exceptions
    logic nmi;                 //Non-Maskable interrupt
    interrupts_t interrupts;   //Interrupts
    exceptions_t exceptions;   //Exceptions
  } interrupts_exceptions_t;


  //State towards core
  typedef struct packed {
    interrupts_t interrupts;
    logic [1:0]  prv;        //Privilege level
    logic [1:0]  xlen;       //Active Architecture
    logic        be;         //Big/little Endian
    logic        tvm,        //trap on satp access or SFENCE.VMA
                 tw,         //trap on WFI (after time >=0)
                 tsr;   
  } state_t;


  localparam       EXCEPTION_SIZE                 = $bits(exceptions_t);

  localparam       CAUSE_MISALIGNED_INSTRUCTION   = 0,
                   CAUSE_INSTRUCTION_ACCESS_FAULT = 1,
                   CAUSE_ILLEGAL_INSTRUCTION      = 2,
                   CAUSE_BREAKPOINT               = 3,
                   CAUSE_MISALIGNED_LOAD          = 4,
                   CAUSE_LOAD_ACCESS_FAULT        = 5,
                   CAUSE_MISALIGNED_STORE         = 6,
                   CAUSE_STORE_ACCESS_FAULT       = 7,
                   CAUSE_UMODE_ECALL              = 8,
                   CAUSE_SMODE_ECALL              = 9,
                   CAUSE_MMODE_ECALL              = 11,
                   CAUSE_INSTRUCTION_PAGE_FAULT   = 12,
                   CAUSE_LOAD_PAGE_FAULT          = 13,
                   CAUSE_STORE_PAGE_FAULT         = 15,
                   CAUSE_SOFTWARE_CHECK           = 18,
                   CAUSE_HARDWARE_ERROR           = 19;

  localparam       CAUSE_SSINT                    = 1,
                   CAUSE_MSINT                    = 3,
                   CAUSE_STINT                    = 5,
                   CAUSE_MTINT                    = 7,
                   CAUSE_SEINT                    = 9,
                   CAUSE_MEINT                    = 11,
                   CAUSE_COUNTER_OVERFLOW         = 13;
endpackage


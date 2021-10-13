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
   *  Per Supervisor Spec draft 1.10
   *
   */

  //MCPUID mapping
  typedef struct packed {
    logic z,y,x,w,v,u,t,s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a;
  } misa_extensions_struct;

  typedef struct packed {
    logic [ 1:0] base;
    misa_extensions_struct extensions;
  } misa_struct;


  typedef struct packed {
    logic [ 7:0] bank;
    logic [ 6:0] offset;
  } mvendorid_struct;


  //MSTATUS mapping
  typedef struct packed {
    logic       sd;
    logic [1:0] sxl,                 //S-Mode XLEN
                uxl;                 //U-Mode XLEN
//    logic [4:0] vm;                  //virtualisation management
    logic       tsr,
                tw,
                tvm,
                mxr,
                sum,
                mprv;                //memory privilege

    logic [1:0] xs;                  //user extension status
    logic [1:0] fs;                  //floating point status

    logic [1:0] mpp, hpp;            //previous privilege levels
    logic       spp;                 //supervisor previous privilege level
    logic       mpie,hpie,spie,upie; //previous interrupt enable bits
    logic       mie, hie, sie, uie;  //interrupt enable bits (per privilege level)
  } mstatus_struct;


  typedef struct packed {
    logic meip, heip, seip, ueip, mtip, htip, stip, utip, msip, hsip, ssip,usip;
  } mip_struct;

  typedef struct packed {
    logic meie, heie, seie, ueie, mtie, htie, stie, utie, msie, hsie, ssie, usie;
  } mie_struct;


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


  //State towards core
  typedef struct packed {
    logic       interrupt;
    logic [1:0] prv;        //Privilege level
    logic [1:0] xlen;       //Active Architecture
    logic       tvm,        //trap on satp access or SFENCE.VMA
                two,        //trap on WFI (after time >=0)
                tsr;   
  } state_t;

  
  //CSR mapping
  parameter [11:0] //User
                   //User Trap Setup
                   USTATUS       = 'h000,
                   UIE           = 'h004,
                   UTVEC         = 'h005,
                   //User Trap Handling
                   USCRATCH      = 'h040,
                   UEPC          = 'h041,
                   UCAUSE        = 'h042,
//                   UBADADDR      = 'h043,
                   UTVAL         = 'h043,
                   UIP           = 'h044,
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
                   SEDELEG       = 'h102,
                   SIDELEG       = 'h103,
                   SIE           = 'h104,
                   STVEC         = 'h105,
                   SCOUNTEREN    = 'h106,
                   //Supervisor Trap Handling
                   SSCRATCH      = 'h140,
                   SEPC          = 'h141,
                   SCAUSE        = 'h142,
                   STVAL         = 'h143,
                   SIP           = 'h144,
                   //Supervisor Protection and Translation
                   SATP          = 'h180,
/*
                   //Hypervisor
                   //Hypervisor trap setup
                   HSTATUS       = 'h200,
                   HEDELEG       = 'h202,
                   HIDELEG       = 'h203,
                   HIE           = 'h204,
                   HTVEC         = 'h205,
                   //Hypervisor Trap Handling
                   HSCRATCH      = 'h240,
                   HEPC          = 'h241,
                   HCAUSE        = 'h242,
                   HTVAL         = 'h243,
                   HIP           = 'h244,
*/

                   //Machine
                   //Machine Information
                   MVENDORID     = 'hF11,
                   MARCHID       = 'hF12,
                   MIMPID        = 'hF13,
                   MHARTID       = 'hF14,
                   //Machine Trap Setup
                   MSTATUS       = 'h300,
                   MISA          = 'h301,
                   MEDELEG       = 'h302,
                   MIDELEG       = 'h303,
                   MIE           = 'h304,
                   MNMIVEC       = 'h7C0, //ROALOGIC NMI Vector
                   MTVEC         = 'h305,
                   MCOUNTEREN    = 'h306,
                   //Machine Trap Handling
                   MSCRATCH      = 'h340,
                   MEPC          = 'h341,
                   MCAUSE        = 'h342,
                   MTVAL         = 'h343,
                   MIP           = 'h344,
                   //Machine Protection and Translation
                   PMPCFG0       = 'h3A0,
                   PMPCFG1       = 'h3A1, //RV32 only
                   PMPCFG2       = 'h3A2,
                   PMPCFG3       = 'h3A3, //RV32 only
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
                   PMPADDR15     = 'h3BF,

                   //Machine Counters/Timers
                   MCYCLE        = 'hB00,
                   MINSTRET      = 'hB02,
                   MHPMCOUNTER3  = 'hB03, //until MHPMCOUNTER31='hB1F
                   MCYCLEH       = 'hB80,
                   MINSTRETH     = 'hB82,
                   MHPMCOUNTER3H = 'hB83, //until MHPMCOUNTER31H='hB9F
                   //Machine Counter Setup
                   MHPEVENT3     = 'h323,   //until MHPEVENT31 = 'h33f

                   //Debug
                   TSELECT       = 'h7A0,
                   TDATA1        = 'h7A1,
                   TDATA2        = 'h7A2,
                   TDATA3        = 'h7A3,
                   DCSR          = 'h7B0,
                   DPC           = 'h7B1,
                   DSCRATCH      = 'h7B2;

  //MXL mapping
  parameter [ 1:0] RV32I  = 2'b01,
                   RV32E  = 2'b01,
                   RV64I  = 2'b10,
                   RV128I = 2'b11;


  //Privilege levels
  parameter [ 1:0] PRV_M = 2'b11,
                   PRV_H = 2'b10,
                   PRV_S = 2'b01,
                   PRV_U = 2'b00;

  //Virtualisation
  parameter [ 3:0] VM_MBARE = 4'd0,
                   VM_SV32  = 4'd1,
                   VM_SV39  = 4'd8,
                   VM_SV48  = 4'd9,
                   VM_SV57  = 4'd10,
                   VM_SV64  = 4'd11;

  //MIE MIP
  parameter        MEI = 11,
                   HEI = 10,
                   SEI = 9,
                   UEI = 8,
                   MTI = 7,
                   HTI = 6,
                   STI = 5,
                   UTI = 4,
                   MSI = 3,
                   HSI = 2,
                   SSI = 1,
                   USI = 0;

  //Performance counters
  parameter        CY = 0,
                   TM = 1,
                   IR = 2;




  //Exceptions
  typedef struct packed {
    logic any;                           //OR of all exception causes

    logic store_page_fault,              //15
          res14,                         //14
	  load_page_fault,               //13
	  instruction_page_fault,        //12
	  mmode_ecall,                   //11
	  hmode_ecall,                   //10
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

  parameter        EXCEPTION_SIZE                 = 16;

  parameter        CAUSE_MISALIGNED_INSTRUCTION   = 0,
                   CAUSE_INSTRUCTION_ACCESS_FAULT = 1,
                   CAUSE_ILLEGAL_INSTRUCTION      = 2,
                   CAUSE_BREAKPOINT               = 3,
                   CAUSE_MISALIGNED_LOAD          = 4,
                   CAUSE_LOAD_ACCESS_FAULT        = 5,
                   CAUSE_MISALIGNED_STORE         = 6,
                   CAUSE_STORE_ACCESS_FAULT       = 7,
                   CAUSE_UMODE_ECALL              = 8,
                   CAUSE_SMODE_ECALL              = 9,
                   CAUSE_HMODE_ECALL              = 10,
                   CAUSE_MMODE_ECALL              = 11,
                   CAUSE_INSTRUCTION_PAGE_FAULT   = 12,
                   CAUSE_LOAD_PAGE_FAULT          = 13,
                   CAUSE_STORE_PAGE_FAULT         = 15;

  parameter        CAUSE_USINT                    = 0,
                   CAUSE_SSINT                    = 1,
                   CAUSE_HSINT                    = 2,
                   CAUSE_MSINT                    = 3,
                   CAUSE_UTINT                    = 4,
                   CAUSE_STINT                    = 5,
                   CAUSE_HTINT                    = 6,
                   CAUSE_MTINT                    = 7,
                   CAUSE_UEINT                    = 8,
                   CAUSE_SEINT                    = 9,
                   CAUSE_HEINT                    = 10,
                   CAUSE_MEINT                    = 11;
endpackage


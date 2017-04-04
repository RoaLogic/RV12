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
//    CPU State Definitions Package                            //
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

package riscv_state_pkg;
  /*
   *  Per Supervisor Spec draft 1.9
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

  //Base mapping
  parameter [ 1:0] RV32I  = 2'b01,
                   RV32E  = 2'b01,
                   RV64I  = 2'b10,
                   RV128I = 2'b11;


  //MSTATUS mapping
  typedef struct packed {
    logic       sd;
    logic [4:0] vm;                  //virtualisation management
    logic       mxr,
                pum,
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


  typedef struct packed {
    logic [31:0] h,l;
  } timer_struct; //mtime, htime, stime


  //user FCR mapping
  typedef struct packed {
    logic [2:0] rm;
    logic [4:0] flags;
  } fcsr_struct;




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
                   UBADADDR      = 'h043,
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
                   //Supervisor Trap Handling
                   SSCRATCH      = 'h140,
                   SEPC          = 'h141,
                   SCAUSE        = 'h142,
                   SBADADDR      = 'h143,
                   SIP           = 'h144,
                   //Supervisor Protection and Translation
                   SPTBR         = 'h180,

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
                   HBADADDR      = 'h243,
                   HIP           = 'h244,

                   //Machine
                   //Machine Information
                   MVENDORID     = 'hF11, //NEW
                   MARCHID       = 'hF12, //NEW
                   MIMPID        = 'hF13,
                   MHARTID       = 'hF14,
                   //Machine Trap Setup
                   MSTATUS       = 'h300,
                   MISA          = 'h301, //NEW
                   MEDELEG       = 'h302, //NEW
                   MIDELEG       = 'h303, //NEW
                   MIE           = 'h304,
                   MNMIVEC       = 'h7C0, //ROALOGIC NMI Vector
                   MTVEC         = 'h305,
                   //Machine Trap Handling
                   MSCRATCH      = 'h340,
                   MEPC          = 'h341,
                   MCAUSE        = 'h342,
                   MBADADDR      = 'h343,
                   MIP           = 'h344,
                   //Machine Protection and Translation
                   MBASE         = 'h380,
                   MBOUND        = 'h381,
                   MIBASE        = 'h382,
                   MIBOUND       = 'h383,
                   MDBASE        = 'h384,
                   MDBOUND       = 'h385,
                   //Machine Counters/Timers
                   MCYCLE        = 'hB00,
                   MINSTRET      = 'hB02,
                   MHPMCOUNTER3  = 'hB03, //until MHPMCOUNTER31='hB1F
                   MCYCLEH       = 'hB80,
                   MINSTRETH     = 'hB82,
                   MHPMCOUNTER3H = 'hB83, //until MHPMCOUNTER31H='hB9F
                   //Machine Counter Setup
                   MUCOUNTEREN   = 'h320,
                   MSCOUNTEREN   = 'h321,
                   MHCOUNTEREN   = 'h322,
                   MHPEVENT3     = 'h323;   //until MHPEVENT31 = 'h33f
                   //Debug


  //Privilege levels
  parameter [ 1:0] PRV_M = 2'b11,
                   PRV_H = 2'b10,
                   PRV_S = 2'b01,
                   PRV_U = 2'b00;

  //Virtualisation
  parameter [ 4:0] VM_MBARE = 5'd0,
                   VM_MBB   = 5'd1,
                   VM_MBBID = 5'd2,
                   VM_SV32  = 5'd8,
                   VM_SV39  = 5'd9,
                   VM_SV48  = 5'd10,
                   VM_SV57  = 5'd11,
                   VM_SV64  = 5'd12;

  //MIE MIP
  parameter        MEI  = 11,
                   HEI  = 10,
                   SEI  = 9,
                   UEI  = 8,
                   MTI  = 7,
                   HTI  = 6,
                   STI  = 5,
                   UTI  = 4,
                   MSI  = 3,
                   HSI  = 2,
                   SSI  = 1,
                   USI  = 0;


  //Exception causes
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
                   CAUSE_MMODE_ECALL              = 11;

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


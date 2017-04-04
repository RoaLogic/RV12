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
   *  Per Supervisor Spec draft 1.7
   *
   * 1.7a:
   * - moved MTIMEH    to 0x781
   * - moved MTOHOST   to 0x7c0
   * - moved MFROMHOST to 0x7c1
   */



  //MCPUID mapping
  typedef struct packed {
    logic z,y,x,w,v,u,t,s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a;
  } mcpuid_extensions_struct;

  typedef struct packed {
    logic [ 1:0] base;
    mcpuid_extensions_struct extensions;
  } mcpuid_struct;

  //Base mapping
  parameter [ 1:0] RV32I  = 2'b00,
                   RV32E  = 2'b01,
                   RV64I  = 2'b10,
                   RV128I = 2'b11;


  //MIMPID mapping
  typedef struct packed {
    logic [ 3:0] cpuidmajor;
    logic [ 3:0] cpuidminor;
    logic [ 3:0] revmajor;
    logic [ 3:0] revminor;
    logic [15:0] source;
  } mimpid_struct;


  //MSTATUS mapping
  typedef struct packed {
    logic [1:0] prv;
    logic       ie;
  } prv_stack_struct;

  typedef struct packed {
    logic       sd;
    logic [4:0] vm;       //virtualisation management
    logic       mprv;     //memory privilege
    logic [1:0] xs;       //user extension status
    logic [1:0] fs;       //floating point status
    prv_stack_struct [3:0] prv;
  } mstatus_struct;

  typedef struct packed {
    logic mtip, htip, stip, msip, hsip, ssip;
  } mip_struct;
  typedef struct packed {
    logic mtie, htie, stie, msie, hsie, ssie;
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
                   FFLAGS    = 'h  1,
                   FRM       = 'h  2,
                   FCSR      = 'h  3,
                   CYCLE     = 'hC00,
                   TIME      = 'hC01,
                   INSTRET   = 'hC02,
                   CYCLEH    = 'hC80,
                   TIMEH     = 'hC81,
                   INSTRETH  = 'hC82,
                   //Supervisor
                   SSTATUS   = 'h100,
                   STVEC     = 'h101,
                   SIE       = 'h104,
                   STIMECMP  = 'h121,
                   STIME     = 'hD01,
                   STIMEH    = 'hD81,
                   SSCRATCH  = 'h140,
                   SEPC      = 'h141,
                   SCAUSE    = 'hD42,
                   SBADADDR  = 'hD43,
                   SIP       = 'h144,
                   SPTBR     = 'h180,
                   SASID     = 'h181,
                   CYCLEW    = 'h900,
                   TIMEW     = 'h901,
                   INSTRETW  = 'h902,
                   CYCLEHW   = 'h980,
                   TIMEHW    = 'h981,
                   INSTRETHW = 'h982,
                   //Hypervisor
                   HSTATUS   = 'h200,
                   HTVEC     = 'h201,
                   HTDELEG   = 'h202,
                   HTIMECMP  = 'h221,
                   HTIME     = 'hE01,
                   HTIMEH    = 'hE81,
                   HSCRATCH  = 'h240,
                   HEPC      = 'h241,
                   HCAUSE    = 'h242,
                   HBADADDR  = 'h243,
                   STIMEW    = 'hA01,
                   STIMEHW   = 'hA81,
                   //Machine
                   MCPUID    = 'hF00,
                   MIMPID    = 'hF01,
                   MHARTID   = 'hF10,
                   MSTATUS   = 'h300,
                   MTVEC     = 'h301,
                   MTDELEG   = 'h302,
                   MIE       = 'h304,
                   MTIMECMP  = 'h321,
                   MTIME     = 'h701,
                   MTIMEH    = 'h781,
                   MSCRATCH  = 'h340,
                   MEPC      = 'h341,
                   MCAUSE    = 'h342,
                   MBADADDR  = 'h343,
                   MIP       = 'h344,
                   MBASE     = 'h380,
                   MBOUND    = 'h381,
                   MIBASE    = 'h382,
                   MIBOUND   = 'h383,
                   MDBASE    = 'h384,
                   MDBOUND   = 'h385,
                   HTIMEW    = 'hB01,
                   HTIMEHW   = 'hB81,

                   //Berkeley Extension
                   MTOHOST   = 'h780, //'h7C0,   //Breaks regressions tests!!!!!
                   MFROMHOST = 'h7C1;


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
  parameter        MTI  = 7,
                   HTI  = 6,
                   STI  = 5,
                   MSI  = 3,
                   HSI  = 2,
                   SSI  = 1;


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

  parameter        CAUSE_SOFTWARE_INT             = 0,
                   CAUSE_TIMER_INT                = 1,
                   CAUSE_HOST_INT                 = 2,  //Berkely extension
                   CAUSE_UART_INT                 = 3,
                   CAUSE_EXT_INT                  = 16; //RoaLogic Extension
endpackage


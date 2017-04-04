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
//    Debug Unit Package                                       //
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


/*
 * One Debug Unit per Hardware Thread (hart)
 */
package riscv_du_pkg;

  parameter DBG_ADDR_SIZE = 16; // 16bit Debug Addresses
  parameter DU_ADDR_SIZE  = 12; // 12bit internal address bus

  parameter MAX_BREAKPOINTS = 8;

  /*
   * Debug Unit Memory Map
   *
   * addr_bits  Description
   * ------------------------------
   * 15-12      Debug bank
   * 11- 0      Address inside bank

   * Bank0      Control & Status
   * Bank1      GPRs
   * Bank2      CSRs
   * Bank3-15   reserved
   */
   parameter [15:12] DBG_INTERNAL = 4'h0,
                     DBG_GPRS     = 4'h1,
                     DBG_CSRS     = 4'h2;

   /*
    * Control registers
    * 0 00 00 ctrl
    * 0 00 01
    * 0 00 10 ie
    * 0 00 11 cause
    *  reserved
    *
    * 1 0000 BP0 Ctrl
    * 1 0001 BP0 Data
    * 1 0010 BP1 Ctrl
    * 1 0011 BP1 Data
    * ...
    * 1 1110 BP7 Ctrl
    * 1 1111 BP7 Data
    */
   parameter [4:0] DBG_CTRL    = 'h00, //debug control
                   DBG_HIT     = 'h01, //debug HIT register
                   DBG_IE      = 'h02, //debug interrupt enable (which exception halts the CPU?)
                   DBG_CAUSE   = 'h03, //debug cause (which exception halted the CPU?)
                   DBG_BPCTRL0 = 'h10, //hardware breakpoint0 control
                   DBG_BPDATA0 = 'h11, //hardware breakpoint0 data
                   DBG_BPCTRL1 = 'h12, //hardware breakpoint1 control
                   DBG_BPDATA1 = 'h13, //hardware breakpoint1 data
                   DBG_BPCTRL2 = 'h14, //hardware breakpoint2 control
                   DBG_BPDATA2 = 'h15, //hardware breakpoint2 data
                   DBG_BPCTRL3 = 'h16, //hardware breakpoint3 control
                   DBG_BPDATA3 = 'h17, //hardware breakpoint3 data
                   DBG_BPCTRL4 = 'h18, //hardware breakpoint4 control
                   DBG_BPDATA4 = 'h19, //hardware breakpoint4 data
                   DBG_BPCTRL5 = 'h1a, //hardware breakpoint5 control
                   DBG_BPDATA5 = 'h1b, //hardware breakpoint5 data
                   DBG_BPCTRL6 = 'h1c, //hardware breakpoint6 control
                   DBG_BPDATA6 = 'h1d, //hardware breakpoint6 data
                   DBG_BPCTRL7 = 'h1e, //hardware breakpoint7 control
                   DBG_BPDATA7 = 'h1f; //hardware breakpoint7 data


  //Debug codes
  parameter        DEBUG_SINGLE_STEP_TRACE  = 0,
                   DEBUG_BRANCH_TRACE       = 1;
  
  parameter        BP_CTRL_IMP         = 0,
                   BP_CTRL_ENA         = 1,
                   BP_CTRL_CC_FETCH    = 3'h0,
                   BP_CTRL_CC_LD_ADR   = 3'h1,
                   BP_CTRL_CC_ST_ADR   = 3'h2,
                   BP_CTRL_CC_LDST_ADR = 3'h3;

   /*
    * addr         Key  Description
    * --------------------------------------------
    * 0x000-0x01f  GPR  General Purpose Registers
    * 0x100-0x11f  FPR  Floating Point Registers
    * 0x200        PC   Program Counter
    * 0x201        PPC  Previous Program Counter
    */
   parameter [11:0] DBG_GPR = 12'b0000_000?_????,
                    DBG_FPR = 12'b0001_000?_????,
                    DBG_NPC = 12'h200,
                    DBG_PPC = 12'h201;


   /*
    * Bank2 - CSRs
    *
    * Direct mapping to the 12bit CSR address space
    */

endpackage

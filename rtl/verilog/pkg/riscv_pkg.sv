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
//    Definitions Package                                      //
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
  2017-02-25: Added MRET/HRET/SRET/URET per 1.9 supervisor spec
  2017-03-01: Removed MRTH/MRTS/HRTS per 1.9 supervisor spec
*/


package riscv_pkg;

  /*
   *  Constants
   */
  parameter [31:0] INSTR_NOP  = 'h13;
  parameter [31:0] MTVEC_INIT = 'h100;

  parameter        EXCEPTION_SIZE = 8;

  /*
   * Opcodes
   */
  parameter [ 6:2] OPC_LOAD     = 5'b00_000,
                   OPC_LOAD_FP  = 5'b00_001,
                   OPC_MISC_MEM = 5'b00_011,
                   OPC_OP_IMM   = 5'b00_100, 
                   OPC_AUIPC    = 5'b00_101,
                   OPC_OP_IMM32 = 5'b00_110,
                   OPC_STORE    = 5'b01_000,
                   OPC_STORE_FP = 5'b01_001,
                   OPC_AMO      = 5'b01_011, 
                   OPC_OP       = 5'b01_100,
                   OPC_LUI      = 5'b01_101,
                   OPC_OP32     = 5'b01_110,
                   OPC_MADD     = 5'b10_000,
                   OPC_MSUB     = 5'b10_001,
                   OPC_NMSUB    = 5'b10_010,
                   OPC_NMADD    = 5'b10_011,
                   OPC_OP_FP    = 5'b10_100,
                   OPC_BRANCH   = 5'b11_000,
                   OPC_JALR     = 5'b11_001,
                   OPC_JAL      = 5'b11_011,
                   OPC_SYSTEM   = 5'b11_100;

  /*
   * RV32/RV64 Base instructions
   */
  //                            f7       f3 opcode
  parameter [14:0] LUI    = 15'b???????_???_01101,
                   AUIPC  = 15'b???????_???_00101,
                   JAL    = 15'b???????_???_11011,
                   JALR   = 15'b???????_000_11001,
                   BEQ    = 15'b???????_000_11000,
                   BNE    = 15'b???????_001_11000,
                   BLT    = 15'b???????_100_11000,
                   BGE    = 15'b???????_101_11000,
                   BLTU   = 15'b???????_110_11000,
                   BGEU   = 15'b???????_111_11000,
                   LB     = 15'b???????_000_00000,
                   LH     = 15'b???????_001_00000,
                   LW     = 15'b???????_010_00000,
                   LBU    = 15'b???????_100_00000,
                   LHU    = 15'b???????_101_00000,
                   LWU    = 15'b???????_110_00000,
                   LD     = 15'b???????_011_00000,
                   SB     = 15'b???????_000_01000,
                   SH     = 15'b???????_001_01000,
                   SW     = 15'b???????_010_01000,
                   SD     = 15'b???????_011_01000,
                   ADDI   = 15'b???????_000_00100,
                   ADDIW  = 15'b???????_000_00110,
                   ADD    = 15'b0000000_000_01100,
                   ADDW   = 15'b0000000_000_01110,
                   SUB    = 15'b0100000_000_01100,
                   SUBW   = 15'b0100000_000_01110,
                   XORI   = 15'b???????_100_00100,
                   XOR    = 15'b0000000_100_01100,
                   ORI    = 15'b???????_110_00100,
                   OR     = 15'b0000000_110_01100,
                   ANDI   = 15'b???????_111_00100,
                   AND    = 15'b0000000_111_01100,
                   SLLI   = 15'b000000?_001_00100,
                   SLLIW  = 15'b0000000_001_00110,
                   SLL    = 15'b0000000_001_01100,
                   SLLW   = 15'b0000000_001_01110,
                   SLTI   = 15'b???????_010_00100,
                   SLT    = 15'b0000000_010_01100,
                   SLTU   = 15'b0000000_011_01100,
                   SLTIU  = 15'b???????_011_00100,
                   SRLI   = 15'b000000?_101_00100,
                   SRLIW  = 15'b0000000_101_00110,
                   SRL    = 15'b0000000_101_01100,
                   SRLW   = 15'b0000000_101_01110,
                   SRAI   = 15'b010000?_101_00100,
                   SRAIW  = 15'b0100000_101_00110,
                   SRA    = 15'b0100000_101_01100,
                   SRAW   = 15'b0100000_101_01110,

                   //pseudo instructions
                   SYSTEM = 15'b???????_000_11100, //excludes RDxxx instructions
                   MISCMEM= 15'b???????_???_00011;


  /*
   * SYSTEM/MISC_MEM opcodes
   */
  parameter [31:0] FENCE      = 32'b0000????????_00000_000_00000_0001111,
                   SFENCE_VM  = 32'b000100000100_?????_000_00000_1110011,
                   FENCE_I    = 32'b000000000000_00000_001_00000_0001111,
                   ECALL      = 32'b000000000000_00000_000_00000_1110011,
                   EBREAK     = 32'b000000000001_00000_000_00000_1110011,
                   MRET       = 32'b001100000010_00000_000_00000_1110011,
                   HRET       = 32'b001000000010_00000_000_00000_1110011,
                   SRET       = 32'b000100000010_00000_000_00000_1110011,
                   URET       = 32'b000000000010_00000_000_00000_1110011,
//                   MRTS       = 32'b001100000101_00000_000_00000_1110011,
//                   MRTH       = 32'b001100000110_00000_000_00000_1110011,
//                   HRTS       = 32'b001000000101_00000_000_00000_1110011,
                   WFI        = 32'b000100000101_00000_000_00000_1110011;

  //                                f7      f3  opcode
  parameter [14:0] CSRRW      = 15'b???????_001_11100,
                   CSRRS      = 15'b???????_010_11100,
                   CSRRC      = 15'b???????_011_11100,
                   CSRRWI     = 15'b???????_101_11100,
                   CSRRSI     = 15'b???????_110_11100,
                   CSRRCI     = 15'b???????_111_11100;


  /*
   * RV32/RV64 A-Extensions instructions
   */
  //                            f7       f3 opcode
  parameter [14:0] LRW      = 15'b00010??_010_01011,
                   SCW      = 15'b00011??_010_01011,
                   AMOSWAPW = 15'b00001??_010_01011,
                   AMOADDW  = 15'b00000??_010_01011,
                   AMOXORW  = 15'b00100??_010_01011,
                   AMOANDW  = 15'b01100??_010_01011,
                   AMOORW   = 15'b01000??_010_01011,
                   AMOMINW  = 15'b10000??_010_01011,
                   AMOMAXW  = 15'b10100??_010_01011,
                   AMOMINUW = 15'b11000??_010_01011,
                   AMOMAXUW = 15'b11100??_010_01011;

  parameter [14:0] LRD      = 15'b00010??_011_01011,
                   SCD      = 15'b00011??_011_01011,
                   AMOSWAPD = 15'b00001??_011_01011,
                   AMOADDD  = 15'b00000??_011_01011,
                   AMOXORD  = 15'b00100??_011_01011,
                   AMOANDD  = 15'b01100??_011_01011,
                   AMOORD   = 15'b01000??_011_01011,
                   AMOMIND  = 15'b10000??_011_01011,
                   AMOMAXD  = 15'b10100??_011_01011,
                   AMOMINUD = 15'b11000??_011_01011,
                   AMOMAXUD = 15'b11100??_011_01011;

  /*
   * RV32/RV64 M-Extensions instructions
   */
  //                            f7       f3 opcode
  parameter [14:0] MUL    = 15'b0000001_000_01100,
                   MULH   = 15'b0000001_001_01100,
                   MULW   = 15'b0000001_000_01110,
                   MULHSU = 15'b0000001_010_01100,
                   MULHU  = 15'b0000001_011_01100,
                   DIV    = 15'b0000001_100_01100,
                   DIVW   = 15'b0000001_100_01110,
                   DIVU   = 15'b0000001_101_01100,
                   DIVUW  = 15'b0000001_101_01110,
                   REM    = 15'b0000001_110_01100,
                   REMW   = 15'b0000001_110_01110,
                   REMU   = 15'b0000001_111_01100,
                   REMUW  = 15'b0000001_111_01110;

endpackage


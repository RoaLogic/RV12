/////////////////////////////////////////////////////////////////////
//   ,------.                    ,--.                ,--.          //
//   |  .--. ' ,---.  ,--,--.    |  |    ,---. ,---. `--' ,---.    //
//   |  '--'.'| .-. |' ,-.  |    |  |   | .-. | .-. |,--.| .--'    //
//   |  |\  \ ' '-' '\ '-'  |    |  '--.' '-' ' '-' ||  |\ `--.    //
//   `--' '--' `---'  `--`--'    `-----' `---' `-   /`--' `---'    //
//                                             `---'               //
//    RISC-V                                                       //
//    Opcodes Package                                              //
//                                                                 //
/////////////////////////////////////////////////////////////////////
//                                                                 //
//             Copyright (C) 2014-2022 ROA Logic BV                //
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

/*
  2017-02-25: Added MRET/HRET/SRET/URET per 1.9 supervisor spec
  2017-03-01: Removed MRTH/MRTS/HRTS per 1.9 supervisor spec
  2021-10-08: Added coding fields and RVC related functions
*/


package riscv_opcodes_pkg;
  localparam            ILEN      = 32;
  localparam [ILEN-1:0] INSTR_NOP = 'h13;

  /*
   * 32bit instructions
   */
  typedef logic [ 6:0] funct7_t;
  typedef logic [ 2:0] funct3_t;
  typedef enum logic [ 4:0] {zero,   //x0
                             ra,     //x1
                             sp,     //x2
                             gp,     //x3
                             tp,     //x4
                             t[0:2], //x5-7
                             s0fp,   //x8
                             s1,     //x9
                             a[0:7], //x10-17
                             s[2:11],//x18-27
                             t[3:6]  //x28-31
                            } rsd_t;

  typedef logic [ 4:0] opcode_t;
  typedef logic [ 1:0] isize_t;

  typedef logic [11:0] immI_t;
  typedef logic [11:0] immS_t;
  typedef logic [12:0] immSB_t;
  typedef logic [31:0] immU_t;
  typedef logic [20:0] immUJ_t;

  //Instruction Format R
  typedef struct packed {
    funct7_t funct7;
    rsd_t    rs2;
    rsd_t    rs1;
    funct3_t funct3;
    rsd_t    rd;
    opcode_t opcode;
    isize_t  size;
  } ins_formatR_t;

  //Instruction Format I
  typedef struct packed {
    logic [11:0] imm;
    rsd_t        rs1;
    funct3_t     funct3;
    rsd_t        rsd;
    opcode_t     opcode;
    isize_t      size;
  } ins_formatI_t;

  //Instruction Format S
  typedef struct packed {
    logic [11:5] imm11_5;
    rsd_t        rs2;
    rsd_t        rs1;
    funct3_t     funct3;
    logic [ 4:0] imm4_0;
    opcode_t     opcode;
    isize_t      size;
  } ins_formatS_t;

  //Instruction Format SB
  typedef struct packed {
    logic        imm12;
    logic [10:5] imm10_5;
    rsd_t        rs2;
    rsd_t        rs1;
    funct3_t     funct3;
    logic [ 4:1] imm4_1;
    logic        imm11;
    opcode_t     opcode;
    isize_t      size;
  } ins_formatSB_t;

  //Instruction Format U
  typedef struct packed {
    logic [31:12] imm;
    rsd_t         rd;
    opcode_t      opcode;
    isize_t       size;
  } ins_formatU_t;

  //Intruction Format UJ for JAL
  typedef struct packed {
    logic         imm20;
    logic [10: 1] imm10_1;
    logic         imm11;
    logic [19:12] imm19_12;
    rsd_t         rd;
    opcode_t      opcode;
    isize_t       size;
  } ins_formatUJ_t;

  //Join all instruction formats
  typedef union packed {
    logic [31:0] instr;
    ins_formatR_t    R;
    ins_formatI_t    I;
    ins_formatS_t    S;
    ins_formatSB_t   SB;
    ins_formatU_t    U;
    ins_formatUJ_t   UJ;
  } instr_t;

  
  //Instruction type = bubble + joined instruction formats
  typedef struct packed {
    logic   dbg;

    logic   bubble;
    instr_t instr;
  } instruction_t;


  //Opcode Intruction Format R
  typedef struct packed {
    funct7_t funct7;
    funct3_t funct3;
    opcode_t opcode;
  } opcR_t;

  function rsd_t decode_rs1 (input instr_t instr);
    decode_rs1 = instr.R.rs1;
  endfunction

  function rsd_t decode_rs2 (input instr_t instr);
    decode_rs2 = instr.R.rs2;
  endfunction

  function rsd_t decode_rd (input instr_t instr);
    decode_rd = instr.R.rd;
  endfunction

  function opcode_t decode_opcode (input instr_t instr);
    decode_opcode = instr.R.opcode;
  endfunction

  function opcR_t decode_opcR (input instr_t instr);
    decode_opcR = {instr.R.funct7, instr.R.funct3, instr.R.opcode};
  endfunction

  function immI_t decode_immI (input instr_t instr);
    decode_immI = instr.I.imm;
  endfunction

  function immS_t decode_immS (input instr_t instr);
    decode_immS = {instr.S.imm11_5, instr.S.imm4_0};
  endfunction

  function immSB_t decode_immSB (input instr_t instr);
    decode_immSB = {instr.SB.imm12, instr.SB.imm11, instr.SB.imm10_5, instr.SB.imm4_1, 1'b0};
  endfunction

  function immU_t decode_immU (input instr_t instr);
    decode_immU = {instr.U.imm, 12'h0};
  endfunction

  function immUJ_t decode_immUJ (input instr_t instr);
    decode_immUJ = {instr.UJ.imm20, instr.UJ.imm19_12, instr.UJ.imm11, instr.UJ.imm10_1, 1'b0};
  endfunction


  /*
   * 16bit instructions
   */
  typedef logic [1:0] funct2_t;
  typedef logic [3:0] funct4_t;
  typedef logic [5:0] funct6_t;
  typedef logic [2:0] rsdp_t;

  typedef logic [5:0] rvc_opcode_t;

  //Instruction Format CR - Register
  typedef struct packed {
    funct4_t      funct4;
    rsd_t         rd;
    rsd_t         rs2;
    isize_t       size;
  } ins_formatCR_t;

  //Instruction Format CI - immediate
  typedef struct packed {
    funct3_t      funct3;
    logic         pos12;
    rsd_t         rd;
    logic [ 6: 2] pos6_2;
    isize_t       size;
  } ins_formatCI_t;

  //Instruction Format CIB
  //Modified CI for C.SRLI/C.SRAI/C.ANDI
  //Spec calls these CB-format instructions, to which I disagree
  typedef struct packed {
    funct3_t      funct3;
    logic         imm5;
    funct2_t      funct2;
    rsdp_t        rd;
    logic [ 4: 0] imm4_0;
    isize_t       size;
  } ins_formatCIB_t;

  //Instruction Format CSS - Stack relative store
  //Use imm_position here, because meaning changes with instruction
  typedef struct packed {
    funct3_t      funct3;
    logic [12: 7] pos12_7;
    rsd_t         rs2;
    isize_t       size;
  } ins_formatCSS_t;

  //Instruction Format CIW - Wide immediate
  typedef struct packed {
    funct3_t      funct3;
    logic [ 5: 4] imm5_4;
    logic [ 9: 6] imm9_6;
    logic         imm2;
    logic         imm3;
    rsdp_t        rd;
    isize_t       size;
  } ins_formatCIW_t;

  //Instruction Format CL - Load
  //Use imm_postion here, because meaning changes with instruction
  typedef struct packed {
    funct3_t      funct3;
    logic [12:10] pos12_10;
    rsdp_t        rs1;
    logic [ 6: 5] pos6_5;
    rsdp_t        rd;
    isize_t       size;
  } ins_formatCL_t;

  //Instruction Format CS - Store
  //Use imm_position here, because meaning changes with instruction
  typedef struct packed {
    funct3_t      funct3;
    logic [12:10] pos12_10;
    rsdp_t        rs1;
    logic [ 6: 5] pos6_5;
    rsdp_t        rs2;
    isize_t       size;
  } ins_formatCS_t;

  //Instruction Format CA - Arithmetic
  typedef struct packed {
    funct6_t      funct6;
    rsdp_t        rs1_d;
    funct2_t      funct2;
    rsdp_t        rs2;
    isize_t       size;
  } ins_formatCA_t;

  //Instruction Format CB - Branch
  typedef struct packed {
    funct3_t      funct3;
    logic         imm8;
    logic [ 4: 3] imm4_3;
    rsdp_t        rs1;
    logic [ 7: 6] imm7_6;
    logic [ 2: 1] imm2_1;
    logic         imm5;
    isize_t       size;
  } ins_formatCB_t;

  //Instruction Format CJ - JUMP
  typedef struct packed {
    funct3_t      funct3;
    logic         imm11;
    logic         imm4;
    logic [ 9: 8] imm9_8;
    logic         imm10;
    logic         imm6;
    logic         imm7;
    logic [ 3: 1] imm3_1;
    logic         imm5;
    isize_t       size;
  } ins_formatCJ_t;

  //Join all instruction formats
  typedef union packed {
    logic [15:0] instr;
    ins_formatCR_t   CR;
    ins_formatCIB_t  CIB;
    ins_formatCI_t   CI;
    ins_formatCSS_t  CSS;
    ins_formatCIW_t  CIW;
    ins_formatCL_t   CL;
    ins_formatCS_t   CS;
    ins_formatCA_t   CA;
    ins_formatCB_t   CB;
    ins_formatCJ_t   CJ;
  } rvc_instr_t;


  //Opcode Intruction Format RVC-R
  typedef struct packed {
    funct4_t funct4;
    isize_t  quadrant;
  } rvc_opcR_t;

  //Opcode Intruction Format RVC-A
  typedef struct packed {
    funct6_t funct6;
    funct2_t funct2;
    isize_t  quadrant;
  } rvc_opcA_t;

  //convert rs/rd' to rs/rd
  function rsd_t rvc_rsdp2rsd (input rsdp_t r);
    rvc_rsdp2rsd = rsd_t'({2'b01,r}); //x8-15
  endfunction

  //Generate R-format opcode
  function rvc_opcR_t decode_rvc_opcR(input rvc_instr_t instr);
    decode_rvc_opcR = {instr.CR.funct4, instr.CR.size};
  endfunction

  //Generate A-format opcode
  function rvc_opcA_t decode_rvc_opcA(input rvc_instr_t instr);
    decode_rvc_opcA = {instr.CA.funct6, instr.CA.funct2, instr.CA.size};
  endfunction

  //decode CIW-format immediate
  function immI_t rvc_decode_immCIW (input rvc_instr_t instr);
    rvc_decode_immCIW = {2'h0,instr.CIW.imm9_6,instr.CIW.imm5_4, instr.CIW.imm3, instr.CIW.imm2, 2'h0};
  endfunction

  //decode CL-format immedate for C.LW/C.FLW
  function immI_t rvc_decode_immCLW(input rvc_instr_t instr);
    rvc_decode_immCLW = {5'h0, instr.CL.pos6_5[5], instr.CL.pos12_10,instr.CL.pos6_5[6], 2'h0};
  endfunction

  //decode CL-format immediate for C.LD/C.FLD
  function immI_t rvc_decode_immCLD(input rvc_instr_t instr);
    rvc_decode_immCLD = {4'h0, instr.CL.pos6_5, instr.CL.pos12_10, 3'h0};
  endfunction

  //decode CL-format immediate for C.LQ
  function immI_t rvc_decode_immCLQ(input rvc_instr_t instr);
    rvc_decode_immCLQ = {3'h0, instr.CL.pos12_10[10], instr.CL.pos6_5, instr.CL.pos12_10[12:11], 4'h0};
  endfunction

  //decode CS-format immediate for C.SW/C.FSW
  function immS_t rvc_decode_immCSW(input rvc_instr_t instr);
    rvc_decode_immCSW = rvc_decode_immCLW(instr);
  endfunction

  //decode CS-format immediate for C.SD/C.FSD
  function immS_t rvc_decode_immCSD(input rvc_instr_t instr);
    rvc_decode_immCSD = rvc_decode_immCLD(instr);
  endfunction

  //decode CS-format immediate for C.SQ
  function immS_t rvc_decode_immCSQ(input rvc_instr_t instr);
    rvc_decode_immCSQ = rvc_decode_immCLQ(instr);
  endfunction

  //decode CSS-format immediate for C.SWSP/C.FSWSP
  function immI_t rvc_decode_immCSSWSP(input rvc_instr_t instr);
    rvc_decode_immCSSWSP = {4'h0, instr.CSS.pos12_7[8:7], instr.CSS.pos12_7[12:9], 2'h0};
  endfunction

  //decode CSS-format immediate for C.SDSP/C.FSDSP
  function immI_t rvc_decode_immCSSDSP(input rvc_instr_t instr);
    rvc_decode_immCSSDSP = {3'h0, instr.CSS.pos12_7[9:7], instr.CSS.pos12_7[12:10], 3'h0};
  endfunction

  //decode CSS-format immediate for C.SQSP
  function immI_t rvc_decode_immCSSQSP(input rvc_instr_t instr);
    rvc_decode_immCSSQSP = {2'h0, instr.CSS.pos12_7[10:7], instr.CSS.pos12_7[12:11], 4'h0};
  endfunction

  //decode CI-format immediate for C.LWSP/C.FLWSP
  function immI_t rvc_decode_immCIWSP(input rvc_instr_t instr);
    rvc_decode_immCIWSP = {4'h0, instr.CI.pos6_2[3:2], instr.CI.pos12, instr.CI.pos6_2[6:4], 2'h0};
  endfunction

  //decode CI-format immediate for C.LDSP/C.FLDSP
  function immI_t rvc_decode_immCIDSP(input rvc_instr_t instr);
    rvc_decode_immCIDSP = {3'h0, instr.CI.pos6_2[4:2],instr.CI.pos12, instr.CI.pos6_2[6:5], 3'h0};
  endfunction

  //decode CI-format immediate for C.LQSP
  function immI_t rvc_decode_immCIQSP(input rvc_instr_t instr);
    rvc_decode_immCIQSP = {2'h0, instr.CI.pos6_2[5:2], instr.CI.pos12, instr.CI.pos6_2[2], 4'h0};
  endfunction

  //decode CI-format sign-extended immediate
  function immI_t rvc_decode_immCI(input rvc_instr_t instr);
    rvc_decode_immCI = {{6{instr.CI.pos12}}, instr.CI.pos12, instr.CI.pos6_2};
  endfunction

  //decode CI-format sign-extended immediate
  function immI_t rvc_decode_immCI4(input rvc_instr_t instr);
    rvc_decode_immCI4 = {{2{instr.CI.pos12}}, instr.CI.pos12, instr.CI.pos6_2[4:3], instr.CI.pos6_2[5], instr.CI.pos6_2[2], instr.CI.pos6_2[6], 4'h0};
  endfunction

  //decode CI-format sign-extended immediate shifted by 12
  function immU_t rvc_decode_immCI12(input rvc_instr_t instr);
    rvc_decode_immCI12 ={{14{instr.CI.pos12}}, instr.CI.pos12, instr.CI.pos6_2, 12'h0}; 
  endfunction

  //decode CJ-format immediate
  function immUJ_t rvc_decode_immCJ(input rvc_instr_t instr);
    rvc_decode_immCJ = {{9{instr.CJ.imm11}},instr.CJ.imm11, instr.CJ.imm10, instr.CJ.imm9_8, instr.CJ.imm7,
                                            instr.CJ.imm6, instr.CJ.imm5, instr.CJ.imm4, instr.CJ.imm3_1, 1'b0};
  endfunction

  //decode CB-format immediate
  function immSB_t rvc_decode_immCB(input rvc_instr_t instr);
    rvc_decode_immCB = { {4{instr.CB.imm8}}, instr.CB.imm8, instr.CB.imm7_6, instr.CB.imm5, instr.CB.imm4_3, instr.CB.imm2_1,  1'b0};
  endfunction

  //decode CIB-format immediate
  function immI_t rvc_decode_immCIB(input rvc_instr_t instr);
    rvc_decode_immCIB = { {6{instr.CIB.imm5}}, instr.CIB.imm5, instr.CIB.imm4_0};
  endfunction


  //Encoding functions to generate RV32 instructions
  function instr_t encode_R (
    input logic [14:0] opcode,
    input rsd_t        rd,
                       rs1,
		       rs2,
    input isize_t      size
  );
    encode_R.R.funct7 = opcode[14:8];
    encode_R.R.rs2    = rs2;
    encode_R.R.rs1   =  rs1;
    encode_R.R.funct3 = opcode[7:5];
    encode_R.R.rd     = rd;
    encode_R.R.opcode = opcode[4:0];
    encode_R.R.size   = size;
  endfunction

  function instr_t encode_I (
    input logic [14:0] opcode,
    input rsd_t        rd,
                       rs1,
    input immI_t       imm,
    input isize_t      size
  );
    encode_I.I.imm    = imm;
    encode_I.I.rs1    = rs1;
    encode_I.I.funct3 = opcode[7:5];
    encode_I.I.rsd    = rd;
    encode_I.I.opcode = opcode[4:0];
    encode_I.I.size   = size;
  endfunction

  //exception to encode Shift instructions
  function instr_t encode_Ishift (
    input logic [14:0] opcode,
    input rsd_t        rd,
                       rs1,
    input immI_t       imm,
    input isize_t      size
  );
    encode_Ishift.I.imm[11:6] = opcode[14:9];
    encode_Ishift.I.imm[ 5:0] = imm[5:0];
    encode_Ishift.I.rs1       = rs1;
    encode_Ishift.I.funct3    = opcode[7:5];
    encode_Ishift.I.rsd       = rd;
    encode_Ishift.I.opcode    = opcode[4:0];
    encode_Ishift.I.size      = size;
  endfunction

  function instr_t encode_S (
    input logic [14:0] opcode,
    input rsd_t        rs1,
		       rs2,
    input immS_t       imm,
    input isize_t      size
  );
    encode_S.S.imm11_5 = imm[11:5];
    encode_S.S.imm4_0  = imm[ 4:0];
    encode_S.S.rs2     = rs2;
    encode_S.S.rs1     = rs1;
    encode_S.S.funct3  = opcode[7:5];
    encode_S.S.opcode  = opcode[4:0];
    encode_S.S.size    = size;
  endfunction

  function instr_t encode_SB (
    input logic [14:0] opcode,
    input rsd_t        rs1,
		       rs2,
    input immSB_t      imm,
    input isize_t      size
  );
    encode_SB.SB.imm12   = imm[12];
    encode_SB.SB.imm11   = imm[11];
    encode_SB.SB.imm10_5 = imm[10:5];
    encode_SB.SB.imm4_1  = imm[ 4:1];
    encode_SB.SB.rs2     = rs2;
    encode_SB.SB.rs1     = rs1;
    encode_SB.SB.funct3  = opcode[7:5];
    encode_SB.SB.opcode  = opcode[4:0];
    encode_SB.SB.size    = size;
  endfunction

  function instr_t encode_U (
    input logic [14:0] opcode,
    input rsd_t        rd,
    input immU_t       imm,
    input isize_t      size
  );
    encode_U.U.imm    = imm[31:12];
    encode_U.U.rd     = rd;
    encode_U.U.opcode = opcode[4:0];
    encode_U.U.size   = size;
  endfunction

  function instr_t encode_UJ (
    input logic [14:0] opcode,
    input rsd_t        rd,
    input immUJ_t      imm,
    input isize_t      size
  );
    encode_UJ.UJ.imm20    = imm[20];
    encode_UJ.UJ.imm19_12 = imm[19:12];
    encode_UJ.UJ.imm11    = imm[11];
    encode_UJ.UJ.imm10_1  = imm[10:1];
    encode_UJ.UJ.rd       = rd;
    encode_UJ.UJ.opcode   = opcode[4:0];
    encode_UJ.UJ.size     = size;
  endfunction


  /*
   * Opcodes
   */
  localparam [ 6:2] OPC_LOAD     = 5'b00_000,
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
  localparam [14:0] LUI    = 15'b???????_???_01101,
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
  localparam [31:0] FENCE      = 32'b0000????????_00000_000_00000_0001111,
                    SFENCE_VM  = 32'b000100000100_?????_000_00000_1110011,
                    FENCE_I    = 32'b000000000000_00000_001_00000_0001111,
                    ECALL      = 32'b000000000000_00000_000_00000_1110011,
                    EBREAK     = 32'b000000000001_00000_000_00000_1110011,
                    MRET       = 32'b001100000010_00000_000_00000_1110011,
                    HRET       = 32'b001000000010_00000_000_00000_1110011,
                    SRET       = 32'b000100000010_00000_000_00000_1110011,
                    URET       = 32'b000000000010_00000_000_00000_1110011,
//                    MRTS       = 32'b001100000101_00000_000_00000_1110011,
//                    MRTH       = 32'b001100000110_00000_000_00000_1110011,
//                    HRTS       = 32'b001000000101_00000_000_00000_1110011,
                    WFI        = 32'b000100000101_00000_000_00000_1110011,

                    //Special instructions
		    NOP        = 32'h13,
		    ILLEGAL    = {32{1'b1}};

  //                                f7      f3  opcode
  localparam [14:0] CSRRW      = 15'b???????_001_11100,
                    CSRRS      = 15'b???????_010_11100,
                    CSRRC      = 15'b???????_011_11100,
                    CSRRWI     = 15'b???????_101_11100,
                    CSRRSI     = 15'b???????_110_11100,
                    CSRRCI     = 15'b???????_111_11100;


  /*
   * RV32/RV64 A-Extensions instructions
   */
  //                            f7       f3 opcode
  localparam [14:0] LRW      = 15'b00010??_010_01011,
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

  localparam [14:0] LRD      = 15'b00010??_011_01011,
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
  localparam [14:0] MUL    = 15'b0000001_000_01100,
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


  /*
   * RVC extension instructions
   * uses rvc_opcR layout
   */
  //                           f6         f2 op
  localparam [9:0] C_ADDI4SPN = 10'b000???_??_00,
                   C_FLD      = 10'b001???_??_00, //RV32/64
                   C_LQ       = 10'b001???_??_00, //RV128
                   C_LW       = 10'b010???_??_00,
                   C_FLW      = 10'b011???_??_00, //RV32
                   C_LD       = 10'b011???_??_00, //RV64/128
                   C_FSD      = 10'b101???_??_00, //RV32/64
                   C_SQ       = 10'b101???_??_00, //RV128
                   C_SW       = 10'b110???_??_00,
                   C_FSW      = 10'b111???_??_00, //RV32
                   C_SD       = 10'b111???_??_00, //RV64/128
                   C_NOP      = 10'b000???_??_01,
                   C_ADDI     = 10'b000???_??_01,
                   C_JAL      = 10'b001???_??_01, //RV32
                   C_ADDIW    = 10'b001???_??_01, //RV64/128
                   C_LI       = 10'b010???_??_01,
                   C_ADDI16SP = 10'b011???_??_01, 
                   C_LUI      = 10'b011???_??_01,
                   C_SRLI     = 10'b100?00_??_01,
                   C_SRLI64   = 10'b100000_??_01, //RV128
                   C_SRAI     = 10'b100?01_??_01,
                   C_SRAI64   = 10'b100001_??_01, //RV128
                   C_ANDI     = 10'b100?10_??_01,
                   C_SUB      = 10'b100011_00_01,
                   C_XOR      = 10'b100011_01_01,
                   C_OR       = 10'b100011_10_01,
                   C_AND      = 10'b100011_11_01,
                   C_SUBW     = 10'b100111_00_01, //RV64/128
                   C_ADDW     = 10'b100111_01_01,
                   C_J        = 10'b101???_??_01,
                   C_BEQZ     = 10'b110???_??_01,
                   C_BNEZ     = 10'b111???_??_01,
                   C_SLLI     = 10'b000???_??_10,
                   C_SLLI64   = 10'b0000??_??_10, //RV128
                   C_FLDSP    = 10'b001???_??_10, //RV32/64
                   C_LQSP     = 10'b001???_??_10, //RV128
                   C_LWSP     = 10'b010???_??_10,
                   C_FLWSP    = 10'b011???_??_10, //RV32
                   C_LDSP     = 10'b011???_??_10, //RV64/128
                   C_JR       = 10'b1000??_??_10,
                   C_MV       = 10'b1000??_??_10,
                   C_EBREAK   = 10'b1001??_??_10,
                   C_JALR     = 10'b1001??_??_10,
                   C_ADD      = 10'b1001??_??_10,
                   C_FSDSP    = 10'b101???_??_10, //RV32/64
                   C_SQSP     = 10'b101???_??_10, //RV128
                   C_SWSP     = 10'b110???_??_10,
                   C_FSWSP    = 10'b111???_??_10, //RV32
                   C_SDSP     = 10'b111???_??_10; //RV64/128

endpackage


/////////////////////////////////////////////////////////////////////
//   ,------.                    ,--.                ,--.          //
//   |  .--. ' ,---.  ,--,--.    |  |    ,---. ,---. `--' ,---.    //
//   |  '--'.'| .-. |' ,-.  |    |  |   | .-. | .-. |,--.| .--'    //
//   |  |\  \ ' '-' '\ '-'  |    |  '--.' '-' ' '-' ||  |\ `--.    //
//   `--' '--' `---'  `--`--'    `-----' `---' `-   /`--' `---'    //
//                                             `---'               //
//    RISC-V                                                       //
//    Instruction Pre-Decoder                                      //
//                                                                 //
/////////////////////////////////////////////////////////////////////
//                                                                 //
//             Copyright (C) 2014-2021 ROA Logic BV                //
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

module riscv_pd
import riscv_opcodes_pkg::*;
import riscv_state_pkg::*;
#(
  parameter                       XLEN           = 32,
  parameter  [XLEN          -1:0] PC_INIT        = 'h200,
  parameter                       HAS_RVC        = 0,
  parameter                       HAS_BPU        = 0,
  parameter                       BP_GLOBAL_BITS = 2,
  parameter                       RSB_DEPTH      = 4
)
(
  input                           rst_ni,          //Reset
  input                           clk_i,           //Clock
  
  input                           id_stall_i,
  output                          pd_stall_o,
  input                           du_mode_i,

  input                           bu_flush_i,      //flush pipe & load new program counter
                                  st_flush_i,

  output                          pd_flush_o,

  output rsd_t                    pd_rs1_o,
                                  pd_rs2_o,

  output     [              11:0] pd_csr_reg_o,

  input      [XLEN          -1:0] bu_nxt_pc_i,     //Branch Unit Next Program Counter
                                  st_nxt_pc_i,     //State Next Program Counter
  output reg [XLEN          -1:0] pd_nxt_pc_o,     //Branch Preditor Next Program Counter
  output reg                      pd_latch_nxt_pc_o,

  input      [BP_GLOBAL_BITS-1:0] if_bp_history_i,
  output reg [BP_GLOBAL_BITS-1:0] pd_bp_history_o,

  input      [               1:0] bp_bp_predict_i, //Branch Prediction bits
  output reg [               1:0] pd_bp_predict_o, //push down the pipe

  input      [XLEN          -1:0] if_pc_i,
  output reg [XLEN          -1:0] pd_pc_o,
                                  pd_rsb_pc_o,

  input  instruction_t            if_insn_i,
  output instruction_t            pd_insn_o,
  input  instruction_t            id_insn_i,

  input  interrupts_exceptions_t  if_exceptions_i,
  output interrupts_exceptions_t  pd_exceptions_o,
  input  interrupts_exceptions_t  id_exceptions_i,
                                  ex_exceptions_i,
                                  mem_exceptions_i,
                                  wb_exceptions_i
);

  ////////////////////////////////////////////////////////////////
  //
  // Constants
  //

  //Instruction address mask
  localparam ADR_MASK = HAS_RVC != 0 ? {XLEN{1'b1}} << 1 : {XLEN{1'b1}} << 2;


  ////////////////////////////////////////////////////////////////
  //
  // Variables
  //

  //RSB
  logic             is_16bit_instruction;
  logic             has_rsb;
  logic [XLEN -1:0] rsb_nxt_pc,
                    rsb_predict_pc;
  logic             rsb_push,
                    rsb_pop,
                    rsb_empty;

  rsd_t             rs1,
                    rd;
  logic             link_rs1,
                    link_rd,
                    decode_rsb_push,
                    decode_rsb_pop;


  //Immediates for branches and jumps
  immUJ_t           immUJ;
  immSB_t           immSB;
  logic [XLEN -1:0] ext_immUJ,
                    ext_immSB;


  logic [      1:0] branch_predicted;

  logic             branch_taken,
                    stalled_branch;

  logic             assert_local_stall;
  logic [      1:0] local_stall;


  ////////////////////////////////////////////////////////////////
  //
  // Module Body
  //

  //for RSB
  assign is_16bit_instruction = ~&if_insn_i.instr[1:0];
  assign rsb_nxt_pc           = if_pc_i + ('h2 << if_insn_i.instr.SB.size);
  assign has_rsb              = RSB_DEPTH > 0;
  assign rs1                  = decode_rs1(if_insn_i.instr);
  assign rd                   = decode_rd (if_insn_i.instr);
  assign link_rs1             = (rs1 == 1) | (rs1 == 5); //x1/ra or x5/t0/ra2
  assign link_rd              = (rd  == 1) | (rd  == 5);

  
  //All flush signals
  assign pd_flush_o = bu_flush_i | st_flush_i;


  //Stall when write-CSR
  //This can be more advanced, but who cares ... this is not critical
  //Two cycle stall to ensure data is written into CSR before it can be read
  always_comb
    casex ( decode_opcR(if_insn_i.instr) )
      CSRRW  : assert_local_stall <= ~if_insn_i.bubble;
      CSRRWI : assert_local_stall <= ~if_insn_i.bubble;
      CSRRS  : assert_local_stall <= ~if_insn_i.bubble & |decode_rs1 (if_insn_i.instr);
      CSRRSI : assert_local_stall <= ~if_insn_i.bubble & |decode_immI(if_insn_i.instr);
      CSRRC  : assert_local_stall <= ~if_insn_i.bubble & |decode_rs1 (if_insn_i.instr);
      CSRRCI : assert_local_stall <= ~if_insn_i.bubble & |decode_immI(if_insn_i.instr);
      default: assert_local_stall <= 1'b0;
    endcase


  always @(posedge clk_i, negedge rst_ni)
    if      (!rst_ni        ) local_stall <= 2'h0;
    else if ( local_stall[1]) local_stall <= 2'h0;
    else if (!id_stall_i    )
    begin
        local_stall[0] <= assert_local_stall | local_stall[0];
        local_stall[1] <= local_stall[0];
    end

  assign pd_stall_o = id_stall_i | local_stall[0];


  /*
   * To Register File (registered outputs)
   */
  //address into register file. Gets registered in memory
  assign pd_rs1_o = decode_rs1(if_insn_i.instr);
  assign pd_rs2_o = decode_rs2(if_insn_i.instr);


  /*
   * To State (CSR - registered output)
   */
  assign pd_csr_reg_o = if_insn_i.instr.I.imm;


  //Program counter
  always @(posedge clk_i, negedge rst_ni)
    if      (!rst_ni     ) pd_pc_o <= PC_INIT     & ADR_MASK;
    else if ( st_flush_i ) pd_pc_o <= st_nxt_pc_i & ADR_MASK;
    else if ( bu_flush_i ) pd_pc_o <= bu_nxt_pc_i & ADR_MASK;
    else if (!pd_stall_o ) pd_pc_o <= if_pc_i     & ADR_MASK;


  //Instruction
  assign pd_insn_o.retired = 1'b0;


  always @(posedge clk_i, negedge rst_ni)
    if      (!rst_ni    ) pd_insn_o.instr <= NOP;
    else if (!id_stall_i) pd_insn_o.instr <= if_insn_i.instr;


  always @(posedge clk_i, negedge rst_ni)
    if      (!rst_ni    ) pd_insn_o.dbg <= 1'b0;
    else if (!id_stall_i) pd_insn_o.dbg <= if_insn_i.dbg;
    

  //Bubble
  always @(posedge clk_i, negedge rst_ni)
    if      (!rst_ni              ) pd_insn_o.bubble <= 1'b1;
    else if ( pd_flush_o          ) pd_insn_o.bubble <= 1'b1;
    else if ( id_exceptions_i.any  ||
              ex_exceptions_i.any  ||
              mem_exceptions_i.any ||
              wb_exceptions_i.any ) pd_insn_o.bubble <= 1'b1;
    else if (!id_stall_i)
      if (local_stall) pd_insn_o.bubble <= 1'b1;
      else             pd_insn_o.bubble <= if_insn_i.bubble;


  //Exceptions
  always @(posedge clk_i, negedge rst_ni)
    if      (!rst_ni     ) pd_exceptions_o <= 'h0;
    else if ( pd_flush_o ) pd_exceptions_o <= 'h0;
    else if ( pd_stall_o ) pd_exceptions_o <= 'h0;
    else                   pd_exceptions_o <= if_exceptions_i;


  //Branch Predict History
  always @(posedge clk_i)
    if (!pd_stall_o) pd_bp_history_o <= if_bp_history_i;

    
  /*
   * Branches & Jump
   */

  //Instantiate RSB
generate
  if (RSB_DEPTH > 0)
  begin: gen_rsb

      riscv_rsb #(
        .XLEN    ( XLEN           ),
        .DEPTH   ( RSB_DEPTH      ) )
      rsb_inst (
        .rst_ni  ( rst_ni         ),
        .clk_i   ( clk_i          ),
	.ena_i   (!pd_stall_o     ),
        .d_i     ( rsb_nxt_pc     ),
        .q_o     ( rsb_predict_pc ),
        .push_i  ( rsb_push       ), //push stack, JAL(R) rd !=x0
        .pop_i   ( rsb_pop        ), //pop stack, RET
        .empty_o ( rsb_empty      ) );

`ifdef RV12_RSB_LOGGER
      /* RSB logger
       */
//synopsys translate_off
      int fd;
      initial fd=$fopen($sformatf("%m_rsb.log"), "w");

      always @(posedge clk_i)
        if (!pd_stall_o)
        begin
            if (rsb_pop ) $fdisplay(fd, "pop  %4s %2d %h %d %b", rs1.name(), rs1, rsb_predict_pc, rsb_inst.cnt, rsb_empty);
            if (rsb_push) $fdisplay(fd, "push %4s %2d %h %d"   , rd.name(),  rd,  rsb_nxt_pc,     rsb_inst.cnt           );
        end
//synopsys translate_on
`endif

  end
endgenerate


  /* decode rbs_push/pop
   * Hint are encoded in the 'rd' field; only push/pop RBS when rd=x1/x5
   *
   * +-------+-------+--------+----------------+
   * |  rd   |  rs1  | rs1=rd | action         |
   * +-------+-------+--------+----------------+
   * | !link | !link |    -   | none           |
   * | !link |  link |    -   | pop            |
   * |  link | !link |    -   | push           |
   * |  link |  link |    0   | pop, then push |
   * |  link |  link |    1   | push           |
   * +-------+-------+--------+----------------+
   */
  always_comb
    unique casex ({link_rd, link_rs1, rs1==rd})
      3'b00? :{decode_rsb_push, decode_rsb_pop} = 2'b00;
      3'b01? :{decode_rsb_push, decode_rsb_pop} = 2'b01;
      3'b10? :{decode_rsb_push, decode_rsb_pop} = 2'b10;
      3'b110 :{decode_rsb_push, decode_rsb_pop} = 2'b11;
      3'b111 :{decode_rsb_push, decode_rsb_pop} = 2'b10;
    endcase


  //Immediates
  assign immUJ = decode_immUJ(if_insn_i.instr);
  assign immSB = decode_immSB(if_insn_i.instr);
  assign ext_immUJ = { {XLEN-$bits(immUJ){immUJ[$left(immUJ,1)]}}, immUJ};
  assign ext_immSB = { {XLEN-$bits(immSB){immSB[$left(immSB,1)]}}, immSB};


  // Branch and Jump prediction
  always_comb
    casex ( {du_mode_i, if_insn_i.bubble, decode_opcode(if_insn_i.instr)} )
      {1'b0,1'b0,OPC_JAL   } : begin
                                   branch_taken     = 1'b1;
                                   branch_predicted = 2'b10;
                                   rsb_push         = decode_rsb_push;
                                   rsb_pop          = decode_rsb_pop;
                                   pd_nxt_pc_o      = if_pc_i + ext_immUJ;
                               end

      {1'b0,1'b0,OPC_JALR  } : begin
                                   branch_taken     = has_rsb ? decode_rsb_pop : 1'b0;
                                   branch_predicted = 2'b00;
                                   rsb_push         = decode_rsb_push;
                                   rsb_pop          = decode_rsb_pop;
                                   pd_nxt_pc_o      = rsb_predict_pc;
                               end

      {1'b0,1'b0,OPC_BRANCH} : begin
                                   //if this CPU has a Branch Predict Unit, then use it's prediction
                                   //otherwise assume backwards jumps taken, forward jumps not taken
                                   branch_taken     = (HAS_BPU != 0) ? bp_bp_predict_i[1] : ext_immSB[31];
                                   branch_predicted = (HAS_BPU != 0) ? bp_bp_predict_i    : {ext_immSB[31], 1'b0};
                                   rsb_push         = 1'b0;
                                   rsb_pop          = 1'b0;
                                   pd_nxt_pc_o      = if_pc_i + ext_immSB;
                               end

      default                : begin
                                   branch_taken     = 1'b0;
                                   branch_predicted = 2'b00;
                                   rsb_push         = 1'b0;
                                   rsb_pop          = 1'b0;
                                   pd_nxt_pc_o      = 'hx;
                               end
    endcase


  always @(posedge clk_i)
    if (!pd_stall_o) pd_rsb_pc_o <= has_rsb ? rsb_predict_pc : {$bits(pd_rsb_pc_o){1'b0}};


  always @(posedge clk_i)
    stalled_branch <= branch_taken & id_stall_i;


  //generate latch strobe
  assign pd_latch_nxt_pc_o = branch_taken & ~stalled_branch;


  //to Branch Prediction Unit
  always @(posedge clk_i, negedge rst_ni)
    if      (!rst_ni    ) pd_bp_predict_o <= 2'b00;
    else if (!pd_stall_o) pd_bp_predict_o <= branch_predicted;

endmodule


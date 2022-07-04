/////////////////////////////////////////////////////////////////////
//   ,------.                    ,--.                ,--.          //
//   |  .--. ' ,---.  ,--,--.    |  |    ,---. ,---. `--' ,---.    //
//   |  '--'.'| .-. |' ,-.  |    |  |   | .-. | .-. |,--.| .--'    //
//   |  |\  \ ' '-' '\ '-'  |    |  '--.' '-' ' '-' ||  |\ `--.    //
//   `--' '--' `---'  `--`--'    `-----' `---' `-   /`--' `---'    //
//                                             `---'               //
//    RISC-V                                                       //
//    Debug Unit                                                   //
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


import riscv_opcodes_pkg::*;
import riscv_state_pkg::*;
import riscv_du_pkg::*;

module riscv_du #(
  parameter XLEN           = 32,
  parameter BREAKPOINTS    = 3
)
(
  input                           rst_ni,
  input                           clk_i,

   
  //Debug Port interface
  input                           dbg_stall_i,
  input                           dbg_strb_i,
  input                           dbg_we_i,
  input      [DBG_ADDR_SIZE -1:0] dbg_addr_i,
  input      [XLEN          -1:0] dbg_d_i,
  output reg [XLEN          -1:0] dbg_q_o,
  output reg                      dbg_ack_o,
  output reg                      dbg_bp_o,
  

  //CPU signals
  output                          du_dbg_mode_o,
  output                          du_stall_o,
                                  du_stall_if_o,

  output                          du_latch_nxt_pc_o,
  output                          du_flush_o,
  output                          du_flush_cache_o,
  output reg                      du_we_rf_o,
  output reg                      du_re_rf_o,
  output reg                      du_we_frf_o,
  output reg                      du_we_csr_o,
  output reg                      du_re_csr_o,
  output reg                      du_we_pc_o,
  output reg [DU_ADDR_SIZE  -1:0] du_addr_o,
  output reg [XLEN          -1:0] du_d_o,
  output     [              31:0] du_ie_o,
  input      [XLEN          -1:0] du_rf_q_i,
                                  du_frf_q_i,
                                  st_csr_q_i,
                                  if_nxt_pc_i,
                                  bu_nxt_pc_i,
                                  if_pc_i,
                                  pd_pc_i,
                                  id_pc_i,
                                  ex_pc_i,
                                  wb_pc_i,
  input                           bu_flush_i,
                                  st_flush_i,

  input  instruction_t            if_nxt_insn_i,
                                  if_insn_i,
                                  pd_insn_i,
                                  mem_insn_i,
                                  wb_insn_i, //only for 'dbg' signal

  input  interrupts_exceptions_t  mem_exceptions_i,
  input      [XLEN          -1:0] mem_memadr_i,
  input                           dmem_ack_i,
                                  ex_stall_i,
  //From state
  input      [              31:0] du_exceptions_i
);

  //////////////////////////////////////////////////////////////////
  //
  // Constants
  //

  typedef struct packed {
    logic       branch_break_ena; //each branch causes a switch to the debug environment
    logic       instr_break_ena;  //each executed instruction causes a switch to the debug environment (=single step)
  } dbg_ctrl_struct;

  typedef struct packed {
    logic [MAX_BREAKPOINTS-1:0] bp_hit;           //15:8
    logic                       branch_break_hit; //1
    logic                       instr_break_hit;  //0
  } dbg_hit_struct;

  typedef struct packed {
    logic [     2:0] cc;          //6:4
    logic            enabled;     //1
    logic            implemented; //0
  } bp_ctrl_struct;

  typedef struct packed {
    bp_ctrl_struct   ctrl;
    logic [XLEN-1:0] data;
  } bp_struct;

  typedef struct packed {
    dbg_ctrl_struct  ctrl;
    logic     [               31:0] ie;
    logic     [XLEN           -1:0] cause;
    dbg_hit_struct                  hit;
    bp_struct [MAX_BREAKPOINTS-1:0] bp;
  } dbg_struct;


  //////////////////////////////////////////////////////////////////
  //
  // Variables
  //
  logic                                dbg_strb_i_dly,
                                       du_stall_dly,
                                       wb_dbg_dly;
				       
  logic [DBG_ADDR_SIZE-1:DU_ADDR_SIZE] du_bank_addr;
  logic                                du_sel_internal,
                                       du_sel_gprs,
                                       du_sel_csrs;
  logic [                         4:0] du_re_csrs;

  logic                                du_access,
                                       du_we;
  logic [                         2:0] du_ack;

  logic                                du_we_internal;
  logic [XLEN                    -1:0] du_internal_regs;

  dbg_struct                           dbg;
  logic                                bp_instr_hit,
                                       bp_branch_hit;
  logic [MAX_BREAKPOINTS         -1:0] bp_hit;

  logic                                mem_read,
                                       mem_write;


  logic [XLEN                    -1:0] dpc; //debug program counter


  genvar n;


  //////////////////////////////////////////////////////////////////
  //
  // Module Body
  //
  import riscv_state_pkg::*;

  /*
   * Debugger Interface
   */
  // Decode incoming address
  assign du_bank_addr    = dbg_addr_i[DBG_ADDR_SIZE-1:DU_ADDR_SIZE];
  assign du_sel_internal = du_bank_addr == DBG_INTERNAL;
  assign du_sel_gprs     = du_bank_addr == DBG_GPRS;
  assign du_sel_csrs     = du_bank_addr == DBG_CSRS;


  //generate 1 cycle pulse strobe
  always @(posedge clk_i)
    dbg_strb_i_dly <= dbg_strb_i;


  //generate (write) access signals
  assign du_access = (dbg_strb_i & dbg_stall_i) | (dbg_strb_i & du_sel_internal);
  assign du_we     = du_access & ~dbg_strb_i_dly & dbg_we_i;


  // generate ACK
  always @(posedge clk_i,negedge rst_ni)
    if      (!rst_ni    ) du_ack <= 'h0;
    else if (!ex_stall_i) du_ack <= {3{du_access & ~dbg_ack_o}} & {1'b1,du_ack[2:1]};

  assign dbg_ack_o = du_ack[0];


  //actual BreakPoint signal
  always @(posedge clk_i,negedge rst_ni)
    if (!rst_ni) dbg_bp_o <= 'b0;
    else         dbg_bp_o <= ~ex_stall_i & ~du_flush_o & ~st_flush_i & (|du_exceptions_i | |dbg.hit);


  /*
   * CPU Interface
   */
  // assign CPU signals
  assign du_stall_o    = dbg_stall_i;
  assign du_stall_if_o = dbg_stall_i | (|dbg.hit);
  

  always @(posedge clk_i,negedge rst_ni)
    if (!rst_ni) du_stall_dly <= 1'b0;
    else         du_stall_dly <= dbg_stall_i;


  always @(posedge clk_i,negedge rst_ni)
    if (!rst_ni) wb_dbg_dly <= 1'b0;
    else         wb_dbg_dly <= wb_insn_i.dbg;


  assign du_latch_nxt_pc_o =  dbg_stall_i   & ~du_stall_dly; //Latch nxt-pc address while entering debug
  assign du_flush_cache_o  =  wb_insn_i.dbg & ~wb_dbg_dly;   //flush cache when stall exits CPU pipeline (i.e. all pending instructions executed)
  assign du_flush_o        = ~dbg_stall_i   &  du_stall_dly; // & |du_exceptions_i; //flush upon debug exit. Maybe program memory contents changed


  always @(posedge clk_i)
  begin
      du_addr_o      <=  dbg_addr_i[DU_ADDR_SIZE-1:0];
      du_d_o         <=  dbg_d_i;

      du_we_rf_o     <=  du_we & du_sel_gprs & (dbg_addr_i[11:8] == 4'h0); //(dbg_addr_i[DU_ADDR_SIZE-1:0] == DBG_GPR);
      du_we_frf_o    <=  du_we & du_sel_gprs & (dbg_addr_i[11:8] == 4'h1); //(dbg_addr_i[DU_ADDR_SIZE-1:0] == DBG_FPR);
      du_we_internal <=  du_we & du_sel_internal;
      du_we_csr_o    <=  du_we & du_sel_csrs;
      du_we_pc_o     <=  du_we & du_sel_gprs & (dbg_addr_i[DU_ADDR_SIZE-1:0] == DBG_NPC);
  end

  assign du_re_csr_o = dbg_strb_i & du_sel_csrs;
  assign du_re_rf_o  = dbg_strb_i & du_sel_gprs & (dbg_addr_i[11:8] == 4'h0);
  

  // Return signals

  always_comb
    case (du_addr_o)
      DBG_CTRL   : du_internal_regs = { {XLEN- 2{1'b0}}, dbg.ctrl };
      DBG_HIT    : du_internal_regs = { {XLEN-16{1'b0}}, dbg.hit.bp_hit, 6'h0, dbg.hit.branch_break_hit, dbg.hit.instr_break_hit};
      DBG_IE     : du_internal_regs = { {XLEN-32{1'b0}}, dbg.ie};
      DBG_CAUSE  : du_internal_regs = { {XLEN-32{1'b0}}, dbg.cause};

      DBG_BPCTRL0: du_internal_regs = { {XLEN- 7{1'b0}}, dbg.bp[0].ctrl.cc, 2'h0, dbg.bp[0].ctrl.enabled, dbg.bp[0].ctrl.implemented};
      DBG_BPDATA0: du_internal_regs = dbg.bp[0].data;

      DBG_BPCTRL1: du_internal_regs = { {XLEN- 7{1'b0}}, dbg.bp[1].ctrl.cc, 2'h0, dbg.bp[1].ctrl.enabled, dbg.bp[1].ctrl.implemented};
      DBG_BPDATA1: du_internal_regs = dbg.bp[1].data;

      DBG_BPCTRL2: du_internal_regs = { {XLEN- 7{1'b0}}, dbg.bp[2].ctrl.cc, 2'h0, dbg.bp[2].ctrl.enabled, dbg.bp[2].ctrl.implemented};
      DBG_BPDATA2: du_internal_regs = dbg.bp[2].data;

      DBG_BPCTRL3: du_internal_regs = { {XLEN- 7{1'b0}}, dbg.bp[3].ctrl.cc, 2'h0, dbg.bp[3].ctrl.enabled, dbg.bp[3].ctrl.implemented};
      DBG_BPDATA3: du_internal_regs = dbg.bp[3].data;

      DBG_BPCTRL4: du_internal_regs = { {XLEN- 7{1'b0}}, dbg.bp[4].ctrl.cc, 2'h0, dbg.bp[4].ctrl.enabled, dbg.bp[4].ctrl.implemented};
      DBG_BPDATA4: du_internal_regs = dbg.bp[4].data;

      DBG_BPCTRL5: du_internal_regs = { {XLEN- 7{1'b0}}, dbg.bp[5].ctrl.cc, 2'h0, dbg.bp[5].ctrl.enabled, dbg.bp[5].ctrl.implemented};
      DBG_BPDATA5: du_internal_regs = dbg.bp[5].data;

      DBG_BPCTRL6: du_internal_regs = { {XLEN- 7{1'b0}}, dbg.bp[6].ctrl.cc, 2'h0, dbg.bp[6].ctrl.enabled, dbg.bp[6].ctrl.implemented};
      DBG_BPDATA6: du_internal_regs = dbg.bp[6].data;

      DBG_BPCTRL7: du_internal_regs = { {XLEN- 7{1'b0}}, dbg.bp[7].ctrl.cc, 2'h0, dbg.bp[7].ctrl.enabled, dbg.bp[7].ctrl.implemented};
      DBG_BPDATA7: du_internal_regs = dbg.bp[7].data;

      default    : du_internal_regs = 'h0;
    endcase

  always @(posedge clk_i)
    casex (dbg_addr_i)
       {DBG_INTERNAL,12'h???}: dbg_q_o <= du_internal_regs;
       {DBG_GPRS    ,DBG_GPR}: dbg_q_o <= du_rf_q_i;
       {DBG_GPRS    ,DBG_FPR}: dbg_q_o <= du_frf_q_i;
       {DBG_GPRS    ,DBG_NPC}: dbg_q_o <= if_nxt_pc_i;
       {DBG_GPRS    ,DBG_PPC}: dbg_q_o <= dpc;
       {DBG_CSRS    ,12'h???}: dbg_q_o <= st_csr_q_i;
       default               : dbg_q_o <= 'h0;
    endcase


  /*
   * Registers
   */

  //DBG CTRL
  always @(posedge clk_i,negedge rst_ni)
    if (!rst_ni)
    begin
        dbg.ctrl.instr_break_ena  <= 1'b0;
        dbg.ctrl.branch_break_ena <= 1'b0;
    end
    else if (du_we_internal && du_addr_o == DBG_CTRL)
    begin
        dbg.ctrl.instr_break_ena  <= du_d_o[0];
        dbg.ctrl.branch_break_ena <= du_d_o[1];
    end


  //DBG HIT
  always @(posedge clk_i,negedge rst_ni)
    if (!rst_ni)
    begin
        dbg.hit.instr_break_hit  <= 1'b0;
        dbg.hit.branch_break_hit <= 1'b0;
    end
    else if (du_we_internal && du_addr_o == DBG_HIT)
    begin
        dbg.hit.instr_break_hit  <= du_d_o[0];
        dbg.hit.branch_break_hit <= du_d_o[1];
    end
    else
    begin
        if (bp_instr_hit ) dbg.hit.instr_break_hit  <= 1'b1;
        if (bp_branch_hit) dbg.hit.branch_break_hit <= 1'b1;
    end

generate
for (n=0; n<MAX_BREAKPOINTS; n++)
begin: gen_bp_hits

  if (n < BREAKPOINTS)
  begin
      always @(posedge clk_i,negedge rst_ni)
        if      (!rst_ni                                ) dbg.hit.bp_hit[n] <= 1'b0;
        else if ( du_we_internal && du_addr_o == DBG_HIT) dbg.hit.bp_hit[n] <= du_d_o[n +4];
        else if ( bp_hit[n]                             ) dbg.hit.bp_hit[n] <= 1'b1;
  end
  else //n >= BREAKPOINTS
    assign dbg.hit.bp_hit[n] = 1'b0;

end
endgenerate


  //DBG PC
  //Stores the nxt_pc to execute
  //Debug Triggers are caught at different stages of the pipeline, thus need to
  //latch PC from different levels of the pipeline
  always @(posedge clk_i)
    if      (|du_exceptions_i) dpc <= wb_pc_i;
    else if ( bu_flush_i     ) dpc <= bu_nxt_pc_i; //when branch/jal(r) during single step
    else if ( bp_instr_hit   ) dpc <= if_nxt_pc_i;
    else if (|bp_hit         ) dpc <= id_pc_i;
    else if ( bp_branch_hit  ) dpc <= id_pc_i;
    else if ( du_latch_nxt_pc_o & ~|dbg.cause) dpc <= id_pc_i;


  //DBG IE
  always @(posedge clk_i,negedge rst_ni)
    if      (!rst_ni                               ) dbg.ie <= 'h0;
    else if ( du_we_internal && du_addr_o == DBG_IE) dbg.ie <= du_d_o[31:0];


  //send to Thread-State
  assign du_ie_o = dbg.ie;


  //DBG CAUSE
  always @(posedge clk_i,negedge rst_ni)
    if (!rst_ni)                                        dbg.cause <= 'h0;
    else if ( du_we_internal && du_addr_o == DBG_CAUSE) dbg.cause <= du_d_o;
    else if ( du_flush_o & ~|du_exceptions_i          ) dbg.cause <= 'h0;
    else if (|du_exceptions_i[15:0]) //traps
    begin
        casex (du_exceptions_i[15:0])
          16'b????_????_????_???1 : dbg.cause <=  0;
          16'b????_????_????_??10 : dbg.cause <=  1;
          16'b????_????_????_?100 : dbg.cause <=  2;
          16'b????_????_????_1000 : dbg.cause <=  3;
          16'b????_????_???1_0000 : dbg.cause <=  4;
          16'b????_????_??10_0000 : dbg.cause <=  5;
          16'b????_????_?100_0000 : dbg.cause <=  6;
          16'b????_????_1000_0000 : dbg.cause <=  7;
          16'b????_???1_0000_0000 : dbg.cause <=  8;
          16'b????_??10_0000_0000 : dbg.cause <=  9;
          16'b????_?100_0000_0000 : dbg.cause <= 10;
          16'b????_1000_0000_0000 : dbg.cause <= 11;
          16'b???1_0000_0000_0000 : dbg.cause <= 12;
          16'b??10_0000_0000_0000 : dbg.cause <= 13;
          16'b?100_0000_0000_0000 : dbg.cause <= 14;
          16'b1000_0000_0000_0000 : dbg.cause <= 15;
          default                 : dbg.cause <=  0;
        endcase
    end
    else if (|du_exceptions_i[31:16]) //Interrupts
    begin
        casex ( du_exceptions_i[31:16])
          16'b????_????_????_???1 : dbg.cause <= ('h1 << (XLEN-1)) |  0;
          16'b????_????_????_??10 : dbg.cause <= ('h1 << (XLEN-1)) |  1;
          16'b????_????_????_?100 : dbg.cause <= ('h1 << (XLEN-1)) |  2;
          16'b????_????_????_1000 : dbg.cause <= ('h1 << (XLEN-1)) |  3;
          16'b????_????_???1_0000 : dbg.cause <= ('h1 << (XLEN-1)) |  4;
          16'b????_????_??10_0000 : dbg.cause <= ('h1 << (XLEN-1)) |  5;
          16'b????_????_?100_0000 : dbg.cause <= ('h1 << (XLEN-1)) |  6;
          16'b????_????_1000_0000 : dbg.cause <= ('h1 << (XLEN-1)) |  7;
          16'b????_???1_0000_0000 : dbg.cause <= ('h1 << (XLEN-1)) |  8;
          16'b????_??10_0000_0000 : dbg.cause <= ('h1 << (XLEN-1)) |  9;
          16'b????_?100_0000_0000 : dbg.cause <= ('h1 << (XLEN-1)) | 10;
          16'b????_1000_0000_0000 : dbg.cause <= ('h1 << (XLEN-1)) | 11;
          16'b???1_0000_0000_0000 : dbg.cause <= ('h1 << (XLEN-1)) | 12;
          16'b??10_0000_0000_0000 : dbg.cause <= ('h1 << (XLEN-1)) | 13;
          16'b?100_0000_0000_0000 : dbg.cause <= ('h1 << (XLEN-1)) | 14;
          16'b1000_0000_0000_0000 : dbg.cause <= ('h1 << (XLEN-1)) | 15;
          default                 : dbg.cause <= ('h1 << (XLEN-1)) |  0;
        endcase
    end
   

  //DBG BPCTRL / DBG BPDATA
generate
for (n=0; n<MAX_BREAKPOINTS; n++)
begin: gen_bp

  if (n < BREAKPOINTS)
  begin
      assign dbg.bp[n].ctrl.implemented = 1'b1;

      always @(posedge clk_i,negedge rst_ni)
        if (!rst_ni)
        begin
            dbg.bp[n].ctrl.enabled <= 'b0;
            dbg.bp[n].ctrl.cc      <= 'h0;
        end
        else if (du_we_internal && du_addr_o == (DBG_BPCTRL0 + 2*n) )
        begin
            dbg.bp[n].ctrl.enabled <= du_d_o[1];
            dbg.bp[n].ctrl.cc      <= du_d_o[6:4];
        end

      always @(posedge clk_i,negedge rst_ni)
        if (!rst_ni) dbg.bp[n].data <= 'h0;
        else if (du_we_internal && du_addr_o == (DBG_BPDATA0 + 2*n) ) dbg.bp[n].data <= du_d_o;
  end
  else
  begin
      assign dbg.bp[n] = 'h0;
  end

end
endgenerate



  /*
   * BreakPoints
   *
   * Combinatorial generation of break-point hit logic
   * For actual registers see 'Registers' section
   */
  assign bp_instr_hit  = dbg.ctrl.instr_break_ena  & ~if_nxt_insn_i.bubble;
  assign bp_branch_hit = dbg.ctrl.branch_break_ena & ~if_insn_i.bubble & (if_insn_i.instr.R.opcode == OPC_BRANCH);

  //Memory access
  assign mem_read  = ~mem_exceptions_i.any & ~mem_insn_i.bubble & (mem_insn_i.instr.R.opcode == OPC_LOAD );
  assign mem_write = ~mem_exceptions_i.any & ~mem_insn_i.bubble & (mem_insn_i.instr.R.opcode == OPC_STORE);

generate
for (n=0; n<MAX_BREAKPOINTS; n++)
begin: gen_bp_hit

  if (n < BREAKPOINTS)
  begin: gen_hit_logic

      always_comb
        if (!dbg.bp[n].ctrl.enabled || !dbg.bp[n].ctrl.implemented) bp_hit[n] = 1'b0;
        else
          case (dbg.bp[n].ctrl.cc)
             BP_CTRL_CC_FETCH    : bp_hit[n] = (pd_pc_i      == dbg.bp[n].data) & ~bu_flush_i & ~st_flush_i;
             BP_CTRL_CC_LD_ADR   : bp_hit[n] = (mem_memadr_i == dbg.bp[n].data) & dmem_ack_i & mem_read;
             BP_CTRL_CC_ST_ADR   : bp_hit[n] = (mem_memadr_i == dbg.bp[n].data) & dmem_ack_i & mem_write;
             BP_CTRL_CC_LDST_ADR : bp_hit[n] = (mem_memadr_i == dbg.bp[n].data) & dmem_ack_i & (mem_read | mem_write);
/*
             BP_CTRL_CC_LD_ADR   : bp_hit[n] = (mem_adr == dbg.bp[n].data) & mem_req & ~mem_we;
             BP_CTRL_CC_ST_ADR   : bp_hit[n] = (mem_adr == dbg.bp[n].data) & mem_req &  mem_we;
             BP_CTRL_CC_LDST_ADR : bp_hit[n] = (mem_adr == dbg.bp[n].data) & mem_req;
*/
             default             : bp_hit[n] = 1'b0;
          endcase

  end
  else //n >= BREAKPOINTS
  begin
      assign bp_hit[n] = 1'b0;
  end

end
endgenerate

endmodule



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
//    Debug Unit                                               //
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

import riscv_opcodes_pkg::*;
import riscv_du_pkg::*;

module riscv_du #(
  parameter XLEN           = 32,
  parameter BREAKPOINTS    = 3
)
(
  input                           rstn,
  input                           clk,

   
  //Debug Port interface
  input                           dbg_stall,
  input                           dbg_strb,
  input                           dbg_we,
  input      [DBG_ADDR_SIZE -1:0] dbg_addr,
  input      [XLEN          -1:0] dbg_dati,
  output reg [XLEN          -1:0] dbg_dato,
  output reg                      dbg_ack,
  output reg                      dbg_bp,
  

  //CPU signals
  output                          du_stall,
  output reg                      du_stall_dly,
  output reg                      du_flush,
  output reg                      du_we_rf,
  output reg                      du_we_frf,
  output reg                      du_we_csr,
  output reg                      du_we_pc,
  output reg [DU_ADDR_SIZE  -1:0] du_addr,
  output reg [XLEN          -1:0] du_dato,
  output     [              31:0] du_ie,
  input      [XLEN          -1:0] du_dati_rf,
                                  du_dati_frf,
                                  st_csr_rval,
                                  if_pc,
                                  id_pc,
                                  ex_pc,
                                  bu_nxt_pc,
  input                           bu_flush,
                                  st_flush,

  input      [ILEN          -1:0] if_instr,
                                  mem_instr,
  input                           if_bubble,
                                  mem_bubble,
  input      [EXCEPTION_SIZE-1:0] mem_exception,
  input      [XLEN          -1:0] mem_memadr,
  input                           dmem_ack,
                                  ex_stall,
/*
                                  mem_req,
                                  mem_we,
  input      [XLEN          -1:0] mem_adr,
*/
  //From state
  input      [              31:0] du_exceptions
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
  logic                                dbg_strb_dly;
  logic [DBG_ADDR_SIZE-1:DU_ADDR_SIZE] du_bank_addr;
  logic                                du_sel_internal,
                                       du_sel_gprs,
                                       du_sel_csrs;
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
  assign du_bank_addr    = dbg_addr[DBG_ADDR_SIZE-1:DU_ADDR_SIZE];
  assign du_sel_internal = du_bank_addr == DBG_INTERNAL;
  assign du_sel_gprs     = du_bank_addr == DBG_GPRS;
  assign du_sel_csrs     = du_bank_addr == DBG_CSRS;


  //generate 1 cycle pulse strobe
  always @(posedge clk)
    dbg_strb_dly <= dbg_strb;


  //generate (write) access signals
  assign du_access = (dbg_strb & dbg_stall) | (dbg_strb & du_sel_internal);
  assign du_we     = du_access & ~dbg_strb_dly & dbg_we;


  // generate ACK
  always @(posedge clk,negedge rstn)
    if      (!rstn    ) du_ack <= 'h0;
    else if (!ex_stall) du_ack <= {3{du_access & ~dbg_ack}} & {1'b1,du_ack[2:1]};

  assign dbg_ack = du_ack[0];


  //actual BreakPoint signal
  always @(posedge clk,negedge rstn)
    if (!rstn) dbg_bp <= 'b0;
    else       dbg_bp <= ~ex_stall & ~du_stall & ~du_flush & ~bu_flush & ~st_flush & (|du_exceptions | |dbg.hit);


  /*
   * CPU Interface
   */
  // assign CPU signals
  assign du_stall = dbg_stall;

  always @(posedge clk,negedge rstn)
    if (!rstn) du_stall_dly <= 1'b0;
    else       du_stall_dly <= du_stall;

  assign du_flush = du_stall_dly & ~dbg_stall & |du_exceptions;


  always @(posedge clk)
  begin
      du_addr        <= dbg_addr[DU_ADDR_SIZE-1:0];
      du_dato        <= dbg_dati;

      du_we_rf       <= du_we & du_sel_gprs & (dbg_addr[DU_ADDR_SIZE-1:0] == DBG_GPR);
      du_we_frf      <= du_we & du_sel_gprs & (dbg_addr[DU_ADDR_SIZE-1:0] == DBG_FPR);
      du_we_internal <= du_we & du_sel_internal;
      du_we_csr      <= du_we & du_sel_csrs;
      du_we_pc       <= du_we & du_sel_gprs & (dbg_addr[DU_ADDR_SIZE-1:0] == DBG_NPC);
  end


  // Return signals

  always_comb
    case (du_addr)
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

  always @(posedge clk)
    casex (dbg_addr)
       {DBG_INTERNAL,12'h???}: dbg_dato <= du_internal_regs;
       {DBG_GPRS    ,DBG_GPR}: dbg_dato <= du_dati_rf;
       {DBG_GPRS    ,DBG_FPR}: dbg_dato <= du_dati_frf;
       {DBG_GPRS    ,DBG_NPC}: dbg_dato <= bu_flush ? bu_nxt_pc : id_pc;
       {DBG_GPRS    ,DBG_PPC}: dbg_dato <= ex_pc;
       {DBG_CSRS    ,12'h???}: dbg_dato <= st_csr_rval;
       default               : dbg_dato <= 'h0;
    endcase


  /*
   * Registers
   */

  //DBG CTRL
  always @(posedge clk,negedge rstn)
    if (!rstn)
    begin
        dbg.ctrl.instr_break_ena  <= 1'b0;
        dbg.ctrl.branch_break_ena <= 1'b0;
    end
    else if (du_we_internal && du_addr == DBG_CTRL)
    begin
        dbg.ctrl.instr_break_ena  <= du_dato[0];
        dbg.ctrl.branch_break_ena <= du_dato[1];
    end


  //DBG HIT
  always @(posedge clk,negedge rstn)
    if (!rstn)
    begin
        dbg.hit.instr_break_hit  <= 1'b0;
        dbg.hit.branch_break_hit <= 1'b0;
    end
    else if (du_we_internal && du_addr == DBG_HIT)
    begin
        dbg.hit.instr_break_hit  <= du_dato[0];
        dbg.hit.branch_break_hit <= du_dato[1];
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
      always @(posedge clk,negedge rstn)
        if      (!rstn                                ) dbg.hit.bp_hit[n] <= 1'b0;
        else if ( du_we_internal && du_addr == DBG_HIT) dbg.hit.bp_hit[n] <= du_dato[n +4];
        else if ( bp_hit[n]                           ) dbg.hit.bp_hit[n] <= 1'b1;
  end
  else //n >= BREAKPOINTS
    assign dbg.hit.bp_hit[n] = 1'b0;

end
endgenerate


  //DBG IE
  always @(posedge clk,negedge rstn)
    if      (!rstn                               ) dbg.ie <= 'h0;
    else if ( du_we_internal && du_addr == DBG_IE) dbg.ie <= du_dato[31:0];

  //send to Thread-State
  assign du_ie = dbg.ie;


  //DBG CAUSE
  always @(posedge clk,negedge rstn)
    if (!rstn)                                        dbg.cause <= 'h0;
    else if ( du_we_internal && du_addr == DBG_CAUSE) dbg.cause <= du_dato;
    else if (|du_exceptions[15:0]) //traps
    begin
        casex (du_exceptions[15:0])
          16'h???1 : dbg.cause <=  0;
          16'h???2 : dbg.cause <=  1;
          16'h???4 : dbg.cause <=  2;
          16'h???8 : dbg.cause <=  3;
          16'h??10 : dbg.cause <=  4;
          16'h??20 : dbg.cause <=  5;
          16'h??40 : dbg.cause <=  6;
          16'h??80 : dbg.cause <=  7;
          16'h?100 : dbg.cause <=  8;
          16'h?200 : dbg.cause <=  9;
          16'h?400 : dbg.cause <= 10;
          16'h?800 : dbg.cause <= 11;
          16'h1000 : dbg.cause <= 12;
          16'h2000 : dbg.cause <= 13;
          16'h4000 : dbg.cause <= 14;
          16'h8000 : dbg.cause <= 15;
          default  : dbg.cause <=  0;
        endcase
    end
    else if (|du_exceptions[31:16]) //Interrupts
    begin
        casex ( du_exceptions[31:16])
          16'h???1 : dbg.cause <= ('h1 << (XLEN-1)) |  0;
          16'h???2 : dbg.cause <= ('h1 << (XLEN-1)) |  1;
          16'h???4 : dbg.cause <= ('h1 << (XLEN-1)) |  2;
          16'h???8 : dbg.cause <= ('h1 << (XLEN-1)) |  3;
          16'h??10 : dbg.cause <= ('h1 << (XLEN-1)) |  4;
          16'h??20 : dbg.cause <= ('h1 << (XLEN-1)) |  5;
          16'h??40 : dbg.cause <= ('h1 << (XLEN-1)) |  6;
          16'h??80 : dbg.cause <= ('h1 << (XLEN-1)) |  7;
          16'h?100 : dbg.cause <= ('h1 << (XLEN-1)) |  8;
          16'h?200 : dbg.cause <= ('h1 << (XLEN-1)) |  9;
          16'h?400 : dbg.cause <= ('h1 << (XLEN-1)) | 10;
          16'h?800 : dbg.cause <= ('h1 << (XLEN-1)) | 11;
          16'h1000 : dbg.cause <= ('h1 << (XLEN-1)) | 12;
          16'h2000 : dbg.cause <= ('h1 << (XLEN-1)) | 13;
          16'h4000 : dbg.cause <= ('h1 << (XLEN-1)) | 14;
          16'h8000 : dbg.cause <= ('h1 << (XLEN-1)) | 15;
          default  : dbg.cause <= ('h1 << (XLEN-1)) |  0;
        endcase
    end
   

  //DBG BPCTRL / DBG BPDATA
generate
for (n=0; n<MAX_BREAKPOINTS; n++)
begin: gen_bp

  if (n < BREAKPOINTS)
  begin
      assign dbg.bp[n].ctrl.implemented = 1'b1;

      always @(posedge clk,negedge rstn)
        if (!rstn)
        begin
            dbg.bp[n].ctrl.enabled <= 'b0;
            dbg.bp[n].ctrl.cc      <= 'h0;
        end
        else if (du_we_internal && du_addr == (DBG_BPCTRL0 + 2*n) )
        begin
            dbg.bp[n].ctrl.enabled <= du_dato[1];
            dbg.bp[n].ctrl.cc      <= du_dato[6:4];
        end

      always @(posedge clk,negedge rstn)
        if (!rstn) dbg.bp[n].data <= 'h0;
        else if (du_we_internal && du_addr == (DBG_BPDATA0 + 2*n) ) dbg.bp[n].data <= du_dato;
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
  assign bp_instr_hit  = dbg.ctrl.instr_break_ena  & ~if_bubble;
  assign bp_branch_hit = dbg.ctrl.branch_break_ena & ~if_bubble & (if_instr[6:2] == OPC_BRANCH);

  //Memory access
  assign mem_read  = ~|mem_exception & ~mem_bubble & (mem_instr[6:2] == OPC_LOAD );
  assign mem_write = ~|mem_exception & ~mem_bubble & (mem_instr[6:2] == OPC_STORE);

generate
for (n=0; n<MAX_BREAKPOINTS; n++)
begin: gen_bp_hit

  if (n < BREAKPOINTS)
  begin: gen_hit_logic

      always_comb
        if (!dbg.bp[n].ctrl.enabled || !dbg.bp[n].ctrl.implemented) bp_hit[n] = 1'b0;
        else
          case (dbg.bp[n].ctrl.cc)
             BP_CTRL_CC_FETCH    : bp_hit[n] = (if_pc     == dbg.bp[n].data) & ~bu_flush & ~st_flush;
             BP_CTRL_CC_LD_ADR   : bp_hit[n] = (mem_memadr == dbg.bp[n].data) & dmem_ack & mem_read;
             BP_CTRL_CC_ST_ADR   : bp_hit[n] = (mem_memadr == dbg.bp[n].data) & dmem_ack & mem_write;
             BP_CTRL_CC_LDST_ADR : bp_hit[n] = (mem_memadr == dbg.bp[n].data) & dmem_ack & (mem_read | mem_write);
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



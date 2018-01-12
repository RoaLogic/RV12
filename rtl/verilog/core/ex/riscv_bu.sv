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
//    Branch Unit                                              //
//                                                             //
/////////////////////////////////////////////////////////////////
//                                                             //
//             Copyright (C) 2017 ROA Logic BV                 //
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

module riscv_bu #(
  parameter            XLEN           = 32,
  parameter            ILEN           = 32,
  parameter [XLEN-1:0] PC_INIT        = 'h200,
  parameter            EXCEPTION_SIZE = 12,
  parameter            BP_GLOBAL_BITS = 2,
  parameter            HAS_RVC        = 0
)
(
  input                           rstn,
  input                           clk,

  input                           ex_stall,
  input                           st_flush,

  //Program counter
  input      [XLEN          -1:0] id_pc,
  output reg [XLEN          -1:0] bu_nxt_pc,
  output reg                      bu_flush,
                                  bu_cacheflush,
  input      [               1:0] id_bp_predict,
  output reg [               1:0] bu_bp_predict,
  output reg [BP_GLOBAL_BITS-1:0] bu_bp_history,
  output reg                      bu_bp_btaken,
  output reg                      bu_bp_update,

  //Instruction
  input                           id_bubble,
  input      [ILEN          -1:0] id_instr,

  input      [EXCEPTION_SIZE-1:0] id_exception,
                                  ex_exception,
                                  mem_exception,
                                  wb_exception,
  output reg [EXCEPTION_SIZE-1:0] bu_exception,

  //from ID
  input      [XLEN          -1:0] opA,
                                  opB,

  //Debug Unit
  input                           du_stall,
                                  du_flush,
  input                           du_we_pc,
  input      [XLEN          -1:0] du_dato,
  input      [              31:0] du_ie
);
  ////////////////////////////////////////////////////////////////
  //
  // Variables
  //
  localparam SBITS=$clog2(XLEN);

  logic [             6:2] opcode;
  logic [             2:0] func3;
  logic [             6:0] func7;
  logic                    has_rvc;

  //Operand generation
  logic [XLEN        -1:0] immJ,
                           immB;

  //Branch controls
  logic                    pipeflush,
                           cacheflush,
                           btaken,
                           bp_update;
  logic [BP_GLOBAL_BITS:0] bp_history;
  logic [XLEN        -1:0] nxt_pc,
                           du_nxt_pc;
  logic                    du_we_pc_dly,
                           du_wrote_pc;

  ////////////////////////////////////////////////////////////////
  //
  // Module Body
  //
  import riscv_pkg::*;
  import riscv_state_pkg::*;


  /*
   * Instruction
   */
  assign func7  = id_instr[31:25];
  assign func3  = id_instr[14:12];
  assign opcode = id_instr[ 6: 2];

  assign has_rvc = (HAS_RVC !=  0);

  /*
   * Exceptions
   */
  always @(posedge clk, negedge rstn)
    if      (!rstn          ) bu_exception <= 'h0;
    else if (!ex_stall)
    begin
        if      ( bu_flush      || st_flush || 
                 |ex_exception  ||
                 |mem_exception ||
                 |wb_exception  ) bu_exception <= 'h0;
        else if (!du_stall      )
        begin
            bu_exception <= id_exception;

            casex ( {id_bubble,opcode} )
              {1'b0,OPC_JALR  } : bu_exception[CAUSE_MISALIGNED_INSTRUCTION] <= id_exception[CAUSE_MISALIGNED_INSTRUCTION] | has_rvc ? nxt_pc[0] : |nxt_pc[1:0];
              {1'b0,OPC_BRANCH} : bu_exception[CAUSE_MISALIGNED_INSTRUCTION] <= id_exception[CAUSE_MISALIGNED_INSTRUCTION] | has_rvc ? nxt_pc[0] : |nxt_pc[1:0];
              default           : bu_exception[CAUSE_MISALIGNED_INSTRUCTION] <= id_exception[CAUSE_MISALIGNED_INSTRUCTION];
            endcase
        end
    end


  /*
   * Decode Immediates
   */
  assign immJ = { {XLEN-20{id_instr[31]}},id_instr[19:12],id_instr[20],id_instr[30:25],id_instr[24:21],        1'b0 };
  assign immB = { {XLEN-12{id_instr[31]}},                id_instr[ 7],id_instr[30:25],id_instr[11: 8],        1'b0 };


  /*
   * Program Counter modifications
   * - Branches/JALR (JAL/JALR results handled by ALU)
   * - Exceptions
   * - Debug Unit NPC access
   */
  always @(posedge clk)
    du_we_pc_dly <= du_we_pc;

  always @(posedge clk,negedge rstn)
    if (!rstn) du_wrote_pc <= 1'b0;
    else       du_wrote_pc <= du_we_pc | (du_wrote_pc & du_stall);


  always @(posedge clk)
    if (du_we_pc) du_nxt_pc <= du_dato;


  always_comb 
    casex ( {id_bubble,func7,func3,opcode} )
      {1'b0,JAL    }: begin //This is really only for the debug unit, such that NPC points to the correct address
                          btaken     = 'b1;
                          bp_update  = 'b0;
                          pipeflush  = 'b0; //Handled in IF, do NOT flush here!!
                          cacheflush = 'b0;
                          nxt_pc     = id_pc + immJ;
                      end
      {1'b0,JALR   }: begin
                          btaken     = 'b1;
                          bp_update  = 'b0;
                          pipeflush  = 'b1;
                          cacheflush = 'b0;
                          nxt_pc     = (opA + opB) & { {XLEN-1{1'b1}},1'b0 };
                      end
      {1'b0,BEQ    }: begin
                          btaken     = (opA == opB);
                          bp_update  = 'b1;
                          pipeflush  = btaken ^ id_bp_predict[1];
                          cacheflush = 'b0;
                          nxt_pc     = btaken ? id_pc + immB : id_pc +'h4;
                      end
      {1'b0,BNE    }: begin
                          btaken     = (opA != opB);
                          bp_update  = 'b1;
                          pipeflush  = btaken ^ id_bp_predict[1];
                          cacheflush = 'b0;
                          nxt_pc     = btaken ? id_pc + immB : id_pc + 'h4;
                       end
      {1'b0,BLTU    }: begin
                           btaken     = (opA < opB);
                           bp_update  = 'b1;
                           pipeflush  = btaken ^ id_bp_predict[1];
                           cacheflush = 'b0;
                           nxt_pc     = btaken ? id_pc + immB : id_pc + 'h4;
                      end
      {1'b0,BGEU   }: begin
                          btaken     = (opA >= opB);
                          bp_update  = 'b1;
                          pipeflush  = btaken ^ id_bp_predict[1];
                          cacheflush = 'b0;
                          nxt_pc     = btaken ? id_pc + immB : id_pc +'h4;
                     end
      {1'b0,BLT   }: begin
                         btaken     = $signed(opA) <  $signed(opB); 
                         bp_update  = 'b1;
                         pipeflush  = btaken ^ id_bp_predict[1];
                         cacheflush = 'b0;
                         nxt_pc     = btaken ? id_pc + immB : id_pc + 'h4;
                      end
      {1'b0,BGE    }: begin
                          btaken     = $signed(opA) >= $signed(opB);
                          bp_update  = 'b1;
                          pipeflush  = btaken ^ id_bp_predict[1];
                          cacheflush = 'b0;
                          nxt_pc     = btaken ? id_pc + immB : id_pc + 'h4;
                      end
      {1'b0,MISCMEM}: case (id_instr)
                         FENCE_I: begin
                                      btaken     = 'b0;
                                      bp_update  = 'b0;
                                      pipeflush  = 'b1;
                                      cacheflush = 'b1;
                                      nxt_pc     = id_pc +'h4;
                                  end
                         default: begin
                                      btaken     = 'b0;
                                      bp_update  = 'b0;
                                      pipeflush  = 'b0;
                                      cacheflush = 'b0;
                                      nxt_pc     = id_pc + 'h4;
                                   end
                      endcase
      default       : begin
                          btaken     = 'b0;
                          bp_update  = 'b0;
                          pipeflush  = 'b0;
                          cacheflush = 'b0;
                          nxt_pc     = id_pc +'h4; //TODO: handle 16bit instructions
                      end
    endcase



  /*
   * Program Counter modifications (Branches/JALR)
   */
  always @(posedge clk, negedge rstn)
    if (!rstn)
    begin
        bu_flush      <= 'b1;
        bu_cacheflush <= 'b1;
        bu_nxt_pc     <= PC_INIT;

        bu_bp_predict <= 'b00;
        bu_bp_btaken  <= 'b0;
        bu_bp_update  <= 'b0;
        bp_history    <= 'h0;
    end
    else if (du_wrote_pc)
    begin
        bu_flush      <= du_we_pc_dly;
        bu_cacheflush <= 1'b0;
        bu_nxt_pc     <= du_nxt_pc;

        bu_bp_predict <= 'b00;
        bu_bp_btaken  <= 'b0;
        bu_bp_update  <= 'b0;
    end
    else
    begin
        bu_flush      <= (pipeflush & ~du_stall & ~du_flush);
        bu_cacheflush <= cacheflush;
        bu_nxt_pc     <= nxt_pc;

        bu_bp_predict <= id_bp_predict;
        bu_bp_btaken  <= btaken;
        bu_bp_update  <= bp_update;

        if (bp_update) bp_history <= {bp_history[BP_GLOBAL_BITS-1:0],btaken};
    end

  //don't take myself (current branch) into account when updating branch history
  assign bu_bp_history = bp_history[BP_GLOBAL_BITS:1];

endmodule 

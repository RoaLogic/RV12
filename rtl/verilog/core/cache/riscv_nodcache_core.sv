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
//    No-Instruction Cache Core Logic                          //
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

module riscv_nodcache_core #(
  parameter XLEN           = 32,
  parameter PHYS_ADDR_SIZE = XLEN, //MSB determines cacheable(0) and non-cacheable(1)
  parameter PARCEL_SIZE    = 32
)
(
  input                           rstn,
  input                           clk,
 
  //CPU side
  input      [XLEN          -1:0] mem_adr,
                                  mem_d,       //from CPU
  input                           mem_req,
                                  mem_we,
  input      [               2:0] mem_size,
  output reg [XLEN          -1:0] mem_q,       //to CPU
  output reg                      mem_ack,
  input                           bu_cacheflush,
  output                          dcflush_rdy,
  input      [               1:0] st_prv,

  //To BIU
  output reg                      biu_stb,
  input                           biu_stb_ack,
  output     [PHYS_ADDR_SIZE-1:0] biu_adri,
  input      [PHYS_ADDR_SIZE-1:0] biu_adro,
  output     [               2:0] biu_size,     //transfer size
  output reg [               2:0] biu_type,     //burst type -AHB style
  output                          biu_lock,
  output                          biu_we,
  output     [XLEN          -1:0] biu_di,
  input      [XLEN          -1:0] biu_do,
  input                           biu_wack,     //data acknowledge, 1 per data
                                  biu_rack,
  input                           biu_err,      //data error

  output                          biu_is_cacheable,
                                  biu_is_instruction,
  output     [               1:0] biu_prv
);

  //////////////////////////////////////////////////////////////////
  //
  // Constants
  //


  //////////////////////////////////////////////////////////////////
  //
  // Variables
  //
  enum logic [2:0] {IDLE=3'h0,WRITE=3'h1,WAIT4ACK=3'h2,READ=3'h4} state;

  logic              is_cacheable;

  logic              hold_mem_req;
  logic              hold_mem_we;
  logic [XLEN  -1:0] hold_mem_adr,
                     hold_mem_d;
  logic [       2:0] hold_mem_size;

  logic [       1:0] write_pending_cnt;


  //////////////////////////////////////////////////////////////////
  //
  // Module Body
  //

  //Is this a cacheable region?
  //MSB=1 non-cacheable (IO region)
  //MSB=0 cacheable (instruction/data region)
  assign is_cacheable = ~mem_adr[PHYS_ADDR_SIZE-1];


  //Data-Cache Flush ready? 
  assign dcflush_rdy = 1'b1;


  /*
   * Statemachine
   */
  always @(posedge clk)
    if (mem_req)
    begin
        hold_mem_we   <= mem_we;
        hold_mem_adr  <= mem_adr;
        hold_mem_d    <= mem_d;
        hold_mem_size <= mem_size;
    end


  always @(posedge clk)
    if (!rstn) hold_mem_req <= 1'b0;
    else       hold_mem_req <= (mem_req | hold_mem_req) & ~biu_stb_ack;


  always @(posedge clk,negedge rstn)
    if (!rstn) write_pending_cnt <= 'h0;
    else
      case ({biu_stb & biu_we,(biu_wack | biu_rack)})
         2'b10 : if (state == WRITE)
                 begin
                     if (biu_stb_ack) write_pending_cnt <= write_pending_cnt +1;
                 end
                 else                 write_pending_cnt <= write_pending_cnt +1;
         2'b01 : write_pending_cnt <= {$size(write_pending_cnt){|write_pending_cnt}} & (write_pending_cnt -1);
         default: ;
      endcase


  always @(posedge clk,negedge rstn)
    if   (!rstn)
    begin 
        state          <= IDLE;
        mem_ack        <= 1'b0;
        mem_q          <= 'h0;
    end
    else
    begin
        mem_ack        <= 1'b0;

        case (state)
          IDLE    : if ((mem_req || hold_mem_req) && biu_stb_ack)
                    begin
                        if (mem_we || (hold_mem_we & hold_mem_req))
                        begin
                            state   <= WRITE;
                            mem_ack <= biu_stb_ack;
                        end
                        else
                        begin
                            state <= READ;
                        end
                    end

          READ    : if (biu_rack)
                    begin
                        mem_ack <= 1'b1;
                        mem_q   <= biu_do;

                        //Read is blocking ... WRITE-after-READ or READ-after-READ (without IDLE) is impossible
                        state   <= IDLE;
                    end

          WRITE   : if (mem_req || hold_mem_req)
                    begin
                        if ((hold_mem_req && hold_mem_we) || (!hold_mem_req && mem_req && mem_we))
                        begin
                            state   <= WRITE; //stay in WRITE state
                            mem_ack <= biu_stb_ack;
                        end
                        else
                        begin
                            //Can we move to READ state or must we wait for biu_wack?
                            if (write_pending_cnt==1 && biu_wack) state <= READ;
                            else                                  state <= WAIT4ACK;
                        end
                    end
                    else if (biu_wack) //wait for WRITE to complete
                    begin
                        state <= IDLE;
                    end

          //avoid triggering the READ state on the pending write's biu_wack
          WAIT4ACK: if (write_pending_cnt==1 && biu_wack) state <= READ;
        endcase
    end


  /*
   * External Interface
   */
  always_comb
    case (state)
      READ    : biu_stb = (mem_req | hold_mem_req) & (biu_wack | biu_rack);
      WRITE   : biu_stb = (mem_req | hold_mem_req);
      WAIT4ACK: biu_stb = (mem_req | hold_mem_req); //actually only the hold_mem_ parts ...
      default : biu_stb = mem_req | hold_mem_req;
    endcase

  assign biu_adri  = hold_mem_req ? hold_mem_adr  : mem_adr;
  assign biu_be    = hold_mem_req ? hold_mem_size : mem_size;
  assign biu_lock  = 1'b0;
  assign biu_we    = hold_mem_req ? hold_mem_we   : mem_we;
  assign biu_di    = hold_mem_req ? hold_mem_d    : mem_d;
  assign biu_type  = 3'h0; //single access


  //Data cache..
  assign biu_is_instruction = 1'b0; //Data cache
  assign biu_is_cacheable   = is_cacheable;
  assign biu_prv            = st_prv;

endmodule



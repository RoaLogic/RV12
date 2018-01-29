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
//    Write Buffer                                             //
//                                                             //
/////////////////////////////////////////////////////////////////
//                                                             //
//             Copyright (C) 2016-2017 ROA Logic BV            //
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

module riscv_wbuf #(
  parameter XLEN  = 32,
  parameter DEPTH = 8
)
(
  input                           rstn,
  input                           clk,
 
  //CPU side
  input      [XLEN          -1:0] mem_adr,
                                  mem_d,       //from CPU
  input                           mem_req,
                                  mem_we,
  input      [XLEN/8        -1:0] mem_be,
  output reg [XLEN          -1:0] mem_q,       //to CPU
  output reg                      mem_ack,
  input                           bu_cacheflush,
  input      [               1:0] st_prv,


  //To Cache Controller
  output                          cache_req,     //cache-section memory request
  output [XLEN              -1:0] cache_adr,     //cache-section memory address
  output                          cache_we,      //cache-section write enable
  output [XLEN              -1:0] cache_d,       //cache-section write data
  output [XLEN/8            -1:0] cache_be,      //cache-section byte enable
  output [                   1:0] cache_prv,
  output                          cache_flush,
  input  [XLEN              -1:0] cache_q,
  input                           cache_ack
);

  //////////////////////////////////////////////////////////////////
  //
  // Constants
  //
  localparam FIFO_DEPTH = 2**$clog2(DEPTH);


  //////////////////////////////////////////////////////////////////
  //
  // Functions
  //


  //////////////////////////////////////////////////////////////////
  //
  // Typedefs
  //
  typedef struct packed {
    logic [XLEN  -1:0] addr;
    logic [XLEN-  1:0] data;
    logic [XLEN/8-1:0] be;
    logic              we;
    logic              acked; //already acknowledged?
    logic [       1:0] priv;  //privilege level
    logic              flush; //forward flush request to cache
  } fifo_struct;


  //////////////////////////////////////////////////////////////////
  //
  // Variables
  //
  genvar  way;
  integer n;

  /*
   * Input section
   */
  fifo_struct                    fifo_data[FIFO_DEPTH];
  logic [$clog2(FIFO_DEPTH)-1:0] fifo_wadr;
  logic                          fifo_we,
                                 fifo_re,
                                 fifo_empty,
                                 fifo_full;

  logic                          we_ack;
  logic                          mem_we_ack;

  logic [$clog2(FIFO_DEPTH)-1:0] pending_cnt;

  logic                          access_pending;
  logic                          read_pending;
  logic                          cache_we_dly;


  //////////////////////////////////////////////////////////////////
  //
  // Module Body
  //

  /*
   * Memory Access Fifo -- This is the write buffer
   *
   * Dont block writes (holds multiple writes)
   * Block reads (holds 1 read)
   *
   * mem_ack immediately when write, upon transfer complete when read
   */

  always @(posedge clk,negedge rstn)
    if (!rstn) fifo_wadr <= 'h0;
    else
      case ({fifo_we,fifo_re})
         2'b01  : fifo_wadr <= fifo_wadr -1;
         2'b10  : fifo_wadr <= fifo_wadr +1;
         default: ;
      endcase


  always @(posedge clk,negedge rstn)
    if (!rstn)
      for (n=0;n<FIFO_DEPTH;n++) fifo_data[n] <= 'h0;
    else
    case ({fifo_we,fifo_re})
       2'b01  : begin
                    for (n=0;n<FIFO_DEPTH-1;n++)
                      fifo_data[n] <= fifo_data[n+1];

                    fifo_data[FIFO_DEPTH-1] <= 'h0;
                end
       2'b10  : fifo_data[fifo_wadr] <= {mem_adr,mem_d,mem_be,mem_we,we_ack,st_prv,bu_cacheflush};
       2'b11  : begin
                    for (n=0;n<FIFO_DEPTH-1;n++)
                      fifo_data[n] <= fifo_data[n+1];

                    fifo_data[FIFO_DEPTH-1] <= 'h0;

                    fifo_data[fifo_wadr-1] <= {mem_adr,mem_d,mem_be,mem_we,we_ack,st_prv,bu_cacheflush};
                end
       default: ;
    endcase


  always @(posedge clk,negedge rstn)
    if (!rstn) fifo_full <= 1'b0;
    else
      case ({fifo_we,fifo_re})
         2'b01  : fifo_full <= 1'b0;
         2'b10  : fifo_full <= &fifo_wadr;
         default: ;
      endcase

  always @(posedge clk,negedge rstn)
    if (!rstn) fifo_empty <= 1'b1;
    else
      case ({fifo_we,fifo_re})
         2'b01  : fifo_empty <= ~|fifo_wadr[$clog2(FIFO_DEPTH)-1:1] & fifo_wadr[0]; //--> fifo_wadr == 1
         2'b10  : fifo_empty <= 1'b0;
         default: ;
      endcase


  /*
   * Control signals
   */
  always @(posedge clk,negedge rstn)
    if (!rstn) read_pending <= 1'b0;
    else       read_pending <= (read_pending & ~mem_ack) | (mem_req & ~mem_we);


  assign we_ack = mem_req & mem_we & ~read_pending;

  always @(posedge clk)
    mem_we_ack  <= we_ack;


  assign mem_q   = cache_q;

  assign mem_ack = (~fifo_full &  mem_we_ack                          ) |
                   ( fifo_full &  fifo_re & fifo_data[FIFO_DEPTH-1].we) |
                   ( cache_ack & ~fifo_data[0].acked                  ) ; //~cache_we_dly                       );


  /*
   Write to FIFO when
   - access pending
   - pending accesses in FIFO
   - bu_cacheflush (use FIFO to ensure cache-flush arrives in-order at the cache)
   otherwise, pass through to cache-section
   */

  always @(posedge clk,negedge rstn)
    if (!rstn) pending_cnt <= 'h0;
    else
      case ({mem_req,cache_ack})
        2'b10  : pending_cnt <= pending_cnt +1;
        2'b01  : pending_cnt <= pending_cnt -1;
        default: ;
      endcase


  assign fifo_we = access_pending &( (mem_req & ~(fifo_empty & cache_ack)) );
  assign fifo_re = cache_ack & ~fifo_empty;                                   //ACK from cache section


  always @(posedge clk, negedge rstn)
    if (!rstn) access_pending <= 1'b0;
    else       access_pending <= cache_req | (access_pending & ~cache_ack);


  assign cache_req   = ~access_pending ? mem_req 
                                       : (mem_req | ~fifo_empty) & cache_ack;
  assign cache_adr   = ~fifo_empty ? fifo_data[0].addr  : mem_adr;
  assign cache_we    = ~fifo_empty ? fifo_data[0].we    : mem_we;
  assign cache_be    = ~fifo_empty ? fifo_data[0].be    : mem_be;
  assign cache_d     = ~fifo_empty ? fifo_data[0].data  : mem_d;

  assign cache_prv   = ~fifo_empty ? fifo_data[0].priv  : st_prv;
  assign cache_flush = ~fifo_empty ? fifo_data[0].flush : bu_cacheflush;


  always @(posedge clk)
    if (cache_req) cache_we_dly <= cache_we;
endmodule


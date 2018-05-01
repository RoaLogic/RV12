/////////////////////////////////////////////////////////////////////
//   ,------.                    ,--.                ,--.          //
//   |  .--. ' ,---.  ,--,--.    |  |    ,---. ,---. `--' ,---.    //
//   |  '--'.'| .-. |' ,-.  |    |  |   | .-. | .-. |,--.| .--'    //
//   |  |\  \ ' '-' '\ '-'  |    |  '--.' '-' ' '-' ||  |\ `--.    //
//   `--' '--' `---'  `--`--'    `-----' `---' `-   /`--' `---'    //
//                                             `---'               //
//    RISC-V                                                       //
//    Write Buffer                                                 //
//                                                                 //
/////////////////////////////////////////////////////////////////////
//                                                                 //
//             Copyright (C) 2016-2018 ROA Logic BV                //
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


module riscv_wbuf #(
  parameter XLEN  = 32,
  parameter DEPTH = 8
)
(
  input                    rst_ni,
  input                    clk_i,
 
  //Downstream
  input                    mem_req_i,
  input      [XLEN   -1:0] mem_adr_i,
  input  biu_size_t        mem_size_i,
  input  biu_type_t        mem_type_i,
  input                    mem_lock_i,
  input  biu_prot_t        mem_prot_i,
  input                    mem_we_i,
  input      [XLEN   -1:0] mem_d_i,
  output reg [XLEN   -1:0] mem_q_o,
  output reg               mem_ack_o,
                           mem_err_o,
  input                    cacheflush_i,


  //Upstream
  output                   mem_req_o,     //memory request
  output     [XLEN   -1:0] mem_adr_o,     //memory address
  output biu_size_t        mem_size_o,    //transfer size
  output biu_type_t        mem_type_o,    //burst type
  output                   mem_lock_o,
  output biu_prot_t        mem_prot_o,
  output                   mem_we_o,      //write enable
  output     [XLEN   -1:0] mem_d_o,       //write data
  input      [XLEN   -1:0] mem_q_i,       //read data
  input                    mem_ack_i,
                           mem_err_i,
  output                   cacheflush_o
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
    biu_size_t         size;
    biu_type_t         burst_type;
    logic              lock;
    biu_prot_t         prot;
    logic              we;
    logic              acked;     //already acknowledged?
    logic              flush;     //forward flush request to cache
  } fifo_struct;


  //////////////////////////////////////////////////////////////////
  //
  // Variables
  //
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

  logic                          access_pending;
  logic                          read_pending;
  logic                          mem_we_o_dly;


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

  always @(posedge clk_i,negedge rst_ni)
    if (!rst_ni) fifo_wadr <= 'h0;
    else
      case ({fifo_we,fifo_re})
         2'b01  : fifo_wadr <= fifo_wadr -1;
         2'b10  : fifo_wadr <= fifo_wadr +1;
         default: ;
      endcase


  always @(posedge clk_i,negedge rst_ni)
    if (!rst_ni)
      for (n=0;n<FIFO_DEPTH;n++) fifo_data[n] <= 'h0;
    else
    case ({fifo_we,fifo_re})
       2'b01  : begin
                    for (n=0;n<FIFO_DEPTH-1;n++)
                      fifo_data[n] <= fifo_data[n+1];

                    fifo_data[FIFO_DEPTH-1] <= 'h0;
                end
       2'b10  : fifo_data[fifo_wadr] <= {mem_adr_i,
                                         mem_d_i,
                                         mem_size_i,
                                         mem_type_i,
                                         mem_lock_i,
                                         mem_prot_i,
                                         mem_we_i,
                                         we_ack,      //locally generated
                                         cacheflush_i};
       2'b11  : begin
                    for (n=0;n<FIFO_DEPTH-1;n++)
                      fifo_data[n] <= fifo_data[n+1];

                    fifo_data[FIFO_DEPTH-1] <= 'h0;

                    fifo_data[fifo_wadr-1] <= {mem_adr_i,
                                               mem_d_i,
                                               mem_size_i,
                                               mem_type_i,
                                               mem_lock_i,
                                               mem_prot_i,
                                               mem_we_i,
                                               we_ack,    //locally generated
                                               cacheflush_i};
                end
       default: ;
    endcase


  always @(posedge clk_i,negedge rst_ni)
    if (!rst_ni)  fifo_full <= 1'b0;
    else
      case ({fifo_we,fifo_re})
         2'b01  : fifo_full <= 1'b0;
         2'b10  : fifo_full <= &fifo_wadr;
         default: ;
      endcase

  always @(posedge clk_i,negedge rst_ni)
    if (!rst_ni)  fifo_empty <= 1'b1;
    else
      case ({fifo_we,fifo_re})
         2'b01  : fifo_empty <= ~|fifo_wadr[$clog2(FIFO_DEPTH)-1:1] & fifo_wadr[0]; //--> fifo_wadr == 1
         2'b10  : fifo_empty <= 1'b0;
         default: ;
      endcase


  /*
   * Control signals
   */
  always @(posedge clk_i,negedge rst_ni)
    if (!rst_ni) read_pending <= 1'b0;
    else         read_pending <= (read_pending & ~mem_ack_o) | (mem_req_i & ~mem_we_i);


  assign we_ack = mem_req_i & mem_we_i & ~read_pending;

  always @(posedge clk_i)
    mem_we_ack  <= we_ack;


  assign mem_q_o   = mem_q_i; //pass read data through

  assign mem_ack_o = (~fifo_full &  mem_we_ack                          ) |
                     ( fifo_full &  fifo_re & fifo_data[FIFO_DEPTH-1].we) |
                     ( mem_ack_i & ~fifo_data[0].acked                  ) ;


  /*
   Write to FIFO when
   - access pending
   - pending accesses in FIFO
   - cacheflush (use FIFO to ensure cache-flush arrives in-order at the cache)
   otherwise, pass through to cache-section
   */
  assign fifo_we = access_pending & ( (mem_req_i & ~(fifo_empty & mem_ack_i)) );
  assign fifo_re = mem_ack_i & ~fifo_empty;                                     //ACK from cache section


  always @(posedge clk_i, negedge rst_ni)
    if (!rst_ni) access_pending <= 1'b0;
    else         access_pending <= mem_req_o | (access_pending & ~mem_ack_i);


  assign mem_req_o   = ~access_pending ?  mem_req_i 
                                       : (mem_req_i | ~fifo_empty) & mem_ack_i;
  assign mem_adr_o    = ~fifo_empty ? fifo_data[0].addr       : mem_adr_i;
  assign mem_size_o   = ~fifo_empty ? fifo_data[0].size       : mem_size_i;
  assign mem_type_o   = ~fifo_empty ? fifo_data[0].burst_type : mem_type_i;
  assign mem_lock_o   = ~fifo_empty ? fifo_data[0].lock       : mem_lock_i;
  assign mem_prot_o   = ~fifo_empty ? fifo_data[0].prot       : mem_prot_i;
  assign mem_we_o     = ~fifo_empty ? fifo_data[0].we         : mem_we_i;
  assign mem_d_o      = ~fifo_empty ? fifo_data[0].data       : mem_d_i;

  assign cacheflush_o = ~fifo_empty ? fifo_data[0].flush      : cacheflush_i;


  always @(posedge clk_i)
    if (mem_req_o) mem_we_o_dly <= mem_we_o;
endmodule


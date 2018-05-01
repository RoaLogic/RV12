/////////////////////////////////////////////////////////////////////
//   ,------.                    ,--.                ,--.          //
//   |  .--. ' ,---.  ,--,--.    |  |    ,---. ,---. `--' ,---.    //
//   |  '--'.'| .-. |' ,-.  |    |  |   | .-. | .-. |,--.| .--'    //
//   |  |\  \ ' '-' '\ '-'  |    |  '--.' '-' ' '-' ||  |\ `--.    //
//   `--' '--' `---'  `--`--'    `-----' `---' `-   /`--' `---'    //
//                                             `---'               //
//    RISC-V                                                       //
//    Memory Access Mux                                            //
//                                                                 //
/////////////////////////////////////////////////////////////////////
//                                                                 //
//             Copyright (C) 2018 ROA Logic BV                     //
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
 * Memory Access Multiplexer
 * This really is a queue of in-flight accesses
 * Access order is maintained
 */

import biu_constants_pkg::*;

module riscv_mem_mux #(
  parameter ADDR_SIZE   = 32,
  parameter DATA_SIZE   = 32,
  parameter PORTS       = 2,
  parameter QUEUE_DEPTH = 2,

  //Port select size
  parameter PORT_SIZE = PORTS==1 ? 1 : $clog2(PORTS)
)
(
  input                      rst_ni,
  input                      clk_i,
 
  //Input Port
  input      [PORT_SIZE-1:0] mem_psel_i,         //select output port
  input                      mem_req_i,          //memory access request
  input      [ADDR_SIZE-1:0] mem_adr_i,          //memory access start address
  input  biu_size_t          mem_size_i,         //memory access data size
  input  biu_type_t          mem_type_i,         //memory access burst type
  input                      mem_lock_i,         //memory access locked access
  input  biu_prot_t          mem_prot_i,         //memory access protection
  input                      mem_we_i,           //memory access write enable
  input      [DATA_SIZE-1:0] mem_d_i,            //memory access write data
  output     [DATA_SIZE-1:0] mem_q_o,            //memory access read data
  output                     mem_ack_o,          //memory access acknowledge
                             mem_err_o,          //memory access error

  //Output (to memories)
  output                     mem_req_o  [PORTS], //memory access request
  output     [ADDR_SIZE-1:0] mem_adr_o  [PORTS], //memory access start address
  output biu_size_t          mem_size_o [PORTS], //memory access data size
  output biu_type_t          mem_type_o [PORTS], //memory access burst type
  output                     mem_lock_o [PORTS], //memory access locked access
  output biu_prot_t          mem_prot_o [PORTS], //memory access protection
  output                     mem_we_o   [PORTS], //memory access write enable
  output     [DATA_SIZE-1:0] mem_d_o    [PORTS], //memory access write data
  input      [DATA_SIZE-1:0] mem_q_i    [PORTS], //memory access read data
  input                      mem_ack_i  [PORTS], //memory access acknowledge
                             mem_err_i  [PORTS]  //memory access error
);
  //////////////////////////////////////////////////////////////////
  //
  // Typedefs
  //
  typedef struct packed {
    logic [ADDR_SIZE-1:0] addr;
    biu_size_t            size;
    biu_type_t            burst_type; //'type' is a reserved word
    logic                 lock;
    biu_prot_t            prot;
    logic                 we;
    logic [DATA_SIZE-1:0] data;
    logic [PORT_SIZE-1:0] port;      //Which port is addressed?
  } queue_struct;


  //////////////////////////////////////////////////////////////////
  //
  // Functions
  //
  function automatic bor;
    input a [PORTS];

    bor = 1'b0;

    for (int p=0; p < PORTS; p++)
      bor |= a[p];
  endfunction: bor


  //////////////////////////////////////////////////////////////////
  //
  // Variables
  //

  /* Queue
   */
  queue_struct                    queue_data[QUEUE_DEPTH];
  logic [$clog2(QUEUE_DEPTH)-1:0] queue_wadr;
  logic                           queue_we,
                                  queue_re,
                                  queue_empty,
                                  queue_full;

  logic                           access_pending;

  logic [PORT_SIZE          -1:0] port_select,
                                  response_select;

  int n;
  genvar p;


  //////////////////////////////////////////////////////////////////
  //
  // Module Body
  //

  /* Queue
   */
  always @(posedge clk_i,negedge rst_ni)
    if (!rst_ni) queue_wadr <= 'h0;
    else
      case ({queue_we,queue_re})
         2'b01  : queue_wadr <= queue_wadr -1;
         2'b10  : queue_wadr <= queue_wadr +1;
         default: ;
      endcase


  always @(posedge clk_i,negedge rst_ni)
    if (!rst_ni)
      for (n=0;n<QUEUE_DEPTH;n++) queue_data[n] <= 'h0;
    else
    case ({queue_we,queue_re})
       2'b01  : begin
                    for (n=0;n<QUEUE_DEPTH-1;n++)
                      queue_data[n] <= queue_data[n+1];

                    queue_data[QUEUE_DEPTH-1] <= 'h0;
                end

       2'b10  : begin
                    queue_data[queue_wadr].addr       <= mem_adr_i;
                    queue_data[queue_wadr].size       <= mem_size_i;
                    queue_data[queue_wadr].burst_type <= mem_type_i;
                    queue_data[queue_wadr].lock       <= mem_lock_i;
                    queue_data[queue_wadr].prot       <= mem_prot_i;
                    queue_data[queue_wadr].we         <= mem_we_i;
                    queue_data[queue_wadr].data       <= mem_d_i;
                    queue_data[queue_wadr].port       <= mem_psel_i;
                end

       2'b11  : begin
                    for (n=0;n<QUEUE_DEPTH-1;n++)
                      queue_data[n] <= queue_data[n+1];

                    queue_data[QUEUE_DEPTH-1] <= 'h0;

                    queue_data[queue_wadr-1].addr       <= mem_adr_i;
                    queue_data[queue_wadr-1].size       <= mem_size_i;
                    queue_data[queue_wadr-1].burst_type <= mem_type_i;
                    queue_data[queue_wadr-1].lock       <= mem_lock_i;
                    queue_data[queue_wadr-1].prot       <= mem_prot_i;
                    queue_data[queue_wadr-1].we         <= mem_we_i;
                    queue_data[queue_wadr-1].data       <= mem_d_i;
                    queue_data[queue_wadr-1].port       <= mem_psel_i;
                end
       default: ;
    endcase


  always @(posedge clk_i, negedge rst_ni)
    if (!rst_ni) queue_full <= 1'b0;
    else
      case ({queue_we,queue_re})
         2'b01  : queue_full <= 1'b0;
         2'b10  : queue_full <= &queue_wadr;
         default: ;
      endcase

  always @(posedge clk_i, negedge rst_ni)
    if (!rst_ni) queue_empty <= 1'b1;
    else
      case ({queue_we,queue_re})
         2'b01  : queue_empty <= (queue_wadr == 1);
         2'b10  : queue_empty <= 1'b0;
         default: ;
      endcase



  /* Control signals
   */
  always @(posedge clk_i, negedge rst_ni)
    if (!rst_ni) access_pending <= 1'b0;
    else         access_pending <= bor(mem_req_o) | (access_pending & ~mem_ack_o);


  assign queue_we = access_pending & (mem_req_i & ~(queue_empty & mem_ack_o));
  assign queue_re = mem_ack_o & ~queue_empty;


  /* generate memory access signals
   */
  assign port_select = queue_empty ? mem_psel_i : queue_data[0].port;

  always @(posedge clk_i)
    if (bor(mem_req_o)) response_select <= port_select;


generate
  for (p=0; p < PORTS; p++)
  begin: gen_ports
      //generate memory request signals
      assign mem_req_o  [p] = (port_select == p) &
                              (~access_pending ?  mem_req_i 
                                               : (mem_req_i | ~queue_empty) & mem_ack_o);

      //simply forward other signals
      assign mem_adr_o  [p] = queue_empty ? mem_adr_i  : queue_data[0].addr;
      assign mem_size_o [p] = queue_empty ? mem_size_i : queue_data[0].size;
      assign mem_type_o [p] = queue_empty ? mem_type_i : queue_data[0].burst_type;
      assign mem_lock_o [p] = queue_empty ? mem_lock_i : queue_data[0].lock;
      assign mem_prot_o [p] = queue_empty ? mem_prot_i : queue_data[0].prot;
      assign mem_we_o   [p] = queue_empty ? mem_we_i   : queue_data[0].we;
      assign mem_d_o    [p] = queue_empty ? mem_d_i    : queue_data[0].data;
  end
endgenerate


  /* Decode MEM ports
   */
  assign mem_q_o   = mem_q_i[ response_select ];
  assign mem_ack_o = bor(mem_ack_i);
  assign mem_err_o = bor(mem_err_i);
endmodule

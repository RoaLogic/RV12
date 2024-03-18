/////////////////////////////////////////////////////////////////////
//   ,------.                    ,--.                ,--.          //
//   |  .--. ' ,---.  ,--,--.    |  |    ,---. ,---. `--' ,---.    //
//   |  '--'.'| .-. |' ,-.  |    |  |   | .-. | .-. |,--.| .--'    //
//   |  |\  \ ' '-' '\ '-'  |    |  '--.' '-' ' '-' ||  |\ `--.    //
//   `--' '--' `---'  `--`--'    `-----' `---' `-   /`--' `---'    //
//                                             `---'               //
//    RISC-V                                                       //
//    Parcel Queue                                                 //
//                                                                 //
/////////////////////////////////////////////////////////////////////
//                                                                 //
//             Copyright (C) 2021 ROA Logic BV                     //
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

/* Parcel Queue
 * BIU pushes 16bit parcels and status signals into the queue
 * The parcel_valid vector indicates where valid parcels start.
 * This allows for offset parcels; e.g. due to 16b reads on 32b bus
 *
 * The instruction fetch unit pulls parcels from the queue, typically
 * one (16bit) or 2 (32bit) at a time
 *
 * The max number of parcels to push and pull is limited to 8 (128bits)
 *
 * 'almost_empty_o' is a user configurable 'empty' signal.
 * 'almost_full_o' is a user configurable 'full' signal.
 * Their thresholds are set by the ALMOST_EMPTY/FULL_THRESHOLD parameters
 *
 * ATTENTION: All output signals must be validated with empty_o
 */

module riscv_parcel_queue
import riscv_opcodes_pkg::*;
#(
  parameter DEPTH                   = 2,    //number of parcels
  parameter WR_PARCELS              = 2,    //push max <n> parcels onto queue
  parameter RD_PARCELS              = 2,    //pull max <n> parcels from queue
  parameter ALMOST_EMPTY_THRESHOLD  = 0,
  parameter ALMOST_FULL_THRESHOLD   = DEPTH,

  localparam PARCEL_SIZE            = 16,
  localparam WR_PARCEL_BITS         = WR_PARCELS * PARCEL_SIZE,
  localparam RD_PARCEL_BITS         = RD_PARCELS * PARCEL_SIZE
)
(
  input  logic                        rst_ni,         //asynchronous, active low reset
  input  logic                        clk_i,          //rising edge triggered clock

  input  logic                        flush_i,        //flush all queue entries

  //Queue Write
  input  logic [WR_PARCEL_BITS  -1:0] parcel_i,
  input  logic [WR_PARCELS      -1:0] parcel_valid_i, //parcel_valid has 1 valid bit per parcel
  input  logic                        parcel_misaligned_i,
  input  logic                        parcel_page_fault_i,
  input  logic                        parcel_error_i,

  //Queue Read
  input  logic [$clog2(RD_PARCELS):0] parcel_rd_i,    //read <n> consecutive parcels
  output logic [RD_PARCEL_BITS  -1:0] parcel_q_o,
  output logic                        parcel_misaligned_o,
  output logic                        parcel_page_fault_o,
  output logic                        parcel_error_o,

  //Status signals
  output logic                        empty_o,        //Queue is empty
                                      full_o,         //Queue is full
                                      almost_empty_o, //Programmable almost empty
                                      almost_full_o   //Programmable almost full
);

  //////////////////////////////////////////////////////////////////
  //
  // Constants
  //
  localparam EMPTY_THRESHOLD = 1;
  localparam FULL_THRESHOLD  = DEPTH - WR_PARCELS;
  localparam ALMOST_EMPTY_THRESHOLD_CHECK = ALMOST_EMPTY_THRESHOLD <= 0     ? EMPTY_THRESHOLD : ALMOST_EMPTY_THRESHOLD +1;
  localparam ALMOST_FULL_THRESHOLD_CHECK  = ALMOST_FULL_THRESHOLD  >= DEPTH ? FULL_THRESHOLD  : ALMOST_FULL_THRESHOLD -2;

  //////////////////////////////////////////////////////////////////
  //
  // Functions
  //
  function logic [$clog2(WR_PARCELS):0] align_cnt (input [WR_PARCELS-1:0] a);
    bit found_one;

    found_one = 0;
    align_cnt = 0;

    for (int n=0; n < WR_PARCELS; n++)
      if (!found_one)
       if (!a[n]) align_cnt++;
       else       found_one = 1;
  endfunction

  function logic [$clog2(WR_PARCELS):0] count_ones (input [WR_PARCELS-1:0] a);
    count_ones = 0;
    for (int n=0; n < WR_PARCELS; n++) if (a[n]) count_ones++;
  endfunction

  
  //////////////////////////////////////////////////////////////////
  //
  // Typedefs
  //
  typedef logic [15:0] parcel_t;

  typedef struct packed {
    logic misaligned,
          page_fault,
	  error;
  } parcel_status_t;


  //////////////////////////////////////////////////////////////////
  //
  // Variables
  //

  //parcel shift register
  parcel_t        [DEPTH                 -1:0] parcel_sr,
                                               nxt_parcel_sr ;

  //parcel status shift register
  parcel_status_t [DEPTH                 -1:0] parcel_st_sr;
  parcel_status_t [DEPTH + RD_PARCELS    -1:0] nxt_parcel_st_sr;

  logic           [WR_PARCEL_BITS        -1:0] align_parcel;
  logic           [$clog2(RD_PARCEL_BITS)  :0] rd_shift;

  logic           [$clog2(DEPTH)           :0] wadr;
  logic           [$clog2(DEPTH)           :0] nxt_wadr;


  //////////////////////////////////////////////////////////////////
  //
  // Module Body
  //

  //align parcel / parcel_wr (remove invalid parcels)
  assign align_parcel = parcel_i >> align_cnt(parcel_valid_i) * PARCEL_SIZE;

  /*
   * decode write location
   */
  assign nxt_wadr = wadr + count_ones(parcel_valid_i) - parcel_rd_i;


  //write pointer
  always @(posedge clk_i, negedge rst_ni)
    if      (!rst_ni ) wadr <= 'h0;
    else if ( flush_i) wadr <= 'h0;
    else               wadr <= nxt_wadr;


  //how much should we shift for a read
  assign rd_shift = parcel_rd_i * PARCEL_SIZE;


  /*
   * Parcel Shift Register
   */

  //next value of parcel shift register (like next state)
  always_comb
  begin
      //first store new value at next location
      nxt_parcel_sr = parcel_sr;

      if (|parcel_valid_i)
        for (int n=0; n < WR_PARCELS; n++)
          nxt_parcel_sr[wadr + n] = align_parcel[n * PARCEL_SIZE +: PARCEL_SIZE];

      // then shift out read parcels
      nxt_parcel_sr = nxt_parcel_sr >> rd_shift;
  end


  //decoder and shifter for simultaneous reading and writing
  always @(posedge clk_i)
    if (flush_i)
      for (int n = 0; n < DEPTH; n = n +2)
        parcel_sr[n +: 2] <= NOP;
    else  parcel_sr <= nxt_parcel_sr;


  /*
   * Parcel Status Shift Register
   */

  //next value of parcel status shift register (like next state)
  always_comb
  begin
      nxt_parcel_st_sr = parcel_st_sr;
      
      /* Store parcel status data
       * Set status for all write parcels, because we don't
       * know where an actual instruction starts/ends
       */
      for (int n=0; n < WR_PARCELS; n++)
      begin
          nxt_parcel_st_sr[wadr + n].misaligned = parcel_misaligned_i;
          nxt_parcel_st_sr[wadr + n].page_fault = parcel_page_fault_i;
          nxt_parcel_st_sr[wadr + n].error      = parcel_error_i;
      end

      //shift out read parcels
      nxt_parcel_st_sr = nxt_parcel_st_sr >> rd_shift;
  end


  //decoder and shifter for simultaneous reading and writing
  always @(posedge clk_i)
    if (flush_i)
      for (int n = 0; n < DEPTH; n++)
        parcel_st_sr[n] <= 'h0;
    else  parcel_st_sr <= nxt_parcel_st_sr;


  /*
   * Assign outputs
   */
  assign parcel_q_o = parcel_sr[0 +: RD_PARCELS];


  //status is only relevant for first parcel, because that's where the
  //instruction starts
  assign parcel_misaligned_o = parcel_st_sr[0].misaligned;
  assign parcel_page_fault_o = parcel_st_sr[0].page_fault;
  assign parcel_error_o      = parcel_st_sr[0].error;


  /*
   * Status Flags
   */

  //Queue Almost Empty
  always @(posedge clk_i, negedge rst_ni)
    if      (!rst_ni  ) almost_empty_o <= 1'b1;
    else if ( flush_i ) almost_empty_o <= 1'b1;
    else                almost_empty_o <= nxt_wadr < ALMOST_EMPTY_THRESHOLD_CHECK;


  //Queue Empty
  always @(posedge clk_i, negedge rst_ni)
    if      (!rst_ni  ) empty_o <= 1'b1;
    else if ( flush_i ) empty_o <= 1'b1;
    else                empty_o <= ~|nxt_wadr;


  //Queue Almost Full
  always @(posedge clk_i, negedge rst_ni)
    if      (!rst_ni  ) almost_full_o <= 1'b0;
    else if ( flush_i ) almost_full_o <= 1'b0;
    else                almost_full_o <= nxt_wadr > ALMOST_FULL_THRESHOLD_CHECK;


  //Queue Full
  always @(posedge clk_i, negedge rst_ni)
    if      (!rst_ni  ) full_o <= 1'b0;
    else if ( flush_i ) full_o <= 1'b0;
    else                full_o <= nxt_wadr > FULL_THRESHOLD;

endmodule

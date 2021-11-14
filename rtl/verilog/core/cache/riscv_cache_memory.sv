/////////////////////////////////////////////////////////////////////
//   ,------.                    ,--.                ,--.          //
//   |  .--. ' ,---.  ,--,--.    |  |    ,---. ,---. `--' ,---.    //
//   |  '--'.'| .-. |' ,-.  |    |  |   | .-. | .-. |,--.| .--'    //
//   |  |\  \ ' '-' '\ '-'  |    |  '--.' '-' ' '-' ||  |\ `--.    //
//   `--' '--' `---'  `--`--'    `-----' `---' `-   /`--' `---'    //
//                                             `---'               //
//    RISC-V                                                       //
//    Cache Memory Block                                           //
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

import riscv_cache_pkg::*;

module riscv_cache_tag_memory #(
  parameter XLEN          = 32,
  parameter SIZE          = 4,
  parameter BLOCK_SIZE    = XLEN,
  parameter WAYS          = 2,

  parameter TECHNOLOGY    = "GENERIC",

  localparam SETS          = no_of_sets(SIZE, BLOCK_SIZE, WAYS),
  localparam IDX_BITS      = no_of_index_bits(SETS),
  localparam BLK_OFFS_BITS = no_of_block_offset_bits(BLOCK_SIZE),
  localparam TAG_BITS      = no_of_tag_bits(XLEN, IDX_BITS, BLK_OFFS_BITS),
  localparam BLK_BITS      = no_of_block_bits(BLOCK_SIZE)
)
(
  input  logic                  rst_ni,
  input  logic                  clk_i,

  input  logic                  stall_i,

  input  logic                  flushing_i,
  input  logic                  filling_i,
  input  logic [WAYS      -1:0] fill_way_select_i,

  input  logic [TAG_BITS  -1:0] core_tag_i,
  input  logic [IDX_BITS  -1:0] tag_idx_i,

  input  logic [IDX_BITS  -1:0] dat_idx_i,
  input  logic [BLK_BITS/8-1:0] dat_be_i,

  input  logic [XLEN      -1:0] writebuffer_data_i,
  input  logic [BLK_BITS  -1:0] biu_d_i,
  input  logic                  biucmd_ack_i,

  output logic                  hit_o,
  output logic [BLK_BITS  -1:0] cache_line_o
);

  //////////////////////////////////////////////////////////////////
  //
  // Typedef
  //
  
  //TAG-structure
  typedef struct packed {
    logic                valid;
    logic [TAG_BITS-1:0] tag;
  } tag_struct;


  //////////////////////////////////////////////////////////////////
  //
  // Variables
  //
  genvar  way;

  logic [IDX_BITS    -1:0]           tag_idx_dly;

  logic [WAYS        -1:0]           tag_we;              //tag memory write enable
  logic [WAYS        -1:0]           fill_way_select_dly;

  logic [IDX_BITS    -1:0]           tag_idx;
  tag_struct                         tag_in      [WAYS],  //tag memory input data
                                     tag_out     [WAYS];  //tag memory output data
  logic [IDX_BITS    -1:0]           tag_byp_idx [WAYS];
  logic [TAG_BITS    -1:0]           tag_byp_tag [WAYS];
  logic [WAYS        -1:0][SETS-1:0] tag_valid;

  logic [WAYS        -1:0]           way_hit;             //got a hit on a way

  logic [IDX_BITS    -1:0]           dat_idx;
  logic [BLK_BITS    -1:0]           dat_in;              //data into memory
  logic [WAYS        -1:0]           dat_we;              //data memory write enable
  logic [BLK_BITS    -1:0]           dat_out     [WAYS];  //data memory output
  logic [BLK_BITS    -1:0]           way_q_mux   [WAYS];  //data out multiplexor


  //////////////////////////////////////////////////////////////////
  //
  // Module Body
  //


  //----------------------------------------------------------------
  // Tag Memory
  //----------------------------------------------------------------


  //delay tag-idx, same delay as through memory
  always @(posedge clk_i)
    if (!stall_i && !filling_i) tag_idx_dly <= tag_idx_i;


  //delay fill-way-select, same delay as through memory
  always @(posedge clk_i)
    if (!stall_i) fill_way_select_dly <= fill_way_select_i;


  //Tag-index
  assign tag_idx = filling_i ? tag_idx_dly : tag_idx;


generate
  for (way=0; way<WAYS; way++)
  begin: gen_ways_tag
      /* TAG RAM
       */
      rl_ram_1rw #(
        .ABITS      ( IDX_BITS               ),
        .DBITS      ( TAG_BITS               ),
        .TECHNOLOGY ( TECHNOLOGY             ) )
      tag_ram (
        .rst_ni     ( rst_ni                 ),
        .clk_i      ( clk_i                  ),
        .addr_i     ( tag_idx                ),
        .we_i       ( tag_we [way]           ),
        .be_i       ( {(TAG_BITS+7)/8{1'b1}} ),
        .din_i      ( tag_in [way].tag       ),
        .dout_o     ( tag_out[way].tag       ) );


      //tag-register for bypass (RAW hazard)
      always @(posedge clk_i)
        if (tag_we[way])
        begin
            tag_byp_tag[way] <= tag_in[way].tag;
            tag_byp_idx[way] <= tag_idx_i;
        end


      /* TAG Valid
       * Valid is stored in DFF
       */ 
      always @(posedge clk_i, negedge rst_ni)
        if      (!rst_ni     ) tag_valid[way]            <= 'h0;
        else if ( flushing_i ) tag_valid[way]            <= 'h0;
        else if ( tag_we[way]) tag_valid[way][tag_idx_i] <= tag_in[way].valid;

      assign tag_out[way].valid = tag_valid[way][tag_idx_dly];


      //compare way-tag to TAG;
      assign way_hit[way] = tag_out[way].valid &
                            (core_tag_i == (tag_idx_dly == tag_byp_idx[way] ? tag_byp_tag[way] : tag_out[way].tag) );


      /* TAG Write Enable
       */
      assign tag_we[way] = filling_i & fill_way_select_dly[way] & biucmd_ack_i;


      /* TAG Write Data
       */
      //clear valid tag during flushing and cache-coherency checks
      assign tag_in[way].valid = ~flushing_i;
      assign tag_in[way].tag   = core_tag_i;

  end
endgenerate


  /* Generate Hit
   */
  always @(posedge clk_i)
    hit_o <= |way_hit;



  //----------------------------------------------------------------
  // Data Memory
  //----------------------------------------------------------------


  //generate DAT-memory data input
  assign dat_in = biucmd_ack_i ? biu_d_i : {BLK_BITS/XLEN{writebuffer_data_i}};


  //Dat-index
  assign dat_idx = filling_i ? tag_idx_dly : dat_idx_i;


generate
  for (way=0; way<WAYS; way++)
  begin: gen_ways_dat
      rl_ram_1rw #(
        .ABITS      ( IDX_BITS      ),
        .DBITS      ( BLK_BITS      ),
        .TECHNOLOGY ( TECHNOLOGY    ) )
      data_ram (
        .rst_ni     ( rst_ni        ),
        .clk_i      ( clk_i         ),
        .addr_i     ( dat_idx       ),
        .we_i       ( dat_we [way]  ),
        .be_i       ( dat_be_i      ),
        .din_i      ( dat_in        ),
        .dout_o     ( dat_out[way]) );


      /* Data Write Enable
       */
      assign dat_we[way] = filling_i & fill_way_select_dly[way] & biucmd_ack_i;
      

      /* Data Ouput Mux
       * assign way_q; Build MUX (AND/OR) structure
       */
      if (way == 0)
        assign way_q_mux[way] =  dat_out[way] & {BLK_BITS{way_hit[way]}};
      else
        assign way_q_mux[way] = (dat_out[way] & {BLK_BITS{way_hit[way]}}) | way_q_mux[way -1];
  end
endgenerate


  always @(posedge clk_i)
    cache_line_o <= way_q_mux[WAYS-1];

endmodule



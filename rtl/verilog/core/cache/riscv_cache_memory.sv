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


/*
 * Actual Cache memories
 * Memory is written when biucmd_ack_i = 1
 * Memory read must stall then
 */


import riscv_cache_pkg::*;

module riscv_cache_memory #(
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

  input  logic                  armed_i,
  input  logic                  flushing_i,
  input  logic                  filling_i,
  input  logic [WAYS      -1:0] fill_way_select_i,

  input  logic [TAG_BITS  -1:0] rd_core_tag_i,
                                wr_core_tag_i,
  input  logic [IDX_BITS  -1:0] rd_tag_idx_i,
                                wr_tag_idx_i,
                                wr_tag_dirty_idx_i,

  input  logic [IDX_BITS  -1:0] rd_dat_idx_i,
                                wr_dat_idx_i,
  input  logic [BLK_BITS/8-1:0] dat_be_i,

  input  logic [XLEN      -1:0] writebuffer_data_i,
  input  logic [BLK_BITS  -1:0] biu_d_i,
  input  logic                  biucmd_ack_i,

  output logic [XLEN      -1:0] evict_buffer_adr_o,
  output logic [BLK_BITS  -1:0] evict_buffer_q_o,

  output logic                  hit_o,
  output logic                  dirty_o,
  output logic                  way_dirty_o,
  output logic [BLK_BITS  -1:0] cache_line_o
);

  //////////////////////////////////////////////////////////////////
  //
  // Typedef
  //
  
  //TAG-structure
  typedef struct packed {
    logic                valid;
    logic                dirty;
    logic [TAG_BITS-1:0] tag;
  } tag_struct;


  //////////////////////////////////////////////////////////////////
  //
  // Variables
  //
  genvar  way;

  logic                              biumem_we,           //write data from BIU
                                     biumem_we_dly;

  logic [WAYS        -1:0]           fill_way_select_dly;

  logic [IDX_BITS    -1:0]           tag_idx,
                                     tag_idx_dly,
                                     tag_idx_filling;     //tag-index for filling
  tag_struct                         tag_in      [WAYS],  //tag memory input data
                                     tag_out     [WAYS];  //tag memory output data
  logic [WAYS        -1:0]           tag_we,              //tag memory write enable
                                     tag_we_dirty;        //tag-dirty write enable
  logic [IDX_BITS    -1:0]           tag_byp_idx;
  logic [TAG_BITS    -1:0]           tag_byp_tag;
  logic                              tag_byp_valid;
  logic [WAYS        -1:0][SETS-1:0] tag_valid;
  logic [WAYS        -1:0][SETS-1:0] tag_dirty;
  logic [WAYS        -1:0]           way_hit,             //got a hit on a way
                                     way_dirty;           //way is dirty


  logic [IDX_BITS    -1:0]           dat_idx,
                                     dat_idx_dly,         //dat-idx delayed, same delay as through memory
                                     dat_idx_filling;     //dat-idx for filling
  logic [BLK_BITS    -1:0]           dat_in;              //data into memory
  logic [WAYS        -1:0]           dat_we;              //data memory write enable
  logic [BLK_BITS    -1:0]           dat_out     [WAYS];  //data memory output
  logic [BLK_BITS    -1:0]           way_q_mux   [WAYS];  //data out multiplexor
  logic [IDX_BITS    -1:0]           dat_byp_idx;
  logic [BLK_BITS    -1:0]           dat_byp_q;


  //////////////////////////////////////////////////////////////////
  //
  // Functions
  //
  function automatic integer onehot2int;
    input [WAYS-1:0] a;

    integer i;

    onehot2int = 0;

    for (i=0; i<WAYS; i++)
      if (a[i]) onehot2int = i;
  endfunction: onehot2int


  //////////////////////////////////////////////////////////////////
  //
  // Module Body
  //


  //----------------------------------------------------------------
  // Tag Memory
  //----------------------------------------------------------------


  //write data from BIU 
  assign biumem_we = filling_i & biucmd_ack_i;

  
  always @(posedge clk_i)
    biumem_we_dly <= biumem_we;


  //hold tag-idx, to be used during biumem_we=1
  always @(posedge clk_i)
    if (!filling_i) tag_idx_filling <= wr_tag_idx_i;


  //delay fill-way-select, same delay as through memory
  always @(posedge clk_i)
    if (!filling_i) fill_way_select_dly <= fill_way_select_i;


  //Tag-index
  assign tag_idx = biumem_we ? tag_idx_filling : rd_tag_idx_i;


  //delay tag-idx, same delay as through memory
  always @(posedge clk_i)
    tag_idx_dly <= rd_tag_idx_i;


  //tag-register for bypass (RAW hazard)
  always @(posedge clk_i)
    if (filling_i & biucmd_ack_i)
    begin
        tag_byp_tag <= wr_core_tag_i;
        tag_byp_idx <= tag_idx_filling;
    end

  always @(posedge clk_i, negedge rst_ni)
    if      (!rst_ni    ) tag_byp_valid <= 1'b0;
    else if ( flushing_i) tag_byp_valid <= 1'b0;
    else if ( biumem_we ) tag_byp_valid <= 1'b1;



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



      /* TAG Valid
       * Valid is stored in DFF
       */ 
      always @(posedge clk_i, negedge rst_ni)
        if      (!rst_ni     ) tag_valid[way]          <= 'h0;
        else if ( flushing_i ) tag_valid[way]          <= 'h0;
        else if ( tag_we[way]) tag_valid[way][tag_idx] <= tag_in[way].valid;

      assign tag_out[way].valid = tag_valid[way][tag_idx_dly];


      //compare way-tag to TAG;
      assign way_hit[way] = tag_out[way].valid & (rd_core_tag_i == tag_out[way].tag);


      /* TAG Dirty
       * Dirty is stored in DFF
       */ 
      always @(posedge clk_i, negedge rst_ni)
        if      (!rst_ni           ) tag_dirty[way]                     <= 'h0;
        else if ( tag_we_dirty[way]) tag_dirty[way][wr_tag_dirty_idx_i] <= tag_in[way].dirty;

      assign tag_out[way].dirty = tag_dirty[way][tag_idx_dly];


      //extract 'dirty' from tag
      assign way_dirty[way] = tag_out[way].valid & tag_out[way].dirty;


      /* TAG Write Enable
       */
      assign tag_we[way] = biumem_we & fill_way_select_dly[way];

/*
          ARMED  : tag_we_dirty[way] = way_hit[way] & ((mem_vreq_dly & mem_we_dly & mem_preq_i) | (mem_preq_dly & mem_we_dly));
          default: tag_we_dirty[way] = (filling & fill_way_select_hold[way] & biufsm_ack) |
                                       (flushing & write_evict_buffer & (get_dirty_way_idx(tag_dirty,flush_idx) == way) );
*/


      /* TAG Write Data
       */
      //clear valid tag during flushing and cache-coherency checks
      assign tag_in[way].valid = ~flushing_i;
      assign tag_in[way].dirty = 1'b1;
      assign tag_in[way].tag   = wr_core_tag_i;
  end
endgenerate


  /* Generate Hit
   */
  always @(posedge clk_i)
    if (!stall_i) hit_o <= tag_idx_dly == tag_byp_idx ? tag_byp_valid & (rd_core_tag_i == tag_byp_tag) : |way_hit & ~biumem_we_dly;


  /* Generate Dirty
  */
  always @(posedge clk_i)
    if (!stall_i) dirty_o <= |way_dirty; //TODO Bypass


  always @(posedge clk_i)
    if (!stall_i) way_dirty_o <= tag_out[ onehot2int(fill_way_select_dly) ].valid & tag_out[ onehot2int(fill_way_select_dly) ].dirty;


  //----------------------------------------------------------------
  // Data Memory
  //----------------------------------------------------------------


  //generate DAT-memory data input
  assign dat_in = biucmd_ack_i ? biu_d_i : {BLK_BITS/XLEN{writebuffer_data_i}};


  //hold dat_idx, to be used when biumem_we=1
  always @(posedge clk_i)
    if (!filling_i) dat_idx_filling <= wr_dat_idx_i;


  //Dat-index
  assign dat_idx = biumem_we ? dat_idx_filling : rd_dat_idx_i;

  
  //delay dat-idx, same delay as through memory
  always @(posedge clk_i)
    dat_idx_dly <= rd_dat_idx_i;


  //dat-register for bypass (RAW hazard)
  always @(posedge clk_i)
    if (filling_i & biucmd_ack_i)
    begin
        dat_byp_q   <= dat_in;
        dat_byp_idx <= dat_idx_filling;
    end


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
      assign dat_we[way] = biumem_we & fill_way_select_dly[way];
      

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
    if (!stall_i) cache_line_o <= dat_idx_dly == dat_byp_idx ? dat_byp_q : way_q_mux[WAYS-1];

endmodule



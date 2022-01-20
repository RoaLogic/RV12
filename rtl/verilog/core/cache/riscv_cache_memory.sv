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
  localparam BLK_BITS      = no_of_block_bits(BLOCK_SIZE),
  localparam BLK_OFFS_BITS = no_of_block_offset_bits(BLOCK_SIZE),
  localparam DAT_OFFS_BITS = no_of_data_offset_bits(XLEN, BLK_BITS),
  localparam TAG_BITS      = no_of_tag_bits(XLEN, IDX_BITS, BLK_OFFS_BITS)
)
(
  input  logic                     rst_ni,
  input  logic                     clk_i,

  input  logic                     stall_i,

  input  logic                     armed_i,
  input  logic                     flushing_i,
  input  logic                     filling_i,
  input  logic [WAYS         -1:0] fill_way_select_i,

  input  logic [TAG_BITS     -1:0] rd_core_tag_i,
                                   wr_core_tag_i,
  input  logic [IDX_BITS     -1:0] rd_idx_i,
                                   wr_idx_i,

  input  logic                     rreq_i,            //Read cache memories?
  input  logic                     writebuffer_we_i,
  input  logic [XLEN/8       -1:0] writebuffer_be_i,
  input  logic [IDX_BITS     -1:0] writebuffer_idx_i,
  input  logic [DAT_OFFS_BITS-1:0] writebuffer_offs_i,
  input  logic [XLEN         -1:0] writebuffer_data_i,
  input  logic [WAYS         -1:0] writebuffer_ways_hit_i,

  input  logic [BLK_BITS     -1:0] biu_line_i,
  input  logic                     biu_line_dirty_i,
  input  logic                     biucmd_ack_i,

  output logic [TAG_BITS     -1:0] evict_tag_o,
  output logic [BLK_BITS     -1:0] evict_line_o,

  output logic                     hit_o,             //cache-hit
  output logic [WAYS         -1:0] ways_hit_o,        //list of hit ways
  output logic                     dirty_o,           //(at least) one way is dirty
  output logic [WAYS         -1:0] ways_dirty_o,      //list of dirty ways
  output logic                     way_dirty_o,       //the selected way is dirty
  output logic [BLK_BITS     -1:0] cache_line_o       //Cacheline
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
  // Functions
  //

  //Byte-Enable driven MUX
  function automatic [XLEN-1:0] be_mux;
    input [XLEN/8-1:0] be;
    input [XLEN  -1:0] data_old; //old data
    input [XLEN  -1:0] data_new; //new data

    for (int i=0; i<XLEN/8;i++)
      be_mux[i*8 +: 8] = be[i] ? data_new[i*8 +: 8] : data_old[i*8 +: 8];
  endfunction: be_mux


  //////////////////////////////////////////////////////////////////
  //
  // Variables
  //
  genvar  way;

  logic                              biumem_we,              //write data from BIU
                                     writebuffer_we,         //write data from WriteBuffer (CPU)
                                     we_dly;


  logic [WAYS        -1:0]           fill_way_select_dly;

  logic [IDX_BITS    -1:0]           idx,                    //Memory index
                                     byp_idx,                //Bypass index (for RAW hazard)
                                     rd_idx_dly,             //delay idx, same delay as through memory
                                     idx_filling;            //index for filling
  logic [TAG_BITS    -1:0]           tag_filling;            //TAG for filling
  logic                              byp_valid,              //bypass(es) valid
                                     rd_idx_dly_eq_byp_idx,  //rd_idx_dly == byp_idx
                                     bypass_biumem_we,       //bypass outputs on biumem_we
                                     bypass_writebuffer_we;  //bypass outputs on writebuffer_we

  /* TAG
   */
  tag_struct                         tag_in      [WAYS],     //tag memory input data
                                     tag_out     [WAYS];     //tag memory output data
  logic [WAYS        -1:0]           tag_we,                 //tag memory write enable
                                     tag_we_dirty;           //tag-dirty write enable
  logic [TAG_BITS    -1:0]           tag_byp_tag;
  logic [WAYS        -1:0][SETS-1:0] tag_valid;
  logic [WAYS        -1:0][SETS-1:0] tag_dirty;
  logic [WAYS        -1:0]           way_hit,                //got a hit on a way
                                     way_dirty;              //way is dirty


  /* DATA
  */
  logic [BLK_BITS    -1:0]           dat_in;                 //data into memory
  logic [WAYS        -1:0]           dat_we;                 //data memory write enable
  logic [BLK_BITS/8  -1:0]           dat_be;                 //data memory write byte enables
  logic [BLK_BITS    -1:0]           dat_out     [WAYS];     //data memory output
  logic [BLK_BITS    -1:0]           way_q_mux   [WAYS];     //data out multiplexor
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

  //write data from BIU 
  assign biumem_we = filling_i & biucmd_ack_i;


  //WriteBuffer write opportunity
  assign writebuffer_we = ~rreq_i & writebuffer_we_i;


  //Delayed write. Masks 'hit'
  always @(posedge clk_i)
    we_dly <= biumem_we | writebuffer_we;


  //delay rd_idx_i, same delay as through memory
  always @(posedge clk_i)
    rd_idx_dly <= rd_idx_i;


  //hold idx and tag, to be used during biumem_we=1
  always @(posedge clk_i)
    if (!filling_i)
    begin
        idx_filling <= wr_idx_i;
        tag_filling <= wr_core_tag_i;
    end


  //delay fill-way-select, same delay as through memory
  always @(posedge clk_i)
    if (!filling_i) fill_way_select_dly <= fill_way_select_i;


  //Memory Index
  always_comb
    unique casex ( {biumem_we, writebuffer_we} )
      {2'b1?}: idx = idx_filling;
      {2'b?1}: idx = writebuffer_idx_i;
      default: idx = rd_idx_i;
    endcase


  //Index bypass (RAW hazard)
  always @(posedge clk_i)
    if (biumem_we) byp_idx <= idx_filling;


  //Bypass(es) valid
  always @(posedge clk_i, negedge rst_ni)
    if      (!rst_ni    ) byp_valid <= 1'b0;
    else if ( flushing_i) byp_valid <= 1'b0;
    else if ( biumem_we ) byp_valid <= 1'b1;


  //Should bypass when rd_idx_dly == byp_idx
  assign rd_idx_dly_eq_byp_idx = byp_valid & (rd_idx_dly == byp_idx);


  //Bypass on biumem_we?
  assign bypass_biumem_we = biumem_we && (wr_idx_i == idx_filling) && (wr_core_tag_i == tag_filling);


  //Bypass on writebuffer_we?
  assign bypass_writebuffer_we = writebuffer_we_i & (rd_idx_dly == writebuffer_idx_i);


  //----------------------------------------------------------------
  // Tag Memory
  //----------------------------------------------------------------

  //tag-register for bypass (RAW hazard)
  always @(posedge clk_i)
    if (biumem_we) tag_byp_tag <= wr_core_tag_i;


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
        .addr_i     ( idx                    ),
        .we_i       ( tag_we [way]           ),
        .be_i       ( {(TAG_BITS+7)/8{1'b1}} ),
        .din_i      ( tag_in [way].tag       ),
        .dout_o     ( tag_out[way].tag       ) );



      /* TAG Valid
       * Valid is stored in DFF
       */ 
      always @(posedge clk_i, negedge rst_ni)
        if      (!rst_ni     ) tag_valid[way]      <= 'h0;
        else if ( flushing_i ) tag_valid[way]      <= 'h0;
        else if ( tag_we[way]) tag_valid[way][idx] <= tag_in[way].valid;

      assign tag_out[way].valid = tag_valid[way][rd_idx_dly];


      //compare way-tag to TAG;
      assign way_hit[way] = tag_out[way].valid & (rd_core_tag_i == tag_out[way].tag);


      /* TAG Dirty
       * Dirty is stored in DFF
       */ 
      always @(posedge clk_i, negedge rst_ni)
        if      (!rst_ni           ) tag_dirty[way]      <= 'h0;
        else if ( tag_we_dirty[way]) tag_dirty[way][idx] <= tag_in[way].dirty;

      assign tag_out[way].dirty = tag_dirty[way][rd_idx_dly];


      //extract 'dirty' from tag
      assign way_dirty[way] = tag_out[way].valid & tag_out[way].dirty;


      /* TAG Write Enable
       */
      assign tag_we      [way] =  biumem_we & fill_way_select_dly[way];
      assign tag_we_dirty[way] = (biumem_we & fill_way_select_dly[way]) |
                                 (writebuffer_we & writebuffer_ways_hit_i[way]);

      /* TAG Write Data
       */
      //clear valid tag during flushing and cache-coherency checks
      assign tag_in[way].valid = ~flushing_i;
      assign tag_in[way].dirty = biumem_we ? biu_line_dirty_i : writebuffer_we_i;
      assign tag_in[way].tag   = tag_filling;
  end
endgenerate


  /* Generate Hit
   */
  always @(posedge clk_i)
    if      ( bypass_biumem_we) hit_o <= 1'b1;
    else if (!stall_i         ) hit_o <= rd_idx_dly_eq_byp_idx ? byp_valid & (rd_core_tag_i == tag_byp_tag)
                                                               : |way_hit & ~we_dly;


  always @(posedge clk_i)
    if      ( bypass_biumem_we) ways_hit_o <= fill_way_select_dly;
    else if (!stall_i         ) ways_hit_o <= way_hit;
    

  /* Generate Dirty
  */
  always @(posedge clk_i)
    if      ( bypass_biumem_we) dirty_o <= biu_line_dirty_i;
    else if (!stall_i         ) dirty_o <= |way_dirty;


  always @(posedge clk_i)
    if      ( bypass_biumem_we) ways_dirty_o <= {WAYS{biu_line_dirty_i}} & fill_way_select_dly;
    else if (!stall_i         ) ways_dirty_o <= way_dirty;


  always @(posedge clk_i)
    if      ( bypass_biumem_we) way_dirty_o <= biu_line_dirty_i;
    else if (!stall_i         ) way_dirty_o <= way_dirty[ onehot2int(fill_way_select_dly) ];


  /* TAG output
   * Used for EVICT address generation
   */
  always @(posedge clk_i)
    if      ( bypass_biumem_we) evict_tag_o <= tag_filling;
    else if (!stall_i         ) evict_tag_o <= rd_idx_dly_eq_byp_idx ? tag_byp_tag
                                                                     : tag_out[ onehot2int(fill_way_select_dly) ].tag;


  //----------------------------------------------------------------
  // Data Memory
  //----------------------------------------------------------------


  //generate DAT-memory data input
  assign dat_in = writebuffer_we ? {BLK_BITS/XLEN{writebuffer_data_i}}
                                 : biu_line_i;

  //generate DAT-memory byte enable
  assign dat_be = writebuffer_we ? writebuffer_be_i << (writebuffer_offs_i * XLEN/8)
                                 : {BLK_BITS/8{1'b1}};

  
  //dat-register for bypass (RAW hazard)
  always @(posedge clk_i)
    if (biumem_we) dat_byp_q   <= dat_in;


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
        .addr_i     ( idx           ),
        .we_i       ( dat_we [way]  ),
        .be_i       ( dat_be        ),
        .din_i      ( dat_in        ),
        .dout_o     ( dat_out[way]) );


      /* Data Write Enable
       */
      assign dat_we[way] = (biumem_we & fill_way_select_dly[way]        ) |
                           (writebuffer_we & writebuffer_ways_hit_i[way]); //TODO: check for overlaps
      

      /* Data Ouput Mux
       * assign way_q; Build MUX (AND/OR) structure
       */
      if (way == 0)
        assign way_q_mux[way] =  dat_out[way] & {BLK_BITS{way_hit[way]}};
      else
        assign way_q_mux[way] = (dat_out[way] & {BLK_BITS{way_hit[way]}}) | way_q_mux[way -1];
  end
endgenerate


  /* Cache line output
   */
  always @(posedge clk_i)
    if      ( bypass_biumem_we ) cache_line_o <= biu_line_i;
    else if (!stall_i          ) cache_line_o <= rd_idx_dly_eq_byp_idx ? dat_byp_q
                                                                       : way_q_mux[WAYS-1];


  /* Evict line output
   */
  always @(posedge clk_i)
    if      ( bypass_biumem_we) evict_line_o <= biu_line_i;
    else if (!stall_i         ) evict_line_o <= rd_idx_dly_eq_byp_idx ? dat_byp_q
                                                                      : dat_out[ onehot2int(fill_way_select_dly) ];
endmodule



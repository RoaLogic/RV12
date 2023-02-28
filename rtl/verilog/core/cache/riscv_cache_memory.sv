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


module riscv_cache_memory
import riscv_cache_pkg::*;
#(
  parameter XLEN          = 32,
  parameter PLEN          = XLEN == 32 ? 34 : 56,
  parameter SIZE          = 4,
  parameter BLOCK_SIZE    = XLEN,
  parameter WAYS          = 2,

  parameter TECHNOLOGY    = "GENERIC",

  localparam SETS          = no_of_sets(SIZE, BLOCK_SIZE, WAYS),
  localparam IDX_BITS      = no_of_index_bits(SETS),
  localparam BLK_BITS      = no_of_block_bits(BLOCK_SIZE),
  localparam BLK_OFFS_BITS = no_of_block_offset_bits(BLOCK_SIZE),
  localparam DAT_OFFS_BITS = no_of_data_offset_bits(XLEN, BLK_BITS),
  localparam TAG_BITS      = no_of_tag_bits(PLEN, IDX_BITS, BLK_OFFS_BITS)
)
(
  input  logic                     rst_ni,
  input  logic                     clk_i,

  input  logic                     stall_i,

  input  logic                     armed_i,
  input  logic                     cleaning_i,
  input  logic                     invalidate_block_i,
  input  logic                     invalidate_all_blocks_i,
  input  logic                     filling_i,
  input  logic [WAYS         -1:0] fill_way_select_i,
  input  logic [WAYS         -1:0] fill_way_i,
  output logic [WAYS         -1:0] fill_way_o,
  output logic [$clog2(WAYS) -1:0] clean_way_int_o,
  output logic [IDX_BITS     -1:0] clean_idx_o,
  input  logic [WAYS         -1:0] clean_way_i,
  input  logic [IDX_BITS     -1:0] clean_idx_i,

  input  logic [TAG_BITS     -1:0] rd_core_tag_i,
                                   wr_core_tag_i,
  input  logic [IDX_BITS     -1:0] rd_idx_i,
                                   wr_idx_i,

  input  logic                     rreq_i,            //Read cache memories?
  input  logic                     writebuffer_we_i,
  input  logic [BLK_BITS/8   -1:0] writebuffer_be_i,  //writebuffer_be is already blk_bits aligned
  input  logic [IDX_BITS     -1:0] writebuffer_idx_i,
  input  logic [DAT_OFFS_BITS-1:0] writebuffer_offs_i,
  input  logic [XLEN         -1:0] writebuffer_data_i,
  input  logic [WAYS         -1:0] writebuffer_ways_hit_i,
  input  logic                     writebuffer_cleaning_i,

  input  logic [BLK_BITS     -1:0] biu_line_i,
  input  logic                     biu_line_dirty_i,
  input  logic                     biucmd_ack_i,

  input  logic                     evict_read_i,
  output logic [PLEN         -1:0] evict_adr_o,
  output logic [BLK_BITS     -1:0] evict_line_o,

  input  logic                     latchmem_i,        //latch output from memories
  output logic                     hit_o,             //cache-hit
  output logic [WAYS         -1:0] ways_hit_o,        //list of hit ways
  output logic                     cache_dirty_o,     //(at least) one way is dirty
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

  //Convert OneHot to integer value
  function automatic int onehot2int;
    input [WAYS-1:0] a;

    integer i;

    onehot2int = 0;

    for (i=0; i<WAYS; i++)
      if (a[i]) onehot2int = i;
  endfunction: onehot2int


  //Byte-Enable driven MUX
  function automatic [BLK_BITS-1:0] be_mux;
    input                  ena;
    input [BLK_BITS/8-1:0] be;
    input [BLK_BITS  -1:0] data_old; //old data
    input [BLK_BITS  -1:0] data_new; //new data

    for (int i=0; i<BLK_BITS/8;i++)
      be_mux[i*8 +: 8] = ena && be[i] ? data_new[i*8 +: 8] : data_old[i*8 +: 8];
  endfunction: be_mux


  //Find first one in dirty_ways (LSB first)
  function automatic int first_dirty_way;
    input [WAYS-1:0][SETS-1:0] valid, dirty;

    logic [WAYS*SETS -1:0] valid_vect, dirty_vect;

    //from packed array to vector
    valid_vect = valid;
    dirty_vect = dirty;

    for (int n=0; n < WAYS*SETS; n++)
      if (valid_vect[n] && dirty_vect[n]) return n;
  endfunction: first_dirty_way


  //////////////////////////////////////////////////////////////////
  //
  // Variables
  //
  genvar  way;

  logic                              biumem_we,               //write data from BIU
                                     writebuffer_we,          //write data from WriteBuffer (CPU)
                                     we_dly;

  logic [WAYS        -1:0]           fill_way_select_dly;
  logic [$clog2(WAYS)-1:0]           fill_way_select_int_dly; //integer version of fill_way_select_dly
  logic [$clog2(WAYS)-1:0]           clean_way_int_dly;       //delayed way currently flushing
  logic [$clog2(WAYS)-1:0]           evict_way_select_int;    //integer version of fill_way_select_dly

  logic [IDX_BITS    -1:0]           rd_idx_dly,              //delay idx, same delay as through memory
                                     filling_idx,             //index for/currently filling
                                     clean_idx,               //index for/currently flushing
                                     clean_idx_dly;           //delayed flusing idx, same delay as through memory
  logic [TAG_BITS    -1:0]           rd_core_tag_dly,         //delay core_tag, same delay as through memory
                                     filling_tag;             //TAG for filling
  logic                              bypass_biumem_we;        //bypass outputs on biumem_we
  logic [WAYS        -1:0]           bypass_writebuffer_we;   //bypass outputs on writebuffer_we

  /* TAG
   */
  logic [IDX_BITS    -1:0]           tag_idx;                 //tag memory read index
  tag_struct                         tag_in          [WAYS],  //tag memory input data
                                     tag_out         [WAYS];  //tag memory output data
  logic [WAYS        -1:0]           tag_we,                  //tag memory write enable
                                     tag_we_dirty;            //tag-dirty write enable
  logic [TAG_BITS    -1:0]           tag_byp_tag;
  logic [WAYS        -1:0][SETS-1:0] tag_valid;
  logic [WAYS        -1:0][SETS-1:0] tag_dirty;
  logic [WAYS        -1:0]           way_hit,                 //got a hit on a way
                                     way_dirty;               //way is dirty


  /* DATA
  */
  logic [IDX_BITS    -1:0]           dat_idx;                 //data memory read index
  logic [BLK_BITS    -1:0]           dat_in;                  //data into memory
  logic [WAYS        -1:0]           dat_we;                  //data memory write enable
  logic [BLK_BITS/8  -1:0]           dat_be;                  //data memory write byte enables
  logic [BLK_BITS    -1:0]           dat_out         [WAYS],  //data memory output
                                     dat_out_bypassed[WAYS];  //data memory output with writebuffer bypass
  logic [BLK_BITS    -1:0]           way_q_mux       [WAYS];  //data out multiplexor


  /* EVICT
   */
  logic                              evict_latch;             //latch evict_* signals
  logic [TAG_BITS    -1:0]           evict_tag;               //tag to evict
  logic [IDX_BITS    -1:0]           evict_idx;               //index to evict


  //////////////////////////////////////////////////////////////////
  //
  // Module Body
  //

  //write data from BIU 
  assign biumem_we = filling_i & biucmd_ack_i;


  //WriteBuffer write opportunity
  assign writebuffer_we = (~rreq_i | writebuffer_cleaning_i) & writebuffer_we_i;


  //Delayed write. Masks 'hit'
  always @(posedge clk_i)
    we_dly <= biumem_we;


  //delay rd_idx_i, rd_core_tag_i, same delay as through memory
  always @(posedge clk_i)
  begin
      rd_idx_dly      <= rd_idx_i;
      rd_core_tag_dly <= rd_core_tag_i;
  end


  //hold idx and tag, to be used during biumem_we=1 and for evict_*
  always @(posedge clk_i)
    if (!filling_i)
    begin
        filling_idx <= wr_idx_i;
        filling_tag <= wr_core_tag_i;
    end


  //Latch evict_*
  always @(posedge clk_i)
    begin
        evict_latch          <= evict_read_i;
        evict_way_select_int <= onehot2int(fill_way_i);
    end


  //Index during cleaning
  always @(posedge clk_i)
  begin
      clean_idx_o       <= first_dirty_way(tag_valid, tag_dirty) % SETS; //from vector-int to index
      clean_way_int_o   <= first_dirty_way(tag_valid, tag_dirty) / SETS; //from vector-int to way

      //same delay as through Data memory (adr=clean_idx_i)
      clean_idx_dly     <= clean_idx_i;
      clean_way_int_dly <= onehot2int(clean_way_i);
  end


  //delay fill-way-select, same delay as through memory
  always @(posedge clk_i)
    begin
        fill_way_select_dly     <= fill_way_select_i;
	fill_way_select_int_dly <= onehot2int(fill_way_select_i);
    end


  //Bypass on biumem_we?
  assign bypass_biumem_we      = biumem_we & (rd_idx_dly == filling_idx) & (rd_core_tag_dly == filling_tag);


  //Bypass on writebuffer_we?
  always_comb
    for (int n=0; n<WAYS; n++)
      bypass_writebuffer_we[n] = writebuffer_we_i & (rd_idx_dly == writebuffer_idx_i) & writebuffer_ways_hit_i[n];


  //----------------------------------------------------------------
  // Tag Memory
  //----------------------------------------------------------------

  //Memory Index
  always_comb
    unique casex ( {cleaning_i, evict_read_i, biumem_we} )
      {3'b1??}: tag_idx = clean_idx_i;
      {3'b?1?}: tag_idx = filling_idx;
      {3'b??1}: tag_idx = filling_idx;
      default : tag_idx = rd_idx_i;
    endcase


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
        .addr_i     ( tag_idx                ),
        .we_i       ( tag_we [way]           ),
        .be_i       ( {(TAG_BITS+7)/8{1'b1}} ),
        .din_i      ( tag_in [way].tag       ),
        .dout_o     ( tag_out[way].tag       ) );



      /* TAG Valid
       * Valid is stored in DFF
       */ 
      always @(posedge clk_i, negedge rst_ni)
        if      (!rst_ni                      ) tag_valid[way]          <= 'h0;
	else if ( invalidate_all_blocks_i     ) tag_valid[way]          <= 'h0;
        else if ( invalidate_block_i          ) tag_valid[way][tag_idx] <= 1'b0;         //TODO: specify block number for cbo.inval
        else if ( tag_we[way]                 ) tag_valid[way][tag_idx] <= tag_in[way].valid;

      assign tag_out[way].valid = tag_valid[way][rd_idx_dly];


      //compare way-tag to TAG;
      assign way_hit[way] = tag_out[way].valid & (rd_core_tag_i == tag_out[way].tag) &
                           ~(filling_i & fill_way_i[way] & ~rreq_i); //actually wreq_i.
                                                                     //Can get a hit when reading data as the block still contains previous data
                                                                     //Cannot get a hit when writing data, because that's for the new block

      /* TAG Dirty
       * Dirty is stored in DFF
       * Use dat_idx here to update dirty on writebuffer_we
       */ 
      always @(posedge clk_i, negedge rst_ni)
        if      (!rst_ni            ) tag_dirty[way]              <= 'h0;
        else if ( clean_way_i [way] ) tag_dirty[way][clean_idx_i] <= 1'b0;
        else if ( tag_we_dirty[way] ) tag_dirty[way][dat_idx    ] <= tag_in[way].dirty;

      assign tag_out[way].dirty = tag_dirty[way][rd_idx_dly];


      //extract 'dirty' from tag
      assign way_dirty[way] = (tag_out[way].valid         & tag_out[way].dirty         ) |
                              (bypass_writebuffer_we[way] & writebuffer_ways_hit_i[way]);


      /* TAG Write Enable
       */
      assign tag_we      [way] =  biumem_we & fill_way_i[way];
      assign tag_we_dirty[way] = (biumem_we & fill_way_i[way]                 ) |
                                 (writebuffer_we & writebuffer_ways_hit_i[way]);

      /* TAG Write Data
       */
      //clear valid tag during flushing and cache-coherency checks
      assign tag_in[way].valid = 1'b1;
      assign tag_in[way].dirty = biumem_we ? biu_line_dirty_i : writebuffer_we_i;
      assign tag_in[way].tag   = filling_tag;
  end
endgenerate


  /* Generate Hit
   */
  always @(posedge clk_i)
    if      ( invalidate_all_blocks_i) hit_o <= 1'b0;
    else if ( bypass_biumem_we       ) hit_o <= 1'b1;
    else if ( latchmem_i             ) hit_o <= |way_hit & ~we_dly;


  always @(posedge clk_i)
    if      ( bypass_biumem_we) ways_hit_o <= fill_way_i;
    else if ( latchmem_i      ) ways_hit_o <= way_hit;
    

  /* Generate Dirty
  */
  //cache has dirty lines
  always @(posedge clk_i)
    if      ( bypass_biumem_we) cache_dirty_o <= biu_line_dirty_i;
    else if ( latchmem_i      ) cache_dirty_o <= |(tag_valid & tag_dirty);


  //TODO: remove?
  always @(posedge clk_i)
    if      ( bypass_biumem_we ) ways_dirty_o <= {WAYS{biu_line_dirty_i}} & fill_way_i;
    else if (latchmem_i        ) ways_dirty_o <= way_dirty;


  //selected way is dirty
  always @(posedge clk_i)
    if      ( bypass_biumem_we) way_dirty_o <= biu_line_dirty_i;
    else if (latchmem_i       ) way_dirty_o <= way_dirty[fill_way_select_int_dly];


  always @(posedge clk_i)
    if (latchmem_i) fill_way_o <= fill_way_select_dly;


  /* TAG output
   * Used for EVICT address generation
   */
  always @(posedge clk_i)
    if      ( cleaning_i ) evict_tag <= tag_out[clean_way_int_o].tag;   //this takes forever, can use clean_way_int_o
    else if ( evict_latch) evict_tag <= tag_out[evict_way_select_int].tag;


  always @(posedge clk_i)
    if      ( cleaning_i ) evict_idx <= clean_idx_dly;
    else if ( evict_latch) evict_idx <= filling_idx;


  assign evict_adr_o = { evict_tag, evict_idx, {BLK_OFFS_BITS{1'b0}} };


  //----------------------------------------------------------------
  // Data Memory
  //----------------------------------------------------------------

  //Memory Index
  always_comb
    unique casex ( {cleaning_i, evict_read_i, biumem_we, writebuffer_we} )
      {4'b1???}: dat_idx = clean_idx_i;
      {4'b?1??}: dat_idx = filling_idx;
      {4'b??1?}: dat_idx = filling_idx;
      {4'b???1}: dat_idx = writebuffer_idx_i;
      default  : dat_idx = rd_idx_i;
    endcase


  //generate DAT-memory data input
  assign dat_in = writebuffer_we ? {BLK_BITS/XLEN{writebuffer_data_i}}
                                 : biu_line_i;


  //generate DAT-memory byte enable
  assign dat_be = writebuffer_we ? writebuffer_be_i
                                 : {BLK_BITS/8{1'b1}};


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
        .be_i       ( dat_be        ),
        .din_i      ( dat_in        ),
        .dout_o     ( dat_out[way]) );


      /* Data Write Enable
       */
      assign dat_we[way] = (biumem_we      & fill_way_i[way]            ) |
                           (writebuffer_we & writebuffer_ways_hit_i[way]);
      
      /* Bypass Data Output
      */
      assign dat_out_bypassed[way] = be_mux(bypass_writebuffer_we[way],
                                            writebuffer_be_i,
                                            dat_out[way],
                                            {BLK_BITS/XLEN{writebuffer_data_i}});

      /* Data Ouput Mux
       * assign way_q; Build MUX (AND/OR) structure
       */
      if (way == 0)
        assign way_q_mux[way] =  dat_out_bypassed[way] & {BLK_BITS{way_hit[way]}};
      else
        assign way_q_mux[way] = (dat_out_bypassed[way] & {BLK_BITS{way_hit[way]}}) | way_q_mux[way -1];
  end
endgenerate


  /* Cache line output
   */
  always @(posedge clk_i)
    if      ( bypass_biumem_we ) cache_line_o <= biu_line_i;
    else if ( latchmem_i       ) cache_line_o <= way_q_mux[WAYS-1];


  /* Evict line output
   */
  always @(posedge clk_i)
    if      ( cleaning_i  ) evict_line_o <= dat_out_bypassed[clean_way_int_o]; //takes forever, can use clean_way_int_o
    else if ( evict_latch ) evict_line_o <= dat_out_bypassed[evict_way_select_int];
endmodule



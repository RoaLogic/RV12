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
//    Data Cache (Write Back implementation)                   //
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

module riscv_dcache_core #(
  parameter XLEN        = 32,
  parameter PHYS_ADDR_SIZE = XLEN,

  parameter SIZE        = 64, //KBYTES
  parameter BLOCK_SIZE  = 32, //BYTES, number of bytes in a block (way). Must be multiple of XLEN/8. And max. 16*(XLEN/8)
  parameter WAYS        =  2, // 1           : Direct Mapped
                              //<n>          : n-way set associative
                              //<n>==<blocks>: fully associative
  parameter REPLACE_ALG = 1,  //0: Random
                              //1: FIFO
                              //2: LRU

  parameter TECHNOLOGY  = "GENERIC"
)
(
  input                           rstn,
  input                           clk,
 
  //CPU side
  input      [XLEN          -1:0] mem_adr,
                                  mem_d,         //from CPU
  input                           mem_req,
                                  mem_we,
  input      [XLEN/8        -1:0] mem_be,
  output reg [XLEN          -1:0] mem_q,       //to CPU
  output reg                      mem_ack,
  input      [               1:0] st_prv,
  input                           bu_cacheflush,
  output reg                      dcflush_rdy,

  //To BIU
  output reg                      biu_stb,
  input                           biu_stb_ack,
  output reg [PHYS_ADDR_SIZE-1:0] biu_adri,
  input      [PHYS_ADDR_SIZE-1:0] biu_adro,
  output reg [XLEN/8        -1:0] biu_be,       //Byte enables
  output reg [               2:0] biu_type,     //burst type -AHB style
  output                          biu_lock,
  output reg                      biu_we,
  output reg [XLEN          -1:0] biu_di,
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
  localparam SETS         = (SIZE*1024) / BLOCK_SIZE / WAYS;    //Number of sets TODO:SETS=1 doesn't work
  localparam BLK_OFF_BITS = $clog2(BLOCK_SIZE);                 //Number of BlockOffset bits
  localparam IDX_BITS     = $clog2(SETS);                       //Number of Index-bits
  localparam TAG_BITS     = XLEN - IDX_BITS - BLK_OFF_BITS;     //Number of TAG-bits
  localparam LRU_BITS     = $clog2(WAYS);
  localparam BLK_BITS     = 8*BLOCK_SIZE;                       //Total number of bits in a Block
  localparam BURST_SIZE   = BLK_BITS / XLEN;                    //Number of transfers to load 1 Block
  localparam BURST_BITS   = $clog2(BURST_SIZE);
  localparam BURST_OFF    = XLEN/8;
  localparam BURST_LSB    = $clog2(BURST_OFF);

  //partial BLOCK decoding done by Data Memory
  localparam DAT_ABITS    = $clog2(BLK_BITS / XLEN);            //Number of abits added to Data Memory
  localparam DAT_IDX_LSB  = $clog2(XLEN/8);
  localparam DAT_IDX_BITS = IDX_BITS + DAT_ABITS;


  //Memory FIFO
  localparam MEM_FIFO_DEPTH = 4;


  //////////////////////////////////////////////////////////////////
  //
  // Functions
  //
  function integer onehot2int;
    input [WAYS-1:0] a;

    integer i;

    for (i=0; i<WAYS; i++)
      if (a[i]) onehot2int = i;
  endfunction


  function [LRU_BITS-1:0] new_lru;
    input [LRU_BITS-1:0] old_lru;
    input [LRU_BITS-1:0] replaced_lru;

    if (old_lru < replaced_lru) new_lru = old_lru;
    else                        new_lru = old_lru -1;
  endfunction


  function [XLEN-1:0] be_mux;
    input [XLEN/8-1:0] be;
    input [XLEN  -1:0] a;
    input [XLEN  -1:0] b;

    integer i;

    for (i=0; i<XLEN/8;i++)
      be_mux[i*8 +: 8] = be[i] ? b[i*8 +: 8] : a[i*8 +: 8];
  endfunction


  //////////////////////////////////////////////////////////////////
  //
  // Typedefs
  //
  typedef struct packed {
    logic [LRU_BITS-1:0] lru;
    logic                valid;
    logic                dirty;
    logic [TAG_BITS-1:0] tag;
  } tag_struct;
  localparam TAG_STRUCT_BITS = (REPLACE_ALG != 0) ? $bits(tag_struct) : $bits(tag_struct) - LRU_BITS;


  //////////////////////////////////////////////////////////////////
  //
  // Variables
  //
  genvar  way;
  integer n;

  /*
   * Input section
   */
  logic                              is_cacheable,
                                     dis_cacheable;         //delayed cacheable check
  logic                              mem_req_cacheable,
                                     mem_req_noncacheable;
  logic                              dmem_req_cacheable,
                                     dmem_req_noncacheable,
                                     dmem_req;              //delayed memory request
  logic [XLEN                  -1:0] dmem_adr;              //registered memory address
  logic                              dmem_we;               //registered write enable
  logic [XLEN                  -1:0] dmem_d;                //registered write data
  logic [XLEN/8                -1:0] dmem_be;               //registered byte enable


  /*
   * Cache Section
   */
//  logic [BLK_OFF_BITS-1:0] block_offset;
  logic [XLEN        -1:0] dat_ridx_adr;
  logic [IDX_BITS    -1:0] tag_ridx, dtag_ridx, ddtag_ridx,
                           tag_widx;
  logic [DAT_IDX_BITS-1:0] dat_ridx, dat_ridx_reg, dat_ridx_reg_plus_one, dat_ridx_nxt,
                           dat_widx;
  logic [TAG_BITS    -1:0] core_tag,
                           core_tag_hold;

  logic [WAYS        -1:0] way_hit;
  logic [WAYS        -1:0] way_dirty, dway_dirty,
                           nxt_way_dirty;
  logic [XLEN        -1:0] way_dat [WAYS]; //only read XLEN from BLK_BITS
  logic                    tag_re;
  logic [WAYS        -1:0] tag_we,
                           dat_we;
  logic [XLEN        -1:0] dat_in,
                           dat_out[WAYS];
  logic [XLEN/8      -1:0] dat_be;
  tag_struct               tag_in [WAYS],
                           tag_out[WAYS],
                           tag_out_hold[WAYS];
  logic                    tag_dirty_hold;


  logic                    kill_cache_ack;
  logic                    cache_raw_hazard;
  logic                    cache_hit,
                           dcache_hit; //for LRU tag-update
  logic                    cache_dirty;
  logic [XLEN        -1:0] cache_dat,
                           cache_raw_dat;

  logic [            19:0] way_random;
  logic [WAYS        -1:0] fill_way_select, dfill_way_select, 
                           fill_way_select_rnd;

  enum logic [7:0] {RESET=8'h0, FLUSH=8'h1, ARMED=8'h2, NONCACHEABLE=8'h4, WAIT4BIU=8'h8, FILL=8'h10, WRITE_SET=8'h20, WRITE_WAY=8'h40} state;
  logic                    hold_bu_cacheflush,
                           flushing,
                           filling,
                           writing;
//  logic [BLK_OFF_BITS-1:0] cnt, nxt_cnt;                   //counts inside block
  logic [BURST_BITS  -1:0] cnt, nxt_cnt;                   //counts inside block
  logic [IDX_BITS    -1:0] ddset_cnt, dset_cnt, set_cnt, nxt_set_cnt; //counts sets
  logic [WAYS        -1:0] way_dirty_select;
  logic [BURST_BITS  -1:0] wrap_adr;


  /*
   * Output Section
   */
  logic                          cacheable_req_pending,
                                 noncacheable_req_pending;

  //ext_dat fifo
  logic [XLEN              -1:0] biu_fifo_data[BURST_SIZE];
  logic [$clog2(BURST_SIZE)-1:0] biu_fifo_wadr;
  logic                          biu_fifo_we,
                                 biu_fifo_re,
                                 biu_fifo_full,
                                 biu_fifo_empty;


  //////////////////////////////////////////////////////////////////
  //
  // Module Body
  //
  import riscv_pkg::*;


  //Is this a cacheable region?
  //MSB=1 non-cacheable (IO region)
  //MSB=0 cacheable (instruction/data region)
  assign is_cacheable = ~mem_adr[PHYS_ADDR_SIZE-1];
  
  assign mem_req_cacheable    = mem_req &  is_cacheable;
  assign mem_req_noncacheable = mem_req & ~is_cacheable;

  //delay memory request
  always @(posedge clk,negedge rstn)
    if (!rstn)
    begin
        dmem_req              <= 'b0;
        dmem_req_cacheable    <= 'b0;
        dmem_req_noncacheable <= 'b0;
    end
    else
    begin
       dmem_req              <= mem_req              | (dmem_req              & ~mem_ack);
       dmem_req_cacheable    <= mem_req_cacheable    | (dmem_req_cacheable    & ~mem_ack);
//       dmem_req_noncacheable <= (mem_req_noncacheable & ~biu_stb_ack) | (dmem_req_noncacheable & ~mem_ack);
       dmem_req_noncacheable <= mem_req_noncacheable | (dmem_req_noncacheable & ~mem_ack);
    end


  //register memory signals
  always @(posedge clk)
    if (mem_req)
    begin
        dis_cacheable <= is_cacheable;
        dmem_adr      <= mem_adr;
        dmem_we       <= mem_we;
        dmem_be       <= mem_be;
        dmem_d        <= mem_d;
    end


  /*
   * + Generate a Tag and Data memory for each way
   * + Generate a Tag comparison for each way
   */
generate
  for (way=0; way<WAYS; way++)
  begin: gen_ways
      //Tag memory
      rl_ram_1r1w #(
        .ABITS      ( IDX_BITS        ),
        .DBITS      ( TAG_STRUCT_BITS ),
        .TECHNOLOGY ( TECHNOLOGY      ) )
      tag_ram (
        .rstn  ( rstn        ),
        .clk   ( clk         ),
        .waddr ( tag_widx    ),
        .we    ( tag_we [way]),
        .be    ( {(TAG_STRUCT_BITS+7)/8{1'b1}} ),
        .din   ( tag_in [way][TAG_STRUCT_BITS-1:0]),

        .raddr ( tag_ridx    ),
        .re    ( tag_re      ),
        .dout  ( tag_out[way][TAG_STRUCT_BITS-1:0]) );

      //Block memory
      rl_ram_1r1w #(
        .ABITS      ( DAT_IDX_BITS ),
        .DBITS      ( XLEN         ),
        .TECHNOLOGY ( TECHNOLOGY   ) )
      data_ram (
        .rstn  ( rstn        ),
        .clk   ( clk         ),
        .waddr ( dat_widx    ),
        .we    ( dat_we[way] ),
        .be    ( dat_be      ),
        .din   ( dat_in      ),

        .raddr ( dat_ridx    ),
        .re    (~dat_we[way] ),
        .dout  ( dat_out[way]) );

      assign way_dirty[way] = tag_out[way].dirty;

      //compare way-tag to TAG;
      assign way_hit[way] = tag_out[way].valid & (tag_out[way].tag == core_tag);

      //assign way-block
      //Clear block if not way_hit OR with other ways (implements MUX)
      if (way == 0)
        assign way_dat[way] =  dat_out[way] & {XLEN{way_hit[way]}};
      else
        assign way_dat[way] = (dat_out[way] & {XLEN{way_hit[way]}}) | way_dat[way -1];
  end


  /*
   * Generate 'hit' and data block
   */
  assign cache_hit   = |way_hit & dmem_req;
  assign cache_dirty = |way_dirty;

/*
  if (DAT_BITS > XLEN)
      assign cache_dat = way_dat[WAYS-1] >> (dmem_adr[DAT_IDX_LSB-1:1] * XLEN);
  else
*/
      assign cache_dat = way_dat[WAYS-1];
endgenerate


  always @(posedge clk)
    case (state)
      WRITE_SET: if (&cnt) dway_dirty <= dway_dirty & ~(1 << onehot2int(dway_dirty));
      default  : dway_dirty <= way_dirty;
    endcase

  always @(posedge clk)
    case (state)
      WRITE_SET: if (~|cnt) nxt_way_dirty <= onehot2int(dway_dirty);
      default  : nxt_way_dirty <= onehot2int(way_dirty);
    endcase


  //used by LRU algorithm, to update 'tag' after a cache-hit (read tag, then update)
  always @(posedge clk)
    dcache_hit <= cache_hit;


  /*
   * Statemachine
   */
  always @(posedge clk, negedge rstn)
    if (!rstn) hold_bu_cacheflush <= 1'b0;
    else       hold_bu_cacheflush <= ~flushing & (bu_cacheflush | hold_bu_cacheflush);


  //generate basic states
  always @(posedge clk,negedge rstn)
    if (!rstn)
    begin
        state    <= RESET;
        flushing <= 1'b1;
        filling  <= 1'b0;
        writing  <= 1'b0;
    end
    else
      case (state)
         //flush FIFO
         RESET    : if (~|set_cnt )
                    begin
                        state    <= ARMED;
                        flushing <= 1'b0;
                        filling  <= 1'b0;
                        writing  <= 1'b0;
                    end

        FLUSH     : if (cache_dirty) //Are there any dirty ways in this set?
                                     //We start checking at the top and count down
                    begin
                        state    <= WRITE_SET;
                        flushing <= 1'b1;
                        filling  <= 1'b0;
                        writing  <= 1'b0;
                    end
                    else if (~|dset_cnt) //no ways to write
                    begin
                        state    <= ARMED;
                        flushing <= 1'b0;
                        filling  <= 1'b0;
                        writing  <= 1'b0;
                    end

        ARMED     : if ( (bu_cacheflush || hold_bu_cacheflush) && !((mem_req && mem_we) || (dmem_req && dmem_we)) )
                    begin
                        //flush when requested and no pending write request
                        state    <= FLUSH;
                        flushing <= 1'b1;
                        filling  <= 1'b0;
                        writing  <= 1'b0;
                    end
                    else if (mem_req || dmem_req)
                      if (mem_req_cacheable || (!mem_req && dmem_req_cacheable))
                      begin
                          if (dmem_req && !cache_hit)
                          begin
                              //Cache miss in a cacheable region

                              if (tag_out[ onehot2int(fill_way_select) ].valid && tag_out[ onehot2int(fill_way_select) ].dirty)
                              begin
                                  //selected Way is dirty, write back to memory
                                  state    <= WRITE_WAY;
                                  flushing <= 1'b0;
                                  filling  <= 1'b0;
                                  writing  <= 1'b1;
                              end
                              else
                              begin
                                  if (biu_stb_ack)
                                  begin
                                      //selected way is not dirty, fill way
                                      state    <= FILL;
                                      flushing <= 1'b0;
                                      filling  <= 1'b1;
                                      writing  <= 1'b0;
                                  end
                                  else
                                  begin
                                      //BIU busy, didn't get biu_stb_ack
                                      state    <= WAIT4BIU;
                                      flushing <= 1'b0;
                                      filling  <= 1'b0;
                                      writing  <= 1'b0;
                                  end
                              end
                          end
                      end
                      else
                      begin
                          state    <= NONCACHEABLE;
                          flushing <= 1'b0;
                          filling  <= 1'b0;
                          writing  <= 1'b0;
                      end

        NONCACHEABLE: if ((biu_wack || biu_rack) && !mem_req_noncacheable)
                      begin
                          //finished non-cacheable access
                          state    <= ARMED;
                          flushing <= 1'b0;
                          filling  <= 1'b0;
                          writing  <= 1'b0;
                      end

        //write a (dirty) way from a set
        WRITE_SET : if (~|dway_dirty && ~|cnt) //cnt counts burst (=1 way). Check all ways!!
                      if (|ddset_cnt)
                      begin
                          state    <= FLUSH;
                          flushing <= 1'b1;
                          filling  <= 1'b0;
                          writing  <= 1'b0; // 1'b1??
                      end
                      else
                      begin
                          state    <= ARMED;
                          flushing <= 1'b0;
                          filling  <= 1'b0;
                          writing  <= 1'b0;
                      end

        WRITE_WAY : if (~|cnt && biu_wack)
                    begin
                        //done writing block
                        state    <= biu_stb_ack ? FILL : WAIT4BIU; //If BIU is still processing the access (e.g. pipelined bus), then go to WAIT4BIU (which moves to FILL)
                        flushing <= 1'b0;
                        filling  <= 1'b1;
                        writing  <= 1'b0;
                    end

         WAIT4BIU : if (biu_stb_ack)
                    begin
                        //got biu_stb_ack from BIU, move to filling
                        state    <= FILL;
                        flushing <= 1'b0;
                        filling  <= 1'b1;
                        writing  <= 1'b0;
                    end

         FILL     : if (~|cnt && biu_rack)
                      if ((mem_req_noncacheable) | (~mem_req & dmem_req_noncacheable))
                      begin
                          state    <= NONCACHEABLE;
                          flushing <= 1'b0;
                          filling  <= 1'b0;
                          writing  <= 1'b0;
                      end
                      else
                      begin
                          state    <= ARMED; //TODO: if another access is pending, should go to FILL again
                          flushing <= 1'b0;
                          filling  <= 1'b0;
                          writing  <= 1'b0;
                      end

/*
         FFLUSH   : if      (~|dcnt                                        ) state <= WAIT;

         FLUSH    : if      (  cache_dirty                                 ) state <= WRITE_ALL;
                    else if (~|set_cnt                                         ) state <= FLUSHWAIT;

         FLUSHWAIT: if      (  cache_dirty                                 ) state <= WRITE_ALL; //tags are 1 cycle delayed, so check here too
                    else                                                     state <= ARMED;

         WRITE_ALL: if      (~|dway_dirty                                  ) state <= FLUSH;
                    else                                                     state <= WRALL_BLK; //assemble dat_ridx from tag_out

         WRALL_BLK: if      (  dat_fifo_empty & biu_ack                    ) state <= WRITE_ALL;

         ARMED    : if      ( (bu_cacheflush | hold_bu_cacheflush) & ~(dmem_req & dmem_we) ) state <= FLUSH;
                    else if ( (mem_adr == dmem_adr) & (dmem_req & dmem_we) & (mem_req & ~mem_we) ) state <= WAIT; //RAW hazard
                    else if ( !cache_hit && dmem_req)
                      if    (  tag_out[ onehot2int(fill_way_select) ].dirty) state <= WRITE_BLK;
                      else                                                   state <= FILL;

         WRITE_BLK: if      (  dat_fifo_empty && biu_ack                   ) state <= FILL;

         FILL     : if      (~|cnt && biu_ack                          ) state <= WAIT;

         WAIT     :                                                          state <= ARMED;
*/
         default  : state <= FLUSH; //kinda like OOPS, how did we get here? Flush and start over.
      endcase



  assign dcflush_rdy = ~(bu_cacheflush | hold_bu_cacheflush | flushing);


  //signals from CPU
  assign core_tag = dmem_adr[ XLEN-1 -: TAG_BITS ]; //allow 1 cycle for TAG memory read 

  //Hold core_tag during filling. Prevents new mem_req (during fill) to mess up the 'tag' value
  always @(posedge clk)
    if (!filling) core_tag_hold <= core_tag;



  //Random generator for RANDOM replacement algorithm
  always @(posedge clk, negedge rstn)
    if      (!rstn               ) way_random <= 'h0;
    else if (!filling && !writing) way_random <= {way_random, way_random[19] ~^ way_random[16]};


generate
  //Fix way-select for Direct Mapped cache (WAYS=1)
  if (WAYS == 1)
    assign fill_way_select_rnd = 1;
  else
    assign fill_way_select_rnd = 1 << way_random[LRU_BITS-1:0];
endgenerate


  //select which way to fill (implement replacement algorithms)
generate
  if (REPLACE_ALG == 0)                             //RANDOM
    assign fill_way_select = fill_way_select_rnd;
  else                                              //FIFO + LRU
    for (way=0; way<WAYS; way++)
    begin: gen_way_select
      if (way == 0)
        assign fill_way_select[way] =  ~tag_out[way].valid | ~|tag_out[way].lru;
      else
        assign fill_way_select[way] = (~tag_out[way].valid | ~|tag_out[way].lru) & ~fill_way_select[way-1];
    end
endgenerate

  //FILL / WRITE_WAYS use fill_way_select 1 cycle later
  always @(posedge clk)
    if (!filling && !writing) dfill_way_select <= fill_way_select;


  /*
   * Generate Cache Data
   */

  //generate Write Enable signals
generate
  for (way=0; way<WAYS; way++)
  begin: gen_dat_we
      //Data (Block) write enable
      assign dat_we[way] = writing ? 1'b0
                                   : filling ? dfill_way_select[way] & biu_rack
                                             : way_hit[way] & dmem_req & dmem_we;
  end
endgenerate


  //generate Dat Byte-Enable
  assign dat_be = filling ? {XLEN/8{1'b1}}
                            : dmem_be;

  //generate BLOCK data
  assign dat_in = filling ? dmem_we && (biu_adro[PHYS_ADDR_SIZE-1:BURST_LSB] == dmem_adr[PHYS_ADDR_SIZE-1:BURST_LSB]) ? be_mux(dmem_be, biu_do, dmem_d)
                                                                                                                      : biu_do
                          : dmem_d;

  //composed byte address
  assign dat_ridx_adr = { tag_out_hold[ nxt_way_dirty ].tag, ddset_cnt, {BLK_OFF_BITS{1'b0}} };

  assign dat_ridx_reg_plus_one = dat_ridx_reg +1;
  assign dat_ridx_nxt          = {dat_ridx_reg[DAT_IDX_BITS-1:DAT_ABITS],dat_ridx_reg_plus_one[DAT_ABITS-1:0]};

  always_comb
    case (state)
      ARMED        : if ( (bu_cacheflush || hold_bu_cacheflush) && !((mem_req && mem_we) || (dmem_req && dmem_we)) )
                       dat_ridx = { set_cnt, {DAT_ABITS{1'b0}} }; //==set_cnt={IDX_BITS{1'b1}}
                     else if (dmem_req_cacheable && !cache_hit) 
                       dat_ridx = dmem_adr[ DAT_IDX_LSB +: DAT_IDX_BITS ] & { {XLEN-BURST_BITS{1'b1}}, {BURST_BITS{1'b0}} };
                     else
                       dat_ridx = mem_adr[ DAT_IDX_LSB +: DAT_IDX_BITS ];
      FLUSH        : dat_ridx = { dset_cnt, {DAT_ABITS{1'b0}} };
      WRITE_SET    : dat_ridx = biu_wack | biu_stb_ack ? dat_ridx_nxt : dat_ridx_reg;
      WRITE_WAY    : dat_ridx = biu_wack | biu_stb_ack ? dat_ridx_nxt : dat_ridx_reg;
      WAIT4BIU     : dat_ridx = biu_wack | biu_stb_ack ? dat_ridx_nxt : dat_ridx_reg;
      FILL         : dat_ridx = dmem_adr[ DAT_IDX_LSB +: DAT_IDX_BITS ];
      default      : dat_ridx = mem_adr[ DAT_IDX_LSB +: DAT_IDX_BITS ];
    endcase

  //registered version of dat_ridx. Same delay as input registers in memory
  always @(posedge clk)
    dat_ridx_reg <= dat_ridx;


  always_comb
    case (state)
      FILL   : dat_widx = biu_adro[ DAT_IDX_LSB +: DAT_IDX_BITS ];
      default: dat_widx = dmem_adr[ DAT_IDX_LSB +: DAT_IDX_BITS ];
    endcase




  /*
   * generate TAG data
   */
  //stretch 'dirty', for when a write happens early in a fill-burst
  always @(posedge clk)
    tag_dirty_hold <= filling & ((dmem_req_cacheable & dmem_we) | tag_dirty_hold);

  always @(posedge clk)
    if (state != WRITE_WAY && state != WRITE_SET) tag_out_hold <= tag_out;

 
  //generate Index
  always_comb
    case (state)
      RESET        : tag_ridx = mem_adr[ BLK_OFF_BITS +: IDX_BITS ];
      ARMED        : tag_ridx = (bu_cacheflush || hold_bu_cacheflush) &&
                               !((mem_req && mem_we) || (dmem_req && dmem_we)) ? set_cnt
                                                                               : mem_adr[ BLK_OFF_BITS +: IDX_BITS ];
      FLUSH        : tag_ridx = set_cnt;
      WRITE_SET    : tag_ridx = ddset_cnt;
      WRITE_WAY    : tag_ridx = ddtag_ridx;
      WAIT4BIU     : tag_ridx = ddtag_ridx;
      FILL         : tag_ridx = dmem_req_cacheable  & ~mem_ack ? dmem_adr[ BLK_OFF_BITS +: IDX_BITS ]
                                                               :  mem_adr[ BLK_OFF_BITS +: IDX_BITS ];
      default      : tag_ridx = mem_adr[ BLK_OFF_BITS +: IDX_BITS ];
    endcase


  always_comb
    case (state)
      RESET    : tag_widx = set_cnt;
      FLUSH    : tag_widx = dset_cnt;
      WRITE_SET: tag_widx = ddset_cnt;
      FILL     : tag_widx = biu_adro [ BLK_OFF_BITS +: IDX_BITS ];
      default  : tag_widx = dmem_adr[ BLK_OFF_BITS +: IDX_BITS ];
    endcase


  always @(posedge clk)
    dtag_ridx <= tag_ridx;

  always @(posedge clk)
    if (state != WRITE_WAY) ddtag_ridx <= dtag_ridx;

  //generate TAG-RE
  //for those memory models that barf on an 'x' on 're'
  assign tag_re = dmem_req_cacheable & ~mem_ack ? dmem_req_cacheable : mem_req_cacheable;


generate
  //generate TAG-WE
  for (way=0; way<WAYS; way++)
  begin: gen_way_we
      //Tag write enables
      if      (REPLACE_ALG == 0) //Random
        assign tag_we[way] =  flushing                                                    | //update during flushing (clear valid and dirty tags)
                             (filling & dfill_way_select[way] & biu_rack & ~|cnt)         | //update way being filled
                             ( (state == ARMED) & way_hit[way] & dmem_req & dmem_we);                   //update during data-write (dirty tag, 1 cycle delay)
      else if (REPLACE_ALG == 1) //FIFO
        assign tag_we[way] = flushing | (filling & biu_rack & ~|cnt);                         //update all ways upon filling
      else if (REPLACE_ALG == 2) //LRU
        assign tag_we[way] = flushing | (filling & biu_rack & ~|cnt) | dcache_hit;            //update all ways upon filling and reading (1 cycle later)
  end


  //generate TAG-IN
  for (way=0; way<WAYS; way++)
  begin: gen_tag
      if      (REPLACE_ALG == 0) //random
      begin
          assign tag_in[way].valid = ~flushing;
          assign tag_in[way].dirty = ~flushing & (filling ? tag_dirty_hold : dmem_we);
          assign tag_in[way].lru   = 'h0;
          assign tag_in[way].tag   = filling ? core_tag_hold : core_tag;
      end
      else if (REPLACE_ALG == 1) //FIFO
      begin
          assign tag_in[way].valid = ~flushing & (tag_out[way].valid | fill_way_select[way]);
          assign tag_in[way].dirty = fill_way_select[way] ? tag_dirty_hold
                                                          : tag_out[way].dirty;
          assign tag_in[way].lru   = fill_way_select[way] ? {LRU_BITS{1'b1}} : tag_out[way].lru -1;
          assign tag_in[way].tag   = fill_way_select[way] ? filling ? core_tag_hold : core_tag
                                                          : tag_out[way].tag;
      end
      else if (REPLACE_ALG == 2) //LRU
      begin
          //LRU writes during reads too. So update 'valid' only while filling
          assign tag_in[way].valid = ~flushing & ( tag_out[way].valid | (filling & fill_way_select[way]) );
          assign tag_in[way].dirty = fill_way_select[way] ? tag_dirty_hold
                                                          : tag_out[way].dirty;
          assign tag_in[way].lru   = filling ? fill_way_select[way] ? {LRU_BITS{1'b1}} : new_lru( tag_out[way].lru, tag_out[ onehot2int(fill_way_select) ].lru )
                                             : way_hit[way]         ? {LRU_BITS{1'b1}} : new_lru( tag_out[way].lru, tag_out[ onehot2int(way_hit        ) ].lru );
          assign tag_in[way].tag   = fill_way_select[way] ? filling ? core_tag_hold : core_tag
                                                                    : tag_out[way].tag;
      end
  end //next way
endgenerate




  /*
   * Internal counting signals
   */
  always_comb
    case (state)
      RESET    : nxt_set_cnt = set_cnt -1;
      ARMED    : nxt_set_cnt = (bu_cacheflush || hold_bu_cacheflush) && !(mem_req && mem_we) ? set_cnt -1
                                                                                           : {IDX_BITS{1'b1}};
      FLUSH    : nxt_set_cnt = set_cnt -1; //cache_dirty ? set_cnt : set_cnt -1;
      default  : nxt_set_cnt = set_cnt; //{IDX_BITS{1'b1}}; //reset, just in case
    endcase

  always_comb
    case (state)
//        FLUSH     : nxt_cnt = cache_dirty ? cnt -1 :BURST_SIZE -1;
        FLUSH     : nxt_cnt = BURST_SIZE -1;
        ARMED     : nxt_cnt = BURST_SIZE -1;
        FILL      : nxt_cnt = biu_rack ? cnt -1 : cnt;
        WRITE_SET : nxt_cnt = biu_wack | biu_stb_ack ? cnt -1 : cnt; //biu_ack     ? cnt -1 : cnt;
        WRITE_WAY : nxt_cnt = biu_wack | biu_stb_ack ? cnt -1 : cnt; //biu_fifo_empty && biu_ack ? BURST_SIZE -1
                                     //                  : biu_fifo_we ? cnt -1 : cnt;
        WAIT4BIU  : nxt_cnt = BURST_SIZE -1;
	default   : nxt_cnt = cnt;
    endcase


  always @(posedge clk,negedge rstn)
    if (!rstn) set_cnt <= {IDX_BITS{1'b1}};
    else       set_cnt <= nxt_set_cnt;


  always @(posedge clk)
    cnt <= nxt_cnt;


  always @(posedge clk,negedge rstn)
    if (!rstn)         dset_cnt <= {IDX_BITS{1'b1}};
    else
      case (state)
         WRITE_SET: if (~|cnt && ~|dway_dirty)
                    begin
                        dset_cnt  <= set_cnt;
                        ddset_cnt <= dset_cnt;
                    end

         default  : begin
                        dset_cnt <= set_cnt;
                        ddset_cnt <= dset_cnt;
                    end
      endcase




  /*
   * CPU response signals
   */
  always_comb
    case (state)
      ARMED        : mem_ack = cache_hit & ~kill_cache_ack;
      FILL         : mem_ack = biu_rack & (biu_adro[PHYS_ADDR_SIZE-1:BURST_LSB] == dmem_adr[PHYS_ADDR_SIZE-1:BURST_LSB]);
      NONCACHEABLE : mem_ack = biu_wack | biu_rack;
      default: mem_ack = 'b0;
    endcase


  always @(posedge clk)
    kill_cache_ack <= (state == RESET) | ( (state == FILL) & mem_ack & ~mem_req); //prevent ACK during fill to generate a 2nd ACK in ARMED and after RESET


  //Assign mem_q
  //Handle Read-after-Write hazards
  always @(posedge clk)
  begin
      cache_raw_hazard <= (mem_adr == dmem_adr) & (dmem_req & dmem_we) & (mem_req & ~mem_we);
      cache_raw_dat    <=  be_mux(dmem_be, cache_dat, dmem_d);
  end

  assign mem_q = (filling | dmem_req_noncacheable) ? biu_do
                                                   : cache_raw_hazard ? cache_raw_dat //RAW hazard
                                                                      : cache_dat;







  /*
   * ---------------  External Interface  ---------------------
   */

  //next fill-address, wrap around, ignore LSBs (they are zero)
  assign wrap_adr = biu_adro[BURST_LSB +: BURST_BITS] + 1;


  //Is there a non-cacheable request pending?
  //Stretches biu_stb when moving from ARMED to NONCACHEABLE
  //mem_req_noncacheable & ~biu_stb_ack     --> biu immediately starts transfer. Normally 1st transfer when in ARMED state. Prevent generating new biu_stb in NONCACHEABLE.
  //                                            A 2nd mem_req_noncacheable doesn't generate biu_stb_ack, thus stretch that request
  //noncacheable_req_pending & ~biu_stb_ack --> clear stretch when BIU accepts 2nd transfer
  always @(posedge clk,negedge rstn)
    if (!rstn) noncacheable_req_pending <= 1'b0;
    else       noncacheable_req_pending <= (mem_req_noncacheable & ~biu_stb_ack) | (noncacheable_req_pending & ~biu_stb_ack);


  //same as 'noncacheable_req_pending', but now for cacheable requests.
  //Stretch biu_stb in FILL state when BIU is (still) busy with previous request
  always @(posedge clk,negedge rstn)
    if (!rstn) cacheable_req_pending <= 1'b0;
    else       cacheable_req_pending <= (mem_req_cacheable & ~biu_stb_ack) | (cacheable_req_pending & ~cache_hit & ~biu_stb_ack);


  always_comb
    case (state)
      ARMED  : if (mem_req || dmem_req)
               begin
                   if (mem_req_cacheable || (!mem_req && dmem_req_cacheable))
                   begin
                       if (tag_out[ onehot2int(fill_way_select) ].dirty && tag_out[ onehot2int(fill_way_select) ].valid)
                       begin //move to WRITE_WAY
                           biu_stb  = 1'b0;
                           biu_we   = 1'b1;
                           biu_adri = { tag_out[ onehot2int(fill_way_select) ].tag, dmem_adr[ BLK_OFF_BITS +: IDX_BITS ], {BLK_OFF_BITS{1'b0}} };
                       end
                       else
                       begin //move to FILL
                           biu_stb = dmem_req & ~cache_hit;
                           biu_we   = 1'b0;
                           biu_adri = { dmem_adr[PHYS_ADDR_SIZE-1:BURST_LSB],{BURST_LSB{1'b0}} };
                       end
                   end
                   else //non-cacheable access
                   begin
                       biu_stb  = 1'b1;
                       biu_we   = mem_req ? mem_we
                                          :dmem_we;
                       biu_adri = mem_req ? mem_adr[PHYS_ADDR_SIZE-1:0]  //access to non-cacheble region; not a wrapping burst
                                          :dmem_adr[PHYS_ADDR_SIZE-1:0];
                   end
               end
               else
               begin
                   biu_stb  = 1'b0;
                   biu_we   = 1'bx;
                   biu_adri =  'hx;
               end

      NONCACHEABLE : begin
                         biu_stb  = mem_req_noncacheable | noncacheable_req_pending;
                         biu_we   = noncacheable_req_pending ? dmem_we
                                                             : mem_we;
                         biu_adri = noncacheable_req_pending ? dmem_adr[PHYS_ADDR_SIZE-1:0]  //access to non-cacheble region; not a wrapping burst
                                                             : mem_adr[PHYS_ADDR_SIZE-1:0];
                     end

      WRITE_WAY    : begin
                           biu_stb  = 1'b1;
                           biu_we   = 1'b1;
                           biu_adri = { tag_out_hold[ onehot2int(dfill_way_select) ].tag, dmem_adr[ BLK_OFF_BITS +: IDX_BITS ], {BLK_OFF_BITS{1'b0}} };
                     end

      WAIT4BIU     : begin
                         //BIU is buys, keep biu_stb asserted
                         biu_stb  = 1'b1;
                         biu_we   = 1'b0;
                         biu_adri = { dmem_adr[PHYS_ADDR_SIZE-1:BURST_LSB],{BURST_LSB{1'b0}} };
                     end

      FILL   : begin
                   //Cannot start a new access while filling ... bus occupied
                   //TODO: can start during last access and non-cacheable
                   biu_stb  = ((mem_req_noncacheable) | (~mem_req & dmem_req_noncacheable)) & (~|cnt & biu_rack);
                   biu_we   = mem_req ? mem_we                      //don't care when biu_stb = 1'b0
                                      :dmem_we;
                   biu_adri = mem_req ? mem_adr[PHYS_ADDR_SIZE-1:0] //don't care when biu_stb = 1'b0
                                      :dmem_adr[PHYS_ADDR_SIZE-1:0];
               end

      WRITE_SET: begin
                     biu_stb  = |dway_dirty; //cache_dirty;
                     biu_we   = 1'b1;
                     biu_adri = dat_ridx_adr[PHYS_ADDR_SIZE-1:0];
                  end

      default: begin
                   biu_stb  = 1'b0;
                   biu_we   = 1'bx;
                   biu_adri =  'hx;
               end
    endcase

/*
  always @(posedge clk, negedge rstn)
    if (!rstn)
    begin
        biu_stb <= 'b0;
        biu_adri <= 'h0;
        biu_we  <= 'b0;
    end
    else
      case (state)
        FLUSH    : if ( cache_dirty)
                   begin
                       biu_adri <= {tag_out[ onehot2int(way_dirty) ].tag,dtag_ridx,{BLK_OFF_BITS{1'b0}}};
                   end
        ARMED    : if (!cache_hit && dmem_req)
                   begin
                       biu_stb <= 'b1;
                       biu_we  <= tag_out[ onehot2int(fill_way_select) ].dirty;
                       biu_adri <= {dmem_adr[XLEN-1:BURST_LSB],{BURST_LSB{1'b0}}}; //LSBs are always zero
                   end
        FILL     : if (biu_ack)
                   begin
                       if (~|cnt) biu_stb <= 'b0;

                       //compile external address
                       //MSBs of current addres, wrapping-LSBs, zero-LSBs
                       biu_adri <= {biu_adri[XLEN-1:BURST_BITS+BURST_LSB], wrap_adr, {BURST_LSB{1'b0}}};
                   end
        WRITE_WAY: if (biu_ack)
                   begin
                       if (dat_fifo_empty)
                       begin
//                           ext_req <= 'b0; //WRITE_BLK always moves to FILL
                           biu_we  <= 'b0;
                       end

                       //compile external address
                       //MSBs of current addres, wrapping-LSBs, zero-LSBs
                       biu_adri <= {biu_adri[XLEN-1:BURST_BITS+BURST_LSB], wrap_adr, {BURST_LSB{1'b0}}};
                   end

        WRALL_BLK: begin
                       biu_stb <= 'b1;
                       biu_we  <= 'b1; 
                       if (biu_ack)
                       begin
                           if (!dat_fifo_empty)
                             biu_adri <= {biu_adri[XLEN-1:BURST_BITS+BURST_LSB], wrap_adr, {BURST_LSB{1'b0}}};
                           else if ( |nxt_way_dirty )
                           begin
                               biu_adri <= dat_ridx_adr;
                           end
                           else
                           begin
                               biu_stb <= 'b0;
                               biu_we  <= 'b0;
                           end
                       end
                   end

        default: ;
      endcase
*/



  /*
   * biu_di fifo
   */

  always @(posedge clk,negedge rstn)
    if (!rstn) biu_fifo_wadr <= 'h0;
    else
      case ({biu_fifo_we,biu_fifo_re})
         2'b01  : biu_fifo_wadr <= biu_fifo_wadr -1;
         2'b10  : biu_fifo_wadr <= biu_fifo_wadr +1;
         default: ;
      endcase


  always @(posedge clk)
    case ({biu_fifo_we,biu_fifo_re})
       2'b01  : for (n=0;n<MEM_FIFO_DEPTH-1;n++)
                  biu_fifo_data[n] <= biu_fifo_data[n+1];
       2'b10  : biu_fifo_data[biu_fifo_wadr] <= dat_out[ onehot2int(fill_way_select) ];
       2'b11  : begin
                    for (n=0;n<MEM_FIFO_DEPTH-1;n++)
                      biu_fifo_data[n] <= biu_fifo_data[n+1];

                    biu_fifo_data[biu_fifo_wadr] <= dat_out[ onehot2int(fill_way_select) ];
                end
       default: ;
    endcase


  always @(posedge clk,negedge rstn)
    if (!rstn) biu_fifo_full <= 1'b0;
    else
      case ({biu_fifo_we,biu_fifo_re})
         2'b01  : biu_fifo_full <= 1'b0;
         2'b10  : biu_fifo_full <= &biu_fifo_wadr;
         default: ;
      endcase

  always @(posedge clk,negedge rstn)
    if (!rstn) biu_fifo_empty <= 1'b1;
    else
      case ({biu_fifo_we,biu_fifo_re})
         2'b01  : biu_fifo_empty <= ~|biu_fifo_wadr;
         2'b10  : biu_fifo_empty <= 1'b0;
         default: ;
      endcase


  /*
   * External Interface
   */
  assign biu_lock           = 1'b0;
  assign biu_is_cacheable   = is_cacheable;
  assign biu_is_instruction = 1'b0;         //This is a Data cache
  assign biu_prv            = st_prv;

  always_comb
    case (state)
      ARMED        : if (mem_req_cacheable || (!mem_req && dmem_req_cacheable))
                     begin
                         biu_di = biu_fifo_empty ? dat_out[ onehot2int(fill_way_select) ] : biu_fifo_data[0];
                         biu_be = {XLEN/8{1'b1}};
                     end
                     else
                     begin
                         biu_di = mem_req ? mem_d  : dmem_d;
                         biu_be = mem_req ? mem_be : dmem_be;
                     end

      NONCACHEABLE : begin
                         biu_di = noncacheable_req_pending ? dmem_d  : mem_d;
                         biu_be = noncacheable_req_pending ? dmem_be : mem_be;
                     end

      WRITE_WAY    : begin
                         biu_di = dat_out[ onehot2int(dfill_way_select) ]; 
                         biu_be = {XLEN/8{1'b1}};
                     end

      WAIT4BIU     : begin
                         biu_di = dat_out[ onehot2int(dfill_way_select) ]; 
                         biu_be = {XLEN/8{1'b1}};
                     end

      FILL         : if(!is_cacheable && ~|cnt && biu_rack)
                     begin
                         biu_di = mem_req ? mem_d  : dmem_d;
                         biu_be = mem_req ? mem_be : dmem_be;
                     end
                     else
                     begin
                         biu_di = 'hx;
                         biu_be = {XLEN/8{1'b1}};
                     end

      FLUSH        : begin
                         biu_di = dat_out[ nxt_way_dirty ];
                         biu_be = {XLEN/8{1'b1}};
                     end

      WRITE_SET    : begin
                         biu_di = dat_out[ nxt_way_dirty ];
                         biu_be = {XLEN/8{1'b1}};
                     end

      default: begin
                   biu_di = biu_fifo_empty ? dat_out[ onehot2int(fill_way_select) ] : biu_fifo_data[0];
                   biu_be = {XLEN/8{1'b1}};
               end
    endcase


  assign biu_fifo_re = biu_fifo_empty ? 1'b0
                                      : ((state == FLUSH    ) |
                                         (state == WRITE_SET) |
                                         (state == WRITE_WAY) ) & biu_wack;
  assign biu_fifo_we = biu_fifo_full  ? 1'b0 
                                      : ((state == FLUSH    ) & cache_dirty ) |
                                        ((state == WRITE_SET)               ) |
                                        ( state == WRITE_WAY                );

  
  //burst size
  always_comb
    if (!(cacheable_req_pending && !mem_ack) &&
        ((state==ARMED && !is_cacheable                     ) ||
         (state==FILL  && ~|cnt && biu_rack && ((mem_req_noncacheable) | (~mem_req & dmem_req_noncacheable))) ||
         (state==NONCACHEABLE                               )  )
       ) biu_type = 3'h0; //single access
    else
      case(BURST_SIZE)
         16     : biu_type = 3'b110;    //wrap16
         8      : biu_type = 3'b100;    //wrap8
         default: biu_type = 3'b010;    //wrap4
      endcase
endmodule



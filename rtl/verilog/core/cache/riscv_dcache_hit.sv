/////////////////////////////////////////////////////////////////////
//   ,------.                    ,--.                ,--.          //
//   |  .--. ' ,---.  ,--,--.    |  |    ,---. ,---. `--' ,---.    //
//   |  '--'.'| .-. |' ,-.  |    |  |   | .-. | .-. |,--.| .--'    //
//   |  |\  \ ' '-' '\ '-'  |    |  '--.' '-' ' '-' ||  |\ `--.    //
//   `--' '--' `---'  `--`--'    `-----' `---' `-   /`--' `---'    //
//                                             `---'               //
//    RISC-V                                                       //
//    Data Cache Hit Stage                                         //
//                                                                 //
/////////////////////////////////////////////////////////////////////
//                                                                 //
//             Copyright (C) 2014-2018 ROA Logic BV                //
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
import biu_constants_pkg::*;


module riscv_dcache_hit #(
  parameter XLEN           = 32,
  parameter PLEN           = XLEN,

  parameter SIZE           = 64,
  parameter BLOCK_SIZE     = XLEN,
  parameter WAYS           = 2,

  parameter INFLIGHT_DEPTH = 2,

  localparam SETS          = no_of_sets(SIZE, BLOCK_SIZE, WAYS),
  localparam BLK_BITS      = no_of_block_bits(BLOCK_SIZE),
  localparam BLK_OFFS_BITS = no_of_block_offset_bits(BLOCK_SIZE),
  localparam DAT_OFFS_BITS = no_of_data_offset_bits (XLEN, BLK_BITS),   //Offset in block
  localparam IDX_BITS      = no_of_index_bits(SETS),
  localparam TAG_BITS      = no_of_tag_bits(XLEN, IDX_BITS, BLK_OFFS_BITS),

  localparam INFLIGHT_BITS = $clog2(INFLIGHT_DEPTH+1)
)
(
  input  logic                        rst_ni,
  input  logic                        clk_i,

  output logic                        stall_o,
  input  logic                        flush_i,           //flush pipe

  input  logic                        cacheflush_req_i,  //flush cache
  output logic                        cacheflush_rdy_o,  //data cache flush ready
  output logic                        armed_o,
  output logic                        flushing_o,
  output logic                        filling_o,
  input  logic [WAYS            -1:0] fill_way_i,
  output logic [WAYS            -1:0] fill_way_o,

  input  logic                        req_i,             //from previous-stage
  input  logic                        wreq_i,
  input  logic [PLEN            -1:0] adr_i,
  input  biu_size_t                   size_i,
  input  logic                        lock_i,
  input  biu_prot_t                   prot_i,
  input  logic                        we_i,
  input  logic [XLEN/8          -1:0] be_i,
  input  logic [XLEN            -1:0] d_i,
  input  logic                        is_cacheable_i,
  output logic [XLEN            -1:0] q_o,
  output logic                        ack_o,
  output logic                        err_o,
  output logic                        misaligned_o,

  //To/From Cache Memories
  input  logic                        cache_hit_i,       //from cache-memory
  input  logic [WAYS            -1:0] ways_hit_i,
  input  logic [BLK_BITS        -1:0] cache_line_i,
  input  logic                        cache_dirty_i,
  input  logic                        way_dirty_i,
  output logic [IDX_BITS        -1:0] idx_o,
  output logic [TAG_BITS        -1:0] core_tag_o,

  //WriteBuffer
  output logic                        writebuffer_we_o,
  input  logic                        writebuffer_ack_i,
  output logic [IDX_BITS        -1:0] writebuffer_idx_o,
  output logic [DAT_OFFS_BITS   -1:0] writebuffer_offs_o,
  output logic [XLEN            -1:0] writebuffer_data_o,
  output logic [BLK_BITS/8      -1:0] writebuffer_be_o,       //writebuffer_be is already blk_bits aligned
  output logic [WAYS            -1:0] writebuffer_ways_hit_o,

  //EvictBuffer
  input  logic [TAG_BITS        -1:0] evict_tag_i,
  input  logic [BLK_BITS        -1:0] evict_line_i,
  output logic [PLEN            -1:0] evictbuffer_adr_o,
  output logic [BLK_BITS        -1:0] evictbuffer_line_o,

  //To/From BIU
  output biucmd_t                     biucmd_o,
  input  logic                        biucmd_ack_i,
  input  logic                        biucmd_busy_i,
  output logic                        biucmd_noncacheable_req_o,
  input  logic                        biucmd_noncacheable_ack_i,
  input  logic [INFLIGHT_BITS   -1:0] inflight_cnt_i,

  input  logic [XLEN            -1:0] biu_q_i,
  input  logic                        biu_stb_ack_i,
                                      biu_ack_i,
                                      biu_err_i,
  input  logic [PLEN            -1:0] biu_adro_i,
  input  logic                        in_biubuffer_i,
  input  logic [BLK_BITS        -1:0] biubuffer_i
);

  //////////////////////////////////////////////////////////////////
  //
  // Constants
  //
  
  //----------------------------------------------------------------
  // Cache
  //----------------------------------------------------------------
/*
  localparam PAGE_SIZE       = 4*1024;                             //4KB pages
  localparam MAX_IDX_BITS    = $clog2(PAGE_SIZE) - $clog2(BLOCK_SIZE); //Maximum IDX_BITS
  

  localparam SETS            = (SIZE*1024) / BLOCK_SIZE / WAYS;    //Number of sets TODO:SETS=1 doesn't work
  localparam BLK_OFF_BITS    = $clog2(BLOCK_SIZE);                 //Number of BlockOffset bits
  localparam IDX_BITS        = $clog2(SETS);                       //Number of Index-bits
  localparam TAG_BITS        = XLEN - IDX_BITS - BLK_OFF_BITS;     //Number of TAG-bits
  localparam BLK_BITS        = 8*BLOCK_SIZE;                       //Total number of bits in a Block
  localparam BURST_SIZE      = BLK_BITS / XLEN;                    //Number of transfers to load 1 Block
  localparam BURST_BITS      = $clog2(BURST_SIZE);
  localparam BURST_OFF       = XLEN/8;
  localparam BURST_LSB       = $clog2(BURST_OFF);

  //BLOCK decoding
  localparam DAT_OFF_BITS    = $clog2(BLK_BITS / XLEN);            //Offset in block
*/

  localparam BURST_OFF     = XLEN/8;
  localparam BURST_LSB     = $clog2(BURST_OFF);


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


  function automatic [XLEN/8-1:0] size2be;
    input [     2:0] size;
    input [XLEN-1:0] adr;

    logic [$clog2(XLEN/8)-1:0] adr_lsbs;

    adr_lsbs = adr[$clog2(XLEN/8)-1:0];

    unique case (size)
      BYTE : size2be = 'h1  << adr_lsbs;
      HWORD: size2be = 'h3  << adr_lsbs;
      WORD : size2be = 'hf  << adr_lsbs;
      DWORD: size2be = 'hff << adr_lsbs;
    endcase
  endfunction: size2be


  function automatic [BLK_BITS-1:0] be_mux;
    input                  ena;
    input [BLK_BITS/8-1:0] be;
    input [BLK_BITS  -1:0] o; //old data
    input [BLK_BITS  -1:0] n; //new data

    integer i;

    for (i=0; i<BLK_BITS/8;i++)
      be_mux[i*8 +: 8] = ena && be[i] ? n[i*8 +: 8] : o[i*8 +: 8];
  endfunction: be_mux


  //////////////////////////////////////////////////////////////////
  //
  // Typedefs
  //


  //////////////////////////////////////////////////////////////////
  //
  // Variables
  //


  /* Memory Interface State Machine Section
   */
  logic [XLEN          -1:0] cache_q;
  logic                      cache_ack,
                             biu_cacheable_ack;

  enum logic [2:0] {ARMED=0,
                    FLUSH,
                    NONCACHEABLE,
                    EVICT,
                    FLUSHWAYS,
                    WAIT4BIUCMD0,
                    RECOVER} nxt_memfsm_state, memfsm_state;
  biucmd_t                   nxt_biucmd;
  logic [WAYS          -1:0] fill_way;


  logic                      biu_adro_eq_cache_adr;
  logic [DAT_OFFS_BITS -1:0] dat_offset;
  logic                      bypass_writebuffer_we;
  logic [BLK_BITS      -1:0] cache_line;


  //////////////////////////////////////////////////////////////////
  //
  // Module Body
  //

  /* State Machine
   */
  always_comb
  begin
      nxt_memfsm_state = memfsm_state;
      nxt_biucmd       = biucmd_o;
      fill_way         = fill_way_o;

      unique case (memfsm_state)
         ARMED        : if (cacheflush_req_i && !we_i)
                        begin
                            nxt_memfsm_state = FLUSH;
                            nxt_biucmd       = BIUCMD_NOP;
                        end
                        else if (req_i && !is_cacheable_i && !flush_i && !biucmd_busy_i)
                        begin
                            nxt_memfsm_state = NONCACHEABLE;
                            nxt_biucmd       = BIUCMD_NOP;
                        end
                        else if (req_i && is_cacheable_i && !cache_hit_i && !flush_i && !biucmd_busy_i)
                        begin
                            fill_way = fill_way_i; //write to same way as we read

                            if (way_dirty_i)
                            begin
                                //selected way is dirty
                                nxt_memfsm_state = EVICT;
                                nxt_biucmd       = BIUCMD_READWAY; //read new line before evicting old one
                            end
                            else
                            begin
                                //Load way
                                nxt_memfsm_state = WAIT4BIUCMD0;
                                nxt_biucmd       = BIUCMD_READWAY;
                            end
                        end
/*                        else
                        begin
                            nxt_memfsm_state = memfsm_state;
                            nxt_biucmd       = BIUCMD_NOP; //biucmd_o;
                        end
*/
         FLUSH        : if (cache_dirty_i)
                        begin
                            //There are dirty ways in this set
                            //First determine dat_idx; this reads all ways for that index (FLUSH)
                            //then check which ways are dirty (FLUSHWAYS)
                            //write dirty way
                            //clear dirty bit
                           nxt_memfsm_state = FLUSHWAYS;
                           nxt_biucmd       = BIUCMD_NOP;
                        end
                        else
                        begin
                           nxt_memfsm_state = RECOVER; //allow to read new tag_idx
                           nxt_biucmd       = BIUCMD_NOP;
                        end

          FLUSHWAYS   : begin
                            //assert WRITE_WAY here (instead of in FLUSH) to allow time to load evict_buffer
                            nxt_memfsm_state = memfsm_state;
                            nxt_biucmd       = BIUCMD_WRITEWAY;

                            if (biucmd_ack_i)
                            begin
                                //Check if there are more dirty ways in this set
                                if (cache_dirty_i)
                                begin
                                    nxt_memfsm_state = FLUSH;
                                    nxt_biucmd       = BIUCMD_NOP;
                                end
                            end
                        end

          NONCACHEABLE: if ( flush_i                                   ||  //flushed pipe, no biu_ack's will come
                            (!req_i && inflight_cnt_i==1 && biu_ack_i) ||  //no new request, wait for BIU to finish transfer
                            ( req_i && is_cacheable_i    && biu_ack_i) )   //new cacheable request, wait for non-cacheable transfer to finish
                        begin
                            nxt_memfsm_state = ARMED;
                            nxt_biucmd       = BIUCMD_NOP;
                        end

          EVICT       : if (biucmd_ack_i || biu_err_i)
                        begin
                            nxt_memfsm_state = RECOVER;
                            nxt_biucmd       = BIUCMD_WRITEWAY; //evict dirty way
                        end

          WAIT4BIUCMD0: if (biucmd_ack_i || biu_err_i)
                        begin
                            nxt_memfsm_state = RECOVER;
                            nxt_biucmd       = BIUCMD_NOP;
                        end

          RECOVER     : begin
                            //Read TAG and DATA memory after writing/filling
                            nxt_memfsm_state = ARMED;
                            nxt_biucmd       = BIUCMD_NOP;
                        end

          default     : begin
                            //something went really wrong, flush cache
                            nxt_memfsm_state = FLUSH;
                            nxt_biucmd       = BIUCMD_NOP;
                        end
      endcase
  end


  always @(posedge clk_i, negedge rst_ni)
    if (!rst_ni)
    begin
        memfsm_state     <= ARMED;
        biucmd_o         <= BIUCMD_NOP;
        armed_o          <= 1'b1;
        flushing_o       <= 1'b0;
        filling_o        <= 1'b0;
        fill_way_o       <=  'hx;
        cacheflush_rdy_o <= 1'b1;
    end
    else
    begin
        memfsm_state <= nxt_memfsm_state;
        biucmd_o     <= nxt_biucmd;
        fill_way_o   <= fill_way;

        unique case (nxt_memfsm_state)
          ARMED        : begin
                             armed_o          <= 1'b1;
                             flushing_o       <= 1'b0;
                             filling_o        <= 1'b0;
                             cacheflush_rdy_o <= 1'b1;
                         end

          FLUSH        : begin
                             armed_o          <= 1'b0;
                             flushing_o       <= 1'b1;
                             filling_o        <= 1'b0;
                             cacheflush_rdy_o <= 1'b0;
                         end

           FLUSHWAYS   : begin
                             armed_o          <= 1'b0;
                             flushing_o       <= 1'b1;
                             filling_o        <= 1'b0;
                             cacheflush_rdy_o <= 1'b0;
                         end

           NONCACHEABLE: begin
                             armed_o          <= 1'b0;
                             flushing_o       <= 1'b0;
                             filling_o        <= 1'b0;
                             cacheflush_rdy_o <= 1'b1;
                         end

           EVICT       : begin
                             armed_o          <= 1'b0;
                             flushing_o       <= 1'b0;
                             filling_o        <= 1'b1;
                             cacheflush_rdy_o <= 1'b1;
                         end

           WAIT4BIUCMD0: begin
                             armed_o          <= 1'b0;
                             flushing_o       <= 1'b0;
                             filling_o        <= 1'b1;
                             cacheflush_rdy_o <= 1'b1;
                         end

           RECOVER     : begin
                             //Read TAG and DATA memory after writing/filling
                             armed_o          <= 1'b0;
                             flushing_o       <= 1'b0;
                             filling_o        <= 1'b0;
                             cacheflush_rdy_o <= 1'b1;
                         end
        endcase

  end

  //Tag/Dat-index (for writing)
  assign idx_o = adr_i[BLK_OFFS_BITS +: IDX_BITS];


  //core-tag (for writing)
  assign core_tag_o = adr_i[PLEN-1 -: TAG_BITS];


  /* WriteBuffer
  */
  always @(posedge clk_i, negedge rst_ni)
    if      (!rst_ni                                 ) writebuffer_we_o <= 1'b0;
    else if ( flush_i                                ) writebuffer_we_o <= 1'b0;
    else if ( wreq_i && is_cacheable_i && cache_hit_i) writebuffer_we_o <= 1'b1;
    else if ( writebuffer_ack_i                      ) writebuffer_we_o <= 1'b0;


  always @(posedge clk_i)
    if (wreq_i && is_cacheable_i && cache_hit_i)
    begin
        writebuffer_idx_o      <= adr_i[BLK_OFFS_BITS +: IDX_BITS];
        writebuffer_offs_o     <= dat_offset;
        writebuffer_data_o     <= d_i;
        writebuffer_be_o       <= be_i << (dat_offset * XLEN/8);
        writebuffer_ways_hit_o <= ways_hit_i;
    end


  /* EvictBuffer
   */
  always @(posedge clk_i)
    if (memfsm_state == ARMED)
    begin
        evictbuffer_adr_o  <= { evict_tag_i, idx_o, {BLK_OFFS_BITS{1'b0}} };
        evictbuffer_line_o <= evict_line_i;
    end


  /* BIU control
  */
  //non-cacheable access
  always_comb
    unique case (memfsm_state)
      ARMED       : biucmd_noncacheable_req_o = req_i & ~is_cacheable_i & ~flush_i;
      default     : biucmd_noncacheable_req_o = 1'b0;
    endcase


  //address check, used in a few places
  assign biu_adro_eq_cache_adr = (biu_adro_i[PLEN-1:BURST_LSB] == adr_i[PLEN-1:BURST_LSB]);


  //acknowledge cache hit
  assign cache_ack         =  req_i & is_cacheable_i & cache_hit_i & ~flush_i;
  assign biu_cacheable_ack = (req_i & biu_ack_i & biu_adro_eq_cache_adr & ~flush_i) |
                              cache_ack;


  /* Stall
  */
  always_comb
    unique case (memfsm_state)
      ARMED       : stall_o =  (req_i & ~is_cacheable_i & (~biu_stb_ack_i | biucmd_busy_i)) | //non-cacheable access
	                       (req_i &  is_cacheable_i & ~cache_hit_i                    );  //cacheable access

      //req_i == 0 ? stall=|inflight_cnt
      //else is_cacheable ? stall=!biu_ack_i (wait for noncacheable transfer to finish)
      //else                stall=!biu_stb_ack_i
      NONCACHEABLE: stall_o = ~req_i ? |inflight_cnt_i
//	                             : ~biu_ack_i; //is_cacheable_i ? ~biu_ack_i : ~biu_stb_ack_i;
                                     :  is_cacheable_i |
                                      (~is_cacheable_i & biu_ack_i); //=is_cacheble | biu_ack_i

      //TODO: Add in_biubuffer
      WAIT4BIUCMD0: stall_o = ~( biu_cacheable_ack |
                                 (req_i & cache_hit_i)
	                       );

      EVICT       : stall_o = ~( biu_cacheable_ack |
                                 (req_i & cache_hit_i)
                               );

      RECOVER     : stall_o = ~(req_i & cache_hit_i);
      default     : stall_o = 1'b0;
    endcase


  /* Downstream signals
  */  
  //signal downstream that data is ready
  always @(posedge clk_i, negedge rst_ni)
    if (!rst_ni) ack_o <= 1'b0;
    else
      unique case (memfsm_state)
        ARMED        : ack_o <= cache_ack;
        NONCACHEABLE : ack_o <= biucmd_noncacheable_ack_i;
	WAIT4BIUCMD0 : ack_o <= biu_cacheable_ack;
	EVICT        : ack_o <= biu_cacheable_ack;
	RECOVER      : ack_o <= cache_ack;
	default      : ack_o <= 1'b0;
      endcase


  //signal downstream the BIU reported an error
  always @(posedge clk_i, negedge rst_ni)
    err_o <= biu_err_i;


  assign misaligned_o = 1'b0; //TODO
  

  //Bypass on writebuffer_we?
  assign bypass_writebuffer_we = writebuffer_we_o & (idx_o == writebuffer_idx_o);

  //Shift amount for data
  assign dat_offset = adr_i[BLK_OFFS_BITS-1 -: DAT_OFFS_BITS];

  //Assign q_o
  assign cache_line = be_mux(bypass_writebuffer_we,
                             writebuffer_be_o,
	                     in_biubuffer_i ? biubuffer_i : cache_line_i,
			     {BLK_BITS/XLEN{writebuffer_data_o}});

  assign cache_q = cache_line >> (dat_offset * XLEN);


  always @(posedge clk_i)
    unique case (memfsm_state)
      EVICT       : q_o <= cache_hit_i    ? cache_q : biu_q_i;
      WAIT4BIUCMD0: q_o <= cache_hit_i    ? cache_q : biu_q_i;
      default     : q_o <= is_cacheable_i ? cache_q : biu_q_i;
    endcase

endmodule



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
  localparam DAT_OFFS_BITS = no_of_data_offset_bits (XLEN, BLK_BITS),                //Offset in block
  localparam IDX_BITS      = no_of_index_bits(SETS),
  localparam TAG_BITS      = no_of_tag_bits(PLEN, IDX_BITS, BLK_OFFS_BITS),

  localparam INFLIGHT_BITS = $clog2(INFLIGHT_DEPTH+1)
)
(
  input  logic                        rst_ni,
  input  logic                        clk_i,

  output logic                        stall_o,
  input  logic                        flush_i,                                       //flush pipe

  input  logic                        invalidate_i,
  input  logic                        clean_i,                                       //clean cache
  output logic                        clean_rdy_o,                                   //cache clean ready
  output logic                        armed_o,
  output logic                        cleaning_o,
  output logic                        invalidate_block_o,
  output logic                        invalidate_all_blocks_o,
  output logic                        filling_o,
  input  logic [WAYS            -1:0] fill_way_i,
  output logic [WAYS            -1:0] fill_way_o,
  input  logic [$clog2(WAYS)    -1:0] clean_way_int_i,
  input  logic [IDX_BITS        -1:0] clean_idx_i,
  output logic [WAYS            -1:0] clean_way_o,
  output logic [IDX_BITS        -1:0] clean_idx_o,

  input  logic                        cacheable_i,
  input  logic                        misaligned_i,
  input  logic                        pma_exception_i,
  input  logic                        pmp_exception_i,
  input  logic                        pagefault_i,
  input  logic                        req_i,                                         //from previous-stage
  input  logic                        wreq_i,
  input  logic [PLEN            -1:0] adr_i,
  input  biu_size_t                   size_i,
  input  logic                        lock_i,
  input  biu_prot_t                   prot_i,
  input  logic                        we_i,
  input  logic [XLEN/8          -1:0] be_i,
  input  logic [XLEN            -1:0] d_i,
  output logic [XLEN            -1:0] q_o,
  output logic                        ack_o,
  output logic                        err_o,
  output logic                        misaligned_o,
  output logic                        pagefault_o,
  
  //To/From Cache Memories
  input  logic                        cache_hit_i,                                   //from cache-memory
  input  logic [WAYS            -1:0] ways_hit_i,
  input  logic [BLK_BITS        -1:0] cache_line_i,
  input  logic                        cache_dirty_i,
  input  logic                        way_dirty_i,
  output logic [IDX_BITS        -1:0] idx_o,
  output logic [TAG_BITS        -1:0] core_tag_o,
  output logic                        latchmem_o,                                    //latch TAG/DATA memory outputs

  //WriteBuffer
  output logic                        writebuffer_we_o,
  input  logic                        writebuffer_ack_i,
  output logic [IDX_BITS        -1:0] writebuffer_idx_o,
  output logic [DAT_OFFS_BITS   -1:0] writebuffer_offs_o,
  output logic [XLEN            -1:0] writebuffer_data_o,
  output logic [BLK_BITS/8      -1:0] writebuffer_be_o,                              //writebuffer_be is already blk_bits aligned
  output logic [WAYS            -1:0] writebuffer_ways_hit_o,
  output logic                        writebuffer_cleaning_o,                        //clean(empty) writebuffer

  //EvictBuffer
  output logic                        evict_read_o,

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
  logic [XLEN          -1:0] cache_q;
  logic                      cache_ack,
                             biu_cacheable_ack;

  logic                      pma_pmp_exception;
  logic                      valid_req,
                             valid_wreq;


  enum logic [          3:0] {ARMED=0,
                              CLEAN0,
                              CLEAN1,
                              CLEAN2,
                              NONCACHEABLE,
                              EVICT,
                              CLEANWAYS,
                              READ,
                              RECOVER0,
                              RECOVER1
                           } nxt_memfsm_state, memfsm_state;

  biucmd_t                   nxt_biucmd;

  logic [WAYS          -1:0] fill_way;

  logic                      invalidate_hold,
                             clean_hold,
                             clean_rdy,
                             clean_block,
                             invalidate_block,
                             invalidate_all_blocks,
                             writebuffer_cleaning;

  logic                      evict_read;

  logic                      biu_adro_eq_cache_adr;
  logic [DAT_OFFS_BITS -1:0] dat_offset;
  logic                      bypass_writebuffer_we;
  logic [BLK_BITS      -1:0] cache_line;


  //////////////////////////////////////////////////////////////////
  //
  // Module Body
  //

  assign pma_pmp_exception = pma_exception_i | pmp_exception_i;
  assign valid_req         = req_i  & ~pma_pmp_exception & ~misaligned_i & ~pagefault_i & ~flush_i;
  assign valid_wreq        = wreq_i & ~pma_pmp_exception & ~misaligned_i & ~pagefault_i & ~flush_i;


  //hold invalidate/clean until ready to be serviced
  always @(posedge clk_i, negedge rst_ni)
    if (!rst_ni) invalidate_hold <= 1'b0;
    else         invalidate_hold <= invalidate_i | (invalidate_hold & ~invalidate_all_blocks_o);


  always @(posedge clk_i, negedge rst_ni)
    if (!rst_ni) clean_hold <= 1'b0;
    else         clean_hold <= clean_i | (clean_hold & ~cleaning_o);


  /* State Machine
   */
  always_comb
  begin
      nxt_memfsm_state      = memfsm_state;
      nxt_biucmd            = biucmd_o;
      fill_way              = fill_way_o;
      clean_rdy             = 1'b1;
      invalidate_all_blocks = 1'b0;
      invalidate_block      = 1'b0;
      clean_block           = 1'b0;
      evict_read            = 1'b0;
      writebuffer_cleaning  = 1'b0;

      unique case (memfsm_state)
        ARMED        : begin 
                           if (clean_hold)
                           begin
                               if (writebuffer_we_o) writebuffer_cleaning = 1'b1;    //wait for writebuffer to empty
                               else
                               begin
                                   if (cache_dirty_i)
                                   begin
                                       //Cache has dirty ways
                                       nxt_memfsm_state = CLEAN0;
                                       nxt_biucmd       = BIUCMD_NOP;
                                       clean_rdy        = 1'b0;
                                   end
			           else if (invalidate_hold)
                                   begin
                                       invalidate_all_blocks = 1'b1;
                                   end
                               end
                           end
                           else if (invalidate_hold)
                           begin
                               if (writebuffer_we_o) writebuffer_cleaning   = 1'b1;  //wait for writebuffer to empty
                               else                  invalidate_all_blocks = 1'b1;
                           end
                           else if (valid_req && !cacheable_i && !biucmd_busy_i)
                           begin
                               nxt_memfsm_state = NONCACHEABLE;
                               nxt_biucmd       = BIUCMD_NOP;
                           end
                           else if (valid_req && cacheable_i && !cache_hit_i && !biucmd_busy_i)
                           begin
                               if (writebuffer_we_o) writebuffer_cleaning = 1'b1;    //wait for writebuffer to empty
                               else
                               begin
                                   fill_way = fill_way_i;                            //write to same way as was read

                                   if (way_dirty_i)
                                   begin
                                       //selected way is dirty
                                       nxt_memfsm_state = EVICT;
                                       nxt_biucmd       = BIUCMD_READWAY;            //read new line before evicting old one
                                       evict_read       = 1'b1;                      //read block to evict
                                                                                     //in evict_* 2 cycles later
                                   end
                                   else
                                   begin
                                       //Load way
                                       nxt_memfsm_state = READ;
                                       nxt_biucmd       = BIUCMD_READWAY;
                                   end
                               end
                           end
                       end

        CLEAN0       : begin
                          //clean_idx_o registered here
                          nxt_memfsm_state = CLEAN1;
                          nxt_biucmd       = BIUCMD_NOP;
                          clean_rdy        = 1'b0;
                      end

        CLEAN1      : begin
                          //clean_idx registered in memory
                          //evict_* ready 2 cycles later
                          nxt_memfsm_state = CLEAN2;
                          nxt_biucmd       = BIUCMD_NOP;
                          clean_rdy        = 1'b0;
                      end

        CLEAN2      : begin
                          //Latch evict data/tag/idx in evict_*
                          //clear way-dirty of flushed way => next flush_idx on next cycle
                          nxt_memfsm_state = CLEANWAYS;
                          nxt_biucmd       = BIUCMD_NOP;
                          clean_rdy        = 1'b0;
                          clean_block      = 1'b1;
                      end


        CLEANWAYS   : begin
                          //assert WRITE_WAY here (instead of in CLEAN) to allow time to load evict_*
                          nxt_memfsm_state = memfsm_state;
                          nxt_biucmd       = BIUCMD_WRITEWAY;
                          clean_rdy        = 1'b0;

                          if (biucmd_ack_i)
                          begin
                              //Check if there are more dirty ways in this set
                              if (cache_dirty_i)
                              begin
                                  nxt_memfsm_state = CLEANWAYS;
                                  nxt_biucmd       = BIUCMD_WRITEWAY;
                                  clean_block      = 1'b1;
                              end
                              else
                              begin
                                  nxt_memfsm_state      = RECOVER0;
                                  nxt_biucmd            = BIUCMD_NOP;
                                  clean_rdy             = 1'b1;
                                  invalidate_all_blocks = invalidate_hold;
                              end
                          end
                      end

        NONCACHEABLE: if ( flush_i                                       ||  //flushed pipe, no biu_ack's will come
                          (!valid_req && inflight_cnt_i==1 && biu_ack_i) ||  //no new request, wait for BIU to finish transfer
                          ( valid_req && cacheable_i       && biu_ack_i) )   //new cacheable request, wait for non-cacheable transfer to finish
                      begin
                          nxt_memfsm_state = ARMED;
                          nxt_biucmd       = BIUCMD_NOP;
                      end

        EVICT       : if (biucmd_ack_i || biu_err_i)
                      begin
                          nxt_memfsm_state = RECOVER0;
                          nxt_biucmd       = BIUCMD_WRITEWAY; //evict dirty way
                      end
                      else
                      begin
                          nxt_biucmd = BIUCMD_NOP;
                      end

        READ        : begin
                          nxt_biucmd = BIUCMD_NOP;

                          if (biucmd_ack_i || biu_err_i)
                            nxt_memfsm_state = RECOVER0;
                      end

        RECOVER0    : begin
                          //setup address (idx) for TAG and data memory
                          nxt_memfsm_state = RECOVER1;
                          nxt_biucmd       = BIUCMD_NOP;
                      end

        RECOVER1    : begin
                          //Latch TAG and DATA memory output
                          nxt_memfsm_state = ARMED;
                          nxt_biucmd       = BIUCMD_NOP;
                      end

        default     : begin
                          //something went really wrong, flush cache
                          nxt_memfsm_state = CLEAN0;
                          nxt_biucmd       = BIUCMD_NOP;
                      end
      endcase
  end


  always @(posedge clk_i, negedge rst_ni)
    if (!rst_ni)
    begin
        memfsm_state            <= ARMED;
        biucmd_o                <= BIUCMD_NOP;
        armed_o                 <= 1'b1;
        cleaning_o              <= 1'b0;
        invalidate_all_blocks_o <= 1'b0;
        invalidate_block_o      <= 1'b0;
        filling_o               <= 1'b0;
        fill_way_o              <=  'hx;
        clean_rdy_o             <= 1'b1;
        evict_read_o            <= 1'b0;
        writebuffer_cleaning_o  <= 1'b1;
    end
    else
    begin
        memfsm_state            <= nxt_memfsm_state;
        biucmd_o                <= nxt_biucmd;
        fill_way_o              <= fill_way;
        clean_rdy_o             <= clean_rdy;
        invalidate_all_blocks_o <= invalidate_all_blocks;
        invalidate_block_o      <= invalidate_block;
        evict_read_o            <= evict_read;
        writebuffer_cleaning_o  <= writebuffer_cleaning;

        unique case (nxt_memfsm_state)
          ARMED       : begin
                            armed_o    <= 1'b1;
                            cleaning_o <= 1'b0;
                            filling_o  <= 1'b0;

                            if (clean_hold && !writebuffer_we_o)
                              if (~cache_dirty_i) cleaning_o <= 1'b1;
                        end

          CLEAN0      : begin
                            armed_o    <= 1'b0;
                            cleaning_o <= 1'b1;
                            filling_o  <= 1'b0;
                        end

          CLEAN1      : begin
                            armed_o    <= 1'b0;
                            cleaning_o <= 1'b1;
                            filling_o  <= 1'b0;
                        end

          CLEAN2      : begin
                            armed_o    <= 1'b0;
                            cleaning_o <= 1'b1;
                            filling_o  <= 1'b0;
                        end


          CLEANWAYS   : begin
                            armed_o    <= 1'b0;
                            cleaning_o <= 1'b1;
                            filling_o  <= 1'b0;
                        end

          NONCACHEABLE: begin
                            armed_o    <= 1'b0;
                            cleaning_o <= 1'b0;
                            filling_o  <= 1'b0;
                        end

          EVICT       : begin
                            armed_o    <= 1'b0;
                            cleaning_o <= 1'b0;
                            filling_o  <= 1'b1;
                        end

          READ        : begin
                            armed_o    <= 1'b0;
                            cleaning_o <= 1'b0;
                            filling_o  <= 1'b1;
                        end

          RECOVER0    : begin
                            //setup IDX for TAG and DATA memory after filling
                            armed_o    <= 1'b0;
                            cleaning_o <= 1'b0;
                            filling_o  <= 1'b0;
                        end

          RECOVER1    : begin
                            //Read TAG and DATA memory after writing/filling
                            armed_o    <= 1'b0;
                            cleaning_o <= 1'b0;
                            filling_o  <= 1'b0;
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
    if      (!rst_ni                                           ) writebuffer_we_o <= 1'b0;
    else if ( flush_i                                          ) writebuffer_we_o <= 1'b0;
    else if ( valid_req && wreq_i && cacheable_i && cache_hit_i) writebuffer_we_o <= 1'b1;
    else if ( writebuffer_ack_i                                ) writebuffer_we_o <= 1'b0;


  always @(posedge clk_i)
    if (valid_req && wreq_i && cacheable_i && cache_hit_i)
    begin
        writebuffer_idx_o      <= adr_i[BLK_OFFS_BITS +: IDX_BITS];
        writebuffer_offs_o     <= dat_offset;
        writebuffer_data_o     <= d_i;
        writebuffer_be_o       <= be_i << (dat_offset * XLEN/8);
        writebuffer_ways_hit_o <= ways_hit_i;
    end


  /*Clean/Invalidate blocks
   */
  always @(posedge clk_i)
    begin
        clean_way_o <= (1 << clean_way_int_i) & {WAYS{clean_block}};
        clean_idx_o <= clean_idx_i;
    end


  /* BIU control
  */
  //non-cacheable access
  always_comb
    unique case (memfsm_state)
      ARMED       : biucmd_noncacheable_req_o = valid_req & ~cacheable_i;
      NONCACHEABLE: biucmd_noncacheable_req_o = valid_req & ~cacheable_i & biu_ack_i;
      default     : biucmd_noncacheable_req_o = 1'b0;
    endcase


  //address check, used in a few places
  assign biu_adro_eq_cache_adr = (biu_adro_i[PLEN-1:BURST_LSB] == adr_i[PLEN-1:BURST_LSB]);


  //acknowledge cache hit
  assign cache_ack         =  valid_req & cacheable_i & cache_hit_i & ~flush_i;
  assign biu_cacheable_ack = (valid_req & biu_ack_i & biu_adro_eq_cache_adr & ~flush_i) |
                              cache_ack;


  /* Stall & Latchmem
   */

  //Always stall on non-cacheable accesses.
  //This removes dependency on biu_stb_ack_i, which is an async path.
  //However this stalls the access, which causes it to be executed twice
  //Use a registered version of biu_stb_ack_i to negate 'stall' for 1 cycle during NONCACHEABLE
  //thus removing the second access
  logic biu_stb_ack_reg;
  always @(posedge clk_i)
    biu_stb_ack_reg <= (memfsm_state == ARMED) && biu_stb_ack_i;

  always_comb
    unique case (memfsm_state)
      ARMED       : begin
                        stall_o    = clean_hold                                                   | //cacheflush pending
                                    (valid_req & ~cacheable_i /*& (~biu_stb_ack_reg | biucmd_busy_i)*/) | //non-cacheable access
                                    (valid_req &  cacheable_i & ~cache_hit_i                    );  //cacheable access

		        latchmem_o = ~stall_o;
                    end

      //req_i == 0 ? stall=|inflight_cnt
      //else is_cacheable ? stall=1 (wait for transition to ARMED state)
      //else                stall=!biu_ack_i
      NONCACHEABLE: begin
                        stall_o    = ~valid_req ? |inflight_cnt_i
                                                :  cacheable_i |
                                                 (~cacheable_i & ~biu_ack_i & ~biu_stb_ack_reg); //=is_cacheble | biu_ack_i

                        latchmem_o = ~stall_o;
                     end

      //TODO: Add in_biubuffer
      READ        : begin
                        stall_o    = ~( biu_cacheable_ack |
                                       (valid_req & cache_hit_i)
                                      );

                        latchmem_o = ~stall_o;
                    end

      EVICT       : begin
                        stall_o    = ~( biu_cacheable_ack |
                                       (valid_req & cache_hit_i)
                                      );

                        latchmem_o = ~stall_o;
                    end

      RECOVER0    : begin
                        stall_o    = 1'b1;
                        latchmem_o = 1'b0;
                    end
      
      RECOVER1    : begin
                        stall_o    = 1'b1;
                        latchmem_o = 1'b1;
                    end

      CLEANWAYS   : begin
                        stall_o    = 1'b1;
                        latchmem_o = 1'b1;
                    end

      default     : begin //CLEAN0,1,2
                        stall_o    = 1'b1;
                        latchmem_o = 1'b1;
                    end
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
	READ         : ack_o <= biu_cacheable_ack;
	EVICT        : ack_o <= biu_cacheable_ack;
	default      : ack_o <= 1'b0;
      endcase


  //generate access error (load/store access exception)
  always @(posedge clk_i) err_o <= biu_err_i | (req_i & pma_pmp_exception);


  //generate misaligned (misaligned load/store exception)
  always @(posedge clk_i) misaligned_o <= req_i & misaligned_i;


  //generate Page Fault
  always @(posedge clk_i) pagefault_o <= pagefault_i;


  //Bypass on writebuffer_we?
  assign bypass_writebuffer_we = writebuffer_we_o & (idx_o == writebuffer_idx_o) & (writebuffer_ways_hit_o == ways_hit_i);
  

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
      EVICT  : q_o <= cache_hit_i ? cache_q : biu_q_i;
      READ   : q_o <= cache_hit_i ? cache_q : biu_q_i;
      default: q_o <= cacheable_i ? cache_q : biu_q_i;
    endcase

endmodule



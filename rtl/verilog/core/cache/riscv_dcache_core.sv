/////////////////////////////////////////////////////////////////////
//   ,------.                    ,--.                ,--.          //
//   |  .--. ' ,---.  ,--,--.    |  |    ,---. ,---. `--' ,---.    //
//   |  '--'.'| .-. |' ,-.  |    |  |   | .-. | .-. |,--.| .--'    //
//   |  |\  \ ' '-' '\ '-'  |    |  '--.' '-' ' '-' ||  |\ `--.    //
//   `--' '--' `---'  `--`--'    `-----' `---' `-   /`--' `---'    //
//                                             `---'               //
//    RISC-V                                                       //
//    Cache Pipeline                                               //
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
  Customer should be able to chose
  - cache size
  - Set associativity
  therefore BLOCK_SIZE is autocalculated

  RISC-V specifies a 4KB page. Thus page offset = 12bits
  MAX_IDX_BITS = $clog2(4*1024) = 12

  BURST_SIZE = 16,8,4

  BLOCK_SIZE = BURST_SIZE * XLEN/8 (bytes)
    rv32:  64,32,16 bytes
    rv64: 128,64,32 bytes

  This affects associativity (the number of ways)
  BLOCK_OFFSET_BITS = $clog2(BLOCK_SIZE)
    rv32: 6,5,4 bits
    rv64: 7,6,5 bits

  IDX_BITS = MAX_IDX_BITS - BLOCK_OFFSET_BITS
    rv32: 6,7,8
    rv64: 5,6,7

  SETS = 2**IDX_BITS
    rv32: 64,128,256
    rv64: 32, 64,128

  WAYS = CACHE_SIZE / (BLOCK_SIZE * SET) = CACHE_SIZE / PAGE_SIZE
     8KB:  2
    16KB:  4
    32KB:  8
    64KB: 16
 */


module riscv_dcache_core
import riscv_cache_pkg::*;
import biu_constants_pkg::*;
#(
  parameter                       XLEN        = 32,
  parameter                       PLEN        = XLEN,

  parameter                       SIZE        = 64,     //KBYTES
  parameter                       BLOCK_SIZE  = XLEN,   //BYTES, number of bytes in a block (way)
                                                        //Must be [XLEN*2,XLEN,XLEN/2]
  parameter                       WAYS        =  2,     // 1           : Direct Mapped
                                                        //<n>          : n-way set associative
                                                        //<n>==<blocks>: fully associative
  parameter                       REPLACE_ALG = 0,      //0: Random
                                                        //1: FIFO
                                                        //2: LRU

  parameter                       TECHNOLOGY  = "GENERIC",

  parameter                       DEPTH       = 2,      //number of transactions in flight
  parameter                       BIUTAG_SIZE = 2
)
(
  input  logic                    rst_ni,
  input  logic                    clk_i,

  output logic                    stall_o,

  //from MMU
  input  logic [PLEN        -1:0] phys_adr_i,           //physical address
  input  logic                    pagefault_i,

  //from PMA
  input  logic                    pma_misaligned_i,
  input  logic                    pma_cacheable_i,
  input  logic                    pma_exception_i,

  //from PMP
  input  logic                    pmp_exception_i,      //aligned with TAG

  //CPU side
  input  logic                    mem_flush_i,
  input  logic                    mem_req_i,
  output logic                    mem_ack_o,
  output logic                    mem_err_o,
  output logic                    mem_misaligned_o,
  output logic                    mem_pagefault_o,
  input  logic [XLEN        -1:0] mem_adr_i,            //virtual address
  input  biu_size_t               mem_size_i,
  input  logic                    mem_lock_i,
  input  biu_prot_t               mem_prot_i,
  input  logic                    mem_we_i,
  input  logic [XLEN        -1:0] mem_d_i,
  output logic [XLEN        -1:0] mem_q_o,

  //Cache Block Management, per CMO spec
  //Flush = Invalidate + Clean
  input  logic                    invalidate_i,         //Invalidate blocks
  input  logic                    clean_i,              //Write back dirty blocks
  input  logic                    clean_rdy_clr_i,      //Clear data-cache-ready signal
  output logic                    clean_rdy_o,          //Data cache ready cleaning

  //To BIU
  output logic                    biu_stb_o,            //access request
  input  logic                    biu_stb_ack_i,        //access acknowledge
  input  logic                    biu_d_ack_i,          //BIU needs new data (biu_d_o)
  output logic [PLEN        -1:0] biu_adri_o,           //access start address
  input  logic [PLEN        -1:0] biu_adro_i,
  output biu_size_t               biu_size_o,           //transfer size
  output biu_type_t               biu_type_o,           //burst type
  output logic                    biu_lock_o,           //locked transfer
  output biu_prot_t               biu_prot_o,           //protection bits
  output logic                    biu_we_o,             //write enable
  output logic [XLEN        -1:0] biu_d_o,              //write data
  input  logic [XLEN        -1:0] biu_q_i,              //read data
  input  logic                    biu_ack_i,            //transfer acknowledge
  input  logic                    biu_err_i,            //transfer error
  output logic [BIUTAG_SIZE -1:0] biu_tagi_o,
  input  logic [BIUTAG_SIZE -1:0] biu_tago_i
);

  //////////////////////////////////////////////////////////////////
  //
  // Constants
  //
  
  //----------------------------------------------------------------
  // Cache
  //----------------------------------------------------------------
  localparam PAGE_SIZE        = 4*1024;                            //4KB pages
  localparam MAX_IDX_BITS     = $clog2(PAGE_SIZE) - $clog2(BLOCK_SIZE); //Maximum IDX_BITS
  

  localparam SETS             = (SIZE*1024) / BLOCK_SIZE / WAYS;   //Number of sets TODO:SETS=1 doesn't work
  localparam BLK_OFFS_BITS    = $clog2(BLOCK_SIZE);                //Number of BlockOffset bits
  localparam IDX_BITS         = $clog2(SETS);                      //Number of Index-bits
  localparam TAG_BITS         = PLEN - IDX_BITS - BLK_OFFS_BITS;   //Number of TAG-bits
  localparam BLK_BITS         = 8*BLOCK_SIZE;                      //Total number of bits in a Block
  localparam BURST_SIZE       = BLK_BITS / XLEN;                   //Number of transfers to load 1 Block
  localparam BURST_BITS       = $clog2(BURST_SIZE);
  localparam BURST_OFFS       = XLEN/8;
  localparam BURST_LSB        = $clog2(BURST_OFFS);

  //BLOCK decoding
  localparam DAT_OFFS_BITS    = $clog2(BLK_BITS / XLEN);           //Offset in block


  //Inflight transfers
  localparam INFLIGHT_DEPTH  = BURST_SIZE;                         //Wishbone has 1 transfers in flight
                                                                   //AHB      has 2 transfers in flight
                                                                   //AXI can have many transfers in flight
  localparam INFLIGHT_BITS   = $clog2(INFLIGHT_DEPTH+1);


  //////////////////////////////////////////////////////////////////
  //
  // Variables
  //
  logic [              6:0] way_random; //Up to 128ways
  logic [WAYS         -1:0] fill_way_select,
                            mem_fill_way, hit_fill_way;

  logic                     setup_req,        tag_req,
                            setup_rreq,       tag_wreq;
  logic [PLEN         -1:0]                   tag_adr;
  biu_size_t                setup_size,       tag_size;
  logic                     setup_lock,       tag_lock;
  biu_prot_t                setup_prot,       tag_prot;
  logic                     setup_we,         tag_we;
  logic [XLEN         -1:0] setup_q,          tag_q;
  logic                     setup_invalidate, tag_invalidate;
  logic                     setup_clean,      tag_clean;
  logic                                       tag_pagefault;
  logic [XLEN/8       -1:0]                   tag_be;

  logic                     writebuffer_we;
  logic [IDX_BITS     -1:0] writebuffer_idx;
  logic [DAT_OFFS_BITS-1:0] writebuffer_offs;
  logic [XLEN         -1:0] writebuffer_data;
  logic [BLK_BITS/8   -1:0] writebuffer_be;
  logic [WAYS         -1:0] writebuffer_ways_hit;
  logic                     writebuffer_cleaning;

  logic [TAG_BITS     -1:0] tag_core_tag,
                            hit_core_tag;
  logic [IDX_BITS     -1:0] setup_idx,
                            hit_idx;
  logic [BLK_BITS/8   -1:0] dat_be;


  logic                     cache_hit,
                            cache_dirty,
                            way_dirty;
  logic [WAYS         -1:0] ways_hit,
                            ways_dirty;
  logic [BLK_BITS     -1:0] cache_line;


  logic                     evict_read;
  logic [PLEN         -1:0] evict_adr;
  logic [BLK_BITS     -1:0] evict_line;

  logic [$clog2(WAYS) -1:0] mem_clean_way_int;
  logic [IDX_BITS     -1:0] mem_clean_idx;
  logic [WAYS         -1:0] hit_clean_way;
  logic [IDX_BITS     -1:0] hit_clean_idx;


  logic [INFLIGHT_BITS-1:0] inflight_cnt;

  biucmd_t                  biucmd;
  logic                     biucmd_ack,
                            biucmd_busy,
                            biucmd_noncacheable_req,
                            biucmd_noncacheable_ack;
  logic [BLK_BITS     -1:0] biubuffer;
  logic                     in_biubuffer;
  logic [BLK_BITS     -1:0] biu_line;
  logic                     biu_line_dirty;

  logic                     hit_latchmem;
  logic                     armed,
                            filling,
                            cleaning,
                            invalidate_block,
                            invalidate_all_blocks;


  //////////////////////////////////////////////////////////////////
  //
  // Module Body
  //

  
  //----------------------------------------------------------------
  // Cache Pipeline
  //----------------------------------------------------------------

  //This should go into a 'way-replacement module'
  //Random generator for RANDOM replacement algorithm
  always @(posedge clk_i, negedge rst_ni)
    if      (!rst_ni ) way_random <= 'h0;
    else if (!filling) way_random <= {way_random, way_random[6] ~^ way_random[5]};


  //fill-way-select
generate
  if (WAYS == 1) assign fill_way_select = 1;
  else           assign fill_way_select = 1 << way_random[$clog2(WAYS)-1:0];
endgenerate


  /* Address Setup Stage
   * Drives signals into TAG and DATA memories
   * Virtual Memory
   */
  riscv_cache_setup #(
    .XLEN                      ( XLEN                    ),
    .SIZE                      ( SIZE                    ),
    .BLOCK_SIZE                ( BLOCK_SIZE              ),
    .WAYS                      ( WAYS                    ) )
  cache_setup_inst (
    .rst_ni                    ( rst_ni                  ),
    .clk_i                     ( clk_i                   ),

    .stall_i                   ( stall_o                 ),
    .flush_i                   ( mem_flush_i             ),

    .req_i                     ( mem_req_i               ),
    .adr_i                     ( mem_adr_i               ),
    .size_i                    ( mem_size_i              ),
    .lock_i                    ( mem_lock_i              ),
    .prot_i                    ( mem_prot_i              ),
    .we_i                      ( mem_we_i                ),
    .d_i                       ( mem_d_i                 ),
    .invalidate_i              ( invalidate_i            ),
    .clean_i                   ( clean_i                 ),

    .req_o                     ( setup_req               ),
    .rreq_o                    ( setup_rreq              ),
    .size_o                    ( setup_size              ),
    .lock_o                    ( setup_lock              ),
    .prot_o                    ( setup_prot              ),
    .we_o                      ( setup_we                ),
    .q_o                       ( setup_q                 ),
    .invalidate_o              ( setup_invalidate        ),
    .clean_o                   ( setup_clean             ),

    .idx_o                     ( setup_idx               ) );


  /* Tag stage
   * Tag/Data memory access. Hit and cache-line available after this stage
   * Physical address is available here
   */
  riscv_cache_tag #(
    .XLEN                      ( XLEN                    ),
    .PLEN                      ( PLEN                    ),
    .SIZE                      ( SIZE                    ),
    .BLOCK_SIZE                ( BLOCK_SIZE              ),
    .WAYS                      ( WAYS                    ) )
  cache_tag_inst (
    .rst_ni                    ( rst_ni                  ),
    .clk_i                     ( clk_i                   ),

    .stall_i                   ( stall_o                 ),
    .flush_i                   ( mem_flush_i             ),
    .req_i                     ( setup_req               ),

    .phys_adr_i                ( phys_adr_i              ),
    .size_i                    ( setup_size              ),
    .lock_i                    ( setup_lock              ),
    .prot_i                    ( setup_prot              ),
    .we_i                      ( setup_we                ),
    .d_i                       ( setup_q                 ),
    .invalidate_i              ( setup_invalidate        ),
    .clean_i                   ( setup_clean             ),
    .pagefault_i               ( pagefault_i             ), //aligned with phys_adr_i
    .invalidate_all_blocks_i   ( invalidate_all_blocks   ),

    .req_o                     ( tag_req                 ),
    .wreq_o                    ( tag_wreq                ),
    .adr_o                     ( tag_adr                 ),
    .size_o                    ( tag_size                ),
    .lock_o                    ( tag_lock                ),
    .prot_o                    ( tag_prot                ),
    .we_o                      ( tag_we                  ),
    .be_o                      ( tag_be                  ),
    .q_o                       ( tag_q                   ),
    .invalidate_o              ( tag_invalidate          ),
    .clean_o                   ( tag_clean               ),
    .pagefault_o               ( tag_pagefault           ),
    .core_tag_o                ( tag_core_tag            ) );

  
  /* Hit stage / Cache Controller (FSM)
   * Takes hit, cache-line and biu signals and generates memory output
   */
  riscv_dcache_fsm #(
    .XLEN                      ( XLEN                    ),
    .PLEN                      ( PLEN                    ),
    .SIZE                      ( SIZE                    ),
    .BLOCK_SIZE                ( BLOCK_SIZE              ),
    .WAYS                      ( WAYS                    ),
    .INFLIGHT_DEPTH            ( INFLIGHT_DEPTH          ) )
  cache_fsm_inst (
    .rst_ni                    ( rst_ni                  ),
    .clk_i                     ( clk_i                   ),

    .stall_o                   ( stall_o                 ),
    .flush_i                   ( mem_flush_i             ),

    //flush in-order with CPU pipeline
    .invalidate_i              ( tag_invalidate          ),
    .clean_i                   ( tag_clean               ),
    .clean_rdy_clr_i           ( clean_rdy_clr_i         ),
    .clean_rdy_o               ( clean_rdy_o             ),
    .armed_o                   ( armed                   ),
    .cleaning_o                ( cleaning                ),
    .invalidate_block_o        ( invalidate_block        ),
    .invalidate_all_blocks_o   ( invalidate_all_blocks   ),
    .filling_o                 ( filling                 ),
    .fill_way_i                ( mem_fill_way            ),
    .fill_way_o                ( hit_fill_way            ),
    .clean_way_int_i           ( mem_clean_way_int       ),
    .clean_idx_i               ( mem_clean_idx           ),
    .clean_way_o               ( hit_clean_way           ),
    .clean_idx_o               ( hit_clean_idx           ),

    .cacheable_i               ( pma_cacheable_i         ),
    .misaligned_i              ( pma_misaligned_i        ),
    .pma_exception_i           ( pma_exception_i         ),
    .pmp_exception_i           ( pmp_exception_i         ),
    .pagefault_i               ( tag_pagefault           ),
    .req_i                     ( tag_req                 ),
    .wreq_i                    ( tag_wreq                ),
    .adr_i                     ( tag_adr                 ),
    .size_i                    ( tag_size                ),
    .lock_i                    ( tag_lock                ),
    .prot_i                    ( tag_prot                ),
    .we_i                      ( tag_we                  ),
    .be_i                      ( tag_be                  ),
    .d_i                       ( tag_q                   ),
    .q_o                       ( mem_q_o                 ),
    .ack_o                     ( mem_ack_o               ),
    .err_o                     ( mem_err_o               ),
    .misaligned_o              ( mem_misaligned_o        ),
    .pagefault_o               ( mem_pagefault_o         ),

    .latchmem_o                ( hit_latchmem            ),
    .idx_o                     ( hit_idx                 ),
    .core_tag_o                ( hit_core_tag            ),

    .cache_hit_i               ( cache_hit               ),
    .ways_hit_i                ( ways_hit                ),
    .cache_line_i              ( cache_line              ),
    .cache_dirty_i             ( cache_dirty             ),
    .way_dirty_i               ( way_dirty               ),

    .writebuffer_we_o          ( writebuffer_we          ),
    .writebuffer_ack_i         (~setup_rreq              ),
    .writebuffer_idx_o         ( writebuffer_idx         ),
    .writebuffer_offs_o        ( writebuffer_offs        ),
    .writebuffer_data_o        ( writebuffer_data        ),
    .writebuffer_be_o          ( writebuffer_be          ),
    .writebuffer_ways_hit_o    ( writebuffer_ways_hit    ),
    .writebuffer_cleaning_o    ( writebuffer_cleaning    ),

    .evict_read_o              ( evict_read              ),

    .biucmd_o                  ( biucmd                  ),
    .biucmd_ack_i              ( biucmd_ack              ),
    .biucmd_busy_i             ( biucmd_busy             ),
    .biucmd_noncacheable_req_o ( biucmd_noncacheable_req ),
    .biucmd_noncacheable_ack_i ( biucmd_noncacheable_ack ),
    .inflight_cnt_i            ( inflight_cnt            ),

    .biu_stb_ack_i             ( biu_stb_ack_i           ),
    .biu_ack_i                 ( biu_ack_i               ),
    .biu_err_i                 ( biu_err_i               ),
    .biu_adro_i                ( biu_adro_i              ),
    .biu_q_i                   ( biu_q_i                 ),
    .in_biubuffer_i            ( in_biubuffer            ),
    .biubuffer_i               ( biubuffer               ) );


  //----------------------------------------------------------------
  // Memory Blocks
  //----------------------------------------------------------------

  riscv_cache_memory #(
    .XLEN                      ( XLEN                    ),
    .PLEN                      ( PLEN                    ),
    .SIZE                      ( SIZE                    ),
    .BLOCK_SIZE                ( BLOCK_SIZE              ),
    .WAYS                      ( WAYS                    ),

    .TECHNOLOGY                ( TECHNOLOGY              ) )
  cache_memory_inst (
    .rst_ni                    ( rst_ni                  ),
    .clk_i                     ( clk_i                   ),

    .stall_i                   ( stall_o                 ),

    .armed_i                   ( armed                   ),
    .cleaning_i                ( cleaning                ),
    .invalidate_block_i        ( 1'b0                    ),
    .invalidate_all_blocks_i   ( invalidate_all_blocks   ),
    .filling_i                 ( filling                 ),
    .fill_way_select_i         ( fill_way_select         ),
    .fill_way_i                ( hit_fill_way            ),
    .fill_way_o                ( mem_fill_way            ),
    .clean_way_int_o           ( mem_clean_way_int       ),
    .clean_idx_o               ( mem_clean_idx           ),
    .clean_way_i               ( hit_clean_way           ),
    .clean_idx_i               ( hit_clean_idx           ),

    .rd_core_tag_i             ( tag_core_tag            ),
    .wr_core_tag_i             ( hit_core_tag            ),
    .rd_idx_i                  ( setup_idx               ),
    .wr_idx_i                  ( hit_idx                 ),

    .rreq_i                    ( setup_rreq              ), //Read cache memories?
    .writebuffer_we_i          ( writebuffer_we          ),
    .writebuffer_be_i          ( writebuffer_be          ),
    .writebuffer_idx_i         ( writebuffer_idx         ),
    .writebuffer_offs_i        ( writebuffer_offs        ),
    .writebuffer_data_i        ( writebuffer_data        ),
    .writebuffer_ways_hit_i    ( writebuffer_ways_hit    ),
    .writebuffer_cleaning_i    ( writebuffer_cleaning    ),

    .evict_read_i              ( evict_read              ),
    .evict_adr_o               ( evict_adr               ),
    .evict_line_o              ( evict_line              ),

    .biu_line_i                ( biu_line                ), //Write data line
    .biu_line_dirty_i          ( biu_line_dirty          ), //Write data dirty
    .biucmd_ack_i              ( biucmd_ack              ), //Write data write-enable

    .latchmem_i                ( hit_latchmem            ), //latch TAG/DATA memory output
    .hit_o                     ( cache_hit               ),
    .ways_hit_o                ( ways_hit                ),
    .cache_dirty_o             ( cache_dirty             ), //cache has dirty lines
    .way_dirty_o               ( way_dirty               ), //selected way is dirty (for evict)
    .ways_dirty_o              (                         ),
    .cache_line_o              ( cache_line              ) );



  //----------------------------------------------------------------
  // Bus Interface Statemachine
  //----------------------------------------------------------------
  riscv_cache_biu_ctrl #(
    .XLEN                      ( XLEN                    ),
    .PLEN                      ( PLEN                    ),
    .SIZE                      ( SIZE                    ),
    .BLOCK_SIZE                ( BLOCK_SIZE              ),
    .WAYS                      ( WAYS                    ),
    .INFLIGHT_DEPTH            ( INFLIGHT_DEPTH          ),
    .BIUTAG_SIZE               ( BIUTAG_SIZE             ) )
  biu_ctrl_inst (
    .rst_ni                    ( rst_ni                  ),
    .clk_i                     ( clk_i                   ),

    .flush_i                   ( mem_flush_i             ),

    .biucmd_i                  ( biucmd                  ),
    .biucmd_ack_o              ( biucmd_ack              ),
    .biucmd_busy_o             ( biucmd_busy             ),
    .biucmd_noncacheable_req_i ( biucmd_noncacheable_req ),
    .biucmd_noncacheable_ack_o ( biucmd_noncacheable_ack ),
    .biucmd_tag_i              ( {BIUTAG_SIZE{1'b0}}     ),
    .inflight_cnt_o            ( inflight_cnt            ),

    .req_i                     ( tag_req                 ),
    .adr_i                     ( tag_adr                 ),
    .size_i                    ( tag_size                ),
    .prot_i                    ( tag_prot                ),
    .lock_i                    ( tag_lock                ),
    .we_i                      ( tag_we                  ),
    .be_i                      ( tag_be                  ),
    .d_i                       ( tag_q                   ),

    .biubuffer_o               ( biubuffer               ),
    .in_biubuffer_o            ( in_biubuffer            ),
    .biu_line_o                ( biu_line                ),
    .biu_line_dirty_o          ( biu_line_dirty          ),

    .evictbuffer_adr_i         ( evict_adr               ),
    .evictbuffer_d_i           ( evict_line              ),

     //To BIU
    .biu_stb_o                 ( biu_stb_o               ),
    .biu_stb_ack_i             ( biu_stb_ack_i           ),
    .biu_d_ack_i               ( biu_d_ack_i             ),
    .biu_adri_o                ( biu_adri_o              ),
    .biu_adro_i                ( biu_adro_i              ),
    .biu_size_o                ( biu_size_o              ),
    .biu_type_o                ( biu_type_o              ),
    .biu_lock_o                ( biu_lock_o              ),
    .biu_prot_o                ( biu_prot_o              ),
    .biu_we_o                  ( biu_we_o                ),
    .biu_d_o                   ( biu_d_o                 ),
    .biu_q_i                   ( biu_q_i                 ),
    .biu_ack_i                 ( biu_ack_i               ),
    .biu_err_i                 ( biu_err_i               ),
    .biu_tagi_o                ( biu_tagi_o              ),
    .biu_tago_i                ( biu_tago_i              ) );

endmodule



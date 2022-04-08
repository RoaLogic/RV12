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

import riscv_cache_pkg::*;
import biu_constants_pkg::*;

module riscv_icache_core #(
  parameter int    XLEN        = 32,
  parameter int    PLEN        = XLEN,
  parameter int    PARCEL_SIZE = XLEN,
  parameter int    HAS_RVC     = 0,

  parameter int    SIZE        = 64,     //KBYTES
  parameter int    BLOCK_SIZE  = XLEN,   //BYTES, number of bytes in a block (way)
                                         //Must be [XLEN*2,XLEN,XLEN/2]
  parameter int    WAYS        =  2,     // 1           : Direct Mapped
                                         //<n>          : n-way set associative
                                         //<n>==<blocks>: fully associative
  parameter int    REPLACE_ALG = 0,      //0: Random
                                         //1: FIFO
                                         //2: LRU

  parameter string TECHNOLOGY  = "GENERIC",

  parameter int    DEPTH       = 2,      //number of transactions in flight
  parameter int    BIUTAG_SIZE = $clog2(XLEN/PARCEL_SIZE)
)
(
  input  logic                        rst_ni,
  input  logic                        clk_i,

  //From MMU
  input  logic [PLEN            -1:0] phys_adr_i, //physical address
  input  logic                        pagefault_i,

  //From PMA
  input  logic                        pma_cacheable_i,
  input  logic                        pma_misaligned_i,
  input  logic                        pma_exception_i,

  //From PMP
  input  logic                        pmp_exception_i,

  //CPU side
  input  logic                        mem_flush_i,
  input  logic                        mem_req_i,
  output logic                        mem_stall_o,
  input  logic [XLEN            -1:0] mem_adr_i,
  input  biu_size_t                   mem_size_i,
  input                               mem_lock_i,
  input  biu_prot_t                   mem_prot_i,
  output logic [XLEN            -1:0] parcel_o,
  output logic [XLEN/PARCEL_SIZE-1:0] parcel_valid_o,
  output logic                        parcel_error_o,
  output logic                        parcel_misaligned_o,
  output logic                        parcel_pagefault_o,

  //Cache management
  input  logic                        invalidate_i,         //invalidate cache
  input  logic                        dc_clean_rdy_i,       //data cache ready cleaning

  //To BIU
  output logic                        biu_stb_o,            //access request
  input  logic                        biu_stb_ack_i,        //access acknowledge
  input  logic                        biu_d_ack_i,          //BIU needs new data (biu_d_o)
  output logic [PLEN            -1:0] biu_adri_o,           //access start address
  input  logic [PLEN            -1:0] biu_adro_i,
  output biu_size_t                   biu_size_o,           //transfer size
  output biu_type_t                   biu_type_o,           //burst type
  output logic                        biu_lock_o,           //locked transfer
  output biu_prot_t                   biu_prot_o,           //protection bits
  output logic                        biu_we_o,             //write enable
  output logic [XLEN            -1:0] biu_d_o,              //write data
  input  logic [XLEN            -1:0] biu_q_i,              //read data
  input  logic                        biu_ack_i,            //transfer acknowledge
  input  logic                        biu_err_i,            //transfer error
  output logic [BIUTAG_SIZE     -1:0] biu_tagi_o,
  input  logic [BIUTAG_SIZE     -1:0] biu_tago_i
);

  //////////////////////////////////////////////////////////////////
  //
  // Constants
  //
  
  //----------------------------------------------------------------
  // Cache
  //----------------------------------------------------------------
  localparam PAGE_SIZE        = 4*1024;                             //4KB pages
  localparam MAX_IDX_BITS     = $clog2(PAGE_SIZE) - $clog2(BLOCK_SIZE); //Maximum IDX_BITS
  

  localparam SETS             = (SIZE*1024) / BLOCK_SIZE / WAYS;    //Number of sets TODO:SETS=1 doesn't work
  localparam BLK_OFFS_BITS    = $clog2(BLOCK_SIZE);                 //Number of BlockOffset bits
  localparam IDX_BITS         = $clog2(SETS);                       //Number of Index-bits
  localparam TAG_BITS         = PLEN - IDX_BITS - BLK_OFFS_BITS;     //Number of TAG-bits
  localparam BLK_BITS         = 8*BLOCK_SIZE;                       //Total number of bits in a Block
  localparam BURST_SIZE       = BLK_BITS / XLEN;                    //Number of transfers to load 1 Block
  localparam BURST_BITS       = $clog2(BURST_SIZE);
  localparam BURST_OFFS       = XLEN/8;
  localparam BURST_LSB        = $clog2(BURST_OFFS);

  //BLOCK decoding
  localparam DAT_OFFS_BITS    = $clog2(BLK_BITS / XLEN);            //Offset in block
  localparam PARCEL_OFFS_BITS = $clog2(XLEN / PARCEL_SIZE);


  //Inflight transfers
  localparam INFLIGHT_DEPTH   = BURST_SIZE;                         //Wishbone has 1 transfers in flight
                                                                    //AHB      has 2 transfers in flight
                                                                    //AXI can have many transfers in flight
  localparam INFLIGHT_BITS    = $clog2(INFLIGHT_DEPTH+1);


  //////////////////////////////////////////////////////////////////
  //
  // Variables
  //

  logic [              6:0] way_random; //Up to 128ways
  logic [WAYS         -1:0] fill_way_select,
                            mem_fill_way, hit_fill_way;

  logic                     setup_req,        tag_req;
  logic [PLEN         -1:0]                   tag_adr;
  biu_size_t                setup_size,       tag_size;
  logic                     setup_lock,       tag_lock;
  biu_prot_t                setup_prot,       tag_prot;
  logic                     setup_invalidate, tag_invalidate;
  logic                                       tag_pagefault;

  logic [TAG_BITS     -1:0] tag_core_tag,
                            hit_core_tag;
  logic [IDX_BITS     -1:0] setup_idx,
                            hit_idx;

  logic                     cache_hit;
  logic [BLK_BITS     -1:0] cache_line;

  logic [INFLIGHT_BITS-1:0] inflight_cnt;

  biucmd_t                  biucmd;
  logic                     biucmd_noncacheable_req,
                            biucmd_noncacheable_ack;
  logic [PLEN         -1:0] biucmd_adr;
  logic [BIUTAG_SIZE  -1:0] biucmd_tag;
  logic [BLK_BITS     -1:0] biubuffer;
  logic                     in_biubuffer;
  logic [BLK_BITS     -1:0] biu_line;

  logic                     armed,
	                    filling,
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

    .stall_i                   ( mem_stall_o             ),
    .flush_i                   ( mem_flush_i             ),

    .req_i                     ( mem_req_i               ),
    .adr_i                     ( mem_adr_i               ),
    .size_i                    ( mem_size_i              ),
    .lock_i                    ( mem_lock_i              ),
    .prot_i                    ( mem_prot_i              ),
    .we_i                      ( 1'b0                    ),
    .d_i                       ( {XLEN{1'b0}}            ),
    .invalidate_i              ( invalidate_i            ),
    .clean_i                   ( 1'b0                    ),

    .req_o                     ( setup_req               ),
    .rreq_o                    (                         ),
    .size_o                    ( setup_size              ),
    .lock_o                    ( setup_lock              ),
    .prot_o                    ( setup_prot              ),
    .we_o                      (                         ),
    .q_o                       (                         ),
    .invalidate_o              ( setup_invalidate        ),
    .clean_o                   (                         ),
 
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

    .stall_i                   ( mem_stall_o             ),
    .flush_i                   ( mem_flush_i             ),
    .pagefault_i               ( pagefault_i             ),
    .req_i                     ( setup_req               ),
    .phys_adr_i                ( phys_adr_i              ),
    .size_i                    ( setup_size              ),
    .lock_i                    ( setup_lock              ),
    .prot_i                    ( setup_prot              ),
    .we_i                      ( 1'b0                    ),
    .d_i                       ( {XLEN{1'b0}}            ),
    .invalidate_i              ( setup_invalidate        ),
    .clean_i                   (                         ),

    .req_o                     ( tag_req                 ),
    .wreq_o                    (                         ),
    .adr_o                     ( tag_adr                 ),
    .size_o                    ( tag_size                ),
    .lock_o                    ( tag_lock                ),
    .prot_o                    ( tag_prot                ),
    .we_o                      (                         ),
    .be_o                      (                         ),
    .q_o                       (                         ),
    .invalidate_o              ( tag_invalidate          ),
    .clean_o                   (                         ),
    .pagefault_o               ( tag_pagefault           ),
    .core_tag_o                ( tag_core_tag            ) );

  
  /* Hit stage
   * Takes hit, cache-line and biu signals and generates parcel-output
   * Contains front-end statemachine
   */
  riscv_cache_hit #(
    .XLEN                      ( XLEN                    ),
    .PLEN                      ( PLEN                    ),
    .PARCEL_SIZE               ( PARCEL_SIZE             ),
    .HAS_RVC                   ( HAS_RVC                 ),
    .SIZE                      ( SIZE                    ),
    .BLOCK_SIZE                ( BLOCK_SIZE              ),
    .WAYS                      ( WAYS                    ),
    .INFLIGHT_DEPTH            ( INFLIGHT_DEPTH          ),
    .BIUTAG_SIZE               ( BIUTAG_SIZE             ) )
  cache_hit_inst (
    .rst_ni                    ( rst_ni                  ),
    .clk_i                     ( clk_i                   ),

    .stall_o                   ( mem_stall_o             ),
    .flush_i                   ( mem_flush_i             ),

    .invalidate_i              ( tag_invalidate          ),
    .dc_clean_rdy_i            ( dc_clean_rdy_i          ),

    .armed_o                   ( armed                   ),
    .invalidate_all_blocks_o   ( invalidate_all_blocks   ),
    .filling_o                 ( filling                 ),
    .fill_way_i                ( mem_fill_way            ),
    .fill_way_o                ( hit_fill_way            ),

    .req_i                     ( tag_req                 ),
    .adr_i                     ( tag_adr                 ),
    .size_i                    ( tag_size                ),
    .lock_i                    ( tag_lock                ),
    .prot_i                    ( tag_prot                ),
    .cacheable_i               ( pma_cacheable_i         ),
    .misaligned_i              ( pma_misaligned_i        ),
    .pma_exception_i           ( pma_exception_i         ),
    .pmp_exception_i           ( pmp_exception_i         ),
    .pagefault_i               ( tag_pagefault           ),

    .idx_o                     ( hit_idx                 ),
    .core_tag_o                ( hit_core_tag            ),

    .biucmd_o                  ( biucmd                  ),
    .biucmd_ack_i              ( biucmd_ack              ),
    .biucmd_noncacheable_req_o ( biucmd_noncacheable_req ),
    .biucmd_noncacheable_ack_i ( biucmd_noncacheable_ack ),
    .biucmd_adri_o             ( biucmd_adr              ),
    .biucmd_tagi_o             ( biucmd_tag              ),
    .inflight_cnt_i            ( inflight_cnt            ),

    .cache_hit_i               ( cache_hit               ),
    .cache_line_i              ( cache_line              ),

    .biu_stb_ack_i             ( biu_stb_ack_i           ),
    .biu_ack_i                 ( biu_ack_i               ),
    .biu_err_i                 ( biu_err_i               ),
    .biu_adro_i                ( biu_adro_i              ),
    .biu_tago_i                ( biu_tago_i              ),
    .biu_q_i                   ( biu_q_i                 ),
    .in_biubuffer_i            ( in_biubuffer            ),
    .biubuffer_i               ( biubuffer               ),

    .parcel_o                  ( parcel_o                ),
    .parcel_valid_o            ( parcel_valid_o          ),
    .parcel_error_o            ( parcel_error_o          ),
    .parcel_misaligned_o       ( parcel_misaligned_o     ),
    .parcel_pagefault_o        ( parcel_pagefault_o      ) );



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

    .stall_i                   ( mem_stall_o             ),

    .armed_i                   ( armed                   ),
    .cleaning_i                ( 1'b0                    ),
    .clean_block_i             ( 1'b0                    ),
    .invalidate_block_i        ( 1'b0                    ),
    .invalidate_all_blocks_i   ( invalidate_all_blocks   ),
    .filling_i                 ( filling                 ),
    .fill_way_select_i         ( fill_way_select         ),
    .fill_way_i                ( hit_fill_way            ),
    .fill_way_o                ( mem_fill_way            ),

    .rd_core_tag_i             ( tag_core_tag            ),
    .wr_core_tag_i             ( hit_core_tag            ),
    .rd_idx_i                  ( setup_idx               ),
    .wr_idx_i                  ( hit_idx                 ),

    .rreq_i                    ( 1'b0                    ), //Read cache memories?
    .writebuffer_we_i          ( 1'b0                    ),
    .writebuffer_be_i          ( {BLK_BITS/8   {1'b0}}   ),
    .writebuffer_idx_i         ( {IDX_BITS     {1'b0}}   ),
    .writebuffer_offs_i        ( {DAT_OFFS_BITS{1'b0}}   ),
    .writebuffer_data_i        ( {XLEN         {1'b0}}   ),
    .writebuffer_ways_hit_i    ( {WAYS         {1'b0}}   ),

    .evict_idx_o               (                         ),
    .evict_tag_o               (                         ),
    .evict_line_o              (                         ),

    .biu_line_i                ( biu_line                ),
    .biu_line_dirty_i          ( 1'b0                    ),
    .biucmd_ack_i              ( biucmd_ack              ),

    .latchmem_i                (~mem_stall_o             ),
    .hit_o                     ( cache_hit               ),
    .ways_hit_o                (                         ),
    .cache_dirty_o             (                         ),
    .way_dirty_o               (                         ),
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
    .biucmd_busy_o             (                         ),
    .biucmd_noncacheable_req_i ( biucmd_noncacheable_req ),
    .biucmd_noncacheable_ack_o ( biucmd_noncacheable_ack ),
    .biucmd_tag_i              ( biucmd_tag              ),
    .inflight_cnt_o            ( inflight_cnt            ),

    .req_i                     ( tag_req                 ),
    .adr_i                     ( biucmd_adr              ),
    .size_i                    ( tag_size                ),
    .prot_i                    ( tag_prot                ),
    .lock_i                    ( 1'b0                    ),
    .we_i                      ( 1'b0                    ),
    .be_i                      ( {XLEN/8  {1'b0}}        ),
    .d_i                       ( {XLEN    {1'b0}}        ),

    .evictbuffer_adr_i         ( {PLEN    {1'b0}}        ),
    .evictbuffer_d_i           ( {BLK_BITS{1'b0}}        ),
    .biubuffer_o               ( biubuffer               ),
    .in_biubuffer_o            ( in_biubuffer            ),
    .biu_line_o                ( biu_line                ),
    .biu_line_dirty_o          (                         ),

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



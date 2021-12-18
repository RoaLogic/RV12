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

module riscv_dcache_core #(
  parameter                XLEN        = 32,
  parameter                PLEN        = XLEN,
  parameter                PARCEL_SIZE = XLEN,
  parameter                HAS_RVC     = 0,

  parameter                SIZE        = 64,     //KBYTES
  parameter                BLOCK_SIZE  = XLEN,   //BYTES, number of bytes in a block (way)
                                                 //Must be [XLEN*2,XLEN,XLEN/2]
  parameter                WAYS        =  2,     // 1           : Direct Mapped
                                                 //<n>          : n-way set associative
                                                 //<n>==<blocks>: fully associative
  parameter                REPLACE_ALG = 0,      //0: Random
                                                 //1: FIFO
                                                 //2: LRU

  parameter                TECHNOLOGY  = "GENERIC",

  parameter                DEPTH       = 2       //number of transactions in flight
)
(
  input  logic             rst_ni,
  input  logic             clk_i,

  //CPU side
  input  logic             is_cacheable_i,       //This needs to move inside this block
  input  logic             misaligned_i,         //this needs to move inside this block
  input  logic             mem_flush_i,
  input  logic             mem_req_i,
  output logic             mem_ack_o,
  output logic             mem_err_o,
  input  logic [XLEN -1:0] mem_adr_i,
  input  biu_size_t        mem_size_i,
  input                    mem_lock_i,
  input  biu_prot_t        mem_prot_i,
  input  logic             mem_we_i,
  input  logic [XLEN -1:0] mem_d_i,
  output logic [XLEN -1:0] mem_q_o,
  input  logic             cache_flush_i,        //flush (invalidate) cache
  output logic             cache_flush_rdy_o,    //data cache ready flushing

  //To BIU
  output logic             biu_stb_o,            //access request
  input  logic             biu_stb_ack_i,        //access acknowledge
  input  logic             biu_d_ack_i,          //BIU needs new data (biu_d_o)
  output logic [PLEN -1:0] biu_adri_o,           //access start address
  input  logic [PLEN -1:0] biu_adro_i,
  output biu_size_t        biu_size_o,           //transfer size
  output biu_type_t        biu_type_o,           //burst type
  output logic             biu_lock_o,           //locked transfer
  output biu_prot_t        biu_prot_o,           //protection bits
  output logic             biu_we_o,             //write enable
  output logic [XLEN -1:0] biu_d_o,              //write data
  input  logic [XLEN -1:0] biu_q_i,              //read data
  input  logic             biu_ack_i,            //transfer acknowledge
  input  logic             biu_err_i             //transfer error
);

  //////////////////////////////////////////////////////////////////
  //
  // Constants
  //
  
  //----------------------------------------------------------------
  // Cache
  //----------------------------------------------------------------
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
  localparam PARCEL_OFF_BITS = $clog2(XLEN / PARCEL_SIZE);


  //Inflight transfers
  localparam INFLIGHT_DEPTH  = 2;                                  //Wishbone has 1 transfers in flight
                                                                   //AHB      has 2 transfers in flight
                                                                   //AXI can have many transfers in flight
  localparam INFLIGHT_BITS   = $clog2(INFLIGHT_DEPTH+1);


  //////////////////////////////////////////////////////////////////
  //
  // Functions
  //   
 

  //////////////////////////////////////////////////////////////////
  //
  // Typedefs
  //



  //////////////////////////////////////////////////////////////////
  //
  // Variables
  //

  logic [              6:0] way_random; //Up to 128ways
  logic [WAYS         -1:0] fill_way_select;
  logic                     cacheflush;

  logic                     stall;

  logic                     setup_req,           tag_req;
  logic [PLEN         -1:0] setup_adr,           tag_adr; 
  biu_size_t                setup_size,          tag_size;
  logic                     setup_lock,          tag_lock;
  biu_prot_t                setup_prot,          tag_prot;
  logic                     wetup_we,            tag_we;
  logic                     setup_is_cacheable,  tag_is_cacheable;
  logic                     setup_is_misaligned, tag_is_misaligned;


  logic                     setup_writebuffer_we,   tag_writebuffer_we;
  logic [IDX_BITS     -1:0] setup_writebuffer_idx,  tag_writebuffer_idx;
  logic [XLEN         -1:0] setup_writebuffer_data, tag_writebuffer_data;
  logic [XLEN/8       -1:0] setup_writebuffer_be,   tag_writebuffer_be;

  logic [TAG_BITS     -1:0] setup_core_tag,
                            hit_core_tag;
  logic [IDX_BITS     -1:0] setup_tag_idx,
                            setup_dat_idx,
                            hit_tag_idx,
                            hit_dat_idx;
  logic [BLK_BITS/8   -1:0] dat_be;


  logic                     cache_hit,
                            cache_dirty,
                            way_dirty;
  logic [BLK_BITS     -1:0] cache_line;


  logic [INFLIGHT_BITS-1:0] inflight_cnt;

  biucmd_t                  biucmd;
  logic                     biucmd_noncacheable_req,
                            biucmd_noncacheable_ack;
  logic                     in_biubuffer;
  logic [BLK_BITS     -1:0] biubuffer;
  logic [BLK_BITS     -1:0] cachemem_dat;

  logic                     armed,
                            flushing,
	                    filling;


  //////////////////////////////////////////////////////////////////
  //
  // Module Body
  //

  assign mem_ack_o = ~stall;

  
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
  

  //hold flush until ready to be serviced
  always @(posedge clk_i, negedge rst_ni)
    if (!rst_ni) cacheflush <= 1'b0;
    else         cacheflush <= cache_flush_i | (cacheflush & ~flushing);



  /* Address Setup Stage
   * Drives signals into TAG and DATA memories
   */
  riscv_cache_setup #(
    .XLEN               ( XLEN                ),
    .SIZE               ( SIZE                ),
    .BLOCK_SIZE         ( BLOCK_SIZE          ),
    .WAYS               ( WAYS                ) )
  cache_setup_inst (
    .rst_ni             ( rst_ni              ),
    .clk_i              ( clk_i               ),

    .stall_i            ( stall               ),
    .flush_i            ( mem_flush_i         ),

    .req_i              ( mem_req_i           ),
    .adr_i              ( mem_adr_i           ),
    .size_i             ( mem_size_i          ),
    .lock_i             ( mem_lock_i          ),
    .prot_i             ( mem_prot_i          ),
    .we_i               ( mem_we_i            ),
    .d_i                ( mem_d_i             ),
    .is_cacheable_i     ( is_cacheable_i      ),
    .is_misaligned_i    ( misaligned_i        ),

    .req_o              ( setup_req           ),
    .adr_o              ( setup_adr           ),
    .size_o             ( setup_size          ),
    .lock_o             ( setup_lock          ),
    .prot_o             ( setup_prot          ),
    .is_cacheable_o     ( setup_is_cacheable  ),
    .is_misaligned_o    ( setup_is_misaligned ),
    .core_tag_o         ( setup_core_tag      ),
    .tag_idx_o          ( setup_tag_idx       ),
    .dat_idx_o          ( setup_dat_idx       ),

    .writebuffer_we_o   ( writebuffer_we      ),
    .writebuffer_idx_o  ( writebuffer_idx     ),
    .writebuffer_data_o ( writebuffer_data    ),
    .writebuffer_be_o   ( writebuffer_be      ) );



  /* Tag stage
   * Tag/Data memory access. Hit and cache-line available after this stage
   * Physical address is available here
   */
  riscv_cache_tag #(
    .XLEN               ( XLEN                   ),
    .PLEN               ( PLEN                   ),
    .IDX_BITS           ( IDX_BITS               ) )
  cache_tag_inst (
    .rst_ni             ( rst_ni                 ),
    .clk_i              ( clk_i                  ),

    .stall_i            ( stall                  ),
    .flush_i            ( mem_flush_i            ),
    .req_i              ( setup_req              ),
    .adr_i              ( setup_adr              ),
    .size_i             ( setup_size             ),
    .lock_i             ( setup_lock             ),
    .prot_i             ( setup_prot             ),
    .is_cacheable_i     ( setup_is_cacheable     ),
    .is_misaligned_i    ( setup_is_misaligned    ),

    .writebuffer_we_i   ( setup_writebuffer_we   ),
    .writebuffer_idx_i  ( setup_writebuffer_idx  ),
    .writebuffer_data_i ( setup_writebuffer_data ),
    .writebuffer_be_i   ( setup_writebuffer_be   ),

    .req_o              ( tag_req                ),
    .adr_o              ( tag_adr                ),
    .size_o             ( tag_size               ),
    .lock_o             ( tag_lock               ),
    .prot_o             ( tag_prot               ),
    .is_cacheable_o     ( tag_cacheable          ),
    .is_misaligned_o    ( tag_misaligned         ),

    .writebuffer_we_o   ( tag_writebuffer_we     ),
    .writebuffer_idx_o  ( tag_writebuffer_idx    ),
    .writebuffer_data_o ( tag_writebuffer_data   ),
    .writebuffer_be_o   ( tag_writebuffer_be     ) );


  
  /* Hit stage
   * Takes hit, cache-line and biu signals and generates parcel-output
   * Contains front-end statemachine
   */
  riscv_dcache_hit #(
    .XLEN                      ( XLEN                    ),
    .PLEN                      ( PLEN                    ),
    .PARCEL_SIZE               ( PARCEL_SIZE             ),
    .HAS_RVC                   ( HAS_RVC                 ),
    .SIZE                      ( SIZE                    ),
    .BLOCK_SIZE                ( BLOCK_SIZE              ),
    .WAYS                      ( WAYS                    ),
    .INFLIGHT_DEPTH            ( INFLIGHT_DEPTH          ) )
  cache_hit_inst (
    .rst_ni                    ( rst_ni                  ),
    .clk_i                     ( clk_i                   ),

    .stall_o                   ( stall                   ),
    .flush_i                   ( mem_flush_i             ),

    .cacheflush_req_i          ( cacheflush              ),
    .dcflush_rdy_i             ( dcflush_rdy_i           ),
    .armed_o                   ( armed                   ),
    .flushing_o                ( flushing                ),
    .filling_o                 ( filling                 ),

    .req_i                     ( tag_req                 ),
    .adr_i                     ( tag_adr                 ),
    .size_i                    ( tag_size                ),
    .lock_i                    ( tag_lock                ),
    .prot_i                    ( tag_prot                ),
    .we_i                      ( tag_we                  ),
    .is_cacheable_i            ( tag_cacheable           ),
    .q_o                       ( mem_q_o                 ),
    .ack_o                     ( mem_ack_o               ),
    .err_o                     ( mem_err_o               ),

    .tag_idx_o                 ( hit_tag_idx             ),
    .dat_idx_o                 ( hit_dat_idx             ),
    .core_tag_o                ( hit_core_tag            ),

    .biucmd_o                  ( biucmd                  ),
    .biucmd_ack_i              ( biucmd_ack              ),
    .biucmd_noncacheable_req_o ( biucmd_noncacheable_req ),
    .biucmd_noncacheable_ack_i ( biucmd_noncacheable_ack ),
    .inflight_cnt_i            ( inflight_cnt            ),

    .cache_hit_i               ( cache_hit               ),
    .cache_line_i              ( cache_line              ),

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

  assign dat_be = {$bits(dat_be){1'b1}};
  
  riscv_cache_memory #(
    .XLEN               ( XLEN             ),
    .SIZE               ( SIZE             ),
    .BLOCK_SIZE         ( BLOCK_SIZE       ),
    .WAYS               ( WAYS             ),

    .TECHNOLOGY         ( TECHNOLOGY       ) )
  cache_memory_inst (
    .rst_ni             ( rst_ni           ),
    .clk_i              ( clk_i            ),

    .stall_i            ( stall            ),

    .armed_i            ( armed            ),
    .flushing_i         ( flushing         ),
    .filling_i          ( filling          ),
    .fill_way_select_i  ( fill_way_select  ),

    .rd_core_tag_i      ( setup_core_tag   ),
    .wr_core_tag_i      ( hit_core_tag     ),
    .rd_tag_idx_i       ( setup_tag_idx    ),
    .wr_tag_idx_i       ( hit_tag_idx      ),
 
    .rd_dat_idx_i       ( setup_dat_idx    ),
    .wr_dat_idx_i       ( hit_dat_idx      ),
    .dat_be_i           ( dat_be           ),
    .writebuffer_data_i ( writebuffer_data ),
    .biu_d_i            ( cachemem_dat     ),
    .biucmd_ack_i       ( biucmd_ack       ),

    .hit_o              ( cache_hit        ),
    .dirty_o            ( cache_dirty      ),
    .way_dirty_o        ( way_dirty        ),
    .cache_line_o       ( cache_line       ) );



  //----------------------------------------------------------------
  // Bus Interface Statemachine
  //----------------------------------------------------------------
  riscv_cache_biu_ctrl #(
    .XLEN                      ( XLEN                    ),
    .PLEN                      ( PLEN                    ),
    .SIZE                      ( SIZE                    ),
    .BLOCK_SIZE                ( BLOCK_SIZE              ),
    .WAYS                      ( WAYS                    ),
    .INFLIGHT_DEPTH            ( INFLIGHT_DEPTH          ) )
  biu_ctrl_inst (
    .rst_ni                    ( rst_ni                  ),
    .clk_i                     ( clk_i                   ),

    .flush_i                   ( mem_flush_i             ),

    .biucmd_i                  ( biucmd                  ),
    .biucmd_ack_o              ( biucmd_ack              ),
    .biucmd_noncacheable_req_i ( biucmd_noncacheable_req ),
    .biucmd_noncacheable_ack_o ( biucmd_noncacheable_ack ),
    .inflight_cnt_o            ( inflight_cnt            ),

    .req_i                     ( tag_req                 ),
    .adr_i                     ( tag_adr                 ),
    .size_i                    ( tag_size                ),
    .prot_i                    ( tag_prot                ),
    .lock_i                    ( tag_lock                ),
    .we_i                      ( tag_we                  ),

    .biu_ack_o                 ( biu_ack                 ),
    .biubuffer_o               ( biubuffer               ),
    .in_biubuffer_o            ( in_biubuffer            ),
    .cachemem_dat_o            ( cachemem_dat            ),

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
    .biu_err_i                 ( biu_err_i               ) );

endmodule



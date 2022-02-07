/////////////////////////////////////////////////////////////////////
//   ,------.                    ,--.                ,--.          //
//   |  .--. ' ,---.  ,--,--.    |  |    ,---. ,---. `--' ,---.    //
//   |  '--'.'| .-. |' ,-.  |    |  |   | .-. | .-. |,--.| .--'    //
//   |  |\  \ ' '-' '\ '-'  |    |  '--.' '-' ' '-' ||  |\ `--.    //
//   `--' '--' `---'  `--`--'    `-----' `---' `-   /`--' `---'    //
//                                             `---'               //
//    RISC-V                                                       //
//    Data Memory Access Block                                     //
//                                                                 //
/////////////////////////////////////////////////////////////////////
//                                                                 //
//             Copyright (C) 2014-2021 ROA Logic BV                //
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


import riscv_state_pkg::*;
import riscv_pma_pkg::*;
import biu_constants_pkg::*;

module riscv_dmem_ctrl #(
  parameter XLEN              = 32,
  parameter PLEN              = XLEN, // XLEN==32 ? 34 : 56

  parameter HAS_RVC           = 0,
  parameter HAS_MMU           = 0,

  parameter PMA_CNT           = 3,
  parameter PMP_CNT           = 16,

  parameter CACHE_SIZE        = 64, //KBYTES
  parameter CACHE_BLOCK_SIZE  = 32, //BYTES
  parameter CACHE_WAYS        =  2, // 1           : Direct Mapped
                                    //<n>          : n-way set associative
                                    //<n>==<blocks>: fully associative

/*
  parameter REPLACE_ALG      = 1,  //0: Random
                                   //1: FIFO
                                   //2: LRU
*/
  parameter TECHNOLOGY       = "GENERIC",
  parameter BIUTAG_SIZE      = 2
)
(
  input  logic                             rst_ni,
  input  logic                             clk_i,
 
  //Configuration
  input  pmacfg_t                          pma_cfg_i [PMA_CNT],
  input                 [XLEN        -1:0] pma_adr_i [PMA_CNT],

  input  pmpcfg_t [15:0]                   st_pmpcfg_i,
  input  logic    [15:0][XLEN        -1:0] st_pmpaddr_i,
  input  logic          [             1:0] st_prv_i,

  //CPU side
  input  logic                             mem_req_i,
  input  biu_size_t                        mem_size_i,
  input  logic                             mem_lock_i, 
  input  logic          [XLEN        -1:0] mem_adr_i,
  input  logic                             mem_we_i,
  input  logic          [XLEN        -1:0] mem_d_i,
  output logic          [XLEN        -1:0] mem_q_o,
  output logic                             mem_ack_o,
  output logic                             mem_err_o,
                                           mem_misaligned_o,
                                           mem_pagefault_o,
  input  logic                             cache_flush_i,
  output logic                             cache_flush_rdy_o,

  //BIU ports
  output logic                             biu_stb_o,
  input  logic                             biu_stb_ack_i,
  input  logic                             biu_d_ack_i,
  output logic          [PLEN        -1:0] biu_adri_o,
  input  logic          [PLEN        -1:0] biu_adro_i,
  output biu_size_t                        biu_size_o,
  output biu_type_t                        biu_type_o,
  output logic                             biu_we_o,
  output logic                             biu_lock_o,
  output biu_prot_t                        biu_prot_o,
  output logic          [XLEN        -1:0] biu_d_o,
  input  logic          [XLEN        -1:0] biu_q_i,
  input  logic                             biu_ack_i,
                                           biu_err_i,
  output logic          [BIUTAG_SIZE -1:0] biu_tagi_o,
  input  logic          [BIUTAG_SIZE -1:0] biu_tago_i
);

  //////////////////////////////////////////////////////////////////
  //
  // Constants
  //


  //////////////////////////////////////////////////////////////////
  //
  // Variables
  //

  //Transfer parameters
  biu_prot_t       prot;


  //Queue
  logic            queue_req;
  logic [XLEN-1:0] queue_adr;
  biu_size_t       queue_size;
  logic            queue_lock;
  biu_prot_t       queue_prot;
  logic            queue_we;
  logic [XLEN-1:0] queue_d;

 
  //MMU
  logic            mmu_req;
  logic [PLEN-1:0] mmu_adr;
  biu_size_t       mmu_size;
  logic            mmu_lock;
  logic            mmu_we;
  logic            mmu_pagefault;


  //Misalignment check
  logic            misaligned;
  

  //from PMA check
  logic            pma_exception,
                   pma_misaligned,
                   pma_cacheable;


  //from PMP check
  logic            pmp_exception;


  //From dcache-ctrl
  logic            stall;


  //////////////////////////////////////////////////////////////////
  //
  // Module Body
  //

  assign prot             = biu_prot_t'( PROT_DATA                                        |
	                                (st_prv_i == PRV_U ? PROT_USER : PROT_PRIVILEGED) );


  /* Hookup buffer
   * Is this necessary in case of nodcache?
   */
  riscv_membuf #(
    .DEPTH   ( 2          ),
    .XLEN    ( XLEN       ) )
  membuffer_inst (
    .rst_ni  ( rst_ni     ),
    .clk_i   ( clk_i      ),

    .flush_i ( 1'b0       ),
    .stall_i ( stall      ),

    .req_i   ( mem_req_i  ),
    .adr_i   ( mem_adr_i  ),
    .size_i  ( mem_size_i ),
    .lock_i  ( mem_lock_i ),
    .prot_i  ( prot       ),
    .we_i    ( mem_we_i   ),
    .d_i     ( mem_d_i    ),

    .req_o   ( queue_req  ),
    .ack_i   ( mem_ack_o | mem_err_o ),
    .adr_o   ( queue_adr  ),
    .size_o  ( queue_size ),
    .lock_o  ( queue_lock ),
    .prot_o  ( queue_prot ),
    .we_o    ( queue_we   ),
    .q_o     ( queue_d    ),

    .empty_o (            ),
    .full_o  (            ) );



  /* Hookup Cache
   */
generate
  if (CACHE_SIZE > 0)
  begin : cache_blk
      /* Hookup MMU
       */
      if (HAS_MMU != 0)
      begin : mmu_blk
      end
      else
      begin : nommu_blk
          riscv_nommu #(
            .XLEN        ( XLEN           ),
            .PLEN        ( PLEN           ) )
          mmu_inst (
            .rst_ni      ( rst_ni         ),
            .clk_i       ( clk_i          ),
            .stall_i     ( stall          ),

            .flush_i     ( 1'b0           ),
            .req_i       ( queue_req      ),
            .adr_i       ( queue_adr      ), //virtual address
            .size_i      ( queue_size     ),
            .lock_i      ( queue_lock     ),
            .we_i        ( queue_we       ),

            .req_o       ( mmu_req        ),
            .adr_o       ( mmu_adr        ), //physical address
            .size_o      ( mmu_size       ),
            .lock_o      ( mmu_lock       ),
            .we_o        ( mmu_we         ),

            .pagefault_o ( mmu_pagefault  ) );
      end


      /* Hookup misalignment check
       */
      riscv_memmisaligned #(
        .PLEN          ( PLEN       ),
        .HAS_RVC       ( HAS_RVC    ) )
      misaligned_inst (
        .clk_i         ( clk_i      ),
        .stall_i       ( stall      ),
        .instruction_i ( 1'b0       ), //data access
        .adr_i         ( mmu_adr    ), //virtual address
        .size_i        ( mmu_size   ),
        .misaligned_o  ( misaligned ) );


      /* Hookup Physical Memory Attribute Unit
       */
      if (PMA_CNT > 0)
      begin : pma_blk
          riscv_pmachk #(
            .XLEN          ( XLEN           ),
            .PLEN          ( PLEN           ),
            .HAS_RVC       ( HAS_RVC        ),
            .PMA_CNT       ( PMA_CNT        ) )
          pmachk_inst (
            .clk_i         ( clk_i          ),
            .stall_i       ( stall          ),

            //Configuration
            .pma_cfg_i     ( pma_cfg_i      ),
            .pma_adr_i     ( pma_adr_i      ),

            //misaligned
            .misaligned_i  ( misaligned     ),

            //Memory Access
            .instruction_i ( 1'b0           ), //data access
            .adr_i         ( mmu_adr        ), //physical address
            .size_i        ( mmu_size       ),
            .lock_i        ( mmu_lock       ),
            .we_i          ( mmu_we         ),

            //Output
            .exception_o   ( pma_exception  ),
            .misaligned_o  ( pma_misaligned ),
            .cacheable_o   ( pma_cacheable  ) );
      end
      else
      begin
          //no PMA-check. Tie off signals
          assign pma_cacheable = 1'b1; //Afterall, we do have a cache ...
          assign pma_exception = 1'b0;

          // pma_misaligned is registered
          always @(posedge clk_i)
            if (!stall) pma_misaligned <= misaligned;
      end



      /* Hookup Physical Memory Protection Unit
       */
      if (PMP_CNT > 0)
      begin : pmp_blk
          riscv_pmpchk #(
            .XLEN          ( XLEN          ),
            .PLEN          ( PLEN          ),
            .PMP_CNT       ( PMP_CNT       ) )
          pmpchk_inst (
            .clk_i         ( clk_i         ),
            .stall_i       ( stall         ),

            .st_pmpcfg_i   ( st_pmpcfg_i   ),
            .st_pmpaddr_i  ( st_pmpaddr_i  ),
            .st_prv_i      ( st_prv_i      ),

            .instruction_i ( 1'b0          ),  //Data access
            .adr_i         ( mmu_adr       ),  //Physical Memory address (i.e. after translation)
            .size_i        ( mmu_size      ),  //Transfer size
            .we_i          ( mmu_we        ),  //Read/Write enable

            .exception_o   ( pmp_exception ) );
      end
      else
      begin
          //No PMP, tie off signals
          assign pmp_exception = 1'b0;
      end


      /* Instantiate Instruction Cache Core
       */
      riscv_dcache_core #(
        .XLEN              ( XLEN              ),
        .PLEN              ( PLEN              ),
        .SIZE              ( CACHE_SIZE        ),
        .BLOCK_SIZE        ( CACHE_BLOCK_SIZE  ),
        .WAYS              ( CACHE_WAYS        ),
        .TECHNOLOGY        ( TECHNOLOGY        ),
        .BIUTAG_SIZE       ( BIUTAG_SIZE       ) )
      dcache_inst (
        //common signals
        .rst_ni            ( rst_ni            ),
        .clk_i             ( clk_i             ),

	.stall_o           ( stall             ),

        //from MMU
        .phys_adr_i        ( mmu_adr           ),
        .pagefault_i       ( mmu_pagefault     ),

        //from PMA
        .pma_cacheable_i   ( pma_cacheable     ),
        .pma_misaligned_i  ( pma_misaligned    ),
        .pma_exception_i   ( pma_exception     ),

        //from PMP
	.pmp_exception_i   ( pmp_exception     ),

        //from/to CPU
        .mem_req_i         ( queue_req         ),
        .mem_ack_o         ( mem_ack_o         ),
        .mem_adr_i         ( queue_adr         ), //virtual address
        .mem_flush_i       ( 1'b0              ),
        .mem_size_i        ( queue_size        ),
        .mem_lock_i        ( queue_lock        ),
        .mem_prot_i        ( queue_prot        ),
        .mem_we_i          ( queue_we          ),
        .mem_d_i           ( queue_d           ),
        .mem_q_o           ( mem_q_o           ),
        .mem_err_o         ( mem_err_o         ),
	.mem_misaligned_o  ( mem_misaligned_o  ),
        .mem_pagefault_o   ( mem_pagefault_o   ),
        .cache_flush_i     ( cache_flush_i     ),
        .cache_flush_rdy_o ( cache_flush_rdy_o ),

        //To BIU
        .biu_stb_o         ( biu_stb_o         ),
        .biu_stb_ack_i     ( biu_stb_ack_i     ),
        .biu_d_ack_i       ( biu_d_ack_i       ),
        .biu_adri_o        ( biu_adri_o        ),
        .biu_adro_i        ( biu_adro_i        ),
        .biu_size_o        ( biu_size_o        ),
        .biu_type_o        ( biu_type_o        ),
        .biu_we_o          ( biu_we_o          ),
        .biu_lock_o        ( biu_lock_o        ),
        .biu_prot_o        ( biu_prot_o        ),
        .biu_d_o           ( biu_d_o           ),
        .biu_q_i           ( biu_q_i           ),
        .biu_ack_i         ( biu_ack_i         ),
        .biu_err_i         ( biu_err_i         ),
        .biu_tagi_o        ( biu_tagi_o        ),
        .biu_tago_i        ( biu_tago_i        ) );
  end
  else  //No cache
  begin
      /*
       * No Data Cache Core
       * Control and glue logic only
       */
      riscv_nodcache_core #(
        .XLEN             ( XLEN             ),
        .ALEN             ( PLEN             ) )
      nodcache_core_inst (
        //common signals
        .rst_ni           ( rst_ni           ),
        .clk_i            ( clk_i            ),

        //CPU
        .mem_req_i        ( mem_req_i        ),
        .mem_size_i       ( mem_size_i       ),
        .mem_lock_i       ( mem_lock_i       ),
        .mem_adr_i        ( mem_adr_i        ),
        .mem_we_i         ( mem_we_i         ),
        .mem_d_i          ( mem_d_i          ),
        .mem_q_o          ( mem_q_o          ),
        .mem_ack_o        ( mem_ack_o        ),
        .mem_err_o        ( mem_err_o        ),
        .mem_misaligned_o ( mem_misaligned_o ),
        .st_prv_i         ( st_prv_i         ),

        //BIU
        .biu_stb_o        ( biu_stb_o        ),
        .biu_stb_ack_i    ( biu_stb_ack_i    ),
        .biu_d_ack_i      ( biu_d_ack_i      ),
        .biu_adri_o       ( biu_adri_o       ),
        .biu_adro_i       ( biu_adro_i       ),
        .biu_size_o       ( biu_size_o       ),
        .biu_type_o       ( biu_type_o       ),
        .biu_we_o         ( biu_we_o         ),
        .biu_lock_o       ( biu_lock_o       ),
        .biu_prot_o       ( biu_prot_o       ),
        .biu_d_o          ( biu_d_o          ),
        .biu_q_i          ( biu_q_i          ),
        .biu_ack_i        ( biu_ack_i        ),
        .biu_err_i        ( biu_err_i        ) );

      assign stall             = 1'b0;
      assign cache_flush_rdy_o = 1'b1; //no data cache to flush. Always ready
      assign mem_pagefault_o   = 1'b0;
  end
endgenerate

endmodule



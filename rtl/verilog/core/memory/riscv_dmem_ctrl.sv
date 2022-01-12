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
  parameter TECHNOLOGY       = "GENERIC"
)
(
  input  logic                      rst_ni,
  input  logic                      clk_i,
 
  //Configuration
  input  pmacfg_t                   pma_cfg_i [PMA_CNT],
  input                 [XLEN -1:0] pma_adr_i [PMA_CNT],

  input  pmpcfg_t [15:0]            st_pmpcfg_i,
  input  logic    [15:0][XLEN -1:0] st_pmpaddr_i,
  input  logic          [      1:0] st_prv_i,

  //CPU side
  input  logic                      mem_req_i,
  input  biu_size_t                 mem_size_i,
  input  logic                      mem_lock_i, 
  input  logic          [XLEN -1:0] mem_adr_i,
  input  logic                      mem_we_i,
  input  logic          [XLEN -1:0] mem_d_i,
  output logic          [XLEN -1:0] mem_q_o,
  output logic                      mem_ack_o,
  output logic                      mem_err_o,
                                    mem_misaligned_o,
                                    mem_page_fault_o,
  input  logic                      cache_flush_i,
  output logic                      cache_flush_rdy_o,

  //BIU ports
  output logic                      biu_stb_o,
  input  logic                      biu_stb_ack_i,
  input  logic                      biu_d_ack_i,
  output logic          [PLEN -1:0] biu_adri_o,
  input  logic          [PLEN -1:0] biu_adro_i,
  output biu_size_t                 biu_size_o,
  output biu_type_t                 biu_type_o,
  output logic                      biu_we_o,
  output logic                      biu_lock_o,
  output biu_prot_t                 biu_prot_o,
  output logic          [XLEN -1:0] biu_d_o,
  input  logic          [XLEN -1:0] biu_q_i,
  input  logic                      biu_ack_i,
                                    biu_err_i
);

  //////////////////////////////////////////////////////////////////
  //
  // Constants
  //


  //////////////////////////////////////////////////////////////////
  //
  // Variables
  //

  //Queue
  logic            queue_req;
  logic [XLEN-1:0] queue_adr;
  biu_size_t       queue_size;
  logic            queue_lock;
  biu_prot_t       queue_prot;
  logic            queue_we;
  logic [XLEN-1:0] queue_d;


  //Transfer parameters
  biu_prot_t       prot;


  //Misalignment check
  logic            misaligned;
  

  //from PMA check
  logic            pma_exception,
                   pma_misaligned;
  logic            is_cacheable;
  logic            pma_req;


  //from PMP check
  logic            pmp_exception;


  //From dcache-ctrl
  logic            stall;


  //////////////////////////////////////////////////////////////////
  //
  // Module Body
  //

  assign prot              = biu_prot_t'( PROT_DATA                                        |
	                                 (st_prv_i == PRV_U ? PROT_USER : PROT_PRIVILEGED) );
  assign lock              = 1'b0; //no locked instruction accesses
  assign mem_page_fault_o = 1'b0; //no MMU


  /* Hookup buffer
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

  
 
  /* Hookup misalignment check
   */
  riscv_memmisaligned #(
    .XLEN    ( XLEN    ),
    .HAS_RVC ( HAS_RVC ) )
  misaligned_inst (
//    .clk_i         ( clk_i      ),
    .instruction_i ( 1'b0              ), //data access
    .req_i         ( queue_req         ),
    .adr_i         ( queue_adr         ),
    .size_i        ( queue_size        ),
    .misaligned_o  ( misaligned        ) );

 
  /* Hookup Physical Memory Attributes Unit
   */
  riscv_pmachk #(
    .XLEN           ( XLEN            ),
    .PLEN           ( PLEN            ),
    .HAS_RVC        ( HAS_RVC         ),
    .PMA_CNT        ( PMA_CNT         ) )
  pmachk_inst (
    //Configuration
    .pma_cfg_i      ( pma_cfg_i       ),
    .pma_adr_i      ( pma_adr_i       ),

    //misaligned
    .misaligned_i   ( misaligned      ),

    //Memory Access
    .instruction_i  ( 1'b0            ), //data access
    .req_i          ( queue_req       ),
    .adr_i          ( queue_adr       ),
    .size_i         ( queue_size      ),
    .lock_i         ( queue_lock      ),
    .we_i           ( queue_we        ), //Instruction bus doesn't write

    //Output
    .pma_o          (                 ),
    .exception_o    ( pma_exception   ),
    .misaligned_o   ( pma_misaligned  ),
    .is_cacheable_o ( is_cacheable    ),
    .req_o          ( pma_req         ) );


  /* Hookup Physical Memory Protection Unit
   */
  riscv_pmpchk #(
    .XLEN          ( XLEN          ),
    .PLEN          ( PLEN          ),
    .PMP_CNT       ( PMP_CNT       ) )
  pmpchk_inst (
    .st_pmpcfg_i   ( st_pmpcfg_i   ),
    .st_pmpaddr_i  ( st_pmpaddr_i  ),
    .st_prv_i      ( st_prv_i      ),

    .instruction_i ( 1'b0          ),  //Data access
    .req_i         ( queue_req     ),  //Memory access request
    .adr_i         ( queue_adr     ),  //Physical Memory address (i.e. after translation)
    .size_i        ( queue_size    ),  //Transfer size
    .we_i          ( queue_we      ),  //Read/Write enable

    .exception_o   ( pmp_exception ) );



  /* Hookup Cache
   */
generate
  if (CACHE_SIZE > 0)
  begin
      /* Instantiate Instruction Cache Core
       */
      riscv_dcache_core #(
        .XLEN              ( XLEN              ),
        .PLEN              ( PLEN              ),
	.HAS_RVC           ( HAS_RVC           ),
        .SIZE              ( CACHE_SIZE        ),
        .BLOCK_SIZE        ( CACHE_BLOCK_SIZE  ),
        .WAYS              ( CACHE_WAYS        ),
        .TECHNOLOGY        ( TECHNOLOGY        ) )
      dcache_inst (
        //common signals
        .rst_ni            ( rst_ni            ),
        .clk_i             ( clk_i             ),

	.stall_o           ( stall             ),

        //from PMA
        .is_cacheable_i    ( is_cacheable      ),
        .misaligned_i      ( pma_misaligned    ),
        .mem_req_i         ( pma_req           ),
        .mem_ack_o         ( mem_ack_o         ),
        .mem_err_o         ( mem_err_o         ),
        .mem_adr_i         ( queue_adr         ),
        .mem_flush_i       ( 1'b0              ),
        .mem_size_i        ( queue_size        ),
        .mem_lock_i        ( queue_lock        ),
        .mem_prot_i        ( queue_prot        ),
        .mem_we_i          ( queue_we          ),
        .mem_d_i           ( queue_d           ),
        .mem_q_o           ( mem_q_o           ),
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
        .biu_err_i         ( biu_err_i         ) );
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
        .mem_misaligned_i ( misaligned       ),
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

      assign cache_flush_rdy_o = 1'b1; //no data cache to flush. Always ready
  end
endgenerate

endmodule



/////////////////////////////////////////////////////////////////////
//   ,------.                    ,--.                ,--.          //
//   |  .--. ' ,---.  ,--,--.    |  |    ,---. ,---. `--' ,---.    //
//   |  '--'.'| .-. |' ,-.  |    |  |   | .-. | .-. |,--.| .--'    //
//   |  |\  \ ' '-' '\ '-'  |    |  '--.' '-' ' '-' ||  |\ `--.    //
//   `--' '--' `---'  `--`--'    `-----' `---' `-   /`--' `---'    //
//                                             `---'               //
//    RISC-V                                                       //
//    Instruction Memory Access Block                              //
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

module riscv_imem_ctrl #(
  parameter XLEN             = 32,
  parameter PLEN             = XLEN, // XLEN==32 ? 34 : 56
  parameter PARCEL_SIZE      = 32,

  parameter HAS_RVC          = 0,

  parameter PMA_CNT          = 3,
  parameter PMP_CNT          = 16,

  parameter CACHE_SIZE       = 64, //KBYTES
  parameter CACHE_BLOCK_SIZE = 32, //BYTES
  parameter CACHE_WAYS       =  2, // 1           : Direct Mapped
                                   //<n>          : n-way set associative
                                   //<n>==<blocks>: fully associative

/*
  parameter REPLACE_ALG     = 1,  //0: Random
                                  //1: FIFO
                                  //2: LRU
*/
  parameter TECHNOLOGY      = "GENERIC",

  parameter BIUTAG_SIZE     = $clog2(XLEN/PARCEL_SIZE)
)
(
  input  logic                                 rst_ni,
  input  logic                                 clk_i,
 
  //Configuration
  input  pmacfg_t                              pma_cfg_i [PMA_CNT],
  input                 [XLEN            -1:0] pma_adr_i [PMA_CNT],

  input  pmpcfg_t [15:0]                       st_pmpcfg_i,
  input  logic    [15:0][XLEN            -1:0] st_pmpaddr_i,
  input  logic          [                 1:0] st_prv_i,

  //CPU side
  input  logic                                 mem_req_i,
  output logic                                 mem_ack_o,
  input  logic                                 mem_flush_i,
  input  logic          [XLEN            -1:0] mem_adr_i,
  output logic          [XLEN            -1:0] parcel_o,
  output logic          [XLEN/PARCEL_SIZE-1:0] parcel_valid_o,
  output logic                                 mem_error_o,
                                               mem_misaligned_o,
                                               mem_page_fault_o,
  input  logic                                 cache_flush_i,
  input  logic                                 dcflush_rdy_i,

  //BIU ports
  output logic                                 biu_stb_o,
  input  logic                                 biu_stb_ack_i,
  input  logic                                 biu_d_ack_i,
  output logic          [PLEN            -1:0] biu_adri_o,
  input  logic          [PLEN            -1:0] biu_adro_i,
  output biu_size_t                            biu_size_o,
  output biu_type_t                            biu_type_o,
  output logic                                 biu_we_o,
  output logic                                 biu_lock_o,
  output biu_prot_t                            biu_prot_o,
  output logic          [XLEN            -1:0] biu_d_o,
  input  logic          [XLEN            -1:0] biu_q_i,
  input  logic                                 biu_ack_i,
                                               biu_err_i,
  output logic          [BIUTAG_SIZE     -1:0] biu_tagi_o,
  input  logic          [BIUTAG_SIZE     -1:0] biu_tago_i
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
  biu_size_t       size;
  biu_prot_t       prot;
  logic            lock;

  //Misalignment check
  logic            misaligned;
  

  //from PMA check
  logic            pma_exception,
                   pma_misaligned;
  logic            is_cacheable;
  logic            pma_req;


  //from PMP check
  logic            pmp_exception;


  //////////////////////////////////////////////////////////////////
  //
  // Module Body
  //

  assign size             = XLEN == 64 ? DWORD : WORD;   //Transfer size
  assign prot             = biu_prot_t'( PROT_INSTRUCTION                                 |
	                                (st_prv_i == PRV_U ? PROT_USER : PROT_PRIVILEGED) );
  assign lock             = 1'b0; //no locked instruction accesses
  assign mem_page_fault_o = 1'b0; //no MMU

  
 
  /* Hookup misalignment check
   */
  riscv_memmisaligned #(
    .XLEN          ( XLEN            ),
    .HAS_RVC       ( HAS_RVC         ) )
  misaligned_inst (
//    .clk_i         ( clk_i      ),
    .instruction_i ( 1'b1            ), //instruction access
    .req_i         ( mem_req_i       ),
    .adr_i         ( mem_adr_i       ),
    .size_i        ( size            ),
    .misaligned_o  ( misaligned      ) );

 
  /* Hookup Physical Memory Attributes Unit
   */
  riscv_pmachk #(
    .XLEN           ( XLEN           ),
    .PLEN           ( PLEN           ),
    .HAS_RVC        ( HAS_RVC        ),
    .PMA_CNT        ( PMA_CNT        ) )
  pmachk_inst (
    //Configuration
    .pma_cfg_i      ( pma_cfg_i      ),
    .pma_adr_i      ( pma_adr_i      ),

    //misaligned
    .misaligned_i   ( misaligned     ),

    //Memory Access
    .instruction_i  ( 1'b1           ), //Instruction access
    .req_i          ( mem_req_i      ),
    .adr_i          ( mem_adr_i      ),
    .size_i         ( size           ),
    .lock_i         ( lock           ),
    .we_i           ( 1'b0           ), //Instruction bus doesn't write

    //Output
    .pma_o          (                ),
    .exception_o    ( pma_exception  ),
    .misaligned_o   ( pma_misaligned ),
    .is_cacheable_o ( is_cacheable   ),
    .req_o          ( pma_req        ) );


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

    .instruction_i ( 1'b1          ),  //Instruction access
    .req_i         ( mem_req_i     ),  //Memory access request
    .adr_i         ( mem_adr_i     ),  //Physical Memory address (i.e. after translation)
    .size_i        ( size          ),  //Transfer size
    .we_i          ( 1'b0          ),  //Read/Write enable

    .exception_o   ( pmp_exception ) );



  /* Hookup Cache
   */
generate
  if (CACHE_SIZE > 0)
  begin
      /* Instantiate Instruction Cache Core
       */
      riscv_icache_core #(
        .XLEN                ( XLEN              ),
        .PLEN                ( PLEN              ),
	.HAS_RVC             ( HAS_RVC           ),
        .PARCEL_SIZE         ( PARCEL_SIZE       ),
        .SIZE                ( CACHE_SIZE        ),
        .BLOCK_SIZE          ( CACHE_BLOCK_SIZE  ),
        .WAYS                ( CACHE_WAYS        ),
        .TECHNOLOGY          ( TECHNOLOGY        ),
        .BIUTAG_SIZE         ( BIUTAG_SIZE       ) )
      icache_inst (
        //common signals
        .rst_ni              ( rst_ni            ),
        .clk_i               ( clk_i             ),

        //from PMA
        .is_cacheable_i      ( is_cacheable      ),
        .misaligned_i        ( pma_misaligned    ),
        .mem_req_i           ( pma_req           ),
	.mem_ack_o           ( mem_ack_o         ),
        .mem_adr_i           ( mem_adr_i         ),
        .mem_flush_i         ( mem_flush_i       ),
        .mem_size_i          ( size              ),
        .mem_lock_i          ( lock              ),
        .mem_prot_i          ( prot              ),
	.parcel_pc_o         (                   ),
        .parcel_o            ( parcel_o          ),
        .parcel_valid_o      ( parcel_valid_o    ),
	.parcel_misaligned_o ( mem_misaligned_o  ),
        .parcel_error_o      ( mem_error_o       ),
        .cache_flush_i       ( cache_flush_i     ),
        .dcflush_rdy_i       ( dcflush_rdy_i     ),

        //To BIU
        .biu_stb_o           ( biu_stb_o         ),
        .biu_stb_ack_i       ( biu_stb_ack_i     ),
        .biu_d_ack_i         ( biu_d_ack_i       ),
        .biu_adri_o          ( biu_adri_o        ),
        .biu_adro_i          ( biu_adro_i        ),
        .biu_size_o          ( biu_size_o        ),
        .biu_type_o          ( biu_type_o        ),
	.biu_we_o            ( biu_we_o          ),
        .biu_lock_o          ( biu_lock_o        ),
        .biu_prot_o          ( biu_prot_o        ),
        .biu_d_o             ( biu_d_o           ),
        .biu_q_i             ( biu_q_i           ),
        .biu_ack_i           ( biu_ack_i         ),
        .biu_err_i           ( biu_err_i         ),
        .biu_tagi_o          ( biu_tagi_o        ),
        .biu_tago_i          ( biu_tago_i        ) );
  end
  else  //No cache
  begin
   /*
    * No Instruction Cache Core
    * Control and glue logic only
    */
   riscv_noicache_core #(
     .XLEN                   ( XLEN              ),
     .ALEN                   ( PLEN              ),
     .HAS_RVC                ( HAS_RVC           ),
     .PARCEL_SIZE            ( PARCEL_SIZE       ),
     .BIUTAG_SIZE            ( BIUTAG_SIZE       ) )
   noicache_core_inst (
     //common signals
     .rst_ni                 ( rst_ni            ),
     .clk_i                  ( clk_i             ),

     //CPU
     .if_req_i               ( mem_req_i         ),
     .if_ack_o               ( mem_ack_o         ),
     .if_prot_i              ( prot              ),
     .if_flush_i             ( mem_flush_i       ),
     .if_nxt_pc_i            ( mem_adr_i         ),
     .if_parcel_pc_o         (                   ),
     .if_parcel_o            ( parcel_o          ),
     .if_parcel_valid_o      ( parcel_valid_o    ),
     .if_parcel_misaligned_o ( mem_misaligned_o  ),
     .if_parcel_error_o      ( mem_error_o       ),
     .dcflush_rdy_i          ( dcflush_rdy_i     ),
     .st_prv_i               ( st_prv_i          ),

     //BIU
     .biu_stb_o              ( biu_stb_o         ),
     .biu_stb_ack_i          ( biu_stb_ack_i     ),
     .biu_d_ack_i            ( biu_d_ack_i       ),
     .biu_adri_o             ( biu_adri_o        ),
     .biu_adro_i             ( biu_adro_i        ),
     .biu_size_o             ( biu_size_o        ),
     .biu_type_o             ( biu_type_o        ),
     .biu_we_o               ( biu_we_o          ),
     .biu_lock_o             ( biu_lock_o        ),
     .biu_prot_o             ( biu_prot_o        ),
     .biu_d_o                ( biu_d_o           ),
     .biu_q_i                ( biu_q_i           ),
     .biu_ack_i              ( biu_ack_i         ),
     .biu_err_i              ( biu_err_i         ),
     .biu_tagi_o             ( biu_tagi_o        ),
     .biu_tago_i             ( biu_tago_i        ) );
  end
endgenerate

endmodule



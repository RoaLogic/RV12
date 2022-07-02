/////////////////////////////////////////////////////////////////////
//   ,------.                    ,--.                ,--.          //
//   |  .--. ' ,---.  ,--,--.    |  |    ,---. ,---. `--' ,---.    //
//   |  '--'.'| .-. |' ,-.  |    |  |   | .-. | .-. |,--.| .--'    //
//   |  |\  \ ' '-' '\ '-'  |    |  '--.' '-' ' '-' ||  |\ `--.    //
//   `--' '--' `---'  `--`--'    `-----' `---' `-   /`--' `---'    //
//                                             `---'               //
//    RISC-V                                                       //
//    Top Level - AMBA3 AHB-Lite Bus Interface                     //
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


import riscv_state_pkg::*;
import riscv_pma_pkg::*;
import riscv_du_pkg::*;
import biu_constants_pkg::*;
import ahb3lite_pkg::*;

module riscv_top_ahb3lite #(
  parameter int        XLEN               = 32,     //CPU data size
  parameter int        ALEN               = XLEN,   //CPU Address Space size
  parameter [XLEN-1:0] PC_INIT            = 'h200,
  parameter int        HAS_USER           = 0,
  parameter int        HAS_SUPER          = 0,
  parameter int        HAS_HYPER          = 0,
  parameter int        HAS_BPU            = 1,
  parameter int        HAS_FPU            = 0,
  parameter int        HAS_MMU            = 0,
  parameter int        HAS_RVM            = 1,
  parameter int        HAS_RVA            = 0,
  parameter int        HAS_RVC            = 0,
  parameter int        IS_RV32E           = 0,

  parameter int        MULT_LATENCY       = 0,

  parameter int        BREAKPOINTS        = 3,  //Number of hardware breakpoints

  parameter int        PMA_CNT            = 1, //16,
  parameter int        PMP_CNT            = 0, //16, //Number of Physical Memory Protection entries

  parameter int        BP_GLOBAL_BITS     = 2,
  parameter int        BP_LOCAL_BITS      = 10,

  parameter int        ICACHE_SIZE        = 0,  //in KBytes
  parameter int        ICACHE_BLOCK_SIZE  = 32, //in Bytes
  parameter int        ICACHE_WAYS        = 2,  //'n'-way set associative
  parameter int        ICACHE_REPLACE_ALG = 0,

  parameter int        DCACHE_SIZE        = 0,  //in KBytes
  parameter int        DCACHE_BLOCK_SIZE  = 32, //in Bytes
  parameter int        DCACHE_WAYS        = 2,  //'n'-way set associative
  parameter int        DCACHE_REPLACE_ALG = 0,
  parameter int        WRITEBUFFER_SIZE   = 8,

  parameter string     TECHNOLOGY         = "GENERIC",

  parameter [XLEN-1:0] MNMIVEC_DEFAULT    = PC_INIT -'h004,
  parameter [XLEN-1:0] MTVEC_DEFAULT      = PC_INIT -'h040,
  parameter [XLEN-1:0] HTVEC_DEFAULT      = PC_INIT -'h080,
  parameter [XLEN-1:0] STVEC_DEFAULT      = PC_INIT -'h0C0,
  parameter [XLEN-1:0] UTVEC_DEFAULT      = PC_INIT -'h100,

  parameter int        JEDEC_BANK            = 10,
  parameter int        JEDEC_MANUFACTURER_ID = 'h6e,

  parameter int        HARTID             = 0,

  parameter int        STRICT_AHB         = 1,

  localparam int       PARCEL_SIZE        = 16, //16bits per parcel
  localparam int       BIUTAG_SIZE        = $clog2(XLEN/PARCEL_SIZE)
)
(
  //AHB interfaces
  input                               HRESETn,
                                      HCLK,
				
  input  pmacfg_t                     pma_cfg_i [PMA_CNT],
  input  logic    [XLEN         -1:0] pma_adr_i [PMA_CNT],
 
  output                              ins_HSEL,
  output          [ALEN         -1:0] ins_HADDR,
  output          [XLEN         -1:0] ins_HWDATA,
  input           [XLEN         -1:0] ins_HRDATA,
  output                              ins_HWRITE,
  output          [HSIZE_SIZE   -1:0] ins_HSIZE,
  output          [HBURST_SIZE  -1:0] ins_HBURST,
  output          [HPROT_SIZE   -1:0] ins_HPROT,
  output          [HTRANS_SIZE  -1:0] ins_HTRANS,
  output                              ins_HMASTLOCK,
  input                               ins_HREADY,
  input                               ins_HRESP,
  
  output                              dat_HSEL,
  output          [ALEN         -1:0] dat_HADDR,
  output          [XLEN         -1:0] dat_HWDATA,
  input           [XLEN         -1:0] dat_HRDATA,
  output                              dat_HWRITE,
  output          [HSIZE_SIZE   -1:0] dat_HSIZE,
  output          [HBURST_SIZE  -1:0] dat_HBURST,
  output          [HPROT_SIZE   -1:0] dat_HPROT,
  output          [HTRANS_SIZE  -1:0] dat_HTRANS,
  output                              dat_HMASTLOCK,
  input                               dat_HREADY,
  input                               dat_HRESP,

  //Interrupts
  input                               ext_nmi,
                                      ext_tint,
                                      ext_sint,
  input           [              3:0] ext_int,

  //Debug Interface
  input                               dbg_stall,
  input                               dbg_strb,
  input                               dbg_we,
  input           [DBG_ADDR_SIZE-1:0] dbg_addr,
  input           [XLEN         -1:0] dbg_dati,
  output          [XLEN         -1:0] dbg_dato,
  output                              dbg_ack,
  output                              dbg_bp
);
  ////////////////////////////////////////////////////////////////
  //
  // Constants
  //
  localparam PLEN = XLEN == 32 ? 34 : 56;


  ////////////////////////////////////////////////////////////////
  //
  // Variables
  //
  logic          [XLEN            -1:0] imem_adr;
  logic                                 imem_req;
  logic                                 imem_ack;
  logic                                 imem_flush;
  logic          [XLEN            -1:0] imem_parcel;
  logic          [XLEN/PARCEL_SIZE-1:0] imem_parcel_valid;
  logic                                 imem_misaligned;
  logic                                 imem_pagefault;
  logic                                 imem_error;

  logic                                 dmem_req;
  logic          [XLEN            -1:0] dmem_adr;
  biu_size_t                            dmem_size;
  logic                                 dmem_we;
  logic          [XLEN            -1:0] dmem_d,
                                        dmem_q;
  logic                                 dmem_ack,
                                        dmem_err;
  logic                                 dmem_misaligned;
  logic                                 dmem_pagefault;

  pmpcfg_t [15:0]                       st_pmpcfg;
  logic    [15:0][XLEN            -1:0] st_pmpaddr;
  logic          [                 1:0] st_prv;

  logic                                 cm_ic_invalidate,
                                        cm_dc_invalidate,
                                        cm_dc_clean,
                                        cm_dc_clean_rdy;

  /* Instruction Memory BIU connections
   */
  logic                                 ibiu_stb;
  logic                                 ibiu_stb_ack;
  logic                                 ibiu_d_ack;
  logic          [PLEN            -1:0] ibiu_adri;
  logic          [ALEN            -1:0] ibiu_adri_tmp;
  logic          [ALEN            -1:0] ibiu_adro;
  logic          [PLEN            -1:0] ibiu_adro_tmp;
  biu_size_t                            ibiu_size;
  biu_type_t                            ibiu_type;
  logic                                 ibiu_we;
  logic                                 ibiu_lock;
  biu_prot_t                            ibiu_prot;
  logic          [XLEN            -1:0] ibiu_d;
  logic          [XLEN            -1:0] ibiu_q;
  logic                                 ibiu_ack,
                                        ibiu_err;
  logic          [BIUTAG_SIZE     -1:0] ibiu_tago,
                                        ibiu_tagi;

  /* Data Memory BIU connections
   */
  logic                                 dbiu_stb;
  logic                                 dbiu_stb_ack;
  logic                                 dbiu_d_ack;
  logic          [PLEN            -1:0] dbiu_adri;
  logic          [ALEN            -1:0] dbiu_adri_tmp;
  logic          [ALEN            -1:0] dbiu_adro;
  logic          [PLEN            -1:0] dbiu_adro_tmp;
  biu_size_t                            dbiu_size;
  biu_type_t                            dbiu_type;
  logic                                 dbiu_we;
  logic                                 dbiu_lock;
  biu_prot_t                            dbiu_prot;
  logic          [XLEN            -1:0] dbiu_d;
  logic          [XLEN            -1:0] dbiu_q;
  logic                                 dbiu_ack,
                                        dbiu_err;
  logic          [BIUTAG_SIZE     -1:0] dbiu_tago,
                                        dbiu_tagi;


  ////////////////////////////////////////////////////////////////
  //
  // Module Body
  //

  /*
   * Instantiate RISC-V core
   */
  riscv_core #(
    .XLEN                     ( XLEN                   ),
    .HAS_USER                 ( HAS_USER               ),
    .HAS_SUPER                ( HAS_SUPER              ),
    .HAS_HYPER                ( HAS_HYPER              ),
    .HAS_BPU                  ( HAS_BPU                ),
    .HAS_FPU                  ( HAS_FPU                ),
    .HAS_MMU                  ( HAS_MMU                ),
    .HAS_RVM                  ( HAS_RVM                ),
    .HAS_RVA                  ( HAS_RVA                ),
    .HAS_RVC                  ( HAS_RVC                ),
    .IS_RV32E                 ( IS_RV32E               ),
	 
    .MULT_LATENCY             ( MULT_LATENCY           ),

    .BREAKPOINTS              ( BREAKPOINTS            ),
    .PMP_CNT                  ( 0                      ),

    .BP_GLOBAL_BITS           ( BP_GLOBAL_BITS         ),
    .BP_LOCAL_BITS            ( BP_LOCAL_BITS          ),

    .TECHNOLOGY               ( TECHNOLOGY             ),

    .MNMIVEC_DEFAULT          ( MNMIVEC_DEFAULT        ),
    .MTVEC_DEFAULT            ( MTVEC_DEFAULT          ),
    .HTVEC_DEFAULT            ( HTVEC_DEFAULT          ),
    .STVEC_DEFAULT            ( STVEC_DEFAULT          ),
    .UTVEC_DEFAULT            ( UTVEC_DEFAULT          ),

    .JEDEC_BANK               ( JEDEC_BANK             ),
    .JEDEC_MANUFACTURER_ID    ( JEDEC_MANUFACTURER_ID  ),

    .HARTID                   ( HARTID                 ), 

    .PC_INIT                  ( PC_INIT                ) )
  core (
    .rst_ni                   ( HRESETn                ),
    .clk_i                    ( HCLK                   ),

    //Instruction Memory Access bus
    .imem_adr_o               ( imem_adr               ),
    .imem_req_o               ( imem_req               ),
    .imem_ack_i               ( imem_ack               ),
    .imem_flush_o             ( imem_flush             ),
    .imem_parcel_i            ( imem_parcel            ),
    .imem_parcel_valid_i      ( imem_parcel_valid      ),
    .imem_parcel_misaligned_i ( imem_misaligned        ),
    .imem_parcel_page_fault_i ( imem_pagefault         ),
    .imem_parcel_error_i      ( imem_error             ),

    //Data Memory Access bus
    .dmem_adr_o               ( dmem_adr               ),
    .dmem_d_o                 ( dmem_d                 ),
    .dmem_q_i                 ( dmem_q                 ),
    .dmem_we_o                ( dmem_we                ),
    .dmem_size_o              ( dmem_size              ),
    .dmem_lock_o              ( dmem_lock              ),
    .dmem_req_o               ( dmem_req               ),
    .dmem_ack_i               ( dmem_ack               ),
    .dmem_err_i               ( dmem_err               ),
    .dmem_misaligned_i        ( dmem_misaligned        ),
    .dmem_page_fault_i        ( dmem_pagefault         ),

    //cpu state
    .st_prv_o                 ( st_prv                 ),
    .st_pmpcfg_o              ( st_pmpcfg              ),
    .st_pmpaddr_o             ( st_pmpaddr             ),
    .cm_ic_invalidate_o       ( cm_ic_invalidate       ),
    .cm_dc_invalidate_o       ( cm_dc_invalidate       ),
    .cm_dc_clean_o            ( cm_dc_clean            ),


    //Interrupts
    .int_nmi_i                ( ext_nmi                ),
    .int_timer_i              ( ext_tint               ),
    .int_software_i           ( ext_sint               ),
    .int_external_i           ( ext_int                ),

    //Debug Interface
    .dbg_stall_i              ( dbg_stall              ),
    .dbg_strb_i               ( dbg_strb               ),
    .dbg_we_i                 ( dbg_we                 ),
    .dbg_addr_i               ( dbg_addr               ),
    .dbg_dati_i               ( dbg_dati               ),
    .dbg_dato_o               ( dbg_dato               ),
    .dbg_ack_o                ( dbg_ack                ),
    .dbg_bp_o                 ( dbg_bp                 ) );


  /*
   * Instantiate bus interfaces and optional caches
   */
  riscv_imem_ctrl #(
    .XLEN              ( XLEN              ),
    .PLEN              ( PLEN              ),
    .PARCEL_SIZE       ( PARCEL_SIZE       ),
    .HAS_RVC           ( HAS_RVC           ),
    .PMA_CNT           ( PMA_CNT           ),
    .PMP_CNT           ( PMP_CNT           ),
    .CACHE_SIZE        ( ICACHE_SIZE       ),
    .CACHE_BLOCK_SIZE  ( ICACHE_BLOCK_SIZE ),
    .CACHE_WAYS        ( ICACHE_WAYS       ),
    .TECHNOLOGY        ( TECHNOLOGY        ) )
  imem_ctrl_inst (
    .rst_ni            ( HRESETn           ),
    .clk_i             ( HCLK              ),
 
    //Configuration
    .pma_cfg_i         ( pma_cfg_i         ),
    .pma_adr_i         ( pma_adr_i         ),
    .st_pmpcfg_i       ( st_pmpcfg         ),
    .st_pmpaddr_i      ( st_pmpaddr        ),
    .st_prv_i          ( st_prv            ),

    //CPU side
    .mem_req_i         ( imem_req          ),
    .mem_ack_o         ( imem_ack          ),
    .mem_flush_i       ( imem_flush        ),
    .mem_adr_i         ( imem_adr          ),
    .mem_misaligned_o  ( imem_misaligned   ),
    .mem_pagefault_o   ( imem_pagefault    ),
    .mem_error_o       ( imem_error        ),
    .parcel_o          ( imem_parcel       ),
    .parcel_valid_o    ( imem_parcel_valid ),

    //Cache management
    .cm_invalidate_i   ( cm_ic_invalidate  ),
    .cm_dc_clean_rdy_i ( cm_dc_clean_rdy   ),

     //BIU ports
    .biu_stb_o         ( ibiu_stb          ),
    .biu_stb_ack_i     ( ibiu_stb_ack      ),
    .biu_d_ack_i       ( ibiu_d_ack        ),
    .biu_adri_o        ( ibiu_adri         ),
    .biu_adro_i        ( ibiu_adro_tmp     ),
    .biu_size_o        ( ibiu_size         ),
    .biu_type_o        ( ibiu_type         ),
    .biu_we_o          ( ibiu_we           ),
    .biu_lock_o        ( ibiu_lock         ),
    .biu_prot_o        ( ibiu_prot         ),
    .biu_d_o           ( ibiu_d            ),
    .biu_q_i           ( ibiu_q            ),
    .biu_ack_i         ( ibiu_ack          ),
    .biu_err_i         ( ibiu_err          ),
    .biu_tagi_o        ( ibiu_tagi         ),
    .biu_tago_i        ( ibiu_tago         ) );

generate
  if (ALEN >= PLEN) assign ibiu_adro_tmp = ibiu_adro[PLEN-1:0];
  else              assign ibiu_adro_tmp = { {PLEN-ALEN{1'b0}}, ibiu_adro};
endgenerate


  riscv_dmem_ctrl #(
    .XLEN              ( XLEN              ),
    .PLEN              ( PLEN              ),
    .HAS_RVC           ( HAS_RVC           ),
    .PMA_CNT           ( PMA_CNT           ),
    .PMP_CNT           ( PMP_CNT           ),
    .CACHE_SIZE        ( DCACHE_SIZE       ),
    .CACHE_BLOCK_SIZE  ( DCACHE_BLOCK_SIZE ),
    .CACHE_WAYS        ( DCACHE_WAYS       ),
    .TECHNOLOGY        ( TECHNOLOGY        ),
    .BIUTAG_SIZE       ( BIUTAG_SIZE       ) )
  dmem_ctrl_inst (
    .rst_ni            ( HRESETn           ),
    .clk_i             ( HCLK              ),
 
    //Configuration
    .pma_cfg_i         ( pma_cfg_i         ),
    .pma_adr_i         ( pma_adr_i         ),
    .st_pmpcfg_i       ( st_pmpcfg         ),
    .st_pmpaddr_i      ( st_pmpaddr        ),
    .st_prv_i          ( st_prv            ),

    //CPU side
    .mem_req_i         ( dmem_req          ),
    .mem_size_i        ( dmem_size         ),
    .mem_lock_i        ( dmem_lock         ),
    .mem_adr_i         ( dmem_adr          ),
    .mem_we_i          ( dmem_we           ),
    .mem_d_i           ( dmem_d            ),
    .mem_q_o           ( dmem_q            ),
    .mem_ack_o         ( dmem_ack          ),
    .mem_err_o         ( dmem_err          ),
    .mem_misaligned_o  ( dmem_misaligned   ),
    .mem_pagefault_o   ( dmem_pagefault    ),

    //Cache management
    .cm_invalidate_i   ( cm_dc_invalidate  ),
    .cm_clean_i        ( cm_dc_clean       ),
    .cm_clean_rdy_o    ( cm_dc_clean_rdy   ),

     //BIU ports
    .biu_stb_o         ( dbiu_stb          ),
    .biu_stb_ack_i     ( dbiu_stb_ack      ),
    .biu_d_ack_i       ( dbiu_d_ack        ),
    .biu_adri_o        ( dbiu_adri         ),
    .biu_adro_i        ( dbiu_adro_tmp     ),
    .biu_size_o        ( dbiu_size         ),
    .biu_type_o        ( dbiu_type         ),
    .biu_we_o          ( dbiu_we           ),
    .biu_lock_o        ( dbiu_lock         ),
    .biu_prot_o        ( dbiu_prot         ),
    .biu_d_o           ( dbiu_d            ),
    .biu_q_i           ( dbiu_q            ),
    .biu_ack_i         ( dbiu_ack          ),
    .biu_err_i         ( dbiu_err          ),
    .biu_tagi_o        ( dbiu_tagi         ),
    .biu_tago_i        ( dbiu_tago         ) );

generate
  if (ALEN >= PLEN) assign dbiu_adro_tmp = dbiu_adro[PLEN-1:0];
  else              assign dbiu_adro_tmp = { {PLEN-ALEN{1'b0}}, dbiu_adro};
endgenerate


  /* Instantiate BIU
   */
  biu_ahb3lite #(
    .DATA_SIZE     ( XLEN          ),
    .ADDR_SIZE     ( ALEN          ),
    .TAG_SIZE      ( BIUTAG_SIZE   ),
    .STRICT_AHB    ( STRICT_AHB    ) )
  ibiu_inst (
    .HRESETn       ( HRESETn       ),
    .HCLK          ( HCLK          ),
    .HSEL          ( ins_HSEL      ),
    .HADDR         ( ins_HADDR     ),
    .HWDATA        ( ins_HWDATA    ),
    .HRDATA        ( ins_HRDATA    ),
    .HWRITE        ( ins_HWRITE    ),
    .HSIZE         ( ins_HSIZE     ),
    .HBURST        ( ins_HBURST    ),
    .HPROT         ( ins_HPROT     ),
    .HTRANS        ( ins_HTRANS    ),
    .HMASTLOCK     ( ins_HMASTLOCK ),
    .HREADY        ( ins_HREADY    ),
    .HRESP         ( ins_HRESP     ),

    .biu_stb_i     ( ibiu_stb      ),
    .biu_stb_ack_o ( ibiu_stb_ack  ),
    .biu_d_ack_o   ( ibiu_d_ack    ),
    .biu_adri_i    ( ibiu_adri_tmp ),
    .biu_adro_o    ( ibiu_adro     ),
    .biu_size_i    ( ibiu_size     ),
    .biu_type_i    ( ibiu_type     ),
    .biu_prot_i    ( ibiu_prot     ),
    .biu_lock_i    ( ibiu_lock     ),
    .biu_we_i      ( ibiu_we       ),
    .biu_d_i       ( ibiu_d        ),
    .biu_q_o       ( ibiu_q        ),
    .biu_ack_o     ( ibiu_ack      ),
    .biu_err_o     ( ibiu_err      ),
    .biu_tagi_i    ( ibiu_tagi     ),
    .biu_tago_o    ( ibiu_tago     ) );

generate
  if (ALEN <= PLEN) assign ibiu_adri_tmp = ibiu_adri[ALEN-1:0];
  else              assign ibiu_adri_tmp = { {ALEN-PLEN{1'b0}}, ibiu_adri};
endgenerate


  biu_ahb3lite #(
    .DATA_SIZE     ( XLEN          ),
    .ADDR_SIZE     ( ALEN          ),
    .TAG_SIZE      ( BIUTAG_SIZE   ),
    .STRICT_AHB    ( STRICT_AHB    ) )
  dbiu_inst (
    .HRESETn       ( HRESETn       ),
    .HCLK          ( HCLK          ),
    .HSEL          ( dat_HSEL      ),
    .HADDR         ( dat_HADDR     ),
    .HWDATA        ( dat_HWDATA    ),
    .HRDATA        ( dat_HRDATA    ),
    .HWRITE        ( dat_HWRITE    ),
    .HSIZE         ( dat_HSIZE     ),
    .HBURST        ( dat_HBURST    ),
    .HPROT         ( dat_HPROT     ),
    .HTRANS        ( dat_HTRANS    ),
    .HMASTLOCK     ( dat_HMASTLOCK ),
    .HREADY        ( dat_HREADY    ),
    .HRESP         ( dat_HRESP     ),

    .biu_stb_i     ( dbiu_stb      ),
    .biu_stb_ack_o ( dbiu_stb_ack  ),
    .biu_d_ack_o   ( dbiu_d_ack    ),
    .biu_adri_i    ( dbiu_adri_tmp ),
    .biu_adro_o    ( dbiu_adro     ),
    .biu_size_i    ( dbiu_size     ),
    .biu_type_i    ( dbiu_type     ),
    .biu_prot_i    ( dbiu_prot     ),
    .biu_lock_i    ( dbiu_lock     ),
    .biu_we_i      ( dbiu_we       ),
    .biu_d_i       ( dbiu_d        ),
    .biu_q_o       ( dbiu_q        ),
    .biu_ack_o     ( dbiu_ack      ),
    .biu_err_o     ( dbiu_err      ),
    .biu_tagi_i    ( dbiu_tagi     ),
    .biu_tago_o    ( dbiu_tago     ) );

generate
  if (ALEN <= PLEN) assign dbiu_adri_tmp = dbiu_adri[ALEN-1:0];
  else              assign dbiu_adri_tmp = { {ALEN-PLEN{1'b0}}, dbiu_adri};
endgenerate

endmodule

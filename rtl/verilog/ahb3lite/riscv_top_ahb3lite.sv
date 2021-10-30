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
  parameter            XLEN               = 32,     //CPU data size
  parameter            ALEN               = XLEN,   //CPU Address Space size
  parameter [XLEN-1:0] PC_INIT            = 'h200,
  parameter            HAS_USER           = 0,
  parameter            HAS_SUPER          = 0,
  parameter            HAS_HYPER          = 0,
  parameter            HAS_BPU            = 1,
  parameter            HAS_FPU            = 0,
  parameter            HAS_MMU            = 0,
  parameter            HAS_RVM            = 1,
  parameter            HAS_RVA            = 0,
  parameter            HAS_RVC            = 0,
  parameter            IS_RV32E           = 0,

  parameter            MULT_LATENCY       = 0,

  parameter            BREAKPOINTS        = 3,  //Number of hardware breakpoints

  parameter            PMA_CNT            = 1, //16,
  parameter            PMP_CNT            = 0, //16, //Number of Physical Memory Protection entries

  parameter            BP_GLOBAL_BITS     = 2,
  parameter            BP_LOCAL_BITS      = 10,

  parameter            ICACHE_SIZE        = 0,  //in KBytes
  parameter            ICACHE_BLOCK_SIZE  = 32, //in Bytes
  parameter            ICACHE_WAYS        = 2,  //'n'-way set associative
  parameter            ICACHE_REPLACE_ALG = 0,
  parameter            ITCM_SIZE          = 0,

  parameter            DCACHE_SIZE        = 0,  //in KBytes
  parameter            DCACHE_BLOCK_SIZE  = 32, //in Bytes
  parameter            DCACHE_WAYS        = 2,  //'n'-way set associative
  parameter            DCACHE_REPLACE_ALG = 0,
  parameter            DTCM_SIZE          = 0,
  parameter            WRITEBUFFER_SIZE   = 8,

  parameter            TECHNOLOGY         = "GENERIC",

  parameter            MNMIVEC_DEFAULT    = PC_INIT -'h004,
  parameter            MTVEC_DEFAULT      = PC_INIT -'h040,
  parameter            HTVEC_DEFAULT      = PC_INIT -'h080,
  parameter            STVEC_DEFAULT      = PC_INIT -'h0C0,
  parameter            UTVEC_DEFAULT      = PC_INIT -'h100,

  parameter            JEDEC_BANK            = 10,
  parameter            JEDEC_MANUFACTURER_ID = 'h6e,

  parameter            HARTID             = 0,

  parameter            PARCEL_SIZE        = 16
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
  // Variables
  //
  logic          [XLEN          -1:0] imem_adr;
  logic                               imem_req;
  logic                               imem_ack;
  logic                               imem_flush;
  logic          [XLEN          -1:0] imem_parcel;
  logic          [XLEN/PARCEL_SIZE-1:0] imem_parcel_valid;
  logic                               imem_parcel_misaligned;
  logic                               imem_parcel_page_fault;
  logic                               imem_parcel_error;

  logic                               dmem_req;
  logic          [XLEN          -1:0] dmem_adr;
  biu_size_t                          dmem_size;
  logic                               dmem_we;
  logic          [XLEN          -1:0] dmem_d,
                                      dmem_q;
  logic                               dmem_ack,
                                      dmem_err;
  logic                               dmem_is_misaligned,
                                      dmem_misaligned;
  logic                               dmem_page_fault;

  logic          [               1:0] st_prv;

  logic                               cacheflush,
                                      dcflush_rdy;

  /* Instruction Memory BIU connections
   */
  logic                               ibiu_stb;
  logic                               ibiu_stb_ack;
  logic                               ibiu_d_ack;
  logic          [ALEN          -1:0] ibiu_adri,
                                      ibiu_adro;
  biu_size_t                          ibiu_size;
  biu_type_t                          ibiu_type;
  logic                               ibiu_we;
  logic                               ibiu_lock;
  biu_prot_t                          ibiu_prot;
  logic          [XLEN          -1:0] ibiu_d;
  logic          [XLEN          -1:0] ibiu_q;
  logic                               ibiu_ack,
                                      ibiu_err;
  /* Data Memory BIU connections
   */
  logic                               dbiu_stb;
  logic                               dbiu_stb_ack;
  logic                               dbiu_d_ack;
  logic          [ALEN          -1:0] dbiu_adri,
                                      dbiu_adro;
  biu_size_t                          dbiu_size;
  biu_type_t                          dbiu_type;
  logic                               dbiu_we;
  logic                               dbiu_lock;
  biu_prot_t                          dbiu_prot;
  logic          [XLEN          -1:0] dbiu_d;
  logic          [XLEN          -1:0] dbiu_q;
  logic                               dbiu_ack,
                                      dbiu_err;


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
    .imem_parcel_misaligned_i ( imem_parcel_misaligned ),
    .imem_parcel_page_fault_i ( 1'b0                   ),
    .imem_parcel_error_i      ( imem_parcel_error      ),

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
    .dmem_page_fault_i        ( 1'b0                   ),

    //cpu state
    .st_prv_o                 ( st_prv                 ),
    .st_pmpcfg_o              (),
    .st_pmpaddr_o             (),
    .bu_cacheflush_o          ( cacheflush             ),


    //Interrupts
    .ext_nmi_i                ( ext_nmi                ),
    .ext_tint_i               ( ext_tint               ),
    .ext_sint_i               ( ext_sint               ),
    .ext_int_i                ( ext_int                ),

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
  assign imem_parcel_page_fault = 0; //No MMU

generate
if (ICACHE_SIZE > 0)
    /* Instruction Cache
     */
    /*
    riscv_icache_core #(
      .XLEN        ( XLEN              ),
      .ALEN        ( ALEN              ),
      .PARCEL_SIZE ( PARCEL_SIZE       ),

      .SIZE        ( ICACHE_SIZE       ),
      .BLOCK_SIZE  ( ICACHE_BLOCK_SIZE ),
      .WAYS        ( 2 )) //ICACHE_WAYS       ) )
    icache_inst (
      .rst_ni           ( HRESETn           ),
      .clk_i            ( HCLK              ),

      .nxt_pc_i         ( imem_adr            ),
      .stall_nxt_pc_o   ( if_stall_nxt_pc      ),
      .stall_i          ( if_stall             ),
      .flush_i          ( imem_flush             ),
      .parcel_pc_o      ( if_parcel_pc         ),
      .parcel_o         ( imem_parcel            ),
      .parcel_valid_o   ( imem_parcel_valid      ),
      .err_o            ( if_parcel_error      ),

      .cache_flush_i    ( cacheflush       ),
      .dcflush_rdy_i    ( dcflush_rdy      ),

      .st_prv_i         ( st_prv           ),

      .biu_stb_o        ( ibiu_stb         ),
      .biu_stb_ack_i    ( ibiu_stb_ack     ),
      .biu_d_ack_i      ( ibiu_d_ack       ),
      .biu_adri_o       ( ibiu_adri        ),
      .biu_adro_i       ( ibiu_adro        ),
      .biu_size_o       ( ibiu_size        ),
      .biu_type_o       ( ibiu_type        ),
      .biu_we_o         ( ibiu_we          ),
      .biu_lock_o       ( ibiu_lock        ),
      .biu_prot_o       ( ibiu_prot        ),
      .biu_d_o          ( ibiu_d           ),
      .biu_q_i          ( ibiu_q           ),
      .biu_ack_i        ( ibiu_ack         ),
      .biu_err_i        ( ibiu_err         )
    );
    */
   assign ibiu_stb = 1'b0;
else
   /*
    * No Instruction Cache Core
    * Control and glue logic only
    */
   riscv_noicache_core #(
     .XLEN                   ( XLEN                   ),
     .ALEN                   ( ALEN                   ),
     .HAS_RVC                ( HAS_RVC                ),
     .PARCEL_SIZE            ( PARCEL_SIZE            ) )
   noicache_core_inst (
     //common signals
     .rst_ni                 ( HRESETn                ),
     .clk_i                  ( HCLK                   ),

     //CPU
     .if_req_i               ( imem_req               ),
     .if_ack_o               ( imem_ack               ),
     .if_flush_i             ( imem_flush             ),
     .if_nxt_pc_i            ( imem_adr               ),
     .if_parcel_pc_o         (   ),
     .if_parcel_o            ( imem_parcel            ),
     .if_parcel_valid_o      ( imem_parcel_valid      ),
     .if_parcel_misaligned_o ( imem_parcel_misaligned ),
     .if_parcel_error_o      ( imem_parcel_error      ),
     .dcflush_rdy_i          ( dcflush_rdy            ),
     .st_prv_i               ( st_prv                 ),

     //BIU
     .biu_stb_o              ( ibiu_stb               ),
     .biu_stb_ack_i          ( ibiu_stb_ack           ),
     .biu_d_ack_i            ( ibiu_d_ack             ),
     .biu_adri_o             ( ibiu_adri              ),
     .biu_adro_i             ( ibiu_adro              ),
     .biu_size_o             ( ibiu_size              ),
     .biu_type_o             ( ibiu_type              ),
     .biu_we_o               ( ibiu_we                ),
     .biu_lock_o             ( ibiu_lock              ),
     .biu_prot_o             ( ibiu_prot              ),
     .biu_d_o                ( ibiu_d                 ),
     .biu_q_i                ( ibiu_q                 ),
     .biu_ack_i              ( ibiu_ack               ),
     .biu_err_i              ( ibiu_err               ) );
endgenerate



  riscv_memmisaligned #(
    .XLEN    ( XLEN    ),
    .HAS_RVC ( HAS_RVC )
  )
  dmisaligned_inst (
    .instruction_i ( 1'b0               ),
    .req_i         ( dmem_req           ),
    .adr_i         ( dmem_adr           ),
    .size_i        ( dmem_size          ),
    .misaligned_o  ( dmem_is_misaligned )
  );

  assign dmem_page_fault = 1'b0; //No MMU
generate
if (DCACHE_SIZE > 0)
    /* Data Cache
     */
    /*
    riscv_icache_core #(
      .XLEN        ( XLEN              ),
      .ALEN        ( ALEN              ),
      .PARCEL_SIZE ( PARCEL_SIZE       ),

      .SIZE        ( ICACHE_SIZE       ),
      .BLOCK_SIZE  ( ICACHE_BLOCK_SIZE ),
      .WAYS        ( 2 )) //ICACHE_WAYS       ) )
    icache_inst (
      .rst_ni           ( HRESETn           ),
      .clk_i            ( HCLK              ),

      .nxt_pc_i         ( imem_adr            ),
      .stall_nxt_pc_o   ( if_stall_nxt_pc      ),
      .stall_i          ( if_stall             ),
      .flush_i          ( imem_flush             ),
      .parcel_pc_o      ( if_parcel_pc         ),
      .parcel_o         ( imem_parcel            ),
      .parcel_valid_o   ( imem_parcel_valid      ),
      .err_o            ( if_parcel_error      ),

      .cache_flush_i    ( cacheflush       ),
      .dcflush_rdy_i    ( dcflush_rdy      ),

      .st_prv_i         ( st_prv           ),

      .biu_stb_o        ( ibiu_stb         ),
      .biu_adri_o       ( ibiu_adri        ),
      .biu_adro_i       (                  ),
      .biu_size_o       ( ibiu_size        ),
      .biu_type_o       ( ibiu_type        ),
      .biu_we_o         ( ibiu_we          ),
      .biu_lock_o       ( ibiu_lock        ),
      .biu_prot_o       ( ibiu_prot        ),
      .biu_d_o          ( ibiu_d           ),
      .biu_q_i          ( ibiu_q           ),
      .biu_stb_ack_i    ( ibiu_stb_ack_i   ),
      .biu_d_ack_i      ( ibiu_d_ack_i     ),
      .biu_ack_i        ( ibiu_ack         ),
      .biu_err_i        ( ibiu_err         )
    );
    */
   assign dcflush_rdy = 1'b1;
else
begin
   /*
    * No Data Cache Core
    * Control and glue logic only
    */
   riscv_nodcache_core #(
     .XLEN        ( XLEN        ),
     .ALEN        ( ALEN        )//,
//     .DEPTH       ( 2           )
   )
   nodcache_core_inst (
     //common signals
     .rst_ni           ( HRESETn            ),
     .clk_i            ( HCLK               ),

     //CPU
     .mem_req_i        ( dmem_req           ),
     .mem_size_i       ( dmem_size          ),
     .mem_lock_i       ( dmem_lock          ),
     .mem_adr_i        ( dmem_adr           ),
     .mem_we_i         ( dmem_we            ),
     .mem_d_i          ( dmem_d             ),
     .mem_q_o          ( dmem_q             ),
     .mem_ack_o        ( dmem_ack           ),
     .mem_err_o        ( dmem_err           ),
     .mem_misaligned_i ( dmem_is_misaligned ),
     .mem_misaligned_o ( dmem_misaligned    ),
     .st_prv_i         ( st_prv             ),

     //BIU
     .biu_stb_o        ( dbiu_stb           ),
     .biu_stb_ack_i    ( dbiu_stb_ack       ),
     .biu_d_ack_i      ( dbiu_d_ack         ),
     .biu_adri_o       ( dbiu_adri          ),
     .biu_adro_i       ( dbiu_adro          ),
     .biu_size_o       ( dbiu_size          ),
     .biu_type_o       ( dbiu_type          ),
     .biu_we_o         ( dbiu_we            ),
     .biu_lock_o       ( dbiu_lock          ),
     .biu_prot_o       ( dbiu_prot          ),
     .biu_d_o          ( dbiu_d             ),
     .biu_q_i          ( dbiu_q             ),
     .biu_ack_i        ( dbiu_ack           ),
     .biu_err_i        ( dbiu_err           )
   );

   assign dcflush_rdy = 1'b1; //no data cache to flush. Always ready
end
endgenerate


  /* Instantiate BIU
   */
  biu_ahb3lite #(
    .DATA_SIZE ( XLEN ),
    .ADDR_SIZE ( ALEN )
  )
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
    .biu_adri_i    ( ibiu_adri     ),
    .biu_adro_o    ( ibiu_adro     ),
    .biu_size_i    ( ibiu_size     ),
    .biu_type_i    ( ibiu_type     ),
    .biu_prot_i    ( ibiu_prot     ),
    .biu_lock_i    ( ibiu_lock     ),
    .biu_we_i      ( ibiu_we       ),
    .biu_d_i       ( ibiu_d        ),
    .biu_q_o       ( ibiu_q        ),
    .biu_ack_o     ( ibiu_ack      ),
    .biu_err_o     ( ibiu_err      )
  );

  biu_ahb3lite #(
    .DATA_SIZE ( XLEN ),
    .ADDR_SIZE ( ALEN )
  )
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
    .biu_adri_i    ( dbiu_adri     ),
    .biu_adro_o    ( dbiu_adro     ),
    .biu_size_i    ( dbiu_size     ),
    .biu_type_i    ( dbiu_type     ),
    .biu_prot_i    ( dbiu_prot     ),
    .biu_lock_i    ( dbiu_lock     ),
    .biu_we_i      ( dbiu_we       ),
    .biu_d_i       ( dbiu_d        ),
    .biu_q_o       ( dbiu_q        ),
    .biu_ack_o     ( dbiu_ack      ),
    .biu_err_o     ( dbiu_err      )
  );

endmodule

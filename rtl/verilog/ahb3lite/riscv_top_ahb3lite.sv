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
import riscv_du_pkg::*;
import biu_constants_pkg::*;

module riscv_top_ahb3lite #(
  parameter            XLEN               = 32,
  parameter            PLEN               = XLEN,
  parameter [XLEN-1:0] PC_INIT            = 'h200,
  parameter            HAS_USER           = 0,
  parameter            HAS_SUPER          = 0,
  parameter            HAS_HYPER          = 0,
  parameter            HAS_BPU            = 1,
  parameter            HAS_FPU            = 0,
  parameter            HAS_MMU            = 0,
  parameter            HAS_RVM            = 0,
  parameter            HAS_RVA            = 0,
  parameter            HAS_RVC            = 0,
  parameter            IS_RV32E           = 0,

  parameter            MULT_LATENCY       = 0,

  parameter            BREAKPOINTS        = 3,  //Number of hardware breakpoints
  parameter            WRITEBUFFER_SIZE   = 8,  //Number of entries in the write buffer
  parameter            PMP_CNT            = 16, //Number of Physical Memory Protection entries

  parameter            BP_GLOBAL_BITS     = 2,
  parameter            BP_LOCAL_BITS      = 10,

  parameter            ICACHE_SIZE        = 0,  //in KBytes
  parameter            ICACHE_BLOCK_SIZE  = 32, //in Bytes
  parameter            ICACHE_WAYS        = 2,  //'n'-way set associative
  parameter            ICACHE_REPLACE_ALG = 0,

  parameter            DCACHE_SIZE        = 0,  //in KBytes
  parameter            DCACHE_BLOCK_SIZE  = 32, //in Bytes
  parameter            DCACHE_WAYS        = 2,  //'n'-way set associative
  parameter            DCACHE_REPLACE_ALG = 0,

  parameter            TECHNOLOGY         = "GENERIC",

  parameter            MNMIVEC_DEFAULT    = PC_INIT -'h004,
  parameter            MTVEC_DEFAULT      = PC_INIT -'h040,
  parameter            HTVEC_DEFAULT      = PC_INIT -'h080,
  parameter            STVEC_DEFAULT      = PC_INIT -'h0C0,
  parameter            UTVEC_DEFAULT      = PC_INIT -'h100,

  parameter            JEDEC_BANK            = 10,
  parameter            JEDEC_MANUFACTURER_ID = 'h6e,

  parameter            HARTID             = 0,

  parameter            PARCEL_SIZE        = 32
)
(
  //AHB interfaces
  input                        HRESETn,
                               HCLK,
										 
  output                     ins_HSEL,
  output [PLEN         -1:0] ins_HADDR,
  output [XLEN         -1:0] ins_HWDATA,
  input  [XLEN         -1:0] ins_HRDATA,
  output                     ins_HWRITE,
  output [              2:0] ins_HSIZE,
  output [              2:0] ins_HBURST,
  output [              3:0] ins_HPROT,
  output [              1:0] ins_HTRANS,
  output                     ins_HMASTLOCK,
  input                      ins_HREADY,
  input                      ins_HRESP,
  
  output                     dat_HSEL,
  output [PLEN         -1:0] dat_HADDR,
  output [XLEN         -1:0] dat_HWDATA,
  input  [XLEN         -1:0] dat_HRDATA,
  output                     dat_HWRITE,
  output [              2:0] dat_HSIZE,
  output [              2:0] dat_HBURST,
  output [              3:0] dat_HPROT,
  output [              1:0] dat_HTRANS,
  output                     dat_HMASTLOCK,
  input                      dat_HREADY,
  input                      dat_HRESP,

  //Interrupts
  input                      ext_nmi,
                             ext_tint,
                             ext_sint,
  input  [              3:0] ext_int,

  //Debug Interface
  input                      dbg_stall,
  input                      dbg_strb,
  input                      dbg_we,
  input  [DBG_ADDR_SIZE-1:0] dbg_addr,
  input  [XLEN         -1:0] dbg_dati,
  output [XLEN         -1:0] dbg_dato,
  output                     dbg_ack,
  output                     dbg_bp
);

  ////////////////////////////////////////////////////////////////
  //
  // Variables
  //
  logic                                 rstn;
  logic                                 clk; 

  logic                                 if_stall_nxt_pc;
  logic               [XLEN       -1:0] if_nxt_pc;
  logic                                 if_stall,
                                        if_flush;
  logic               [PARCEL_SIZE-1:0] if_parcel;
  logic               [XLEN       -1:0] if_parcel_pc;
  logic                                 if_parcel_valid;
  logic                                 if_parcel_misaligned;
  logic                                 if_parcel_page_fault;

  logic                                 dmem_req;
  logic                                 dmem_ack;
  logic               [XLEN       -1:0] dmem_adr;
  logic               [XLEN       -1:0] dmem_d,
                                        dmem_q;
  logic                                 dmem_we;
  biu_size_t                            dmem_size;
  logic                                 dmem_misaligned;
  logic                                 dmem_page_fault;

  logic               [            1:0] st_prv;
  pmpcfg_struct [15:0]                  st_pmpcfg;
  logic         [15:0][XLEN       -1:0] st_pmpaddr;

  logic                                 bu_cacheflush,
                                        dcflush_rdy;

  /* Data Memory BIU connections
   */
  logic                                 dmem_biu_stb;
  logic                                 dmem_biu_stb_ack;
  logic                                 dmem_biu_d_ack;
  logic               [PLEN       -1:0] dmem_biu_adri,
                                        dmem_biu_adro;
  biu_size_t                            dmem_biu_size;
  biu_type_t                            dmem_biu_type;
  logic                                 dmem_biu_we;
  logic                                 dmem_biu_lock;
  biu_prot_t                            dmem_biu_prot;
  logic               [XLEN       -1:0] dmem_biu_d;
  logic               [XLEN       -1:0] dmem_biu_q;
  logic                                 dmem_biu_ack,
                                        dmem_biu_err;


  ////////////////////////////////////////////////////////////////
  //
  // Module Body
  //

  assign rstn = HRESETn;
  assign clk  = HCLK;

  /*
   * Instantiate RISC-V core
   */
  riscv_core #(
    .XLEN                  ( XLEN                  ),
    .HAS_USER              ( HAS_USER              ),
    .HAS_SUPER             ( HAS_SUPER             ),
    .HAS_HYPER             ( HAS_HYPER             ),
    .HAS_BPU               ( HAS_BPU               ),
    .HAS_FPU               ( HAS_FPU               ),
    .HAS_MMU               ( HAS_MMU               ),
    .HAS_RVM               ( HAS_RVM               ),
    .HAS_RVA               ( HAS_RVA               ),
    .HAS_RVC               ( HAS_RVC               ),
    .IS_RV32E              ( IS_RV32E              ),
	 
    .MULT_LATENCY          ( MULT_LATENCY          ),

    .BREAKPOINTS           ( BREAKPOINTS           ),
    .PMP_CNT               ( PMP_CNT               ),

    .BP_GLOBAL_BITS        ( BP_GLOBAL_BITS        ),
    .BP_LOCAL_BITS         ( BP_LOCAL_BITS         ),

    .TECHNOLOGY            ( TECHNOLOGY            ),

    .MNMIVEC_DEFAULT       ( MNMIVEC_DEFAULT       ),
    .MTVEC_DEFAULT         ( MTVEC_DEFAULT         ),
    .HTVEC_DEFAULT         ( HTVEC_DEFAULT         ),
    .STVEC_DEFAULT         ( STVEC_DEFAULT         ),
    .UTVEC_DEFAULT         ( UTVEC_DEFAULT         ),

    .JEDEC_BANK            ( JEDEC_BANK            ),
    .JEDEC_MANUFACTURER_ID ( JEDEC_MANUFACTURER_ID ),

    .HARTID                ( HARTID                ), 

    .PC_INIT               ( PC_INIT               ),
    .PARCEL_SIZE           ( PARCEL_SIZE           )
  )
  core (
    .rstn ( HRESETn ),
    .clk  ( HCLK    ),

    .*
  ); 


  /*
   * Instantiate bus interfaces and optional caches
   */

  /*
   * L1 Instruction Cache
   */
  riscv_icache_ahb3lite #(
    .XLEN           ( XLEN               ),
    .PHYS_ADDR_SIZE ( PLEN               ),
    .PARCEL_SIZE    ( PARCEL_SIZE        ),

    .SIZE           ( ICACHE_SIZE        ),
    .BLOCK_SIZE     ( ICACHE_BLOCK_SIZE  ),
    .WAYS           ( ICACHE_WAYS        ),
    .REPLACE_ALG    ( ICACHE_REPLACE_ALG ) )
  icache (
    .HRESETn   ( HRESETn       ),
    .HCLK      ( HCLK          ),
    .HSEL      ( ins_HSEL      ),
    .HADDR     ( ins_HADDR     ),
    .HWDATA    ( ins_HWDATA    ),
    .HRDATA    ( ins_HRDATA    ),
    .HWRITE    ( ins_HWRITE    ),
    .HSIZE     ( ins_HSIZE     ),
    .HBURST    ( ins_HBURST    ),
    .HPROT     ( ins_HPROT     ),
    .HTRANS    ( ins_HTRANS    ),
    .HMASTLOCK ( ins_HMASTLOCK ),
    .HREADY    ( ins_HREADY    ),
    .HRESP     ( ins_HRESP     ),

    .*
  );
  assign if_parcel_page_fault = 1'b0; //TODO: for now

  /* Data Memory Access Block
   */
  riscv_dmem_ctrl #(
    .XLEN             ( XLEN               ),
    .PLEN             ( PLEN               ),

    .WRITEBUFFER_SIZE ( WRITEBUFFER_SIZE   ),
    .PMP_CNT          ( PMP_CNT            ),

    .SIZE             ( DCACHE_SIZE        ),
    .BLOCK_SIZE       ( DCACHE_BLOCK_SIZE  ),
    .WAYS             ( DCACHE_WAYS        ),
    .REPLACE_ALG      ( DCACHE_REPLACE_ALG ) )
  dmem_ctrl_inst (
    .rst_ni           ( HRESETn          ),
    .clk_i            ( HCLK             ),

    .biu_stb_o        ( dmem_biu_stb     ),
    .biu_stb_ack_i    ( dmem_biu_stb_ack ),
    .biu_d_ack_i      ( dmem_biu_d_ack   ),
    .biu_adri_o       ( dmem_biu_adri    ),
    .biu_adro_i       ( dmem_biu_adro    ),
    .biu_size_o       ( dmem_biu_size    ),
    .biu_type_o       ( dmem_biu_type    ),
    .biu_we_o         ( dmem_biu_we      ),
    .biu_lock_o       ( dmem_biu_lock    ),
    .biu_prot_o       ( dmem_biu_prot    ),
    .biu_d_o          ( dmem_biu_d       ),
    .biu_q_i          ( dmem_biu_q       ),
    .biu_ack_i        ( dmem_biu_ack     ),
    .biu_err_i        ( dmem_biu_err     ),

    .mem_req_i        ( dmem_req         ),
    .mem_adr_i        ( dmem_adr         ),
    .mem_size_i       ( dmem_size        ),
    .mem_lock_i       ( dmem_lock        ),
    .mem_we_i         ( dmem_we          ),
    .mem_d_i          ( dmem_d           ),
    .mem_q_o          ( dmem_q           ),
    .mem_ack_o        ( dmem_ack         ),
    .mem_err_o        ( dmem_err         ),
    .mem_misaligned_o ( dmem_misaligned  ),

    .bu_cacheflush_i  ( bu_cacheflush    ),
    .dcflush_rdy_o    ( dcflush_rdy      ),

    .st_prv_i         ( st_prv           ),
    .st_pmpcfg_i      ( st_pmpcfg        ),
    .st_pmpaddr_i     ( st_pmpaddr       )
  );
  assign dmem_page_fault = 1'b0; //TODO: for now


  /* Instantiate BIU
   */
  biu_ahb3lite #(
    .DATA_SIZE ( XLEN ),
    .ADDR_SIZE ( PLEN )
  )
  biu_inst (
    .HRESETn       ( HRESETn           ),
    .HCLK          ( HCLK              ),
    .HSEL          ( dat_HSEL          ),
    .HADDR         ( dat_HADDR         ),
    .HWDATA        ( dat_HWDATA        ),
    .HRDATA        ( dat_HRDATA        ),
    .HWRITE        ( dat_HWRITE        ),
    .HSIZE         ( dat_HSIZE         ),
    .HBURST        ( dat_HBURST        ),
    .HPROT         ( dat_HPROT         ),
    .HTRANS        ( dat_HTRANS        ),
    .HMASTLOCK     ( dat_HMASTLOCK     ),
    .HREADY        ( dat_HREADY        ),
    .HRESP         ( dat_HRESP         ),

    .biu_stb_i     ( dmem_biu_stb      ),
    .biu_stb_ack_o ( dmem_biu_stb_ack  ),
    .biu_d_ack_o   ( dmem_biu_d_ack    ),
    .biu_adri_i    ( dmem_biu_adri     ),
    .biu_adro_o    ( dmem_biu_adro     ),
    .biu_size_i    ( dmem_biu_size     ),
    .biu_type_i    ( dmem_biu_type     ),
    .biu_prot_i    ( dmem_biu_prot     ),
    .biu_lock_i    ( dmem_biu_lock     ),
    .biu_we_i      ( dmem_biu_we       ),
    .biu_d_i       ( dmem_biu_d        ),
    .biu_q_o       ( dmem_biu_q        ),
    .biu_ack_o     ( dmem_biu_ack      ),
    .biu_err_o     ( dmem_biu_err      )
  );

endmodule


/////////////////////////////////////////////////////////////////
//                                                             //
//    ██████╗  ██████╗  █████╗                                 //
//    ██╔══██╗██╔═══██╗██╔══██╗                                //
//    ██████╔╝██║   ██║███████║                                //
//    ██╔══██╗██║   ██║██╔══██║                                //
//    ██║  ██║╚██████╔╝██║  ██║                                //
//    ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═╝                                //
//          ██╗      ██████╗  ██████╗ ██╗ ██████╗              //
//          ██║     ██╔═══██╗██╔════╝ ██║██╔════╝              //
//          ██║     ██║   ██║██║  ███╗██║██║                   //
//          ██║     ██║   ██║██║   ██║██║██║                   //
//          ███████╗╚██████╔╝╚██████╔╝██║╚██████╗              //
//          ╚══════╝ ╚═════╝  ╚═════╝ ╚═╝ ╚═════╝              //
//                                                             //
//    RISC-V                                                   //
//    Top Level - AMBA3 AHB-Lite Bus Interface                 //
//                                                             //
/////////////////////////////////////////////////////////////////
//                                                             //
//             Copyright (C) 2014-2017 ROA Logic BV            //
//             www.roalogic.com                                //
//                                                             //
//    Unless specifically agreed in writing, this software is  //
//  licensed under the RoaLogic Non-Commercial License         //
//  version-1.0 (the "License"), a copy of which is included   //
//  with this file or may be found on the RoaLogic website     //
//  http://www.roalogic.com. You may not use the file except   //
//  in compliance with the License.                            //
//                                                             //
//    THIS SOFTWARE IS PROVIDED "AS IS" AND WITHOUT ANY        //
//  EXPRESS OF IMPLIED WARRANTIES OF ANY KIND.                 //
//  See the License for permissions and limitations under the  //
//  License.                                                   //
//                                                             //
/////////////////////////////////////////////////////////////////

module riscv_top_ahb3lite #(
  parameter            XLEN               = 32,
  parameter [XLEN-1:0] PC_INIT            = 'h200,
  parameter            PHYS_ADDR_SIZE     = XLEN,
  parameter            HAS_USER           = 0,
  parameter            HAS_SUPER          = 0,
  parameter            HAS_HYPER          = 0,
  parameter            HAS_BPU            = 1,
  parameter            HAS_FPU            = 0,
  parameter            HAS_MMU            = 0,
  parameter            HAS_MULDIV         = 0,
  parameter            HAS_AMO            = 0,
  parameter            HAS_RVC            = 0,
  parameter            IS_RV32E           = 0,

  parameter            MULT_LATENCY       = 0,

  parameter            BREAKPOINTS        = 3,

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
  parameter            WRITEBUFFER_SIZE   = 8,  //Number of entries in the write buffer

  parameter            TECHNOLOGY         = "GENERIC",

  parameter            MNMIVEC_DEFAULT    = PC_INIT -'h004,
  parameter            MTVEC_DEFAULT      = PC_INIT -'h040,
  parameter            HTVEC_DEFAULT      = PC_INIT -'h080,
  parameter            STVEC_DEFAULT      = PC_INIT -'h0C0,
  parameter            UTVEC_DEFAULT      = PC_INIT -'h100,

  parameter            VENDORID           = 16'h0001,
  parameter            ARCHID             = (1<<XLEN) | 12,
  parameter            REVMAJOR           = 4'h0,
  parameter            REVMINOR           = 4'h0,

  parameter            HARTID             = 0,

  parameter            PARCEL_SIZE        = 32
)
(
  //AHB interfaces
  input                        HRESETn,
                               HCLK,
										 
  output                       ins_HSEL,
  output [PHYS_ADDR_SIZE -1:0] ins_HADDR,
  output [XLEN           -1:0] ins_HWDATA,
  input  [XLEN           -1:0] ins_HRDATA,
  output                       ins_HWRITE,
  output [                2:0] ins_HSIZE,
  output [                2:0] ins_HBURST,
  output [                3:0] ins_HPROT,
  output [                1:0] ins_HTRANS,
  output                       ins_HMASTLOCK,
  input                        ins_HREADY,
  input                        ins_HRESP,
  
  output                       dat_HSEL,
  output [PHYS_ADDR_SIZE -1:0] dat_HADDR,
  output [XLEN           -1:0] dat_HWDATA,
  input  [XLEN           -1:0] dat_HRDATA,
  output                       dat_HWRITE,
  output [                2:0] dat_HSIZE,
  output [                2:0] dat_HBURST,
  output [                3:0] dat_HPROT,
  output [                1:0] dat_HTRANS,
  output                       dat_HMASTLOCK,
  input                        dat_HREADY,
  input                        dat_HRESP,

  //Interrupts
  input                        ext_nmi,
                               ext_tint,
                               ext_sint,
  input  [                3:0] ext_int,

  //Debug Interface
  input                        dbg_stall,
  input                        dbg_strb,
  input                        dbg_we,
  input  [riscv_du_pkg::DBG_ADDR_SIZE-1:0] dbg_addr,
  input  [XLEN           -1:0] dbg_dati,
  output [XLEN           -1:0] dbg_dato,
  output                       dbg_ack,
  output                       dbg_bp
);

  ////////////////////////////////////////////////////////////////
  //
  // Variables
  //
  logic                   rstn;
  logic                   clk; 

  logic                   if_stall_nxt_pc;
  logic [XLEN       -1:0] if_nxt_pc;
  logic                   if_stall,
                          if_flush;
  logic			  if_out_order;
  logic [PARCEL_SIZE-1:0] if_parcel;
  logic [XLEN       -1:0] if_parcel_pc;
  logic [            1:0] if_parcel_valid;
  logic                   if_parcel_misaligned;
  logic                   if_parcel_page_fault;

  logic                   mem_req;
  logic                   mem_ack;
  logic [XLEN       -1:0] mem_adr;
  logic [XLEN       -1:0] mem_d,
                          mem_q;
  logic                   mem_we;
  logic [XLEN/8     -1:0] mem_be;
  logic                   mem_misaligned;
  logic                   mem_page_fault;

  logic [            1:0] st_prv;

  logic                   bu_cacheflush,
                          dcflush_rdy;


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
    .XLEN           ( XLEN            ),
    .HAS_USER       ( HAS_USER        ),
    .HAS_SUPER      ( HAS_SUPER       ),
    .HAS_HYPER      ( HAS_HYPER       ),
    .HAS_BPU        ( HAS_BPU         ),
    .HAS_FPU        ( HAS_FPU         ),
    .HAS_MMU        ( HAS_MMU         ),
    .HAS_MULDIV     ( HAS_MULDIV      ),
    .HAS_AMO        ( HAS_AMO         ),
    .HAS_RVC        ( HAS_RVC         ),
    .IS_RV32E       ( IS_RV32E        ),
	 
    .MULT_LATENCY   ( MULT_LATENCY    ),

    .BREAKPOINTS    ( BREAKPOINTS     ),

    .BP_GLOBAL_BITS ( BP_GLOBAL_BITS  ),
    .BP_LOCAL_BITS  ( BP_LOCAL_BITS   ),

    .TECHNOLOGY     ( TECHNOLOGY      ),

    .MNMIVEC_DEFAULT( MNMIVEC_DEFAULT ),
    .MTVEC_DEFAULT  ( MTVEC_DEFAULT   ),
    .HTVEC_DEFAULT  ( HTVEC_DEFAULT   ),
    .STVEC_DEFAULT  ( STVEC_DEFAULT   ),
    .UTVEC_DEFAULT  ( UTVEC_DEFAULT   ),

    .VENDORID       ( VENDORID        ),
    .ARCHID         ( ARCHID          ),
    .REVMAJOR       ( REVMAJOR        ),
    .REVMINOR       ( REVMINOR        ),

    .HARTID         ( HARTID          ), 

    .PC_INIT        ( PC_INIT         ),
    .PARCEL_SIZE    ( PARCEL_SIZE     )
  )
  core (
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
    .PHYS_ADDR_SIZE ( PHYS_ADDR_SIZE     ),
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

  ahb3lite_checker #(
   .ADDR_SIZE  ( PHYS_ADDR_SIZE ),
   .DATA_SIZE  ( XLEN	        ))
  instruction_bus_checker (
   .HRESETn  ( HRESETn        ),
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
   .HRESP     ( ins_HRESP     )
  );

  assign if_parcel_page_fault = 1'b0; //TODO: for now

  /*
   * L1 Data Cache
   */
  riscv_dcache_ahb3lite #(
    .XLEN           ( XLEN               ),
    .PHYS_ADDR_SIZE ( PHYS_ADDR_SIZE     ),

    .SIZE           ( DCACHE_SIZE        ),
    .BLOCK_SIZE     ( DCACHE_BLOCK_SIZE  ),
    .WAYS           ( DCACHE_WAYS        ),
    .REPLACE_ALG    ( DCACHE_REPLACE_ALG ) )
  dcache (
    .HRESETn   ( HRESETn       ),
    .HCLK      ( HCLK          ),
    .HSEL      ( dat_HSEL      ),
    .HADDR     ( dat_HADDR     ),
    .HWDATA    ( dat_HWDATA    ),
    .HRDATA    ( dat_HRDATA    ),
    .HWRITE    ( dat_HWRITE    ),
    .HSIZE     ( dat_HSIZE     ),
    .HBURST    ( dat_HBURST    ),
    .HPROT     ( dat_HPROT     ),
    .HTRANS    ( dat_HTRANS    ),
    .HMASTLOCK ( dat_HMASTLOCK ),
    .HREADY    ( dat_HREADY    ),
    .HRESP     ( dat_HRESP     ),

    .*
  );

 ahb3lite_checker #(
   .ADDR_SIZE  ( PHYS_ADDR_SIZE ),
   .DATA_SIZE  ( XLEN	        ))
  data_bus_checker (
   .HRESETn  ( HRESETn        ),
   .HCLK      ( HCLK          ),
   .HSEL      ( dat_HSEL      ),
   .HADDR     ( dat_HADDR     ),
   .HWDATA    ( dat_HWDATA    ),
   .HRDATA    ( dat_HRDATA    ),
   .HWRITE    ( dat_HWRITE    ),
   .HSIZE     ( dat_HSIZE     ),
   .HBURST    ( dat_HBURST    ),
   .HPROT     ( dat_HPROT     ),
   .HTRANS    ( dat_HTRANS    ),
   .HMASTLOCK ( dat_HMASTLOCK ),
   .HREADY    ( dat_HREADY    ),
   .HRESP     ( dat_HRESP     )
  );



  assign mem_page_fault = 1'b0; //TODO: for now

endmodule


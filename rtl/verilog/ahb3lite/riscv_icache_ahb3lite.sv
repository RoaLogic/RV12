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
//    Instruction Cache                                        //
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

module riscv_icache_ahb3lite #(
  parameter XLEN           = 32,
  parameter PHYS_ADDR_SIZE = XLEN,
  parameter PARCEL_SIZE    = 32,

  parameter SIZE           = 64, //KBYTES
  parameter BLOCK_SIZE     = 32, //BYTES
  parameter WAYS           =  2, // 1           : Direct Mapped
                                 //<n>          : n-way set associative
                                 //<n>==<blocks>: fully associative
  parameter REPLACE_ALG    = 0,  //0: Random
                                 //1: FIFO
                                 //2: LRU

//cacheable region ...
  parameter TECHNOLOGY     = "GENERIC"
)
(
  input                           HRESETn,
  input                           HCLK,
 
  //AHB3 Lite Bus
  output                          HSEL,
  output     [PHYS_ADDR_SIZE-1:0] HADDR,
  input      [XLEN          -1:0] HRDATA,
  output     [XLEN          -1:0] HWDATA,
  output                          HWRITE,
  output     [               2:0] HSIZE,
  output     [               2:0] HBURST,
  output     [               3:0] HPROT,
  output     [               1:0] HTRANS,
  output                          HMASTLOCK,
  input                           HREADY,
  input                           HRESP,

  //CPU side
//  input      [XLEN       -1:0] non_cacheable_mask, 
  output                       if_stall_nxt_pc,
  input                        if_stall,
                               if_flush,
  input			       if_out_order,
  input      [XLEN       -1:0] if_nxt_pc,
  output     [XLEN       -1:0] if_parcel_pc,
  output     [PARCEL_SIZE-1:0] if_parcel,
  output     [            1:0] if_parcel_valid,
  output                       if_parcel_misaligned,
  input                        bu_cacheflush,
                               dcflush_rdy,

  input       [           1:0] st_prv
);

  //////////////////////////////////////////////////////////////////
  //
  // Constants
  //
  import ahb3lite_pkg::*;


  //////////////////////////////////////////////////////////////////
  //
  // Variables
  //
  //From Cache Controller Core
  logic                      biu_stb;
  logic                      biu_stb_ack;
  logic [PHYS_ADDR_SIZE-1:0] biu_adro,
                             biu_adri;  
  logic [XLEN/8        -1:0] biu_be;       //Byte enables
  logic [               2:0] biu_type;     //burst type -AHB style
  logic                      biu_lock;
  logic                      biu_we;
  logic [XLEN          -1:0] biu_di;
  logic [XLEN          -1:0] biu_do;
  logic                      biu_rack;     //data acknowledge, 1 per data
  logic                      biu_err;      //data error,

  logic                      biu_is_cacheable,
                             biu_is_instruction;
  logic [               1:0] biu_prv;       


  //////////////////////////////////////////////////////////////////
  //
  // Module Body
  //
  import riscv_pkg::*;


generate
if (SIZE == 0)
begin
  /*
   * No Instruction Cache Core
   * Control and glue logic only
   */
   riscv_noicache_core #(
    .XLEN           ( XLEN           ),
    .PHYS_ADDR_SIZE ( PHYS_ADDR_SIZE ),
    .PARCEL_SIZE    ( PARCEL_SIZE    )
  )
  noicache_core_inst (
    //common signals
    .rstn                 ( HRESETn ),
    .clk                  ( HCLK    ),

    //from CPU Core
    //To BIU
    .*
  );
end
else //SIZE > 0
begin
  /*
   * Instantiate Instruction Cache Core
   */
  riscv_icache_core #(
    .XLEN           ( XLEN           ),
    .PHYS_ADDR_SIZE ( PHYS_ADDR_SIZE ),
    .PARCEL_SIZE    ( PARCEL_SIZE    ),

    .SIZE           ( SIZE           ),
    .BLOCK_SIZE     ( BLOCK_SIZE     ),
    .WAYS           ( WAYS           ),
    .REPLACE_ALG    ( REPLACE_ALG    ),
    .TECHNOLOGY     ( TECHNOLOGY     )
  )
  icache_core_inst (
    //common signals
    .rstn                 ( HRESETn ),
    .clk                  ( HCLK    ),

    //from CPU Core
    //To BIU
    .*
  );
end
endgenerate

  /*
   * Instantiate BIU
   */
  riscv_cache_biu_ahb3lite #(
    .XLEN           ( XLEN           ),
    .PHYS_ADDR_SIZE ( PHYS_ADDR_SIZE )
  )
  biu_inst (
    .biu_wack( ),
    .biu_prv ( st_prv ),
    .*
  );

endmodule



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
//    Data Cache                                               //
//                                                             //
/////////////////////////////////////////////////////////////////
//                                                             //
//             Copyright (C) 201i4-2017 ROA Logic BV           //
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

module riscv_dcache_ahb3lite #(
  parameter XLEN             = 32,
  parameter PHYS_ADDR_SIZE   = XLEN,

  parameter WRITEBUFFER_SIZE = 8,

  parameter SIZE             = 64, //KBYTES
  parameter BLOCK_SIZE       = 32, //BYTES
  parameter WAYS             =  2, // 1           : Direct Mapped
                                   //<n>          : n-way set associative
                                   //<n>==<blocks>: fully associative
  parameter REPLACE_ALG      = 1,  //0: Random
                                   //1: FIFO
                                   //2: LRU

//cacheable region ...
  parameter TECHNOLOGY       = "GENERIC"
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
  input      [XLEN          -1:0] mem_adr,
                                  mem_d,       //from CPU
  input                           mem_req,
                                  mem_we,
  input      [XLEN/8        -1:0] mem_be,
  output     [XLEN          -1:0] mem_q,       //to CPU
  output                          mem_ack,
  output                          mem_misaligned,
  input                           bu_cacheflush,
  output                          dcflush_rdy,

  input       [              1:0] st_prv
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
  logic                      is_misaligned;
  logic                      wbuf_mem_req;     //memory request to write buffer (from misalignment check)
  logic                      wbuf_mem_ack;     //memory ack from write buffer

  //from Write Buffer
  logic                      cache_req,        //cache access request
                             cache_ack;        //cache access acknowledge
  logic [XLEN          -1:0] cache_adr;        //cache memory address
  logic                      cache_we;         //cache write enable
  logic [XLEN          -1:0] cache_d,          //cache write data
                             cache_q;          //cache read data
  logic [XLEN/8        -1:0] cache_be;         //cache byte enable
  logic [               1:0] cache_prv;        //piped st_prv
  logic                      cache_flush;      //piped bu_cacheflush

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
  logic                      biu_wack,     //data acknowledge, 1 per data
                             biu_rack;
  logic                      biu_err;      //data error,

  logic                      biu_is_cacheable,
                             biu_is_instruction;
  logic [               1:0] biu_prv;


  //////////////////////////////////////////////////////////////////
  //
  // Module Body
  //
  import riscv_pkg::*;


  /*
   * Check if the access is misaligned
   */
  riscv_memmisaligned #(
    .XLEN ( XLEN )
  )
  misaligned_chk_inst (
    .rstn           ( HRESETn        ),
    .clk            ( HCLK           ),
    .mem_req        ( mem_req        ),
    .mem_adr        ( mem_adr        ),
    .mem_be         ( mem_be         ),
    .mem_misaligned ( mem_misaligned ),
    .is_misaligned  ( is_misaligned  )
  );

  //acknowledge memory access when misaligned
  assign mem_ack = mem_misaligned | wbuf_mem_ack;


  //don't process memory access when misaligned
  assign wbuf_mem_req = mem_req & ~is_misaligned;


  /*
   * Hookup Write Buffer
   */
generate
  if (WRITEBUFFER_SIZE > 0)
  begin
      riscv_wbuf #(
        .XLEN  ( XLEN             ),
        .DEPTH ( WRITEBUFFER_SIZE )
      )
      wbuf_inst (
        .rstn ( HRESETn),
        .clk  ( HCLK   ),

        //from CPU
        .mem_req ( wbuf_mem_req ),
        .mem_ack ( wbuf_mem_ack ),

        //to cache controller
        .*
      );
  end
  else
  begin
      //No write buffer ... passthrough signals
      assign cache_req      = wbuf_mem_req;
      assign cache_adr      = mem_adr;
      assign cache_we       = mem_we;
      assign cache_be       = mem_be;
      assign cache_d        = mem_d;
      assign mem_q          = cache_q;
      assign wbuf_mem_ack   = cache_ack;
      assign cache_prv      = st_prv;
      assign cache_flush    = bu_cacheflush;
  end
endgenerate


  /*
   * Hookup Data Cache
   */
generate
if (SIZE == 0)
begin
  /*
   * No Data Cache Core
   * Control and glue logic only
   */
   riscv_nodcache_core #(
    .XLEN           ( XLEN           ),
    .PHYS_ADDR_SIZE ( PHYS_ADDR_SIZE )
  )
  nodcache_core_inst (
    //common signals
    .rstn                 ( HRESETn ),
    .clk                  ( HCLK    ),

    //from CPU Core
    .mem_adr        ( cache_adr        ),
    .mem_d          ( cache_d          ),
    .mem_req        ( cache_req        ),
    .mem_we         ( cache_we         ),
    .mem_be         ( cache_be         ),
    .mem_q          ( cache_q          ),
    .mem_ack        ( cache_ack        ),
    .st_prv         ( cache_prv        ),
    .bu_cacheflush  ( cache_flush      ),
 

    //To BIU
    .*
  );
end
else //SIZE > 0
begin
  /*
   * Instantiate Instruction Cache Core
   */
  riscv_dcache_core #(
    .XLEN           ( XLEN           ),
    .PHYS_ADDR_SIZE ( PHYS_ADDR_SIZE ),

    .SIZE           ( SIZE           ),
    .BLOCK_SIZE     ( BLOCK_SIZE     ),
    .WAYS           ( WAYS           ),
    .REPLACE_ALG    ( REPLACE_ALG    ),
    .TECHNOLOGY     ( TECHNOLOGY     )
  )
  dcache_core_inst (
    //common signals
    .rstn                 ( HRESETn ),
    .clk                  ( HCLK    ),

    //from WriteBuffer Core
    .mem_adr        ( cache_adr        ),
    .mem_d          ( cache_d          ),
    .mem_req        ( cache_req        ),
    .mem_we         ( cache_we         ),
    .mem_be         ( cache_be         ),
    .mem_q          ( cache_q          ),
    .mem_ack        ( cache_ack        ),
    .bu_cacheflush  ( cache_flush      ),

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
    .*
  );

endmodule



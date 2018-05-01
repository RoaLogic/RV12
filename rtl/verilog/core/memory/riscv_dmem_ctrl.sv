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
import biu_constants_pkg::*;

module riscv_dcache_ahb3lite #(
  parameter XLEN             = 32,
  parameter PLEN             = XLEN, // XLEN==32 ? 34 : 56

  parameter WRITEBUFFER_SIZE = 8,
  parameter PMP_CNT          = 16,
  parameter MUX_PORTS        = 2,

  parameter SIZE             = 64, //KBYTES
  parameter BLOCK_SIZE       = 32, //BYTES
  parameter WAYS             =  2, // 1           : Direct Mapped
                                   //<n>          : n-way set associative
                                   //<n>==<blocks>: fully associative
  parameter REPLACE_ALG      = 1,  //0: Random
                                   //1: FIFO
                                   //2: LRU

  parameter TECHNOLOGY       = "GENERIC"
)
(
  input  logic                          rst_ni,
  input  logic                          clk_i,
 
  //BIU ports
  output logic                          biu_stb_o,
  input  logic                          biu_stb_ack_i,
  input  logic                          biu_d_ack_i,
  output logic               [PLEN-1:0] biu_adri_o,
  input  logic               [PLEN-1:0] biu_adro_i,
  output biu_size_t                     biu_size_o,
  output biu_type_t                     biu_type_o,
  output logic                          biu_we_o,
  output logic                          biu_lock_o,
  output biu_prot_t                     biu_prot_o,
  output logic               [XLEN-1:0] biu_d_o,
  input  logic               [XLEN-1:0] biu_q_i,
  input  logic                          biu_ack_i,
                                        biu_err_i,

  //CPU side
  input  logic                          mem_req_i,
  input  logic               [XLEN-1:0] mem_adr_i,
  input  biu_size_t                     mem_size_i,
  input  logic                          mem_lock_i,
  input  logic                          mem_we_i,
  input  logic               [XLEN-1:0] mem_d_i,
  output logic               [XLEN-1:0] mem_q_o,
  output logic                          mem_ack_o,
                                        mem_err_o,
  output logic                          mem_misaligned_o,
  input  logic                          bu_cacheflush_i,
  output logic                          dcflush_rdy_o,

  input  pmpcfg_struct [15:0]           st_pmpcfg_i,
  input  logic         [15:0][XLEN-1:0] st_pmpaddr_i,
  input  logic               [     1:0] st_prv_i
);

  //////////////////////////////////////////////////////////////////
  //
  // Variables
  //

  //from PMP check
  logic            is_misaligned;
  logic            is_cacheable;

  //to/from Write Buffer
  logic            mem_req2wbuf;     //memory request to write buffer (from misalignment check)
  biu_prot_t       mem_prot2wbuf;
  biu_type_t       mem_type2wbuf;
  logic            wbuf_mem_ack;     //memory ack from write buffer

  logic            wbuf_req;
  logic [XLEN-1:0] wbuf_adr;
  biu_size_t       wbuf_size;
  biu_type_t       wbuf_type;
  logic            wbuf_lock;
  biu_prot_t       wbuf_prot;
  logic            wbuf_we;
  logic [XLEN-1:0] wbuf_d,
                   wbuf_q;
  logic            wbuf_ack,
                   wbuf_err;
  logic            wbuf_flush;


  //to/from Memory Mux
  logic            mux_psel;                    //output port select

  logic            mux_req     [MUX_PORTS];     //memory request from write buffer
  logic [XLEN-1:0] mux_adr     [MUX_PORTS];
  biu_size_t       mux_size    [MUX_PORTS];
  biu_type_t       mux_type    [MUX_PORTS];
  logic            mux_lock    [MUX_PORTS];
  biu_prot_t       mux_prot    [MUX_PORTS];
  logic            mux_we      [MUX_PORTS];
  logic [XLEN-1:0] mux_d       [MUX_PORTS],
                   mux_q       [MUX_PORTS];
  logic            mux_ack     [MUX_PORTS],
                   mux_err     [MUX_PORTS];


  //From Cache Controller Core
  logic            biu_stb     [2];
  logic            biu_stb_ack [2];
  logic            biu_d_ack   [2];
  logic [PLEN-1:0] biu_adro    [2],
                   biu_adri    [2];
  biu_size_t       biu_size    [2];
  biu_type_t       biu_type    [2];
  logic            biu_we      [2];
  logic            biu_lock    [2];
  biu_prot_t       biu_prot    [2];
  logic [XLEN-1:0] biu_d       [2];
  logic [XLEN-1:0] biu_q       [2];
  logic            biu_wack    [2],
                   biu_rack    [2],
                   biu_ack     [2],
                   biu_err     [2];


  //////////////////////////////////////////////////////////////////
  //
  // Module Body
  //


  /* Hookup Physical Memory Protection Unit
   */
  riscv_pmpchk #(
    .XLEN    ( XLEN    ),
    .PLEN    ( PLEN    ),
    .HAS_RVC (       0 ), //RVC not applicable for data access
    .PMP_CNT ( PMP_CNT )
  )
  pmpchk_inst (
    .rstn                ( rst_ni           ),
    .clk                 ( clk_i            ),

    .st_pmpcfg           ( st_pmpcfg_i      ),
    .st_pmpaddr          ( st_pmpaddr_i     ),
    .st_prv              ( st_prv_i         ),

    .access_instruction  ( 1'b0             ),  //This is a data access
    .access_req          ( mem_req_i        ),  //Memory access requested
    .access_adr          ( mem_adr_i        ),  //Physical Memory address (i.e. after translation)
    .access_size         ( mem_size_i       ),  //Transfer size
    .access_we           ( mem_we_i         ),  //Read/Write enable

    .access_exception    ( ),
    .access_misaligned   ( mem_misaligned_o ),
    .is_access_exception ( ),
    .is_misaligned       ( is_misaligned    ),
    .is_cacheable        ( is_cacheable     ) );


  //acknowledge memory access when misaligned
  assign mem_ack_o = mem_misaligned_o | wbuf_mem_ack;


  //don't process memory access when misaligned
  assign mem_req2wbuf = mem_req_i & ~is_misaligned;


  //generate PROT
  assign mem_prot2wbuf = biu_prot_t'(                                                //cast to biu_prot_t
                          PROT_DATA                                                | //data access
                          (st_prv_i == PRV_U ? PROT_USER      : PROT_PRIVILEGED  ) |
                          (is_cacheable      ? PROT_CACHEABLE : PROT_NONCACHEABLE)
                         );


  //generate burst type
  assign mem_type2wbuf = SINGLE;


  //generate mem-mux port selection
  assign mux_psel = wbuf_prot & PROT_CACHEABLE ? 1'b0 : 1'b1; //cache is located on port0


  /* Hookup Write Buffer
   * Push all accesses through write buffer to ensure
   * the ACK appears in the right order, otherwise cache-ack may come before nocache-ack
   */
generate
  if (WRITEBUFFER_SIZE > 0)
  begin
      riscv_wbuf #(
        .XLEN  ( XLEN             ),
        .DEPTH ( WRITEBUFFER_SIZE )
      )
      wbuf_inst (
        .rst_ni       ( rst_ni          ),
        .clk_i        ( clk_i           ),

        //Downstream
        .mem_req_i    ( mem_req2wbuf    ),
        .mem_adr_i    ( mem_adr_i       ),
        .mem_size_i   ( mem_size_i      ),
        .mem_type_i   ( mem_type2wbuf   ),
        .mem_lock_i   ( mem_lock_i      ),
        .mem_we_i     ( mem_we_i        ),
        .mem_prot_i   ( mem_prot2wbuf   ),
        .mem_d_i      ( mem_d_i         ),
        .mem_q_o      ( mem_q_o         ),
        .mem_ack_o    ( wbuf_mem_ack    ),
        .mem_err_o    ( mem_err_o       ),
        .cacheflush_i ( bu_cacheflush_i ),

        //Upstream
        .mem_req_o    ( wbuf_req        ),    //memory request
        .mem_adr_o    ( wbuf_adr        ),    //memory address
        .mem_size_o   ( wbuf_size       ),    //transfer size
        .mem_type_o   ( wbuf_type       ),    //burst type
        .mem_lock_o   ( wbuf_lock       ),
        .mem_prot_o   ( wbuf_prot       ),
        .mem_we_o     ( wbuf_we         ),    //write enable
        .mem_d_o      ( wbuf_d          ),    //write data
        .mem_q_i      ( wbuf_q          ),    //read data
        .mem_ack_i    ( wbuf_ack        ),
        .mem_err_i    ( wbuf_err        ),
        .cacheflush_o ( wbuf_flush      )
      );
  end
  else //WRITEBUFFER_SIZE == 0
  begin
      //No write buffer ... passthrough signals
      assign wbuf_req       = mem_req2wbuf;
      assign wbuf_adr       = mem_adr_i;
      assign wbuf_size      = mem_size_i;
      assign wbuf_type      = mem_type2wbuf;
      assign wbuf_lock      = mem_lock_i;
      assign wbuf_prot      = mem_prot2wbuf;
      assign wbuf_we        = mem_we_i;
      assign wbuf_d         = mem_d_i;
      assign mem_q_o        = wbuf_q;
      assign wbuf_mem_ack   = wbuf_ack;
      assign mem_err_o      = wbuf_err;
      assign wbuf_flush     = bu_cacheflush_i;
  end
endgenerate


  /*
   * Hookup Data Cache
   */
generate
  if (SIZE > 0)
  begin
      /* Instantiate memory-access-mux
       */
      riscv_mem_mux #(
        .ADDR_SIZE   ( PLEN ),
        .DATA_SIZE   ( XLEN ),
        .PORTS       ( 2    ),
        .QUEUE_DEPTH ( 2    )
      )
      mem_mux_inst (
        .rst_ni     ( rst_ni    ),
        .clk_i      ( clk_i     ),

        .mem_psel_i ( mux_psel  ),
        .mem_req_i  ( wbuf_req  ),
        .mem_adr_i  ( wbuf_adr  ),
        .mem_size_i ( wbuf_size ),
        .mem_type_i ( wbuf_type ),
        .mem_lock_i ( wbuf_lock ),
        .mem_prot_i ( wbuf_prot ),
        .mem_we_i   ( wbuf_we   ),
        .mem_d_i    ( wbuf_d    ),
        .mem_q_o    ( wbuf_q    ),
        .mem_ack_o  ( wbuf_ack  ),
        .mem_err_o  ( wbuf_err  ),

        .mem_req_o  ( mux_req   ),
        .mem_adr_o  ( mux_adr   ),
        .mem_size_o ( mux_size  ),
        .mem_type_o ( mux_type  ),
        .mem_lock_o ( mux_lock  ),
        .mem_prot_o ( mux_prot  ),
        .mem_we_o   ( mux_we    ),
        .mem_d_o    ( mux_d     ),
        .mem_q_i    ( mux_q     ),
        .mem_ack_i  ( mux_ack   ),
        .mem_err_i  ( mux_err   )
      );


      /* Instantiate Data Cache Core
       */
      riscv_dcache_core #(
        .XLEN           ( XLEN        ),
        .PLEN           ( PLEN        ),

        .SIZE           ( SIZE        ),
        .BLOCK_SIZE     ( BLOCK_SIZE  ),
        .WAYS           ( WAYS        ),
        .REPLACE_ALG    ( REPLACE_ALG ),
        .TECHNOLOGY     ( TECHNOLOGY  )
      )
      dcache_core_inst (
        //common signals
        .rst_ni          ( rst_ni        ),
        .clk_i           ( clk_i         ),

        //from WriteBuffer Core
        .mem_req_i       ( mux_req   [0] ),
        .mem_adr_i       ( mux_adr   [0] ),
        .mem_size_i      ( mux_size  [0] ),
        .mem_type_i      ( mux_type  [0] ),
        .mem_lock_i      ( mux_lock  [0] ),
        .mem_prot_i      ( mux_prot  [0] ),
        .mem_we_i        ( mux_we    [0] ),
        .mem_d_i         ( mux_d     [0] ),
        .mem_q_o         ( mux_q     [0] ),
        .mem_ack_o       ( mux_ack   [0] ),
        .mem_err_o       ( mux_err   [0] ),
        .flush_i         ( wbuf_flush    ),
        .flushrdy_o      ( dcflush_rdy_o ),

        //To BIU
        .biu_stb_o      ( biu_stb     [0] ),
        .biu_stb_ack_i  ( biu_stb_ack [0] ),
        .biu_d_ack_i    ( biu_d_ack   [0] ),
        .biu_adri_o     ( biu_adri    [0] ),
        .biu_adro_i     ( biu_adro    [0] ),
        .biu_size_o     ( biu_size    [0] ),
        .biu_type_o     ( biu_type    [0] ),
        .biu_lock_o     ( biu_lock    [0] ),
        .biu_prot_o     ( biu_prot    [0] ),
        .biu_we_o       ( biu_we      [0] ),
        .biu_d_o        ( biu_d       [0] ),
        .biu_q_i        ( biu_q       [0] ),
        .biu_ack_i      ( biu_ack     [0] ),
        .biu_err_i      ( biu_err     [0] )
      );


      /* Instantiate No-Cacheable interface
       */
      riscv_nodcache_core #(
        .XLEN ( XLEN ),
        .PLEN ( PLEN )
      )
      nodcache_core_inst (
        .rst_ni             ( rst_ni          ),
        .clk_i              ( clk_i           ),

        .mem_req_i          ( mux_req     [1] ),
        .mem_adr_i          ( mux_adr     [1] ),
        .mem_size_i         ( mux_size    [1] ),
        .mem_type_i         ( mux_type    [1] ),
        .mem_lock_i         ( mux_lock    [1] ),
        .mem_prot_i         ( mux_prot    [1] ),
        .mem_we_i           ( mux_we      [1] ),
        .mem_d_i            ( mux_d       [1] ),
        .mem_q_o            ( mux_q       [1] ),
        .mem_ack_o          ( mux_ack     [1] ),
        .mem_err_o          ( mux_err     [1] ),

        .biu_stb_o          ( biu_stb     [1] ),
        .biu_stb_ack_i      ( biu_stb_ack [1] ),
        .biu_adri_o         ( biu_adri    [1] ),
        .biu_size_o         ( biu_size    [1] ),
        .biu_type_o         ( biu_type    [1] ),
        .biu_lock_o         ( biu_lock    [1] ),
        .biu_prot_o         ( biu_prot    [1] ),
        .biu_we_o           ( biu_we      [1] ),
        .biu_d_o            ( biu_d       [1] ),
        .biu_q_i            ( biu_q       [1] ),
        .biu_ack_i          ( biu_ack     [1] ),
        .biu_err_i          ( biu_err     [1] )
      );


      /* Hook up BIU mux
       */
      biu_mux #(
       .ADDR_SIZE ( PLEN ),
       .DATA_SIZE ( XLEN ),
       .PORTS     ( 2    )
      )
      biu_mux_inst (
       .rst_ni        ( rst_ni        ),
       .clk_i         ( clk_i         ),

       .biu_stb_i     ( biu_stb       ), //access request
       .biu_stb_ack_o ( biu_stb_ack   ), //access request acknowledge
       .biu_d_ack_o   ( biu_d_ack     ),
       .biu_adri_i    ( biu_adri      ), //access start address
       .biu_adro_o    ( biu_adro      ), //transfer addresss
       .biu_size_i    ( biu_size      ), //access data size
       .biu_type_i    ( biu_type      ), //access burst type
       .biu_lock_i    ( biu_lock      ), //access locked access
       .biu_prot_i    ( biu_prot      ), //access protection bits
       .biu_we_i      ( biu_we        ), //access write enable
       .biu_d_i       ( biu_d         ), //access write data
       .biu_q_o       ( biu_q         ), //access read data
       .biu_ack_o     ( biu_ack       ), //transfer acknowledge
       .biu_err_o     ( biu_err       ), //transfer error

       .biu_stb_o     ( biu_stb_o     ),
       .biu_d_ack_i   ( biu_d_ack_i   ),
       .biu_stb_ack_i ( biu_stb_ack_i ),
       .biu_adri_o    ( biu_adri_o    ),
       .biu_adro_i    ( biu_adro_i    ),
       .biu_size_o    ( biu_size_o    ),
       .biu_type_o    ( biu_type_o    ),
       .biu_lock_o    ( biu_lock_o    ),
       .biu_prot_o    ( biu_prot_o    ),
       .biu_we_o      ( biu_we_o      ),
       .biu_d_o       ( biu_d_o       ),
       .biu_q_i       ( biu_q_i       ),
       .biu_ack_i     ( biu_ack_i     ),
       .biu_err_i     ( biu_err_i     )
      );
  end
  else //SIZE == 0
  begin
      assign dcflush_rdy_o = 1'b1;

      /* Instantiate No-Cacheable interface
       */
      riscv_nodcache_core #(
        .XLEN           ( XLEN ),
        .PHYS_ADDR_SIZE ( PLEN )
      )
      nodcache_core_inst (
        .rst_ni             ( reset_ni      ),
        .clk_i              ( clk_i         ),

        .mem_req_i          ( wbuf_req      ),
        .mem_adr_i          ( wbuf_adr      ),
        .mem_size_i         ( wbuf_size     ),
        .mem_type_i         ( wbuf_type     ),
        .mem_lock_i         ( wbuf_lock     ),
        .mem_prot_i         ( wbuf_prot     ),
        .mem_we_i           ( wbuf_we       ),
        .mem_d_i            ( wbuf_d        ),
        .mem_q_o            ( wbuf_q        ),
        .mem_ack_o          ( wbuf_ack      ),
        .mem_err_o          ( wbuf_err      ),

        .biu_stb_o          ( biu_stb_o     ),
        .biu_stb_ack_i      ( biu_stb_ack_i ),
        .biu_adri_o         ( biu_adri_o    ),
        .biu_size_o         ( biu_size_o    ),
        .biu_type_o         ( biu_type_o    ),
        .biu_we_o           ( biu_we_o      ),
        .biu_lock_o         ( biu_lock_o    ),
        .biu_prot_o         ( biu_prot_o    ),
        .biu_d_o            ( biu_d_o       ),
        .biu_q_i            ( biu_q_i       ),
        .biu_ack_i          ( biu_ack_i     ),
        .biu_err_i          ( biu_err_i     )
      );
  end
endgenerate

endmodule



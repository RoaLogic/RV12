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
import biu_constants_pkg::*;

module riscv_imem_ctrl #(
  parameter XLEN              = 32,
  parameter PLEN              = XLEN, // XLEN==32 ? 34 : 56
  parameter PARCEL_SIZE       = 32,

  parameter HAS_RVC           = 0,

  parameter PMA_CNT           = 3,
  parameter PMP_CNT           = 16,

  parameter CACHE_SIZE        = 64, //KBYTES
  parameter CACHE_BLOCK_SIZE  = 32, //BYTES
  parameter CACHE_WAYS        =  2, // 1           : Direct Mapped
                                    //<n>          : n-way set associative
                                    //<n>==<blocks>: fully associative

  parameter TCM_SIZE          = 0,  //KBYTES

  parameter PIPELINE_SIZE     = 8,


/*
  parameter REPLACE_ALG      = 1,  //0: Random
                                   //1: FIFO
                                   //2: LRU
*/
  parameter TECHNOLOGY       = "GENERIC"
)
(
  input  logic                               rst_ni,
  input  logic                               clk_i,
 
  //Configuration
  input  pmacfg_t                            pma_cfg_i [PMA_CNT],
  input                 [XLEN          -1:0] pma_adr_i [PMA_CNT],

  //CPU side
  input  logic          [XLEN          -1:0] nxt_pc_i,
  output logic                               stall_nxt_pc_o,
  input  logic                               stall_i,
  input  logic                               flush_i,
  output logic          [XLEN          -1:0] parcel_pc_o,
  output logic          [PARCEL_SIZE   -1:0] parcel_o,
  output logic          [PARCEL_SIZE/16-1:0] parcel_valid_o,
  output logic                               err_o,
                                             misaligned_o,
                                             page_fault_o,
  input  logic                               cache_flush_i,
  input  logic                               dcflush_rdy_i,

  input  pmpcfg_t [PMP_CNT-1:0]                     st_pmpcfg_i,
  input  logic    [PMP_CNT-1:0][XLEN          -1:0] st_pmpaddr_i,
  input  logic          [               1:0] st_prv_i,

  //BIU ports
  output logic                               biu_stb_o,
  input  logic                               biu_stb_ack_i,
  input  logic                               biu_d_ack_i,
  output logic          [PLEN          -1:0] biu_adri_o,
  input  logic          [PLEN          -1:0] biu_adro_i,
  output biu_size_t                          biu_size_o,
  output biu_type_t                          biu_type_o,
  output logic                               biu_we_o,
  output logic                               biu_lock_o,
  output biu_prot_t                          biu_prot_o,
  output logic          [XLEN          -1:0] biu_d_o,
  input  logic          [XLEN          -1:0] biu_q_i,
  input  logic                               biu_ack_i,
                                             biu_err_i
);

  //////////////////////////////////////////////////////////////////
  //
  // Constants
  //

  localparam TID_SIZE  = 3;

  localparam MUX_PORTS = (CACHE_SIZE > 0) ? 2 : 1;

  localparam EXT       = 0,
             CACHE     = 1,
             TCM       = 2;
  localparam SEL_EXT   = (1 << EXT  ),
             SEL_CACHE = (1 << CACHE),
             SEL_TCM   = (1 << TCM  );


  //////////////////////////////////////////////////////////////////
  //
  // Typedefs
  //
  typedef struct packed {
    logic [XLEN          -1:0] pc;        //virtual PC
    logic [PARCEL_SIZE   -1:0] parcel;    //Parcel
    logic [PARCEL_SIZE/16-1:0] valid;     //valid bits
    logic                      misaligned,//misaligned parcel PC
                               page_fault,//page fault
                               error;     //access error
  } parcel_queue_t;


  //////////////////////////////////////////////////////////////////
  //
  // Variables
  //


  //Buffered memory request signals
  //Virtual memory access signals
  logic            buf_req,
                   buf_ack;
  logic [XLEN-1:0] buf_adr,
                   buf_adr_dly;
  biu_size_t       buf_size;
  logic            buf_lock;
  biu_prot_t       buf_prot;

  logic            nxt_pc_queue_req,
                   nxt_pc_queue_empty,
                   nxt_pc_queue_full;

  //Misalignment check
  logic            misaligned;


  //MMU signals
  //Physical memory access signals
  logic            preq;
  logic [PLEN-1:0] padr;
  biu_size_t       psize;
  logic            plock;
  biu_prot_t       pprot;
  logic            page_fault;
  

  //from PMA check
  logic            pma_exception,
                   pma_misaligned;
  logic            is_cache_access;
  logic            is_ext_access,
                   ext_access_req;
  logic            is_tcm_access;

  //from PMP check
  logic            pmp_exception;


  //From Cache Controller Core
  logic [PARCEL_SIZE-1:0] cache_q;
  logic            cache_ack,
                   cache_err;

  //From TCM
  logic [XLEN-1:0] tcm_q;
  logic            tcm_ack;

  //From IO
  logic [XLEN-1:0] ext_vadr,
                   ext_q;
  logic            ext_access_ack,   //address transfer acknowledge
                   ext_ack,          //data transfer acknowledge
                   ext_err;


  //BIU ports
  logic            biu_stb     [MUX_PORTS];
  logic            biu_stb_ack [MUX_PORTS];
  logic            biu_d_ack   [MUX_PORTS];
  logic [PLEN-1:0] biu_adro    [MUX_PORTS],
                   biu_adri    [MUX_PORTS];
  biu_size_t       biu_size    [MUX_PORTS];
  biu_type_t       biu_type    [MUX_PORTS];
  logic            biu_we      [MUX_PORTS];
  logic            biu_lock    [MUX_PORTS];
  biu_prot_t       biu_prot    [MUX_PORTS];
  logic [XLEN-1:0] biu_d       [MUX_PORTS];
  logic [XLEN-1:0] biu_q       [MUX_PORTS];
  logic            biu_ack     [MUX_PORTS],
                   biu_err     [MUX_PORTS];

  //to CPU
  logic [PARCEL_SIZE/16-1:0] parcel_valid;
  parcel_queue_t             parcel_queue_d,
                             parcel_queue_q;
  logic                      parcel_queue_empty,
                             parcel_queue_full;


  //////////////////////////////////////////////////////////////////
  //
  // Module Body
  //

/* For debugging
int fd;
initial fd = $fopen("memtrace.dat");

logic [XLEN-1:0] adr_dly, d_dly;
logic            we_dly;
int n =0;

always @(posedge clk_i)
  begin
      if (buf_req)
      begin
          adr_dly <= buf_adr;
      end
      
      if (mem_ack_o)
      begin
          n++;
          if (we_dly) $fdisplay (fd, "%0d, [%0x] <= %x", n, adr_dly, d_dly);
          else        $fdisplay (fd, "%0d, [%0x] == %x", n, adr_dly, mem_q_o);
      end
  end
*/


  /* Hookup Access Buffer
   */
  riscv_membuf #(
    .DEPTH ( 2    ),
    .DBITS ( XLEN )
  )
  nxt_pc_queue_inst (
    .rst_ni  ( rst_ni            ),
    .clk_i   ( clk_i             ),

    .clr_i   ( flush_i           ),
    .ena_i   ( 1'b1              ),

    .req_i   (~stall_nxt_pc_o    ),
    .d_i     ( nxt_pc_i          ),

    .req_o   ( buf_req           ),
    .q_o     ( buf_adr           ),
    .ack_i   ( buf_ack           ),

    .empty_o (                   ),
    .full_o  ( nxt_pc_queue_full )
  );

  //stall nxt_pc when queues full, or when DCACHE is flushing
  assign stall_nxt_pc_o = nxt_pc_queue_full | parcel_queue_full | ~dcflush_rdy_i;

  assign buf_ack  = ext_access_ack | cache_ack | tcm_ack;
  assign buf_size = WORD;
  assign buf_lock = 1'b0;
  assign buf_prot = biu_prot_t'(PROT_DATA |
                                st_prv_i == PRV_U ? PROT_USER : PROT_PRIVILEGED);


  /* Hookup misalignment check
   */
  riscv_memmisaligned #(
    .XLEN    ( XLEN    ),
    .HAS_RVC ( HAS_RVC )
  )
  misaligned_inst (
    .clk_i         ( clk_i      ),
    .instruction_i ( 1'b1       ), //instruction access
    .req_i         ( buf_req    ),
    .adr_i         ( buf_adr    ),
    .size_i        ( buf_size   ),
    .misaligned_o  ( misaligned )
  );

   
  /* Hookup MMU
   * TODO
   */
  riscv_mmu #(
    .XLEN ( XLEN ),
    .PLEN ( PLEN )
  )
  mmu_inst (
    .rst_ni       ( rst_ni       ),
    .clk_i        ( clk_i        ),
    .clr_i        ( flush_i      ),

    .vreq_i       ( buf_req      ),
    .vadr_i       ( buf_adr      ),
    .vsize_i      ( buf_size     ),
    .vlock_i      ( buf_lock     ),
    .vprot_i      ( buf_prot     ),
    .vwe_i        ( 1'b0         ), //instructions only read
    .vd_i         ( {XLEN{1'b0}} ), //no write data

    .preq_o       ( preq         ),
    .padr_o       ( padr         ),
    .psize_o      ( psize        ),
    .plock_o      ( plock        ),
    .pprot_o      ( pprot        ),
    .pwe_o        (              ),
    .pd_o         (              ),
    .pq_i         ( {XLEN{1'b0}} ),
    .pack_i       ( 1'b0         ),

    .page_fault_o ( page_fault   )
  );


  /* Hookup Physical Memory Atrributes Unit
   */
  riscv_pmachk #(
    .XLEN    ( XLEN    ),
    .PLEN    ( PLEN    ),
    .HAS_RVC ( HAS_RVC ),
    .PMA_CNT ( PMA_CNT )
  )
  pmachk_inst (
    //Configuration
    .pma_cfg_i         ( pma_cfg_i       ),
    .pma_adr_i         ( pma_adr_i       ),

    //misaligned
    .misaligned_i      ( misaligned      ),

    //Memory Access
    .instruction_i     ( 1'b1            ), //Instruction access
    .req_i             ( preq            ),
    .adr_i             ( padr            ),
    .size_i            ( psize           ),
    .lock_i            ( plock           ),
    .we_i              ( 1'b0            ),

    //Output
    .pma_o             (                 ),
    .exception_o       ( pma_exception   ),
    .misaligned_o      ( pma_misaligned  ),
    .is_cache_access_o ( is_cache_access ),
    .is_ext_access_o   ( is_ext_access   ),
    .is_tcm_access_o   ( is_tcm_access   )
  );


  /* Hookup Physical Memory Protection Unit
   */
  riscv_pmpchk #(
    .XLEN    ( XLEN    ),
    .PLEN    ( PLEN    ),
    .PMP_CNT ( PMP_CNT )
  )
  pmpchk_inst (
    .st_pmpcfg_i   ( st_pmpcfg_i   ),
    .st_pmpaddr_i  ( st_pmpaddr_i  ),
    .st_prv_i      ( st_prv_i      ),

    .instruction_i ( 1'b1          ),  //Instruction access
    .req_i         ( preq          ),  //Memory access request
    .adr_i         ( padr          ),  //Physical Memory address (i.e. after translation)
    .size_i        ( psize         ),  //Transfer size
    .we_i          ( 1'b0          ),  //Read/Write enable

    .exception_o   ( pmp_exception )
  );


  /* Hookup Cache, TCM, external-interface
   */
generate
  if (CACHE_SIZE > 0)
  begin
      /* Instantiate Data Cache Core
       */
      riscv_icache_core #(
        .XLEN           ( XLEN             ),
        .PLEN           ( PLEN             ),
        .PARCEL_SIZE    ( PARCEL_SIZE      ),

        .SIZE           ( CACHE_SIZE       ),
        .BLOCK_SIZE     ( CACHE_BLOCK_SIZE ),
        .WAYS           ( CACHE_WAYS       ),
        .TECHNOLOGY     ( TECHNOLOGY       )
      )
      icache_inst (
        //common signals
        .rst_ni          ( rst_ni           ),
        .clk_i           ( clk_i            ),
        .clr_i           ( flush_i          ),

        //from MMU/PMA
        .mem_vreq_i      ( buf_req          ),
        .mem_preq_i      ( is_cache_access  ),
        .mem_vadr_i      ( buf_adr          ),
        .mem_padr_i      ( padr             ),
        .mem_size_i      ( buf_size         ),
        .mem_lock_i      ( buf_lock         ),
        .mem_prot_i      ( buf_prot         ),
        .mem_q_o         ( cache_q          ),
        .mem_ack_o       ( cache_ack        ),
        .mem_err_o       ( cache_err        ),
        .flush_i         ( cache_flush_i    ),
        .flushrdy_i      ( 1'b1             ), //handled by stall_nxt_pc

        //To BIU
        .biu_stb_o       ( biu_stb     [CACHE] ),
        .biu_stb_ack_i   ( biu_stb_ack [CACHE] ),
        .biu_d_ack_i     ( biu_d_ack   [CACHE] ),
        .biu_adri_o      ( biu_adri    [CACHE] ),
        .biu_adro_i      ( biu_adro    [CACHE] ),
        .biu_size_o      ( biu_size    [CACHE] ),
        .biu_type_o      ( biu_type    [CACHE] ),
        .biu_lock_o      ( biu_lock    [CACHE] ),
        .biu_prot_o      ( biu_prot    [CACHE] ),
        .biu_we_o        ( biu_we      [CACHE] ),
        .biu_d_o         ( biu_d       [CACHE] ),
        .biu_q_i         ( biu_q       [CACHE] ),
        .biu_ack_i       ( biu_ack     [CACHE] ),
        .biu_err_i       ( biu_err     [CACHE] )
      );
  end
  else  //No cache
  begin
      assign cache_q         =  'h0;
      assign cache_ack       = 1'b0;
      assign cache_err       = 1'b0;
  end


  /* Instantiate TCM block
   */
  if (TCM_SIZE > 0)
  begin
  end
  else  //No TCM
  begin
      assign tcm_q   =  'h0;
      assign tcm_ack = 1'b0;
  end


  /* Instantiate EXT block
   */
  if (CACHE_SIZE > 0)
  begin
      if (TCM_SIZE > 0) assign ext_access_req = is_ext_access;
      else              assign ext_access_req = is_ext_access | is_tcm_access;
  end
  else
  begin
      if (TCM_SIZE > 0) assign ext_access_req = is_ext_access | is_cache_access;
      else              assign ext_access_req = is_ext_access | is_cache_access | is_tcm_access;
  end


  riscv_dext #(
    .XLEN ( XLEN ),
    .PLEN ( PLEN )
  )
  dext_inst (
    .rst_ni             ( rst_ni            ),
    .clk_i              ( clk_i             ),
    .clr_i              ( flush_i           ),

    .mem_req_i          ( ext_access_req    ),
    .mem_adr_i          ( padr              ),
    .mem_size_i         ( psize             ),
    .mem_type_i         ( SINGLE            ),
    .mem_lock_i         ( plock             ),
    .mem_prot_i         ( pprot             ),
    .mem_we_i           ( 1'b0              ),
    .mem_d_i            ( {XLEN{1'b0}}      ),
    .mem_adr_ack_o      ( ext_access_ack    ),
    .mem_q_o            ( ext_q             ),
    .mem_ack_o          ( ext_ack           ),
    .mem_err_o          ( ext_err           ),

    .biu_stb_o          ( biu_stb     [EXT] ),
    .biu_stb_ack_i      ( biu_stb_ack [EXT] ),
    .biu_adri_o         ( biu_adri    [EXT] ),
    .biu_size_o         ( biu_size    [EXT] ),
    .biu_type_o         ( biu_type    [EXT] ),
    .biu_lock_o         ( biu_lock    [EXT] ),
    .biu_prot_o         ( biu_prot    [EXT] ),
    .biu_we_o           ( biu_we      [EXT] ),
    .biu_d_o            ( biu_d       [EXT] ),
    .biu_q_i            ( biu_q       [EXT] ),
    .biu_ack_i          ( biu_ack     [EXT] ),
    .biu_err_i          ( biu_err     [EXT] )
  );

  //store virtual addresses for external access
  rl_queue #(
    .DEPTH ( 8    ),
    .DBITS ( XLEN )
  )
  ext_vadr_queue_inst (
    .rst_ni         ( rst_ni         ),
    .clk_i          ( clk_i          ),

    .clr_i          ( flush_i        ),
    .ena_i          ( 1'b1           ),

    .we_i           ( ext_access_req ),
    .d_i            ( buf_adr_dly    ),

    .re_i           ( ext_ack        ),
    .q_o            ( ext_vadr       ),

    .almost_empty_o (                ),
    .almost_full_o  (                ),
    .empty_o        (                ),
    .full_o         (                )  //stall access requests when full (AXI bus ...)
  );

endgenerate


  /* Hookup BIU mux
   */
  biu_mux #(
    .ADDR_SIZE ( PLEN      ),
    .DATA_SIZE ( XLEN      ),
    .PORTS     ( MUX_PORTS )
  )
  biu_mux_inst (
    .rst_ni        ( rst_ni        ),
    .clk_i         ( clk_i         ),

    .biu_req_i     ( biu_stb       ), //access request
    .biu_req_ack_o ( biu_stb_ack   ), //access request acknowledge
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

    .biu_req_o     ( biu_stb_o     ),
    .biu_req_ack_i ( biu_stb_ack_i ),
    .biu_d_ack_i   ( biu_d_ack_i   ),
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


  /* Results back to CPU
   */

  assign parcel_valid = {2{ext_ack | cache_ack | tcm_ack}};


  //Instruction Queue
  always @(posedge clk_i)
    if (buf_req) buf_adr_dly <= buf_adr;

  assign parcel_queue_d.pc = ext_ack ? ext_vadr : buf_adr_dly;

  always_comb
    unique case ({ext_ack, cache_ack, tcm_ack})
      3'b001 : parcel_queue_d.parcel = tcm_q;
      3'b010 : parcel_queue_d.parcel = cache_q;
      default: parcel_queue_d.parcel = ext_q >> (16 * parcel_queue_d.pc[1 +: $clog2(XLEN/16)]);
    endcase

  assign parcel_queue_d.valid      = parcel_valid;
  assign parcel_queue_d.misaligned = pma_misaligned;
  assign parcel_queue_d.page_fault = page_fault;
  assign parcel_queue_d.error      = ext_err | cache_err | pma_exception | pmp_exception;


  //Instruction queue
  //Add some extra words for inflight instructions
  rl_queue #(
    .DEPTH                 ( 4+4                   ),
    .DBITS                 ( $bits(parcel_queue_d) ),
    .ALMOST_FULL_THRESHOLD ( 4                     )
  )
  parcel_queue_inst (
    .rst_ni         ( rst_ni ),
    .clk_i          ( clk_i  ),

    .clr_i          ( flush_i ),
    .ena_i          ( 1'b1 ),

    .we_i           (|parcel_valid         ),
    .d_i            ( parcel_queue_d        ),

    .re_i           (~parcel_queue_empty & ~stall_i),
    .q_o            ( parcel_queue_q        ),

    .almost_empty_o (                    ),
    .almost_full_o  ( parcel_queue_full  ),
    .empty_o        ( parcel_queue_empty ),
    .full_o         (                    )
  );


  //CPU signals
  assign parcel_pc_o    = parcel_queue_q.pc;
  assign parcel_o       = parcel_queue_q.parcel;
  assign parcel_valid_o = parcel_queue_q.valid & ~{PARCEL_SIZE/16{parcel_queue_empty}};
  assign misaligned_o   = parcel_queue_q.misaligned;
  assign page_fault_o   = parcel_queue_q.page_fault;
  assign err_o          = parcel_queue_q.error;

endmodule



/////////////////////////////////////////////////////////////////////
//   ,------.                    ,--.                ,--.          //
//   |  .--. ' ,---.  ,--,--.    |  |    ,---. ,---. `--' ,---.    //
//   |  '--'.'| .-. |' ,-.  |    |  |   | .-. | .-. |,--.| .--'    //
//   |  |\  \ ' '-' '\ '-'  |    |  '--.' '-' ' '-' ||  |\ `--.    //
//   `--' '--' `---'  `--`--'    `-----' `---' `-   /`--' `---'    //
//                                             `---'               //
//    RISC-V                                                       //
//    Data Cache Hit Stage                                         //
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


import riscv_cache_pkg::*;
import biu_constants_pkg::*;


module riscv_cache_hit #(
  parameter XLEN           = 32,
  parameter PLEN           = XLEN,
  parameter PARCEL_SIZE    = XLEN,
  parameter HAS_RVC        = 0,

  parameter SIZE           = 64,
  parameter BLOCK_SIZE     = XLEN,
  parameter WAYS           = 2,

  parameter INFLIGHT_DEPTH = 2,
  parameter BIUTAG_SIZE    = $clog2(XLEN/PARCEL_SIZE),
 
  localparam BLK_BITS      = no_of_block_bits(BLOCK_SIZE),
  localparam SETS          = no_of_sets(SIZE, BLOCK_SIZE, WAYS),
  localparam BLK_OFFS_BITS = no_of_block_offset_bits(BLOCK_SIZE),
  localparam IDX_BITS      = no_of_index_bits(SETS),
  localparam TAG_BITS      = no_of_tag_bits(XLEN, IDX_BITS, BLK_OFFS_BITS),
  localparam INFLIGHT_BITS = $clog2(INFLIGHT_DEPTH+1)
)
(
  input  logic                        rst_ni,
  input  logic                        clk_i,

  output logic                        stall_o,
  input  logic                        flush_i,          //flush pipe

  input  logic                        cacheflush_req_i, //flush cache
  input  logic                        dcflush_rdy_i,    //data cache flush ready
  output logic                        armed_o,
  output logic                        flushing_o,
  output logic                        filling_o,
  input  logic [WAYS            -1:0] fill_way_i,
  output logic [WAYS            -1:0] fill_way_o,

  input  logic                        req_i,            //from previous-stage
  input  logic [PLEN            -1:0] adr_i,
  input  biu_size_t                   size_i,
  input  logic                        lock_i,
  input  biu_prot_t                   prot_i,
  input  logic                        is_cacheable_i,

  input  logic                        cache_hit_i,      //from cache-memory
  input  logic [BLK_BITS        -1:0] cache_line_i,
  output logic [IDX_BITS        -1:0] idx_o,
  output logic [TAG_BITS        -1:0] core_tag_o,

  output biucmd_t                     biucmd_o,
  input  logic                        biucmd_ack_i,
  output logic                        biucmd_noncacheable_req_o,
  input  logic                        biucmd_noncacheable_ack_i,
  output logic [PLEN            -1:0] biucmd_adri_o,
  output logic [BIUTAG_SIZE     -1:0] biucmd_tagi_o,
  input  logic [INFLIGHT_BITS   -1:0] inflight_cnt_i,


  input  logic [XLEN            -1:0] biu_q_i,
  input  logic                        biu_stb_ack_i,
                                      biu_ack_i,
                                      biu_err_i,
  input  logic [PLEN            -1:0] biu_adro_i,
  input  logic [BIUTAG_SIZE     -1:0] biu_tago_i,
  input  logic                        in_biubuffer_i,
  input  logic [BLK_BITS        -1:0] biubuffer_i,

  output logic [XLEN            -1:0] parcel_pc_o,
  output logic [XLEN            -1:0] parcel_o,
  output logic [XLEN/PARCEL_SIZE-1:0] parcel_valid_o,
  output logic                        parcel_error_o,
  output logic                        parcel_misaligned_o
);

  //////////////////////////////////////////////////////////////////
  //
  // Constants
  //
  
  //----------------------------------------------------------------
  // Cache
  //----------------------------------------------------------------
/*
  localparam PAGE_SIZE       = 4*1024;                             //4KB pages
  localparam MAX_IDX_BITS    = $clog2(PAGE_SIZE) - $clog2(BLOCK_SIZE); //Maximum IDX_BITS
  

  localparam SETS            = (SIZE*1024) / BLOCK_SIZE / WAYS;    //Number of sets TODO:SETS=1 doesn't work
  localparam BLK_OFF_BITS    = $clog2(BLOCK_SIZE);                 //Number of BlockOffset bits
  localparam IDX_BITS        = $clog2(SETS);                       //Number of Index-bits
  localparam TAG_BITS        = XLEN - IDX_BITS - BLK_OFF_BITS;     //Number of TAG-bits
  localparam BLK_BITS        = 8*BLOCK_SIZE;                       //Total number of bits in a Block
  localparam BURST_SIZE      = BLK_BITS / XLEN;                    //Number of transfers to load 1 Block
  localparam BURST_BITS      = $clog2(BURST_SIZE);
  localparam BURST_OFF       = XLEN/8;
  localparam BURST_LSB       = $clog2(BURST_OFF);

  //BLOCK decoding
  localparam DAT_OFF_BITS    = $clog2(BLK_BITS / XLEN);            //Offset in block
  localparam PARCEL_OFF_BITS = $clog2(XLEN / PARCEL_SIZE);
*/

  localparam DAT_OFFS_BITS = no_of_data_offset_bits (XLEN, BLK_BITS);   //Offset in block
  localparam BURST_OFF     = XLEN/8;
  localparam BURST_LSB     = $clog2(BURST_OFF);


  //////////////////////////////////////////////////////////////////
  //
  // Functions
  //
  function automatic integer onehot2int;
    input [WAYS-1:0] a;

    integer i;

    onehot2int = 0;

    for (i=0; i<WAYS; i++)
      if (a[i]) onehot2int = i;
  endfunction: onehot2int


  function automatic [XLEN/8-1:0] size2be;
    input [     2:0] size;
    input [XLEN-1:0] adr;

    logic [$clog2(XLEN/8)-1:0] adr_lsbs;

    adr_lsbs = adr[$clog2(XLEN/8)-1:0];

    unique case (size)
      BYTE : size2be = 'h1  << adr_lsbs;
      HWORD: size2be = 'h3  << adr_lsbs;
      WORD : size2be = 'hf  << adr_lsbs;
      DWORD: size2be = 'hff << adr_lsbs;
    endcase
  endfunction: size2be


  function automatic [XLEN-1:0] be_mux;
    input [XLEN/8-1:0] be;
    input [XLEN  -1:0] o; //old data
    input [XLEN  -1:0] n; //new data

    integer i;

    for (i=0; i<XLEN/8;i++)
      be_mux[i*8 +: 8] = be[i] ? n[i*8 +: 8] : o[i*8 +: 8];
  endfunction: be_mux


  //////////////////////////////////////////////////////////////////
  //
  // Typedefs
  //


  //////////////////////////////////////////////////////////////////
  //
  // Variables
  //


  /* Memory Interface State Machine Section
   */
  logic [XLEN         -1:0] cache_q;
  logic                     cache_ack,
                            biu_cacheable_ack;

  logic                     biu_cache_we_unstall;


  enum logic [2:0] {ARMED=0,
                    FLUSH,
                    NONCACHEABLE,
                    WAIT4BIUCMD0,
                    RECOVER} memfsm_state;


  logic [PLEN          -1:0] biu_adro;
  logic                      biu_adro_eq_cache_adr_dly;
  logic [DAT_OFFS_BITS -1:0] dat_offset;


  //////////////////////////////////////////////////////////////////
  //
  // Module Body
  //

  //State Machine
  always @(posedge clk_i, negedge rst_ni)
    if (!rst_ni)
    begin
        memfsm_state <= ARMED;
        armed_o      <= 1'b1;
        flushing_o   <= 1'b0;
        filling_o    <= 1'b0;
        fill_way_o   <=  'hx;
        biucmd_o     <= BIUCMD_NOP;
    end
    else
    unique case (memfsm_state)
       ARMED        : if (cacheflush_req_i)
                      begin
                          memfsm_state <= FLUSH;
                          armed_o      <= 1'b0;
                          flushing_o   <= 1'b1;
                      end
		      else if (req_i && !is_cacheable_i && !flush_i)
                      begin
                          memfsm_state <= NONCACHEABLE;
                          armed_o      <= 1'b0;
                      end
                      else if (req_i && is_cacheable_i && !cache_hit_i && !flush_i)
                      begin
                          //Load way
                          memfsm_state <= WAIT4BIUCMD0;
                          biucmd_o     <= BIUCMD_READWAY;
                          armed_o      <= 1'b0;
                          filling_o    <= 1'b1;
                          fill_way_o   <= fill_way_i;
                      end
                      else
                      begin
                          biucmd_o <= BIUCMD_NOP;
                      end

       FLUSH        : if (dcflush_rdy_i) //wait for data-cache to complete flushing
                      begin
                          memfsm_state <= RECOVER; //allow to read new tag_idx
                          flushing_o   <= 1'b0;
                      end

        NONCACHEABLE: if ( flush_i                                   ||  //flushed pipe, no biu_ack's will come
	                  (!req_i && inflight_cnt_i==1 && biu_ack_i) ||  //no new request, wait for BIU to finish transfer
                          ( req_i && is_cacheable_i    && biu_ack_i) )   //new cacheable request, wait for non-cacheable transfer to finish
                      begin
                          memfsm_state <= ARMED;
                          armed_o      <= 1'b1;
                      end

        WAIT4BIUCMD0: if (biucmd_ack_i || biu_err_i)
                      begin
                          memfsm_state <= RECOVER;
                          biucmd_o     <= BIUCMD_NOP;
                          filling_o    <= 1'b0;
                      end

        RECOVER     : begin
                          //Read TAG and DATA memory after writing/filling
                          memfsm_state <= ARMED;
                          biucmd_o     <= BIUCMD_NOP;
                          armed_o      <= 1'b1;
                      end
    endcase



  //Tag/Dat-index (for writing)
  assign idx_o = adr_i[BLK_OFFS_BITS +: IDX_BITS];


  //core-tag (for writing)
  assign core_tag_o = adr_i[XLEN-1 -: TAG_BITS];



  //non-cacheable access
  always_comb
    unique case (memfsm_state)
      FLUSH       : biucmd_noncacheable_req_o = 1'b0;
      WAIT4BIUCMD0: biucmd_noncacheable_req_o = 1'b0;
      RECOVER     : biucmd_noncacheable_req_o = 1'b0;
      default     : biucmd_noncacheable_req_o = req_i & ~is_cacheable_i & ~flush_i;
    endcase


  //Instruction fetch address
  assign biucmd_adri_o = ~is_cacheable_i
                       ? adr_i & (XLEN==64 ? ~'h7 : ~'h3)
                       : adr_i;
  assign biucmd_tagi_o = adr_i[1 +: BIUTAG_SIZE];


  //re-assemble biu_adro
  assign biu_adro = {biu_adro_i[PLEN-1:BIUTAG_SIZE+1], biu_tago_i, 1'b0};

  //address check, used in a few places
  assign biu_adro_eq_cache_adr_dly = (biu_adro[PLEN-1:BURST_LSB] == adr_i[PLEN-1:BURST_LSB]);


  //Cache core halt signal
  always_comb
    unique case (memfsm_state)
      ARMED       : stall_o =  req_i & (is_cacheable_i ? ~cache_hit_i : ~biu_stb_ack_i);

      //req_i == 0 ? stall=|inflight_cnt
      //else is_cacheable ? stall=!biu_ack_i (wait for noncacheable transfer to finish)
      //else                stall=!biu_stb_ack_i
      NONCACHEABLE: stall_o = ~req_i ? |inflight_cnt_i
	                             : is_cacheable_i ? ~biu_ack_i : ~biu_stb_ack_i;

      //TODO: Add in_biubuffer
      WAIT4BIUCMD0: stall_o = ~( (req_i & biu_ack_i & biu_adro_eq_cache_adr_dly & ~biucmd_ack_i) |
                                 (req_i & cache_hit_i)
	                       );

      RECOVER     : stall_o = ~( biu_cache_we_unstall |
	                         (req_i & cache_hit_i)
                               );
      default     : stall_o = 1'b0;
    endcase


  //signal downstream the BIU reported an error
  assign parcel_error_o = biu_err_i;


  //Assign parcel_pc
//  assign parcel_pc_o = { {XLEN-PLEN{1'b0}}, biu_adro_i };
  assign parcel_pc_o = { {XLEN-PLEN{1'b0}}, biu_adro};


  //Shift amount for data
  assign dat_offset = adr_i[BLK_OFFS_BITS-1 -: DAT_OFFS_BITS];

  //Assign parcel_o
  assign cache_q = (in_biubuffer_i ? biubuffer_i : cache_line_i) >> (dat_offset * XLEN);

  always_comb
    unique case (memfsm_state)
      WAIT4BIUCMD0: parcel_o = cache_hit_i    ? cache_q : biu_q_i;
      default     : parcel_o = is_cacheable_i ? cache_q : biu_q_i;
    endcase


  //acknowledge cache hit
  assign cache_ack         =  req_i & is_cacheable_i & cache_hit_i & ~flush_i;
  assign biu_cacheable_ack = (req_i & biu_ack_i & biu_adro_eq_cache_adr_dly & ~flush_i) |
                              cache_ack;


  //Assign parcel_valid
  always_comb
    unique case (memfsm_state)
/*    
      ARMED       : parcel_valid_o = is_cacheable_i ? {$bits(parcel_valid_o){cache_ack            }} << adr_i      [1 +: $clog2(XLEN/PARCEL_SIZE)]
                                                    : {$bits(parcel_valid_o){biu_ack_i}} << parcel_pc_o[1 +: $clog2(XLEN/PARCEL_SIZE)];
*/
      ARMED       : parcel_valid_o = {$bits(parcel_valid_o){cache_ack                }} << adr_i      [1 +: $clog2(XLEN/PARCEL_SIZE)]; 
      NONCACHEABLE: parcel_valid_o = {$bits(parcel_valid_o){biucmd_noncacheable_ack_i}} << parcel_pc_o[1 +: $clog2(XLEN/PARCEL_SIZE)];
      WAIT4BIUCMD0: parcel_valid_o = {$bits(parcel_valid_o){biu_cacheable_ack        }} << adr_i      [1 +: $clog2(XLEN/PARCEL_SIZE)];
      RECOVER     : parcel_valid_o = {$bits(parcel_valid_o){cache_ack                }} << adr_i      [1 +: $clog2(XLEN/PARCEL_SIZE)];
      default     : parcel_valid_o = {$bits(parcel_valid_o){1'b0}};
    endcase    


  //unstall when parcel was valid during Cache Memory write
  always @(posedge clk_i)
    biu_cache_we_unstall = req_i & biu_adro_eq_cache_adr_dly & biucmd_ack_i & |parcel_valid_o;


  always_comb
    unique case (memfsm_state)
      WAIT4BIUCMD0: parcel_misaligned_o = (HAS_RVC != 0) ? adr_i[0] : |adr_i[1:0];
      default     : parcel_misaligned_o = is_cacheable_i ? (HAS_RVC != 0) ? adr_i[0]       : |adr_i[1:0]
	                                                 : (HAS_RVC != 0) ? parcel_pc_o[0] : |parcel_pc_o[1:0]; 
    endcase


endmodule



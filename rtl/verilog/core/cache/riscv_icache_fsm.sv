/////////////////////////////////////////////////////////////////////
//   ,------.                    ,--.                ,--.          //
//   |  .--. ' ,---.  ,--,--.    |  |    ,---. ,---. `--' ,---.    //
//   |  '--'.'| .-. |' ,-.  |    |  |   | .-. | .-. |,--.| .--'    //
//   |  |\  \ ' '-' '\ '-'  |    |  '--.' '-' ' '-' ||  |\ `--.    //
//   `--' '--' `---'  `--`--'    `-----' `---' `-   /`--' `---'    //
//                                             `---'               //
//    RISC-V                                                       //
//    Instruction Cache FSM                                        //
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


module riscv_icache_fsm
import riscv_cache_pkg::*;
import biu_constants_pkg::*;
#(
  parameter XLEN           = 32,
  parameter PLEN           = XLEN == 32 ? 34 : 56,
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
  localparam TAG_BITS      = no_of_tag_bits(PLEN, IDX_BITS, BLK_OFFS_BITS),
  localparam INFLIGHT_BITS = $clog2(INFLIGHT_DEPTH+1)
)
(
  input  logic                        rst_ni,
  input  logic                        clk_i,

  output logic                        stall_o,
  input  logic                        flush_i,                 //flush pipe

  input  logic                        invalidate_i,            //invalidate cache
  input  logic                        dc_clean_rdy_i,          //data cache clean ready

  output logic                        armed_o,
  output logic                        invalidate_all_blocks_o, //invalidate all cache valid bits
  output logic                        filling_o,
  input  logic [WAYS            -1:0] fill_way_i,
  output logic [WAYS            -1:0] fill_way_o,

  input  logic                        req_i,                   //from previous-stage
  input  logic [PLEN            -1:0] adr_i,
  input  biu_size_t                   size_i,
  input  logic                        lock_i,
  input  biu_prot_t                   prot_i,
  input  logic                        cacheable_i,
  input  logic                        misaligned_i,
  input  logic                        pma_exception_i,
  input  logic                        pmp_exception_i,
  input  logic                        pagefault_i,

  input  logic                        cache_hit_i,             //from cache-memory
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

  output logic [XLEN            -1:0] parcel_o,
  output logic [XLEN/PARCEL_SIZE-1:0] parcel_valid_o,
  output logic                        parcel_error_o,
  output logic                        parcel_misaligned_o,
  output logic                        parcel_pagefault_o
);

  //////////////////////////////////////////////////////////////////
  //
  // Constants
  //
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
  logic [XLEN          -1:0] cache_q;
  logic                      cache_ack;
  logic                      biu_cacheable_ack;
  logic                      invalidate_hold;
  logic                      pma_pmp_exception;
  logic                      valid_req;

  enum logic [2:0] {ARMED=0,
                    INVALIDATE,
                    NONCACHEABLE,
                    READ,
                    RECOVER0,
                    RECOVER1 } memfsm_state;

  logic [PLEN          -1:0] biu_adro;
  logic                      biu_adro_eq_cache_adr_dly;
  logic [DAT_OFFS_BITS -1:0] dat_offset;


  //////////////////////////////////////////////////////////////////
  //
  // Module Body
  //

  assign pma_pmp_exception = pma_exception_i | pmp_exception_i;
  assign valid_req         = req_i & ~pma_pmp_exception & ~misaligned_i & ~pagefault_i & ~flush_i;


  //hold flush until ready to be serviced
  always @(posedge clk_i, negedge rst_ni)
    if (!rst_ni) invalidate_hold <= 1'b0;
    else         invalidate_hold <= invalidate_i | (invalidate_hold & ~invalidate_all_blocks_o);


  //State Machine
  always @(posedge clk_i, negedge rst_ni)
    if (!rst_ni)
    begin
        memfsm_state            <= ARMED;
        armed_o                 <= 1'b1;
        invalidate_all_blocks_o <= 1'b0;
        filling_o               <= 1'b0;
        fill_way_o              <=  'hx;
        biucmd_o                <= BIUCMD_NOP;
    end
    else
    unique case (memfsm_state)
       ARMED        : if (invalidate_i | invalidate_hold)
                      begin
                          memfsm_state            <= INVALIDATE;
                          armed_o                 <= 1'b0;
                          invalidate_all_blocks_o <= 1'b1;
                      end
		      else if (valid_req && !cacheable_i)
                      begin
                          memfsm_state <= NONCACHEABLE;
                          armed_o      <= 1'b0;
                      end
                      else if (valid_req && cacheable_i && !cache_hit_i)
                      begin
                          //Load way
                          memfsm_state <= READ;
                          biucmd_o     <= BIUCMD_READWAY;
                          armed_o      <= 1'b0;
                          filling_o    <= 1'b1;
                          fill_way_o   <= fill_way_i;
                      end
                      else
                      begin
                          biucmd_o <= BIUCMD_NOP;
                      end

       INVALIDATE   : if (dc_clean_rdy_i) //wait for data-cache to complete cleaning
                      begin
                          memfsm_state            <= RECOVER0; //allow to read new tag_idx
                          invalidate_all_blocks_o <= 1'b0;
                      end

        NONCACHEABLE: if ( flush_i                                       ||  //flush pipe, no biu_ack's will come
	                  (!valid_req && inflight_cnt_i==1 && biu_ack_i) ||  //no new request, wait for BIU to finish transfer
                          ( valid_req && cacheable_i       && biu_ack_i) )   //new cacheable request, wait for non-cacheable transfer to finish
                      begin
                          memfsm_state <= ARMED;
                          armed_o      <= 1'b1;
                      end

        READ        : begin
                          biucmd_o <= BIUCMD_NOP;

                          if (biucmd_ack_i || biu_err_i)
                          begin
                              memfsm_state <= RECOVER0;
                              filling_o    <= 1'b0;
                          end
                      end

        RECOVER0    : begin
                          //Setup TAG and DATA IDX after writing/filling
			  memfsm_state <= RECOVER1;
			  biucmd_o     <= BIUCMD_NOP;
                      end

        RECOVER1    : begin
                          //Read TAG and DATA memory after writing/filling
                          memfsm_state <= ARMED;
                          biucmd_o     <= BIUCMD_NOP;
                          armed_o      <= 1'b1;
                      end

    endcase



  //Tag/Dat-index (for writing)
  assign idx_o = adr_i[BLK_OFFS_BITS +: IDX_BITS];


  //core-tag (for writing)
  assign core_tag_o = adr_i[PLEN-1 -: TAG_BITS];



  //non-cacheable access
  always_comb
    unique case (memfsm_state)
      INVALIDATE: biucmd_noncacheable_req_o = 1'b0;
      READ      : biucmd_noncacheable_req_o = 1'b0;
      RECOVER0  : biucmd_noncacheable_req_o = 1'b0;
      RECOVER1  : biucmd_noncacheable_req_o = 1'b0;
      default   : biucmd_noncacheable_req_o = valid_req & ~cacheable_i & ~(invalidate_i | invalidate_hold);
    endcase


  //Instruction fetch address
  assign biucmd_adri_o = ~cacheable_i
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
      ARMED       : stall_o = (invalidate_i | invalidate_hold) |
                              (valid_req & (cacheable_i ? ~cache_hit_i : ~biu_stb_ack_i));

      //req_i == 0 ? stall=|inflight_cnt
      //else is_cacheable ? stall=!biu_ack_i (wait for noncacheable transfer to finish)
      //else                stall=!biu_stb_ack_i
      NONCACHEABLE: stall_o = ~valid_req ? |inflight_cnt_i
	                                 : cacheable_i ? ~biu_ack_i : ~biu_stb_ack_i;

      //TODO: Add in_biubuffer
      READ        : stall_o = ~( (valid_req & biu_ack_i & biu_adro_eq_cache_adr_dly) |
                                 (valid_req & cache_hit_i)
                               );

      RECOVER0    : stall_o = 1'b1;

      RECOVER1    : stall_o = 1'b1;

      INVALIDATE  : stall_o = 1'b1;

      default     : stall_o = 1'b0;
    endcase


 

  //Shift amount for data
  assign dat_offset = adr_i[BLK_OFFS_BITS-1 -: DAT_OFFS_BITS];

  //Assign parcel_o
  assign cache_q = (in_biubuffer_i ? biubuffer_i : cache_line_i) >> (dat_offset * XLEN);

  always_comb
    unique case (memfsm_state)
      READ   : parcel_o = cache_hit_i ? cache_q : biu_q_i;
      default: parcel_o = cacheable_i ? cache_q : biu_q_i;
    endcase


  //acknowledge cache hit
  assign cache_ack         =  valid_req & cacheable_i & cache_hit_i & ~(invalidate_i | invalidate_hold);
  assign biu_cacheable_ack = (valid_req & biu_ack_i & biu_adro_eq_cache_adr_dly) |
                              cache_ack;


  //Assign parcel_valid
  always_comb
    unique case (memfsm_state)
      ARMED       : parcel_valid_o = {$bits(parcel_valid_o){cache_ack                }} << adr_i   [1 +: $clog2(XLEN/PARCEL_SIZE)]; 
      NONCACHEABLE: parcel_valid_o = {$bits(parcel_valid_o){biucmd_noncacheable_ack_i}} << biu_adro[1 +: $clog2(XLEN/PARCEL_SIZE)];
      READ        : parcel_valid_o = {$bits(parcel_valid_o){biu_cacheable_ack        }} << adr_i   [1 +: $clog2(XLEN/PARCEL_SIZE)];
      default     : parcel_valid_o = {$bits(parcel_valid_o){1'b0}};
    endcase    


 //signal downstream the BIU reported an error
  assign parcel_error_o = biu_err_i | (req_i & pma_pmp_exception);


  //generate misaligned
  assign parcel_misaligned_o = req_i & misaligned_i;


  //generate pagefault
  assign parcel_pagefault_o = req_i & pagefault_i;

endmodule



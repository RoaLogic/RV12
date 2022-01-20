/////////////////////////////////////////////////////////////////////
//   ,------.                    ,--.                ,--.          //
//   |  .--. ' ,---.  ,--,--.    |  |    ,---. ,---. `--' ,---.    //
//   |  '--'.'| .-. |' ,-.  |    |  |   | .-. | .-. |,--.| .--'    //
//   |  |\  \ ' '-' '\ '-'  |    |  '--.' '-' ' '-' ||  |\ `--.    //
//   `--' '--' `---'  `--`--'    `-----' `---' `-   /`--' `---'    //
//                                             `---'               //
//    RISC-V                                                       //
//    Cache Bus Interface Statemachine                             //
//                                                                 //
/////////////////////////////////////////////////////////////////////
//                                                                 //
//             Copyright (C) 2021 ROA Logic BV                     //
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

module riscv_cache_biu_ctrl #(
  parameter                        XLEN           = 32,
  parameter                        PLEN           = XLEN,

  parameter                        SIZE           = 64,
  parameter                        BLOCK_SIZE     = XLEN,
  parameter                        WAYS           = 2,

  parameter                        INFLIGHT_DEPTH = 2,
  parameter                        BIUTAG_SIZE    = 2,

  localparam                       BLK_BITS      = no_of_block_bits(BLOCK_SIZE),
  localparam                       INFLIGHT_BITS = $clog2(INFLIGHT_DEPTH+1)
)
(
  input  logic                     rst_ni,
  input  logic                     clk_i,

  input  logic                     flush_i,              //flush pipe

  input  biucmd_t                  biucmd_i,
  output logic                     biucmd_ack_o,
  output logic                     biucmd_busy_o,
  input  logic                     biucmd_noncacheable_req_i,
  output logic                     biucmd_noncacheable_ack_o,
  input  logic [BIUTAG_SIZE  -1:0] biucmd_tag_i,
  output logic [INFLIGHT_BITS-1:0] inflight_cnt_o,

  input  logic                     req_i,
  input  logic [PLEN         -1:0] adr_i,
  input  biu_size_t                size_i,
  input  biu_prot_t                prot_i,
  input  logic                     lock_i,
  input  logic                     we_i,
  input  logic [XLEN/8       -1:0] be_i,
  input  logic [XLEN         -1:0] d_i,

  input  logic [PLEN         -1:0] evictbuffer_adr_i,
  input  logic [BLK_BITS     -1:0] evictbuffer_d_i,
  output logic                     in_biubuffer_o,
  output logic [BLK_BITS     -1:0] biubuffer_o,          //data to cache-ctrl
  output logic [BLK_BITS     -1:0] biu_line_o,           //data to be written in DAT memory
  output logic                     biu_line_dirty_o,     //data to be written into DAT memory is dirty


  //To BIU
  output logic                     biu_stb_o,            //access request
  input  logic                     biu_stb_ack_i,        //access acknowledge
  input  logic                     biu_d_ack_i,          //BIU needs new data (biu_d_o)
  output logic [PLEN         -1:0] biu_adri_o,           //access start address
  input  logic [PLEN         -1:0] biu_adro_i,
  output biu_size_t                biu_size_o,           //transfer size
  output biu_type_t                biu_type_o,           //burst type
  output logic                     biu_lock_o,           //locked transfer
  output biu_prot_t                biu_prot_o,           //protection bits
  output logic                     biu_we_o,             //write enable
  output logic [XLEN         -1:0] biu_d_o,              //write data
  input  logic [XLEN         -1:0] biu_q_i,              //read data
  input  logic                     biu_ack_i,            //transfer acknowledge
  input  logic                     biu_err_i,            //transfer error
  output logic [BIUTAG_SIZE  -1:0] biu_tagi_o,
  input  logic [BIUTAG_SIZE  -1:0] biu_tago_i
);

  //////////////////////////////////////////////////////////////////
  //
  // Constants
  //
  localparam SETS          = no_of_sets(SIZE, BLOCK_SIZE, WAYS);
  localparam BLK_OFFS_BITS = no_of_block_offset_bits(BLOCK_SIZE);
  localparam DAT_OFFS_BITS = no_of_data_offset_bits(XLEN, BLK_BITS);
  localparam BURST_SIZE    = burst_size(XLEN, BLK_BITS);

  localparam BURST_BITS = $clog2(BURST_SIZE);
  localparam BURST_OFFS = XLEN / 8;
  localparam BURST_LSB  = $clog2(BURST_OFFS);


  //////////////////////////////////////////////////////////////////
  //
  // Functions
  //

  //convert burst type to counter length (actually length -1)
  function automatic [3:0] biu_type2cnt;
    input biu_type_t biu_type;

    case (biu_type)
      SINGLE : biu_type2cnt =  0;
      INCR   : biu_type2cnt =  0;
      WRAP4  : biu_type2cnt =  3;
      INCR4  : biu_type2cnt =  3;
      WRAP8  : biu_type2cnt =  7;
      INCR8  : biu_type2cnt =  7;
      WRAP16 : biu_type2cnt = 15;
      INCR16 : biu_type2cnt = 15;
      default: biu_type2cnt = 4'hx; //OOPS
    endcase
  endfunction: biu_type2cnt


  //Byte-Enable driven MUX
  function automatic [XLEN-1:0] be_mux;
    input [XLEN/8-1:0] be;
    input [XLEN  -1:0] data_old; //old data
    input [XLEN  -1:0] data_new; //new data

    for (int i=0; i<XLEN/8;i++)
      be_mux[i*8 +: 8] = be[i] ? data_new[i*8 +: 8] : data_old[i*8 +: 8];
  endfunction: be_mux



  //////////////////////////////////////////////////////////////////
  //
  // Variables
  //
  genvar  way;
  integer n;


  /* Bus Interface State Machine Section
   */
  enum logic [               1:0] {IDLE, WAIT4BIU, BURST} biufsm_state;

  logic      [BURST_SIZE    -1:0] biubuffer_valid;
  logic                           biubuffer_dirty;
  logic      [DAT_OFFS_BITS -1:0] dat_offset;

  logic                           biu_adro_eq_cache_adr;
  logic      [XLEN          -1:0] biu_q;

  logic      [PLEN          -1:0] biu_adri_hold;
  logic      [XLEN          -1:0] biu_d_hold;
  logic                           biu_we_hold;

  logic      [BURST_BITS    -1:0] burst_cnt;

  logic      [INFLIGHT_BITS -1:0] discard;
 


  //////////////////////////////////////////////////////////////////
  //
  // Module Body
  //


  always @(posedge clk_i, negedge rst_ni)
    if (!rst_ni)
    begin
        biufsm_state <= IDLE;
        biucmd_busy_o <= 1'b0;
    end
    else
    begin
        unique case (biufsm_state)
          IDLE    : unique case (biucmd_i)
                      BIUCMD_NOP      : ; //do nothing
                                          //non-cacheable transfers may be initiated

                      BIUCMD_READWAY : begin
                                           biucmd_busy_o <= 1'b1;

                                           //read a way from main memory
                                           if (biu_stb_ack_i)
                                           begin
                                               biufsm_state <= BURST;
                                           end
                                           else
                                           begin
                                               //BIU is not ready to start a new transfer
                                               biufsm_state <= WAIT4BIU;
                                           end
                                       end

                      BIUCMD_WRITEWAY: begin
                                           biucmd_busy_o <= 1'b1;

                                           //write way back to main memory
                                           if (biu_stb_ack_i)
                                           begin
                                               biufsm_state <= BURST;
                                           end
                                           else
                                           begin
                                               //BIU is not ready to start a new transfer
                                               biufsm_state <= WAIT4BIU;
                                           end
                                       end
                       endcase

          WAIT4BIU : if (biu_stb_ack_i)
                     begin
                         //BIU acknowledged burst transfer
                         biufsm_state <= BURST;
                     end

          BURST    : if (biu_err_i || (~|burst_cnt && biu_ack_i))
                     begin
                         //write complete
                         biufsm_state  <= IDLE; //TODO: detect if another BURST request is pending, skip IDLE
                         biucmd_busy_o <= 1'b0;
                     end
        endcase
    end



  //address check, used in a few places
  assign biu_adro_eq_cache_adr = (biu_adro_i[PLEN-1:BURST_LSB] == adr_i[PLEN-1:BURST_LSB]);


  //handle writing bits in read-cache-line
  assign biu_q = we_i && biu_adro_eq_cache_adr ? be_mux(be_i, biu_q_i, d_i)
                                               : biu_q_i;

  //BIU Buffer
  always @(posedge clk_i)
    unique case (biufsm_state)
     IDLE   : begin
                  if (biucmd_i == BIUCMD_WRITEWAY) biubuffer_o <= evictbuffer_d_i >> XLEN;
                  biubuffer_valid <=  'h0;
		  biubuffer_dirty <= 1'b0;
              end

     BURST  : begin
                  if (!biu_we_hold)
                  begin
                      if (biu_ack_i)   //latch incoming data when transfer-acknowledged
                      begin
                          biubuffer_o    [ biu_adro_i[BLK_OFFS_BITS-1 -: DAT_OFFS_BITS] * XLEN +: XLEN ] <= biu_q;
                          biubuffer_valid[ biu_adro_i[BLK_OFFS_BITS-1 -: DAT_OFFS_BITS] ]                <= 1'b1;
                          biubuffer_dirty                                                                <= biubuffer_dirty | we_i; //& biu_adro_eq_cache_adr_dly
                      end
                  end
		  else
                  begin
                      if (biu_d_ack_i)
                      begin
                          biubuffer_o     <= biubuffer_o >> XLEN; //next data to transfer (to BIU)
                          biubuffer_valid <=  'h0;
                          biubuffer_dirty <= 1'b0;
                      end
                  end
              end
      default: ;
    endcase


  //Shift amount for data
  assign dat_offset = adr_i[BLK_OFFS_BITS-1 -: DAT_OFFS_BITS];


  //Is requested data in biubuffer?
  assign in_biubuffer_o = req_i & (biu_adri_hold[PLEN-1:BLK_OFFS_BITS] == adr_i[PLEN-1:BLK_OFFS_BITS]) & (biubuffer_valid >> dat_offset);


  //Data to be written into DAT memory
  //Data is in biubuffer, except for last transaction
  always_comb
    begin
        biu_line_o = biubuffer_o;
        biu_line_o[ biu_adro_i[BLK_OFFS_BITS-1 -: DAT_OFFS_BITS] * XLEN +: XLEN] = biu_q;
    end

  assign biu_line_dirty_o = biubuffer_dirty | we_i;


  //Acknowledge burst to memfsm
  always_comb
    unique case (biufsm_state)
      BURST   : biucmd_ack_o = (~|burst_cnt & biu_ack_i ) | biu_err_i;
      default : biucmd_ack_o = 1'b0;
    endcase


  always @(posedge clk_i)
    unique case (biufsm_state)
      IDLE  : burst_cnt <= {BURST_BITS{1'b1}};
      BURST : if (biu_ack_i) burst_cnt <= burst_cnt -1;
    endcase


  //Keep track of inflight transactions
  always @(posedge clk_i, negedge rst_ni)
    if      (!rst_ni) inflight_cnt_o <= 'h0;
    else
      unique case ({biu_stb_ack_i, biu_ack_i | biu_err_i})
        2'b01  : inflight_cnt_o <= inflight_cnt_o -1;
        2'b10  : inflight_cnt_o <= inflight_cnt_o +1 + biu_type2cnt(biu_type_o);
        default: ; //do nothing
      endcase

      
  always @(posedge clk_i, negedge rst_ni)
    if (!rst_ni) discard <= 'h0;
    else if (flush_i)
    begin
        if (|inflight_cnt_o && (biu_ack_i | biu_err_i)) discard <= inflight_cnt_o -1;
        else                                            discard <= inflight_cnt_o;
    end
    else if (|discard       && (biu_ack_i | biu_err_i)) discard <= discard -1;


  assign biucmd_noncacheable_ack_o = biu_ack_i & ~flush_i & ~|discard;


  //output BIU signals asynchronously for speed reasons. BIU will synchronize ...
  always_comb
    unique case (biufsm_state)
      IDLE    : unique case (biucmd_i)
                  BIUCMD_NOP      : begin
                                        biu_stb_o  = biucmd_noncacheable_req_i;
                                        biu_adri_o = adr_i[0 +: PLEN];
                                        biu_we_o   = we_i;
                                        biu_d_o    = d_i;
                                    end

                  BIUCMD_READWAY  : begin
                                        biu_stb_o  = 1'b1;
                                        biu_adri_o = {adr_i[PLEN-1 : BURST_LSB],{BURST_LSB{1'b0}}};
                                        biu_we_o   = 1'b0;
                                        biu_d_o    =  'hx;
                                    end

                  BIUCMD_WRITEWAY : begin
                                        biu_stb_o  = 1'b1;
                                        biu_adri_o = evictbuffer_adr_i;
                                        biu_we_o   = 1'b1;
                                        biu_d_o    = evictbuffer_d_i[0 +: XLEN];
                                    end

                endcase

      WAIT4BIU: begin
                    //stretch biu_*_o signals until BIU acknowledges strobe
                    biu_stb_o  = 1'b1;
                    biu_adri_o = biu_adri_hold;
                    biu_we_o   = biu_we_hold;
                    biu_d_o    = biu_d_hold;
                end

      BURST   : begin
                    //continue burst operation
                    biu_stb_o  = 1'b0;                    //don't start new (burst) transaction
                    biu_adri_o =  'hx;                    //don't care
                    biu_we_o   = 1'bx;                    //don't care
                    biu_d_o    = biubuffer_o[0 +: XLEN];  //next data to transfer
                end

      default : begin
                    biu_stb_o  = 1'b0; //don't start a transaction
                    biu_adri_o =  'hx; //don't care
                    biu_we_o   = 1'bx; //don't care
                    biu_d_o    =  'hx; //don't care
                end
    endcase


  //store biu_we/adri/d used when stretching biu_stb
  always @(posedge clk_i)
    if (biufsm_state == IDLE)
    begin
        biu_adri_hold <= biu_adri_o;
        biu_we_hold   <= biu_we_o;
        biu_d_hold    <= biu_d_o;
    end


  //BIU TAG
  assign biu_tagi_o = biucmd_tag_i;


  //transfer size
  assign biu_size_o = biucmd_noncacheable_req_i
                    ? size_i
                    : XLEN==64 ? DWORD : WORD;

 
  //Protection bits
  assign biu_prot_o = biu_prot_t'(prot_i | (biucmd_noncacheable_req_i ? PROT_NONCACHEABLE : PROT_CACHEABLE));
  assign biu_lock_o = lock_i;
  

  //burst length
  always_comb
    if ( (biufsm_state == IDLE) && (biucmd_i == BIUCMD_NOP) )
      biu_type_o = INCR;
    else
    unique case(BURST_SIZE)
       16     : biu_type_o = WRAP16;
       8      : biu_type_o = WRAP8;
       default: biu_type_o = WRAP4;
    endcase
endmodule



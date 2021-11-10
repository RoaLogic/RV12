/////////////////////////////////////////////////////////////////////
//   ,------.                    ,--.                ,--.          //
//   |  .--. ' ,---.  ,--,--.    |  |    ,---. ,---. `--' ,---.    //
//   |  '--'.'| .-. |' ,-.  |    |  |   | .-. | .-. |,--.| .--'    //
//   |  |\  \ ' '-' '\ '-'  |    |  '--.' '-' ' '-' ||  |\ `--.    //
//   `--' '--' `---'  `--`--'    `-----' `---' `-   /`--' `---'    //
//                                             `---'               //
//    RISC-V                                                       //
//    Data Cache  (Write Back)                                     //
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

/*
  Customer should be able to chose
  - cache size
  - Set associativity
  therefore BLOCK_SIZE is autocalculated

  RISC-V specifies a 4KB page. Thus page offset = 12bits
  MAX_IDX_BITS = $clog2(4*1024) = 12

  BURST_SIZE = 16,8,4

  BLOCK_SIZE = BURST_SIZE * XLEN/8 (bytes)
    rv32:  64,32,16 bytes
    rv64: 128,64,32 bytes

  This affects associativity (the number of ways)
  BLOCK_OFFSET_BITS = $clog2(BLOCK_SIZE)
    rv32: 6,5,4 bits
    rv64: 7,6,5 bits

  IDX_BITS = MAX_IDX_BITS - BLOCK_OFFSET_BITS
    rv32: 6,7,8
    rv64: 5,6,7

  SETS = 2**IDX_BITS
    rv32: 64,128,256
    rv64: 32, 64,128

  WAYS = CACHE_SIZE / (BLOCK_SIZE * SET) = CACHE_SIZE / PAGE_SIZE
     8KB:  2
    16KB:  4
    32KB:  8
    64KB: 16
 */

import biu_constants_pkg::*;

module riscv_icache_core #(
  parameter XLEN        = 32,
  parameter PLEN        = XLEN,
  parameter PARCEL_SIZE = XLEN,
  parameter HAS_RVC     = 0,

  parameter SIZE        = 64,     //KBYTES
  parameter BLOCK_SIZE  = XLEN,   //BYTES, number of bytes in a block (way)
                                  //Must be [XLEN*2,XLEN,XLEN/2]
  parameter WAYS        =  2,     // 1           : Direct Mapped
                                  //<n>          : n-way set associative
                                  //<n>==<blocks>: fully associative
  parameter REPLACE_ALG = 0,      //0: Random
                                  //1: FIFO
                                  //2: LRU

  parameter TECHNOLOGY  = "GENERIC",

  parameter DEPTH       = 2       //number of transactions in flight
)
(
  input  logic                        rst_ni,
  input  logic                        clk_i,

  //CPU side
  input  logic                        is_cacheable_i,       //cacheable transfer?
  input  logic                        misaligned_i,
  input  logic                        mem_flush_i,
  input  logic                        mem_req_i,
  output logic                        mem_ack_o,
  input  logic [XLEN            -1:0] mem_adr_i,
  input  biu_size_t                   mem_size_i,
  input                               mem_lock_i,
  input  biu_prot_t                   mem_prot_i,
  output logic [XLEN            -1:0] parcel_pc_o,
  output logic [XLEN            -1:0] parcel_o,
  output logic [XLEN/PARCEL_SIZE-1:0] parcel_valid_o,
  output logic                        parcel_error_o,
  output logic                        parcel_misaligned_o,
  input  logic                        flush_i,              //flush (invalidate) cache
  input  logic                        flushrdy_i,           //data cache ready flushing

  //To BIU
  output logic                        biu_stb_o,            //access request
  input  logic                        biu_stb_ack_i,        //access acknowledge
  input  logic                        biu_d_ack_i,          //BIU needs new data (biu_d_o)
  output logic [PLEN            -1:0] biu_adri_o,           //access start address
  input  logic [PLEN            -1:0] biu_adro_i,
  output biu_size_t                   biu_size_o,           //transfer size
  output biu_type_t                   biu_type_o,           //burst type
  output logic                        biu_lock_o,           //locked transfer
  output biu_prot_t                   biu_prot_o,           //protection bits
  output logic                        biu_we_o,             //write enable
  output logic [XLEN            -1:0] biu_d_o,              //write data
  input  logic [XLEN            -1:0] biu_q_i,              //read data
  input  logic                        biu_ack_i,            //transfer acknowledge
  input  logic                        biu_err_i             //transfer error
);

  //////////////////////////////////////////////////////////////////
  //
  // Constants
  //
  
  //----------------------------------------------------------------
  // Cache
  //----------------------------------------------------------------
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

  //pipeline-write-buffer
  typedef struct {
    logic [IDX_BITS -1:0] idx;
    logic [PLEN     -1:0] adr;  //physical address
    logic [XLEN/8   -1:0] be;
    logic [XLEN     -1:0] data;

    //internal signals
    logic [WAYS     -1:0] hit;
    logic                 was_write;
  } pwb_t;


  //TAG-structure
  typedef struct packed {
    logic                valid;
    logic [TAG_BITS-1:0] tag;
  } tag_struct;

  localparam TAG_STRUCT_BITS = $bits(tag_struct);


  //////////////////////////////////////////////////////////////////
  //
  // Variables
  //
  genvar  way;
  integer n;


  /* Memory Interface State Machine Section
   */
  logic                                      mem_req_dly;
  logic      [XLEN           -1:0]           mem_adr_dly;
  logic                                      is_cacheable_dly;

  logic      [TAG_BITS       -1:0]           core_tag,
                                             core_tag_hold;

  logic                                      hold_flush;           //stretch flush_i until FSM is ready to serve

  enum logic [                2:0] {ARMED=0, FLUSH=1, WAIT4BIUCMD0=2, RECOVER=4} memfsm_state;


  /* Cache Section
   */
  logic      [IDX_BITS       -1:0]           tag_idx,
                                             tag_idx_dly,          //delayed version for writing valid/dirty
                                             tag_idx_hold,         //stretched version for writing TAG during fill
                                             adr_idx,              //index bits extracted from adr_i
                                             adr_dly_idx;          //index bits extracted from adr_dly

  logic      [WAYS           -1:0]           tag_we;
  tag_struct                                 tag_in      [WAYS],
                                             tag_out     [WAYS];
  logic      [IDX_BITS       -1:0]           tag_byp_idx [WAYS];
  logic      [TAG_BITS       -1:0]           tag_byp_tag [WAYS];
  logic      [WAYS           -1:0][SETS-1:0] tag_valid;

  logic      [IDX_BITS       -1:0]           dat_idx, dat_idx_dly;
  logic      [WAYS           -1:0]           dat_we;
  logic      [BLK_BITS/8     -1:0]           dat_be;
  logic      [BLK_BITS       -1:0]           dat_in;
  logic      [BLK_BITS       -1:0]           dat_out     [WAYS];

  logic      [BLK_BITS       -1:0]           way_q_mux   [WAYS];
  logic      [WAYS           -1:0]           way_hit;

  logic      [DAT_OFF_BITS   -1:0]           dat_offset;
  logic      [PARCEL_OFF_BITS  :0]           parcel_offset;

  logic                                      cache_hit;
  logic      [XLEN           -1:0]           cache_q;

  logic      [                3:0]           way_random;
  logic      [WAYS           -1:0]           fill_way_select, fill_way_select_hold; 

  logic                                      biu_adro_eq_cache_adr_dly;
  logic                                      flushing,
                                             filling;
  logic      [IDX_BITS       -1:0]           flush_idx;


  /* Bus Interface State Machine Section
   */
  enum logic [                1:0]           {IDLE, WAIT4BIU, BURST} biufsm_state;
  enum logic [                1:0]           {NOP=0, WRITE_WAY=1, READ_WAY=2} biucmd;
  logic                                      biufsm_ack,
                                             biufsm_err,
                                             biufsm_ack_write_way; //BIU FSM should generate biufsm_ack on WRITE_WAY
  logic      [BLK_BITS       -1:0]           biu_buffer;
  logic      [BURST_SIZE     -1:0]           biu_buffer_valid;
  logic                                      in_biubuffer;

  logic      [PLEN           -1:0]           biu_adri_hold;
  logic      [XLEN           -1:0]           biu_d_hold;

  logic      [BURST_BITS     -1:0]           burst_cnt;

  logic      [$clog2(DEPTH)    :0]           inflight,
	                                     discard;
  logic                                      biu_non_cacheable_ack;



  //////////////////////////////////////////////////////////////////
  //
  // Module Body
  //

  //----------------------------------------------------------------
  // Memory Interface State Machine
  //----------------------------------------------------------------

  //generate delayed mem_* signals
  always @(posedge clk_i,negedge rst_ni)
    if      (!rst_ni      ) mem_req_dly <= 1'b0;
    else if ( mem_flush_i ) mem_req_dly <= 1'b0;
    else                    mem_req_dly <= mem_req_i | (mem_req_dly & ~mem_ack_o);

    
  always @(posedge clk_i,negedge rst_ni)
    if (!rst_ni) is_cacheable_dly <= 1'b0;
    else         is_cacheable_dly <= is_cacheable_i;



  //register memory signals
  always @(posedge clk_i, negedge rst_ni)
    if      (!rst_ni   ) mem_adr_dly <= 'h0;
    else if ( mem_req_i) mem_adr_dly <= mem_adr_i;


  //extract index bits from address(es)
  assign adr_idx     = mem_adr_i  [BLK_OFF_BITS +: IDX_BITS];
  assign adr_dly_idx = mem_adr_dly[BLK_OFF_BITS +: IDX_BITS];


  //extract core_tag from address
  assign core_tag = mem_adr_i[XLEN-1 -: TAG_BITS];


  //hold core_tag during filling. Prevents new mem_req (during fill) to mess up the 'tag' value
  always @(posedge clk_i)
    if (!filling) core_tag_hold <= core_tag;


  //hold flush until ready to service it
  always @(posedge clk_i, negedge rst_ni)
    if (!rst_ni) hold_flush <= 1'b0;
    else         hold_flush <= ~flushing & (flush_i | hold_flush);


  //State Machine
  always @(posedge clk_i, negedge rst_ni)
    if (!rst_ni)
    begin
        memfsm_state <= ARMED;
        flushing     <= 1'b0;
        filling      <= 1'b0;
        biucmd       <= NOP;
    end
    else
    unique case (memfsm_state)
       ARMED        : if (flush_i || hold_flush)
                      begin
                          memfsm_state <= FLUSH;
                          flushing     <= 1'b1;
                      end
                      else if (is_cacheable_dly && mem_req_dly && !cache_hit && (mem_req_i || mem_req_dly) ) //it takes 1 cycle to read TAG
                      begin
                          //Load way
                          memfsm_state <= WAIT4BIUCMD0;
                          biucmd       <= READ_WAY;
                          filling      <= 1'b1;
                      end
                      else
                      begin
                          biucmd <= NOP;
                      end

       FLUSH        : if (flushrdy_i) 
                      begin
                          memfsm_state <= RECOVER; //allow to read new tag_idx
                          flushing     <= 1'b0;
                      end

        WAIT4BIUCMD0: if (biufsm_err)
                      begin
                          memfsm_state <= adr_idx != tag_idx_hold ? RECOVER : ARMED;
                          biucmd       <= NOP;
                          filling      <= 1'b0;
                      end
                      else if (biufsm_ack)
                      begin
                          memfsm_state <= adr_idx != tag_idx_hold ? RECOVER : ARMED;
                          biucmd       <= NOP;
                          filling      <= 1'b0;
                      end

        RECOVER     : begin
                          //Allow DATA memory read after writing/filling
                          memfsm_state <= ARMED;
                          biucmd       <= NOP;
                          filling      <= 1'b0;
                      end
    endcase


  //address check, used in a few places
  assign biu_adro_eq_cache_adr_dly = (biu_adro_i[PLEN-1:BURST_LSB] == mem_adr_i  [PLEN-1:BURST_LSB]); //mem_adr_dly!


  //signal downstream that data is ready
  always_comb
    unique case (memfsm_state)
      ARMED       : mem_ack_o = is_cacheable_dly ? mem_req_dly & (mem_req_i | mem_req_dly) & cache_hit
                                                 : biu_stb_ack_i;
      WAIT4BIUCMD0: mem_ack_o = biu_stb_ack_i;
//      WAIT4BIUCMD0: mem_ack_o = mem_req_dly & (mem_req_i | mem_req_dly) & biu_ack_i & biu_adro_eq_cache_adr_dly;
      default     : mem_ack_o = 1'b0;
    endcase


  //signal downstream the BIU reported an error
  assign parcel_error_o = biu_err_i;


  //Assign parcel_pc
  assign parcel_pc_o = { {XLEN-PLEN{1'b0}}, biu_adro_i };

  //Assign parcel_q
  always_comb
    unique case (memfsm_state)
      WAIT4BIUCMD0: parcel_o = biu_q_i;
      default     : parcel_o = is_cacheable_dly ? cache_q : biu_q_i;
    endcase


  //Assign parcel_valid
  always_comb
    unique case (memfsm_state)
      ARMED       : parcel_valid_o = is_cacheable_dly ? {$bits(parcel_valid_o){                 1'b1}} << mem_adr_dly[1 +: $clog2(XLEN/PARCEL_SIZE)]
                                                      : {$bits(parcel_valid_o){biu_non_cacheable_ack}} << parcel_pc_o[1 +: $clog2(XLEN/PARCEL_SIZE)];
      WAIT4BIUCMD0: parcel_valid_o = {$bits(parcel_valid_o){biu_non_cacheable_ack}} << parcel_pc_o[1 +: $clog2(XLEN/PARCEL_SIZE)];
      default     : parcel_valid_o = {$bits(parcel_valid_o){1'b0}};
    endcase    


  always_comb
    unique case (memfsm_state)
      WAIT4BIUCMD0: parcel_misaligned_o = (HAS_RVC != 0) ? mem_adr_dly[0] : |mem_adr_dly[1:0];
      default     : parcel_misaligned_o = is_cacheable_dly ? (HAS_RVC != 0) ? mem_adr_dly[0] : |mem_adr_dly[1:0]
	                                                   : (HAS_RVC != 0) ? parcel_pc_o[0] : |parcel_pc_o[1:0]; 
    endcase


/*
  assign if_parcel_valid_o      = dcflush_rdy_i & ~(if_flush_i | if_flush_dly) & biu_ack_i & ~|discard       ?
                                   {XLEN/PARCEL_SIZE{1'b1}} << if_parcel_pc_o[1 +: $clog2(XLEN/PARCEL_SIZE)] :
				   {XLEN/PARCEL_SIZE{1'b0}};
*/


  //----------------------------------------------------------------
  // End Memory Interface State Machine
  //----------------------------------------------------------------


  //----------------------------------------------------------------
  // TAG and Data memory
  //----------------------------------------------------------------

  /* TAG
   */
generate
  for (way=0; way<WAYS; way++)
  begin: gen_ways_tag
      //TAG is stored in RAM
      rl_ram_1rw #(
        .ABITS      ( IDX_BITS   ),
        .DBITS      ( TAG_BITS   ),
        .TECHNOLOGY ( TECHNOLOGY )
      )
      tag_ram (
        .rst_ni ( rst_ni       ),
        .clk_i  ( clk_i        ),
        .addr_i ( tag_idx      ),
        .we_i   ( tag_we [way] ),
        .be_i   ( {(TAG_BITS+7)/8{1'b1}} ),
        .din_i  ( tag_in [way].tag ),
        .dout_o ( tag_out[way].tag )
      );

      //tag-register for bypass (RAW hazard)
      always @(posedge clk_i)
        if (tag_we[way])
        begin
            tag_byp_tag[way] <= tag_in[way].tag;
            tag_byp_idx[way] <= tag_idx;
        end


      //Valid is stored in DFF
      always @(posedge clk_i, negedge rst_ni)
        if      (!rst_ni     ) tag_valid[way]          <= 'h0;
        else if ( flush_i    ) tag_valid[way]          <= 'h0;
        else if ( tag_we[way]) tag_valid[way][tag_idx] <= tag_in[way].valid;

      assign tag_out[way].valid = tag_valid[way][tag_idx_dly];


      //compare way-tag to TAG;
      assign way_hit[way] = tag_out[way].valid &
                            (core_tag == (tag_idx_dly == tag_byp_idx[way] ? tag_byp_tag[way] : tag_out[way].tag) );
  end
endgenerate

  // Generate 'hit'
  assign cache_hit = |way_hit; // & mem_vreq_dly;


  /* DATA
   */
generate
  for (way=0; way<WAYS; way++)
  begin: gen_ways_dat
      rl_ram_1rw #(
        .ABITS      ( IDX_BITS   ),
        .DBITS      ( BLK_BITS   ),
        .TECHNOLOGY ( TECHNOLOGY )
      )
      data_ram (
        .rst_ni ( rst_ni      ),
        .clk_i  ( clk_i       ),
        .addr_i ( dat_idx     ),
        .we_i   ( dat_we[way] ),
        .be_i   ( dat_be      ),
        .din_i  ( dat_in      ),
        .dout_o ( dat_out[way])
      );


      //assign way_q; Build MUX (AND/OR) structure
      if (way == 0)
        assign way_q_mux[way] =  dat_out[way] & {BLK_BITS{way_hit[way]}};
      else
        assign way_q_mux[way] = (dat_out[way] & {BLK_BITS{way_hit[way]}}) | way_q_mux[way -1];
  end
endgenerate


  //get requested data (XLEN-size) from way_q_mux(BLK_BITS-size)
  assign in_biubuffer = mem_req_dly ? (biu_adri_hold[PLEN-1:BLK_OFF_BITS] == mem_adr_dly[PLEN-1:BLK_OFF_BITS]) & (biu_buffer_valid >> dat_offset)
                                    : (biu_adri_hold[PLEN-1:BLK_OFF_BITS] == mem_adr_i  [PLEN-1:BLK_OFF_BITS]) & (biu_buffer_valid >> dat_offset);


  assign cache_q = (in_biubuffer ? biu_buffer : way_q_mux[WAYS-1]) >> (dat_offset * XLEN);


  //----------------------------------------------------------------
  // END TAG and Data memory
  //----------------------------------------------------------------


  //----------------------------------------------------------------
  // TAG and Data memory control signals
  //----------------------------------------------------------------

  //Random generator for RANDOM replacement algorithm
  always @(posedge clk_i, negedge rst_ni)
    if      (!rst_ni ) way_random <= 'h0;
    else if (!filling) way_random <= {way_random, way_random[3] ~^ way_random[2]};


  //select which way to fill
generate
  if (WAYS <= 1)
    assign fill_way_select = 1;
  else
    assign fill_way_select = 1 << way_random[$clog2(WAYS)-1:0];
endgenerate

  //FILL / WRITE_WAYS use fill_way_select 1 cycle later
  always @(posedge clk_i)
    unique case (memfsm_state)
      ARMED  : fill_way_select_hold <= fill_way_select;
      default: ;
    endcase


  //TAG Index
  always_comb
    unique case (memfsm_state)
      //TAG write
      WAIT4BIUCMD0: tag_idx = tag_idx_hold;

      //TAG read
      FLUSH       : tag_idx = flush_idx;
      RECOVER     : tag_idx = mem_req_dly ? adr_dly_idx  //pending access
                                          : adr_idx;     //new access
      default     : tag_idx = adr_idx;                   //current access
    endcase


  //registered version, for tag_valid
  always @(posedge clk_i)
    tag_idx_dly <= tag_idx;


  //hold tag-idx; prevent new mem_req_i from messing up tag during filling
  always @(posedge clk_i)
    unique case (memfsm_state)
      ARMED   : if (mem_req_dly && !cache_hit) tag_idx_hold <= adr_dly_idx;
      RECOVER : tag_idx_hold <= mem_req_dly ? adr_dly_idx  //pending access
                                            : adr_idx;     //current access
       default: ;
    endcase

generate
  //TAG Write Enable
  //Update tag during flushing    (clear valid bits)
  for (way=0; way < WAYS; way++)
  begin: gen_way_we
      always_comb
        unique case (memfsm_state)
          default: tag_we[way] = filling & fill_way_select_hold[way] & biufsm_ack; 
        endcase
  end


  //TAG Write Data
  for (way=0; way < WAYS; way++)
  begin: gen_tag
      //clear valid tag during flushing and cache-coherency checks
      assign tag_in[way].valid = ~flushing;

      assign tag_in[way].tag   = core_tag_hold;
  end
endgenerate



  //Shift amount for data
  assign dat_offset = mem_adr_dly[BLK_OFF_BITS-1 -: DAT_OFF_BITS];


  //DAT Byte Enable
  assign dat_be = {BLK_BITS/8{1'b1}};


  //DAT Index
   always_comb
     unique case (memfsm_state)
       ARMED       : dat_idx = adr_idx;                         //read access
       RECOVER     : dat_idx = mem_req_dly  ? adr_dly_idx       //read pending cycle
                                            : adr_idx;          //read new access
       default     : dat_idx = tag_idx_hold;
     endcase


  //delayed dat_idx
  always @(posedge clk_i)
    dat_idx_dly <= dat_idx;


generate
  //DAT Write Enable
  for (way=0; way < WAYS; way++)
  begin: gen_dat_we
      always_comb
        unique case (memfsm_state)
          WAIT4BIUCMD0: dat_we[way] = fill_way_select_hold[way] & biufsm_ack; //write BIU data
          default     : dat_we[way] = 1'b0;
        endcase
  end
endgenerate


  //DAT Write Data
  always_comb
    begin
        dat_in = biu_buffer;                                                          //dat_in = biu_buffer
        dat_in[ biu_adro_i[BLK_OFF_BITS-1 -: DAT_OFF_BITS] * XLEN +: XLEN] = biu_q_i; //except for last transaction
    end

   
  //----------------------------------------------------------------
  // TAG and Data memory control signals
  //----------------------------------------------------------------



  //----------------------------------------------------------------
  // Bus Interface State Machine
  //----------------------------------------------------------------
  assign biu_lock_o = 1'b0;

  //TODO
  assign biu_prot_o = biu_prot_t'( mem_prot_i | (is_cacheable_i ? PROT_CACHEABLE : PROT_NONCACHEABLE) );


  always @(posedge clk_i, negedge rst_ni)
    if (!rst_ni)
    begin
        biufsm_state <= IDLE;
    end
    else
    begin
        unique case (biufsm_state)
          IDLE    : unique case (biucmd)
                      NOP      : ; //do nothing

                      READ_WAY : begin
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

                      WRITE_WAY: begin
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
                         biufsm_state <= IDLE; //TODO: detect if another BURST request is pending, skip IDLE
                     end
        endcase
    end


  //write data
  always @(posedge clk_i)
    unique case (biufsm_state)
     IDLE   : begin
                  biu_buffer       <=  'h0;
                  biu_buffer_valid <=  'h0;
              end

     BURST  : begin
                  if (biu_ack_i)   //latch incoming data when transfer-acknowledged
                  begin
                      biu_buffer      [ biu_adro_i[BLK_OFF_BITS-1 -: DAT_OFF_BITS] * XLEN +: XLEN ] <= biu_q_i;
                      biu_buffer_valid[ biu_adro_i[BLK_OFF_BITS-1 -: DAT_OFF_BITS] ]                <= 1'b1;
                  end
              end
      default: ;
    endcase



  //acknowledge burst to memfsm
  always_comb
    unique case (biufsm_state)
      BURST   : biufsm_ack = (~|burst_cnt & biu_ack_i ) | biu_err_i;
      default : biufsm_ack = 1'b0;
    endcase


  always @(posedge clk_i)
    unique case (biufsm_state)
      IDLE  : case (biucmd)
                READ_WAY : burst_cnt <= {BURST_BITS{1'b1}};
                WRITE_WAY: burst_cnt <= {BURST_BITS{1'b1}};
              endcase
      BURST : if (biu_ack_i) burst_cnt <= burst_cnt -1;
    endcase


  assign biufsm_err = biu_err_i;


  //Keep track of inflight transactions
  always @(posedge clk_i, negedge rst_ni)
    if      (!rst_ni) inflight <= 'h0;
    else
      unique case ({biu_stb_ack_i, biu_ack_i | biu_err_i})
        2'b01  : inflight <= inflight -1;
        2'b10  : inflight <= inflight +1;
        default: ; //do nothing
      endcase

      
  always @(posedge clk_i, negedge rst_ni)
    if (!rst_ni) discard <= 'h0;
    else if (mem_flush_i)
    begin
        if (|inflight && (biu_ack_i | biu_err_i)) discard <= inflight -1;
        else                                      discard <= inflight;
    end
    else if (|discard && (biu_ack_i | biu_err_i)) discard <= discard -1;


  assign biu_non_cacheable_ack = biu_ack_i & ~mem_flush_i & ~|discard;


  //output BIU signals asynchronously for speed reasons. BIU will synchronize ...
  assign biu_d_o  = 'h0;
  assign biu_we_o = 1'b0;

  always_comb
    unique case (biufsm_state)
      IDLE    : unique case (biucmd)
                  NOP       : begin
                                  biu_stb_o  = ~is_cacheable_i & ~mem_flush_i & mem_req_i;
                                  biu_adri_o = mem_adr_i[PLEN-1:0];
                              end

                  READ_WAY  : begin
                                  biu_stb_o  = 1'b1;
                                  biu_adri_o = {mem_adr_dly[PLEN-1 : BURST_LSB],{BURST_LSB{1'b0}}};
                              end
                endcase

      WAIT4BIU: begin
                    //stretch biu_*_o signals until BIU acknowledges strobe
                    biu_stb_o  = 1'b1;
                    biu_adri_o = biu_adri_hold;
                end

      BURST   : begin
                    biu_stb_o  = 1'b0;
                    biu_adri_o =  'hx; //don't care
                end

      default : begin
                    biu_stb_o  = 1'b0;
                    biu_adri_o =  'hx; //don't care
                end
    endcase


  //store biu_we/adri/d used when stretching biu_stb
  always @(posedge clk_i)
    if (biufsm_state == IDLE)
    begin
        biu_adri_hold <= biu_adri_o;
        biu_d_hold    <= biu_d_o;
    end


  //transfer size
  assign biu_size_o = mem_size_i; // --> XLEN == 64 ? DWORD : WORD;


  //burst length
  always_comb
    if ( (biufsm_state == IDLE) && (biucmd == NOP) )
      biu_type_o = (XLEN==64 && |mem_adr_i[2:0]) ||
                   (XLEN==32 && |mem_adr_i[1:0]) ? SINGLE : INCR;
    else
    unique case(BURST_SIZE)
       16     : biu_type_o = WRAP16;
       8      : biu_type_o = WRAP8;
       default: biu_type_o = WRAP4;
    endcase
endmodule



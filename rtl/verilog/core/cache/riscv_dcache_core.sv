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


import biu_constants_pkg::*;

module riscv_dcache_core #(
  parameter XLEN        = 32,
  parameter PLEN        = XLEN,

  parameter SIZE        = 64, //KBYTES
  parameter BLOCK_SIZE  = 32, //BYTES, number of bytes in a block (way). Must be multiple of XLEN/8. And max. 16*(XLEN/8)
  parameter WAYS        =  2, // 1           : Direct Mapped
                              //<n>          : n-way set associative
                              //<n>==<blocks>: fully associative
  parameter REPLACE_ALG = 1,  //0: Random
                              //1: FIFO
                              //2: LRU

  parameter TECHNOLOGY  = "GENERIC"
)
(
  input                           rst_ni,
  input                           clk_i,
 
  //CPU side
  input                           mem_req_i,
  input      [XLEN          -1:0] mem_adr_i,
  input  biu_size_t               mem_size_i,
  input  biu_type_t               mem_type_i,
  input                           mem_lock_i,
  input  biu_prot_t               mem_prot_i,
  input      [XLEN          -1:0] mem_d_i,
  input                           mem_we_i,
  output     [XLEN          -1:0] mem_q_o,
  output                          mem_ack_o,
  output                          mem_err_o,
  input                           flush_i,
  output                          flushrdy_o,

  //To BIU
  output reg                      biu_stb_o,      //access request
  input                           biu_stb_ack_i,  //access acknowledge
  input                           biu_d_ack_i,    //BIU needs new data (biu_d_o)
  output reg [PLEN          -1:0] biu_adri_o,     //access start address
  input      [PLEN          -1:0] biu_adro_i,
  output biu_size_t               biu_size_o,     //transfer size
  output biu_type_t               biu_type_o,     //burst type
  output                          biu_lock_o,     //locked transfer
  output biu_prot_t               biu_prot_o,     //protection bits
  output reg                      biu_we_o,       //write enable
  output reg [XLEN          -1:0] biu_d_o,        //write data
  input      [XLEN          -1:0] biu_q_i,        //read data
  input                           biu_ack_i,      //transfer acknowledge
  input                           biu_err_i       //transfer error
);
  //////////////////////////////////////////////////////////////////
  //
  // Constants
  //
  
  //----------------------------------------------------------------
  // Input queue
  //----------------------------------------------------------------
  localparam QUEUE_DEPTH = 2;
  localparam QUEUE_ADDR_SIZE = $clog2(QUEUE_DEPTH);


  //----------------------------------------------------------------
  // Cache
  //----------------------------------------------------------------
  localparam SETS         = (SIZE*1024) / BLOCK_SIZE / WAYS;    //Number of sets TODO:SETS=1 doesn't work
  localparam BLK_OFF_BITS = $clog2(BLOCK_SIZE);                 //Number of BlockOffset bits
  localparam IDX_BITS     = $clog2(SETS);                       //Number of Index-bits
  localparam TAG_BITS     = XLEN - IDX_BITS - BLK_OFF_BITS;     //Number of TAG-bits
  localparam BLK_BITS     = 8*BLOCK_SIZE;                       //Total number of bits in a Block
  localparam BURST_SIZE   = BLK_BITS / XLEN;                    //Number of transfers to load 1 Block
  localparam BURST_BITS   = $clog2(BURST_SIZE);
  localparam BURST_OFF    = XLEN/8;
  localparam BURST_LSB    = $clog2(BURST_OFF);

  //BLOCK decoding
  localparam DAT_OFF_BITS = $clog2(BLK_BITS / XLEN);            //Number of abits added to Data Memory


  //Memory FIFO
  localparam MEM_FIFO_DEPTH = 4;


  //////////////////////////////////////////////////////////////////
  //
  // Functions
  //
  function automatic integer onehot2int;
    input [WAYS-1:0] a;

    integer i;

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
    input [XLEN  -1:0] a;
    input [XLEN  -1:0] b;

    integer i;

    for (i=0; i<XLEN/8;i++)
      be_mux[i*8 +: 8] = be[i] ? b[i*8 +: 8] : a[i*8 +: 8];
  endfunction: be_mux


  //////////////////////////////////////////////////////////////////
  //
  // Typedefs
  //
  typedef struct packed {
    logic [XLEN     -1:0] addr;
    biu_size_t            size;
    biu_prot_t            prot;
    logic                 we;
    logic [XLEN     -1:0] data;
  } queue_t;


  typedef struct packed {
    logic                valid;
    logic                dirty;
    logic [TAG_BITS-1:0] tag;
  } tag_struct;
  localparam TAG_STRUCT_BITS = $bits(tag_struct);


  //////////////////////////////////////////////////////////////////
  //
  // Variables
  //
  genvar  way;
  integer n;


  /* Input queue
   */
  queue_t                     queue_data[QUEUE_DEPTH];
  logic [QUEUE_ADDR_SIZE-1:0] queue_wadr;
  logic                       queue_we,
                              queue_re,
                              queue_empty,
                              queue_full;

  logic                       access_pending;

  logic                       cache_req,               //cache access request
                              cache_req_dly;           //delayed access request
  logic [XLEN           -1:0] cache_adr,               //cache access address
                              cache_adr_dly;           //delayed access address
  logic                       cache_we,                //cache access write-enable
                              cache_we_dly;            //delayed write enable
  biu_size_t                  cache_size,              //cache access transfer size
                              cache_size_dly;          //delayed transfer size
  biu_prot_t                  cache_prot;              //protection code
  logic [XLEN/8         -1:0] cache_be,                //byte enable, generated from adr+size
                              cache_be_dly;            //registered byte enable
  logic [XLEN           -1:0] cache_d,                 //cache access write data
                              cache_d_dly;             //delayed write data

  logic [XLEN           -1:0] cache_q;
  logic                       cache_ack,
                              cache_err;


  /* Memory Interface State Machine Section
   */
  logic [TAG_BITS       -1:0] core_tag,
                              core_tag_hold;

  logic                       hold_flush;              //stretch flush_i until FSM is ready to serve
  logic                       biu_adro_eq_cache_adr_dly;

  logic [IDX_BITS       -1:0] set_cnt;                 //counts sets
  enum logic [4:0] {ARMED=0, FLUSH=1, WAIT4BIUCMD1=2, WAIT4BIUCMD0=4, WAIT4BIUACK=8, RECOVER=16} memfsm_state;
  enum logic [1:0] {NOP=0, WRITE_WAY=1, READ_WAY=2} biucmd;

  logic                       flushing,
                              filling,
                              writing;



  /* Cache Section
   */
  logic      [IDX_BITS    -1:0]           tag_idx,
                                          tag_idx_reg,          //delayed version for writing valid/dirty
                                          tag_idx_hold,         //stretched version for writing TAG during fill
                                          cache_adr_idx,        //index bits extracted from cache_adr
                                          cache_adr_dly_idx;    //index bits extracted from cache_adr_dly
  logic      [WAYS        -1:0]           tag_we, tag_we_dirty;
  tag_struct                              tag_in      [WAYS],
                                          tag_out     [WAYS];
  logic      [WAYS        -1:0][SETS-1:0] tag_valid;
  logic      [WAYS        -1:0][SETS-1:0] tag_dirty;
  logic      [IDX_BITS-    1:0]           dat_idx;
  logic      [WAYS        -1:0]           dat_we;
  logic      [BLK_BITS/8  -1:0]           dat_be;
  logic      [BLK_BITS    -1:0]           dat_in;
  logic      [BLK_BITS    -1:0]           dat_out     [WAYS];
  logic      [BLK_BITS    -1:0]           way_dat_mux [WAYS];
  logic      [XLEN        -1:0]           way_dat;            //Only use XLEN bits from way_dat
  logic      [WAYS        -1:0]           way_hit;
  logic      [WAYS        -1:0]           way_dirty;

  logic      [DAT_OFF_BITS-1:0]           dat_offset,
                                          dat_in_offset;
  logic      [2*BLK_BITS  -1:0]           dat_in_rol;

  logic                                   cache_hit;
  logic                                   cache_dirty;
  logic      [XLEN        -1:0]           cache_dat;

  logic                                   cache_dat_raw_hazard;
  logic      [XLEN        -1:0]           cache_dat_raw_fixed;


  logic      [            19:0]           way_random;
  logic      [WAYS        -1:0]           fill_way_select, fill_way_select_hold; 


  /* Bus Interface State Machine Section
   */
  enum logic [             1:0] {IDLE, WAIT4BIU, BURST} biufsm_state;
  logic                         biucmd_ack,
                                biufsm_ack;
  logic      [BLK_BITS    -1:0] biu_sr;

  logic                         biu_we_hold;
  logic      [PLEN        -1:0] biu_adri_hold;
  logic      [XLEN        -1:0] biu_d_hold;
  logic      [BLK_BITS    -1:0] dat_out_fillway;
  logic      [XLEN        -1:0] biu_q;

  logic      [BURST_BITS  -1:0] burst_cnt;





  //////////////////////////////////////////////////////////////////
  //
  // Module Body
  //

  //----------------------------------------------------------------
  // Input Queue 
  //----------------------------------------------------------------
  always @(posedge clk_i,negedge rst_ni)
    if (!rst_ni) queue_wadr <= 'h0;
    else
      unique case ({queue_we,queue_re})
         2'b01  : queue_wadr <= queue_wadr -1;
         2'b10  : queue_wadr <= queue_wadr +1;
         default: ;
      endcase


  always @(posedge clk_i,negedge rst_ni)
    if (!rst_ni)
      for (n=0; n<QUEUE_DEPTH; n++) queue_data[n] <= 'h0;
    else
    unique case ({queue_we,queue_re})
       2'b01  : begin
                    for (n=0; n<QUEUE_DEPTH-1; n++)
                      queue_data[n] <= queue_data[n+1];

                    queue_data[QUEUE_DEPTH-1] <= 'h0;
                end

       2'b10  : begin
                    queue_data[queue_wadr].addr <= mem_adr_i;
                    queue_data[queue_wadr].size <= mem_size_i;
                    queue_data[queue_wadr].prot <= mem_prot_i;
                    queue_data[queue_wadr].we   <= mem_we_i;
                    queue_data[queue_wadr].data <= mem_d_i;
                end

       2'b11  : begin
                    for (n=0; n<QUEUE_DEPTH-1; n++)
                      queue_data[n] <= queue_data[n+1];

                    queue_data[QUEUE_DEPTH-1] <= 'h0;

                    queue_data[queue_wadr-1].addr <= mem_adr_i;
                    queue_data[queue_wadr-1].size <= mem_size_i;
                    queue_data[queue_wadr-1].prot <= mem_prot_i;
                    queue_data[queue_wadr-1].we   <= mem_we_i;
                    queue_data[queue_wadr-1].data <= mem_d_i;
                end
       default: ;
    endcase


  always @(posedge clk_i, negedge rst_ni)
    if (!rst_ni) queue_full <= 1'b0;
    else
      unique case ({queue_we,queue_re})
         2'b01  : queue_full <= 1'b0;
         2'b10  : queue_full <= &queue_wadr;
         default: ;
      endcase

  always @(posedge clk_i, negedge rst_ni)
    if (!rst_ni) queue_empty <= 1'b1;
    else
      unique case ({queue_we,queue_re})
         2'b01  : queue_empty <= (queue_wadr == 1);
         2'b10  : queue_empty <= 1'b0;
         default: ;
      endcase


  //control signals
  always @(posedge clk_i, negedge rst_ni)
    if (!rst_ni) access_pending <= 1'b0;
    else         access_pending <= mem_req_i | (access_pending & ~mem_ack_o);


  assign queue_we = access_pending & (mem_req_i & ~(queue_empty & mem_ack_o));
  assign queue_re = mem_ack_o & ~queue_empty;


  //queue outputs
  assign cache_req = ~access_pending ?  mem_req_i 
                                     : (mem_req_i | ~queue_empty) & mem_ack_o;
  assign cache_adr  = queue_empty ? mem_adr_i  : queue_data[0].addr;
  assign cache_size = queue_empty ? mem_size_i : queue_data[0].size;
  assign cache_prot = queue_empty ? mem_prot_i : queue_data[0].prot;
  assign cache_we   = queue_empty ? mem_we_i   : queue_data[0].we;
  assign cache_d    = queue_empty ? mem_d_i    : queue_data[0].data;

  assign mem_q_o    = cache_q;
  assign mem_ack_o  = cache_ack;
  assign mem_err_o  = cache_err;

  //----------------------------------------------------------------
  // End Input Queue 
  //----------------------------------------------------------------




  //----------------------------------------------------------------
  // Memory Interface State Machine
  //----------------------------------------------------------------

  //generate cache_* signals
  assign cache_be = size2be(cache_size, cache_adr);


  //generate delayed cache_* signals
  always @(posedge clk_i,negedge rst_ni)
    if (!rst_ni) cache_req_dly <= 'b0;
    else         cache_req_dly <= cache_req | (cache_req_dly & ~mem_ack_o);


  //register memory signals
  always @(posedge clk_i)
    if (cache_req)
    begin
        cache_adr_dly  <= cache_adr;
        cache_size_dly <= cache_size;
        cache_we_dly   <= cache_we;
        cache_be_dly   <= cache_be;
        cache_d_dly    <= cache_d;
    end


  //extract index bits from address(es)
  assign cache_adr_idx     = cache_adr    [BLK_OFF_BITS +: IDX_BITS];
  assign cache_adr_dly_idx = cache_adr_dly[BLK_OFF_BITS +: IDX_BITS];


  //extract core_tag from address
  assign core_tag = cache_adr_dly[XLEN-1 -: TAG_BITS]; //allow 1 cycle for TAG memory read 


  //hold core_tag during filling. Prevents new mem_req (during fill) to mess up the 'tag' value
  always @(posedge clk_i)
    if (!filling) core_tag_hold <= core_tag;


  //hold flush until ready to service it
  always @(posedge clk_i, negedge rst_ni)
    if (!rst_ni) hold_flush <= 1'b0;
    else         hold_flush <= ~flushing & (flush_i | hold_flush);


  //signal Instruction Cache when FLUSH is done
  assign flushrdy_o = ~(flush_i | hold_flush);

  

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
       ARMED        : if ( (flush_i || hold_flush) && !(cache_req && cache_we) && !(cache_req_dly && cache_we_dly) )
                      begin
                          memfsm_state <= FLUSH;
                          flushing     <= 1'b1;
                      end
                      else if (cache_req && !cache_we  &&  cache_req_dly && cache_we_dly)
                      begin
                          //read after write to cache memory
                          // this causes a conflict on the address bus (tag_idx, dat_idx)
                          // because writing is delayed (must check 'cache_hit' first)
                          // therefore move to RECOVER state
                          memfsm_state <= RECOVER;
//$display ("DataCache: Read-after-Write @%0t", $time);
                      end
                      else if (cache_req_dly && !cache_hit) //it takes 1 cycle to read TAG
                      begin
                          if (tag_out[ onehot2int(fill_way_select) ].valid &&
                              tag_out[ onehot2int(fill_way_select) ].dirty)
                          begin
                              //selected way is dirty, write back to upstream
                              memfsm_state <= WAIT4BIUCMD1;
                              biucmd       <= WRITE_WAY;
                          end
                          else
                          begin
                              //selected way not dirty, overwrite
                              memfsm_state <= WAIT4BIUCMD0;
                              biucmd       <= READ_WAY;
                              filling      <= 1'b1;
                          end
                      end

       FLUSH        : if (cache_dirty) 
                      begin
                          //There are dirty ways in this set
                      end
                      else
                      begin
                         memfsm_state <= ARMED;
                         flushing     <= 1'b0;
                      end

        WAIT4BIUCMD1 : if (biufsm_ack) //wait for WRITE_WAY to complete
                       begin
                           memfsm_state <= WAIT4BIUCMD0;
                           biucmd       <= READ_WAY;
                           filling      <= 1'b1;
                       end

        WAIT4BIUCMD0: if (biucmd_ack)
                      begin
                          memfsm_state <= WAIT4BIUACK;
                          biucmd       <= NOP;
                      end

        WAIT4BIUACK : if (biufsm_ack)
                      begin
                          memfsm_state <= RECOVER;
                          filling      <= 1'b0;
                      end

        RECOVER     : begin
                          //Allow DATA memory read after writing/filling
                          memfsm_state <= ARMED;
                      end
    endcase


  //address check, used in a few places
  assign biu_adro_eq_cache_adr_dly = (biu_adro_i[PLEN-1:BURST_LSB] == cache_adr_dly[PLEN-1:BURST_LSB]);


  //signal downstream that data is ready
  always_comb
    unique case (memfsm_state)
      ARMED      : cache_ack = cache_hit;
      WAIT4BIUACK: cache_ack = biu_ack_i & biu_adro_eq_cache_adr_dly;
      default    : cache_ack = 1'b0;
    endcase


  //Assign mem_q
  always_comb
    unique case (memfsm_state)
      WAIT4BIUACK: cache_q = biu_q_i; //data to CPU, no need for biu_q here, because we're reading, not writing
      default    : cache_q = cache_dat;
    endcase


  //SET counter
  always @(posedge clk_i, negedge rst_ni)
    if (!rst_ni) set_cnt <= {IDX_BITS{1'b1}};
    else
    unique case (memfsm_state)
      default: ;
    endcase

  
  //----------------------------------------------------------------
  // End Memory Interface State Machine
  //----------------------------------------------------------------


  //----------------------------------------------------------------
  // TAG and Data memory
  //----------------------------------------------------------------

  // TAG
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
        .rstn  ( rst_ni       ),
        .clk   ( clk_i        ),
        .addr  ( tag_idx      ),
        .we    ( tag_we [way] ),
        .be    ( {(TAG_BITS+7)/8{1'b1}} ),
        .din   ( tag_in [way].tag ),
        .dout  ( tag_out[way].tag )
      );

      //Valid / Dirty are stored in DFF
      always @(posedge clk_i, negedge rst_ni)
        if      (!rst_ni     ) tag_valid[way]          <= 'h0;
        else if ( tag_we[way]) tag_valid[way][tag_idx] <= tag_in[way].valid;

      assign tag_out[way].valid = tag_valid[way][tag_idx_reg];


      always @(posedge clk_i, negedge rst_ni)
        if      (!rst_ni           ) tag_dirty[way]              <= 'h0;
        else if ( tag_we_dirty[way]) tag_dirty[way][tag_idx_reg] <= tag_in[way].dirty;

      assign tag_out[way].dirty = tag_dirty[way][tag_idx_reg];


      //extract 'dirty' from tag
      assign way_dirty[way] = tag_out[way].dirty;

      //compare way-tag to TAG;
      assign way_hit[way] = tag_out[way].valid & (tag_out[way].tag == core_tag);
  end
endgenerate

  // Generate 'hit', dirty, and data block
  assign cache_hit   = |way_hit & cache_req_dly;
  assign cache_dirty = |way_dirty;

  //DATA
generate
  for (way=0; way<WAYS; way++)
  begin: gen_ways_dat
      rl_ram_1rw #(
        .ABITS      ( IDX_BITS   ),
        .DBITS      ( BLK_BITS   ),
        .TECHNOLOGY ( TECHNOLOGY )
      )
      data_ram (
        .rstn  ( rst_ni      ),
        .clk   ( clk_i       ),
        .addr  ( dat_idx     ),
        .we    ( dat_we[way] ),
        .be    ( dat_be      ),
        .din   ( dat_in      ),
        .dout  ( dat_out[way])
      );


      //assign way_dat; Build MUX (AND/OR) structure
      if (way == 0)
        assign way_dat_mux[way] =  dat_out[way] & {BLK_BITS{way_hit[way]}};
      else
        assign way_dat_mux[way] = (dat_out[way] & {BLK_BITS{way_hit[way]}}) | way_dat_mux[way -1];
  end
endgenerate


  //get requested data (XLEN-size) from way_dat_mux(BLK_BITS-size)
  assign way_dat = way_dat_mux[WAYS-1] >> (dat_offset * XLEN);

  //Handle Data Read-After-Write hazards
  always @(posedge clk_i)
  begin
      cache_dat_raw_hazard <= (cache_adr == cache_adr_dly) & (cache_req_dly & cache_we_dly) & (cache_req & ~cache_we);
      cache_dat_raw_fixed  <=  be_mux(cache_be_dly, way_dat, cache_d_dly);
  end


  assign cache_dat     = cache_dat_raw_hazard ? cache_dat_raw_fixed : way_dat;


  //----------------------------------------------------------------
  // END TAG and Data memory
  //----------------------------------------------------------------


  //----------------------------------------------------------------
  // TAG and Data memory control signals
  //----------------------------------------------------------------

  //Random generator for RANDOM replacement algorithm
  always @(posedge clk_i, negedge rst_ni)
    if      (!rst_ni ) way_random <= 'h0;
    else if (!filling) way_random <= {way_random, way_random[19] ~^ way_random[16]};


  //select which way to fill
  assign fill_way_select = (WAYS == 1) ? 1 : 1 << way_random[$clog2(WAYS)-1:0];


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
      WAIT4BIUACK: tag_idx = tag_idx_hold;                      //retain tag_idx

      //TAG read
      RECOVER    : tag_idx = cache_req_dly ? cache_adr_dly_idx  //pending access
                                           : cache_adr_idx;     //new access
      default    : tag_idx = cache_adr_idx;                     //current access
    endcase


  //registered version, for tag_valid/dirty
  always @(posedge clk_i)
    tag_idx_reg <= tag_idx;


  //hold tag-idx; prevent new cache_req from messing up tag during filling
  always @(posedge clk_i)
    unique case (memfsm_state)
      ARMED   : if (cache_req_dly && !cache_hit)
                  tag_idx_hold <= cache_adr_dly_idx;
      RECOVER : tag_idx_hold <= cache_req_dly ? cache_adr_dly_idx  //pending access
                                              : cache_adr_idx;     //current access
      default : ;
    endcase

generate
  //TAG Write Enable
  //Update tag
  // 1. during flushing    (clear valid/dirty bits)
  // 2. during cache-write (set dirty bit)
  for (way=0; way < WAYS; way++)
  begin: gen_way_we
      always_comb
        unique case (memfsm_state)
          default: tag_we[way] = filling & fill_way_select_hold[way] & biufsm_ack;
        endcase

      always_comb
        unique case (memfsm_state)
          ARMED  : tag_we_dirty[way] = way_hit[way] & cache_req_dly & cache_we_dly;
          default: tag_we_dirty[way] = filling & fill_way_select_hold[way] & biufsm_ack;
        endcase
  end


  //TAG Write Data
  for (way=0; way < WAYS; way++)
  begin: gen_tag
      assign tag_in[way].valid = ~flushing;
      assign tag_in[way].dirty = ~flushing & cache_we_dly;
      assign tag_in[way].tag   = core_tag_hold;
  end
endgenerate



  //Shift amount for data
  assign dat_offset = cache_adr_dly[BLK_OFF_BITS-1 -: DAT_OFF_BITS];


  //DAT Byte Enable
  assign dat_be = filling ? {BLK_BITS/8{1'b1}} : cache_be_dly << (dat_offset * XLEN/8);

  always @(posedge clk_i)
    unique case (memfsm_state)
      ARMED  : dat_in_offset <= dat_offset;
      default: ;
    endcase


  //DAT Index
   always_comb
     unique case (memfsm_state)
       ARMED  : dat_idx = (cache_req_dly && cache_we_dly) ? cache_adr_dly_idx   //write 1 cycle later
                                                          : cache_adr_idx;      //read new access
       RECOVER: dat_idx =  cache_req_dly                  ? cache_adr_dly_idx   //read pending cycle
                                                          : cache_adr_idx;      //read new access

       default: dat_idx = tag_idx_hold;
     endcase


generate
  //DAT Write Enable
  for (way=0; way < WAYS; way++)
  begin: gen_dat_we
      always_comb
        unique case (memfsm_state)
          WAIT4BIUACK: dat_we[way] = fill_way_select_hold[way] & biufsm_ack;
          RECOVER    : dat_we[way] = 1'b0;
          default    : dat_we[way] = way_hit[way] & cache_req_dly & cache_we_dly;
        endcase
  end
endgenerate


  //DAT Write Data
  //rotate data read from main memory. We start reading at the required address, which can be in the middle of the block
  assign dat_in_rol = {2{biu_q,biu_sr[BLK_BITS-1:XLEN]}} << (dat_in_offset * XLEN);

  always_comb
    unique case (memfsm_state)
      WAIT4BIUACK: dat_in = dat_in_rol[BLK_BITS +: BLK_BITS];
      default    : dat_in = {BURST_SIZE{cache_d_dly}};         //write 1 cycle later (check way_hit first)
    endcase


  //----------------------------------------------------------------
  // TAG and Data memory control signals
  //----------------------------------------------------------------



  //----------------------------------------------------------------
  // Bus Interface State Machine
  //----------------------------------------------------------------
  assign biu_lock_o = 1'b0;
  assign biu_prot_o = mem_prot_i;


  always @(posedge clk_i, negedge rst_ni)
    if (!rst_ni)
    begin
        biufsm_state <= IDLE;
        biucmd_ack   <= 1'b0;
    end
    else
    begin
        biucmd_ack <= 1'b0; //biucmd_ack is a single cycle strobe

        unique case (biufsm_state)
          IDLE    : unique case (biucmd)
                      NOP         : ; //do nothing

                      READ_WAY    : begin
                                        //read a way from main memory
                                        biucmd_ack <= 1'b1;

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
                         //BIU acknowledged burst transfer, go to write
                         biufsm_state <= BURST;
                     end

          BURST    : if (~|burst_cnt && biu_ack_i)
                     begin
                         //write complete
                         biufsm_state <= IDLE;
                     end
        endcase
    end


  //handle writing bits in read-cache-line
  assign biu_q = cache_we_dly && biu_adro_eq_cache_adr_dly ? be_mux(cache_be_dly, biu_q_i, cache_d_dly)
                                                           : biu_q_i;

  //write data
  always @(posedge clk_i)
    unique case (biufsm_state)
     IDLE   : biu_sr <= dat_out_fillway >> XLEN;      //first XLEN bits went out already

     BURST  : unique case (biucmd)
                WRITE_WAY: if (biu_d_ack_i) biu_sr <= {biu_q, biu_sr[BLK_BITS-1:XLEN]};
                default  : if (biu_ack_i  ) biu_sr <= {biu_q, biu_sr[BLK_BITS-1:XLEN]};
              endcase

      default: ;
    endcase


  assign dat_out_fillway = dat_out[ onehot2int(fill_way_select_hold) ];


  //acknowledge burst to memfsm
  always_comb
    unique case (biufsm_state)
      BURST   : biufsm_ack = (~|burst_cnt & biu_ack_i);
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


  //output BIU signals asynchronously for speed reasons. BIU will synchronize ...
  always_comb
    unique case (biufsm_state)
      IDLE    : unique case (biucmd)
                  NOP       : begin
                                  biu_stb_o  = 1'b0;
                                  biu_we_o   = 1'bx;
                                  biu_adri_o =  'hx;
                                  biu_d_o    =  'hx;
                              end

                  READ_WAY  : begin
                                  biu_stb_o  = 1'b1;
                                  biu_we_o   = 1'b0; //read
                                  biu_adri_o = {cache_adr_dly[PLEN-1 : BURST_LSB],{BURST_LSB{1'b0}}};
                                  biu_d_o    =  'hx;
                              end

                   WRITE_WAY: begin
                                  biu_stb_o  = 1'b1;
                                  biu_we_o   = 1'b1;
                                  biu_adri_o = {tag_out[ onehot2int(fill_way_select_hold) ].tag, cache_adr_dly_idx,{BLK_OFF_BITS{1'b0}}};
                                  biu_d_o    = dat_out_fillway[XLEN-1:0];
                              end
                endcase

      WAIT4BIU: begin
                    //stretch biu_*_o signals until BIU acknowledges strobe
                    biu_stb_o  = 1'b1;
                    biu_we_o   = biu_we_hold;
                    biu_adri_o = biu_adri_hold;
                    biu_d_o    = dat_out_fillway[XLEN-1:0]; //retain same data
                end

      BURST   : begin
                    biu_stb_o  = 1'b0;
                    biu_we_o   = 1'bx; //don't care
                    biu_adri_o =  'hx; //don't care
                    biu_d_o    = biu_sr[0 +: XLEN];
                end

      default : begin
                    biu_stb_o  = 1'b0;
                    biu_we_o   = 1'bx; //don't care
                    biu_adri_o =  'hx; //don't care
                    biu_d_o    =  'hx; //don't care
                end
    endcase


  //store biu_we/adri/d used when stretching biu_stb
  always @(posedge clk_i)
    if (biufsm_state != WAIT4BIU)
    begin
        biu_we_hold   <= biu_we_o;
        biu_adri_hold <= biu_adri_o;
        biu_d_hold    <= biu_d_o;
    end


  //transfer size
  assign biu_size_o = XLEN == 64 ? DWORD : WORD;

  //burst length
  always_comb
    unique case(BURST_SIZE)
       16     : biu_type_o = WRAP16;
       8      : biu_type_o = WRAP8;
       default: biu_type_o = WRAP4;
    endcase
endmodule



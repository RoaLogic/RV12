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

module riscv_dcache_core #(
  parameter XLEN        = 32,
  parameter PLEN        = XLEN,

  parameter SIZE        = 64,     //KBYTES
  parameter BLOCK_SIZE  = XLEN,   //BYTES, number of bytes in a block (way)
                                  //Must be [XLEN*2,XLEN,XLEN/2]
  parameter WAYS        =  2,     // 1           : Direct Mapped
                                  //<n>          : n-way set associative
                                  //<n>==<blocks>: fully associative
  parameter REPLACE_ALG = 1,      //0: Random
                                  //1: FIFO
                                  //2: LRU

  parameter TECHNOLOGY  = "GENERIC"
)
(
  input  logic            rst_ni,
  input  logic            clk_i,
 
  //CPU side
  input  logic            mem_vreq_i,
  input  logic            mem_preq_i,
  input  logic [XLEN-1:0] mem_vadr_i,
  input  logic [PLEN-1:0] mem_padr_i,
  input  biu_size_t       mem_size_i,
  input                   mem_lock_i,
  input  biu_prot_t       mem_prot_i,
  input  logic [XLEN-1:0] mem_d_i,
  input  logic            mem_we_i,
  output logic [XLEN-1:0] mem_q_o,
  output logic            mem_ack_o,
  output logic            mem_err_o,
  input  logic            flush_i,
  output logic            flushrdy_o,

  //To BIU
  output logic            biu_stb_o,      //access request
  input  logic            biu_stb_ack_i,  //access acknowledge
  input  logic            biu_d_ack_i,    //BIU needs new data (biu_d_o)
  output logic [PLEN-1:0] biu_adri_o,     //access start address
  input  logic [PLEN-1:0] biu_adro_i,
  output biu_size_t       biu_size_o,     //transfer size
  output biu_type_t       biu_type_o,     //burst type
  output logic            biu_lock_o,     //locked transfer
  output biu_prot_t       biu_prot_o,     //protection bits
  output logic            biu_we_o,       //write enable
  output logic [XLEN-1:0] biu_d_o,        //write data
  input  logic [XLEN-1:0] biu_q_i,        //read data
  input  logic            biu_ack_i,      //transfer acknowledge
  input  logic            biu_err_i       //transfer error
);

  //////////////////////////////////////////////////////////////////
  //
  // Constants
  //
  
  //----------------------------------------------------------------
  // Cache
  //----------------------------------------------------------------
  localparam PAGE_SIZE    = 4*1024;                             //4KB pages
  localparam MAX_IDX_BITS = $clog2(PAGE_SIZE) - $clog2(BLOCK_SIZE); //Maximum IDX_BITS
  

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
  localparam DAT_OFF_BITS = $clog2(BLK_BITS / XLEN);            //Byte offset in block


  //Memory FIFO
  localparam MEM_FIFO_DEPTH = 4;


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


  //return which SET has dirty WAYs
  function automatic [IDX_BITS-1:0] get_dirty_set_idx;
    input [WAYS-1:0][SETS-1:0] dirty_ways;

    logic [SETS-1:0] dirty_sets;

    //OR all ways dirty bits for a set
    for (int s=0; s < SETS; s++)
    begin
        dirty_sets[s] = 0;

        for (int w=0; w < WAYS; w++)
          dirty_sets[s] |= dirty_ways[w][s];
    end

    //Now get next dirty set
    get_dirty_set_idx = 0;

    for (int i=0; i < SETS; i++)
      if (dirty_sets[i]) get_dirty_set_idx = i;
  endfunction: get_dirty_set_idx


  //return next dirty WAY in dirty SET
  function automatic [$clog2(WAYS)-1:0] get_dirty_way_idx;
    input [WAYS-1:0][SETS-1:0] dirty_ways;
    input [IDX_BITS-1:0]       dirty_set_idx;

    get_dirty_way_idx = 0;

    for (int w=0; w < WAYS; w++)
      if (dirty_ways[w][dirty_set_idx]) get_dirty_way_idx = w;
  endfunction: get_dirty_way_idx


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


  //evict-buffer
  typedef struct packed {
    logic [PLEN    -1:0] adr;
    logic [BLK_BITS-1:0] data;
  } evict_buffer_t;


  //TAG-structure
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


  /* Memory Interface State Machine Section
   */
  logic                                   mem_vreq_dly,
                                          mem_preq_dly;
  logic      [XLEN        -1:0]           mem_vadr_dly;
  logic      [PLEN        -1:0]           mem_padr_dly;
  logic      [XLEN/8      -1:0]           mem_be,
                                          mem_be_dly;
  logic                                   mem_we_dly;
  logic      [XLEN        -1:0]           mem_d_dly;



  logic      [TAG_BITS    -1:0]           core_tag,
                                          core_tag_hold;

  logic                                   hold_flush;              //stretch flush_i until FSM is ready to serve

  enum logic [             4:0] {ARMED=0, FLUSH=1, FLUSHWAYS=2, WAIT4BIUCMD1=4, WAIT4BIUCMD0=8, RECOVER=16} memfsm_state;


  /* Cache Section
   */
  logic      [IDX_BITS    -1:0]           tag_idx,
                                          tag_idx_dly,          //delayed version for writing valid/dirty
                                          tag_idx_hold,         //stretched version for writing TAG during fill
                                          tag_dirty_write_idx,  //index for writing tag.dirty
                                          vadr_idx,             //index bits extracted from vadr_i
                                          vadr_dly_idx,         //index bits extracted from vadr_dly
                                          padr_idx,
                                          padr_dly_idx;

  logic      [WAYS        -1:0]           tag_we, tag_we_dirty;
  tag_struct                              tag_in      [WAYS],
                                          tag_out     [WAYS];
  logic      [IDX_BITS    -1:0]           tag_byp_idx [WAYS];
  logic      [TAG_BITS    -1:0]           tag_byp_tag [WAYS];
  logic      [WAYS        -1:0][SETS-1:0] tag_valid;
  logic      [WAYS        -1:0][SETS-1:0] tag_dirty;

  pwb_t                                   write_buffer;
  logic                                   in_writebuffer;

  logic      [IDX_BITS    -1:0]           dat_idx, dat_idx_dly;
  logic      [WAYS        -1:0]           dat_we;
  logic                                   dat_we_enable;
  logic      [BLK_BITS/8  -1:0]           dat_be;
  logic      [BLK_BITS    -1:0]           dat_in;
  logic      [BLK_BITS    -1:0]           dat_out     [WAYS];

  logic      [BLK_BITS    -1:0]           way_q_mux   [WAYS];
  logic      [XLEN        -1:0]           way_q;                //Only use XLEN bits from way_q
  logic      [WAYS        -1:0]           way_hit;
  logic      [WAYS        -1:0]           way_dirty;

  logic      [DAT_OFF_BITS-1:0]           dat_offset,
                                          dat_in_offset;

  logic                                   cache_hit;
  logic      [XLEN        -1:0]           cache_q;

  logic      [            19:0]           way_random;
  logic      [WAYS        -1:0]           fill_way_select, fill_way_select_hold; 

  logic                                   biu_adro_eq_cache_adr_dly;
  logic                                   flushing,
                                          filling;
  logic      [IDX_BITS    -1:0]           flush_idx;


  /* Bus Interface State Machine Section
   */
  enum logic [             1:0] {IDLE, WAIT4BIU, BURST} biufsm_state;
  enum logic [             1:0] {NOP=0, WRITE_WAY=1, READ_WAY=2} biucmd;
  logic                                   biufsm_ack,
                                          biufsm_err,
                                          biufsm_ack_write_way; //BIU FSM should generate biufsm_ack on WRITE_WAY
  logic      [XLEN        -1:0]           biu_q;
  logic      [BLK_BITS    -1:0]           biu_buffer;
  logic      [BURST_SIZE  -1:0]           biu_buffer_valid;
  logic                                   biu_buffer_dirty;
  logic                                   in_biubuffer;

  logic                                   biu_we_hold;
  logic      [PLEN        -1:0]           biu_adri_hold;
  logic      [XLEN        -1:0]           biu_d_hold;
  evict_buffer_t                          evict_buffer;
  logic                                   is_read_way,
                                          is_read_way_dly,
                                          write_evict_buffer;

  logic      [BURST_BITS  -1:0]           burst_cnt;





  //////////////////////////////////////////////////////////////////
  //
  // Module Body
  //

  //----------------------------------------------------------------
  // Memory Interface State Machine
  //----------------------------------------------------------------

  //generate cache_* signals
  assign mem_be = size2be(mem_size_i, mem_vadr_i);


  //generate delayed mem_* signals
  always @(posedge clk_i,negedge rst_ni)
    if (!rst_ni) mem_vreq_dly <= 'b0;
    else         mem_vreq_dly <= mem_vreq_i | (mem_vreq_dly & ~mem_ack_o);

  always @(posedge clk_i,negedge rst_ni)
    if (!rst_ni) mem_preq_dly <= 'b0;
    else         mem_preq_dly <= (mem_preq_i | mem_preq_dly) & ~mem_ack_o;


  //register memory signals
  always @(posedge clk_i)
    if (mem_vreq_i)
    begin
        mem_vadr_dly <= mem_vadr_i;
        mem_we_dly   <= mem_we_i;
        mem_be_dly   <= mem_be;
        mem_d_dly    <= mem_d_i;
    end

  always @(posedge clk_i)
    if (mem_preq_i) mem_padr_dly <= mem_padr_i;


  //extract index bits from virtual address(es)
  assign vadr_idx     = mem_vadr_i  [BLK_OFF_BITS +: IDX_BITS];
  assign vadr_dly_idx = mem_vadr_dly[BLK_OFF_BITS +: IDX_BITS];
  assign padr_idx     = mem_padr_i  [BLK_OFF_BITS +: IDX_BITS];
  assign padr_dly_idx = mem_padr_dly[BLK_OFF_BITS +: IDX_BITS];


  //extract core_tag from physical address
  assign core_tag = mem_padr_i[XLEN-1 -: TAG_BITS];


  //hold core_tag during filling. Prevents new mem_req (during fill) to mess up the 'tag' value
  always @(posedge clk_i)
    if (!filling) core_tag_hold <= core_tag;


  //hold flush until ready to service it
  always @(posedge clk_i, negedge rst_ni)
    if (!rst_ni) hold_flush <= 1'b0;
    else         hold_flush <= ~flushing & (flush_i | hold_flush);


  //signal Instruction Cache when FLUSH is done
  assign flushrdy_o = ~(flush_i | hold_flush | flushing);


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
       ARMED        : if ( (flush_i || hold_flush) && !(mem_vreq_i && mem_we_i) && !(mem_vreq_dly && mem_we_dly && (mem_preq_i || mem_preq_dly)) )
                      begin
                          memfsm_state <= FLUSH;
                          flushing     <= 1'b1;
                      end
                      else if (mem_vreq_dly && !cache_hit && (mem_preq_i || mem_preq_dly) ) //it takes 1 cycle to read TAG
                      begin
                          if (tag_out[ onehot2int(fill_way_select) ].valid &&
                              tag_out[ onehot2int(fill_way_select) ].dirty)
                          begin
                              //selected way is dirty, write back to upstream
                              memfsm_state <= WAIT4BIUCMD1;
                              biucmd       <= READ_WAY;
                              filling      <= 1'b1;
                          end
                          else
                          begin
                              //selected way not dirty, overwrite
                              memfsm_state <= WAIT4BIUCMD0;
                              biucmd       <= READ_WAY;
                              filling      <= 1'b1;
                          end
                      end
                      else
                      begin
                          biucmd <= NOP;
                      end

       FLUSH        : if (|tag_dirty) 
                      begin
                          //There are dirty ways in this set
                          //TODO
                          //First determine dat_idx; this reads all ways for that index (FLUSH)
                          //then check which ways are dirty (FLUSHWAYS)
                          //write dirty way
                          //clear dirty bit
                         memfsm_state <= FLUSHWAYS;
                         biucmd       <= WRITE_WAY;
                      end
                      else
                      begin
                         memfsm_state <= RECOVER; //allow to read new tag_idx
                         flushing     <= 1'b0;
                      end

        FLUSHWAYS   : if (biufsm_ack)
                      begin
                          //Check if there are more dirty ways in this set
                          if (~|way_dirty)
                          begin
                              memfsm_state <= FLUSH;
                              biucmd       <= NOP;
                          end
                      end
                      

        //TODO: Can we merge WAIT4BIUCMD0 and WAIT4BIUCMD1?
        WAIT4BIUCMD1: if (biufsm_err)
                      begin
                          //if tag_idx already selected, go to ARMED
                          //otherwise go to RECOVER to read tag (1 cycle delay)
                          memfsm_state <= ((mem_preq_dly && mem_we_dly) ? write_buffer.idx : vadr_idx) != tag_idx_hold ? RECOVER : ARMED;
                          biucmd       <= WRITE_WAY;
                          filling      <= 1'b0;
                      end
                      else if (biufsm_ack) //wait for READ_WAY to complete
                      begin
                          //if tag_idx already selected, go to ARMED
                          //otherwise go to recover to read tag (1 cycle delay)
                          memfsm_state <= ((mem_preq_dly && mem_we_dly) ? write_buffer.idx : vadr_idx) != tag_idx_hold ? RECOVER : ARMED;
                          biucmd       <= WRITE_WAY;
                          filling      <= 1'b0;
                      end

        WAIT4BIUCMD0: if (biufsm_err)
                      begin
                          memfsm_state <= ((mem_preq_dly && mem_we_dly) ? write_buffer.idx : vadr_idx) != tag_idx_hold ? RECOVER : ARMED;
                          biucmd       <= NOP;
                          filling      <= 1'b0;
                      end
                      else if (biufsm_ack)
                      begin
                          memfsm_state <= ((mem_preq_dly && mem_we_dly) ? write_buffer.idx : vadr_idx) != tag_idx_hold ? RECOVER : ARMED;
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
  assign biu_adro_eq_cache_adr_dly = (biu_adro_i[PLEN-1:BURST_LSB] == mem_padr_i  [PLEN-1:BURST_LSB]);


  //dat/tag index during flushing
  assign flush_idx = get_dirty_set_idx(tag_dirty);


  //signal downstream that data is ready
  always_comb
    unique case (memfsm_state)
      ARMED       : mem_ack_o = mem_vreq_dly & cache_hit & (mem_preq_i | mem_preq_dly); //cache_hit
      WAIT4BIUCMD1: mem_ack_o = biu_ack_i & biu_adro_eq_cache_adr_dly;
      WAIT4BIUCMD0: mem_ack_o = biu_ack_i & biu_adro_eq_cache_adr_dly;
      default     : mem_ack_o = 1'b0;
    endcase


  //signal downstream the BIU reported an error
  assign mem_err_o = biu_err_i;


  //Assign mem_q
  always_comb
    unique case (memfsm_state)
      WAIT4BIUCMD1: mem_q_o = biu_q_i;
      WAIT4BIUCMD0: mem_q_o = biu_q_i;
      default     : mem_q_o = cache_q;
    endcase


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
        .rstn  ( rst_ni       ),
        .clk   ( clk_i        ),
        .addr  ( tag_idx      ),
        .we    ( tag_we [way] ),
        .be    ( {(TAG_BITS+7)/8{1'b1}} ),
        .din   ( tag_in [way].tag ),
        .dout  ( tag_out[way].tag )
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
        else if ( tag_we[way]) tag_valid[way][tag_idx] <= tag_in[way].valid;

      assign tag_out[way].valid = tag_valid[way][tag_idx_dly];


      //Dirty is stored in DFF
      always @(posedge clk_i, negedge rst_ni)
        if      (!rst_ni           ) tag_dirty[way]                      <= 'h0;
        else if ( tag_we_dirty[way]) tag_dirty[way][tag_dirty_write_idx] <= tag_in[way].dirty;

      assign tag_out[way].dirty = tag_dirty[way][tag_idx_dly];


      //extract 'dirty' from tag
      assign way_dirty[way] = tag_out[way].dirty;


      //compare way-tag to TAG;
      assign way_hit[way] = tag_out[way].valid &
                            (core_tag == (tag_idx_dly == tag_byp_idx[way] ? tag_byp_tag[way] : tag_out[way].tag) );
  end
endgenerate

  // Generate 'hit'
  assign cache_hit = |way_hit; // & mem_vreq_dly;


  /* DATA
   */
  //pipelined write buffer
  assign dat_we_enable = (mem_vreq_i & mem_we_i) | ~mem_vreq_i; //enable writing to data memory

  always @(posedge clk_i)
    write_buffer.was_write <= (mem_vreq_i & mem_we_i);


  always @(posedge clk_i)
    if (mem_vreq_i && mem_we_i) //must store during vreq, otherwise data gets lost
    begin
        write_buffer.idx  <= vadr_idx;
        write_buffer.data <= mem_d_i;
        write_buffer.be   <= mem_be;
    end


  always @(posedge clk_i, negedge rst_ni)
    if (!rst_ni)
      write_buffer.hit <= 'h0;
    else if (write_buffer.was_write)
      write_buffer.hit <= way_hit & {WAYS{mem_preq_i}}; //store current transaction's hit, qualify with preq
    else if (dat_we_enable)
      write_buffer.hit <= 'h0;                          //data written into RAM


  always @(posedge clk_i)
    if (write_buffer.was_write && mem_preq_i) write_buffer.adr <= mem_padr_i;


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


      //assign way_q; Build MUX (AND/OR) structure
      if (way == 0)
        assign way_q_mux[way] =  dat_out[way] & {BLK_BITS{way_hit[way]}};
      else
        assign way_q_mux[way] = (dat_out[way] & {BLK_BITS{way_hit[way]}}) | way_q_mux[way -1];
  end
endgenerate


  //get requested data (XLEN-size) from way_q_mux(BLK_BITS-size)
  assign way_q = way_q_mux[WAYS-1] >> (dat_offset * XLEN);


  assign in_biubuffer = mem_preq_dly ? (biu_adri_hold[PLEN-1:BLK_OFF_BITS] == mem_padr_dly[PLEN-1:BLK_OFF_BITS]) & (biu_buffer_valid >> dat_offset)
                                     : (biu_adri_hold[PLEN-1:BLK_OFF_BITS] == mem_padr_i  [PLEN-1:BLK_OFF_BITS]) & (biu_buffer_valid >> dat_offset);

  assign in_writebuffer = (mem_padr_i == write_buffer.adr) & |write_buffer.hit;


  assign cache_q = in_biubuffer ? biu_buffer >> (dat_offset * XLEN)
                                : in_writebuffer ? be_mux(write_buffer.be, way_q, write_buffer.data)
                                                 : way_q;


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
      WAIT4BIUCMD1: tag_idx = tag_idx_hold;
      WAIT4BIUCMD0: tag_idx = tag_idx_hold;

      //TAG read
      FLUSH       : tag_idx = flush_idx;
      FLUSHWAYS   : tag_idx = flush_idx;
      RECOVER     : tag_idx = mem_vreq_dly ? vadr_dly_idx  //pending access
                                           : vadr_idx;     //new access
      default     : tag_idx = vadr_idx;                    //current access
    endcase


  always_comb
    unique case (memfsm_state)
      //TAG write
      WAIT4BIUCMD1: tag_dirty_write_idx = tag_idx_dly;
      WAIT4BIUCMD0: tag_dirty_write_idx = tag_idx_dly;
      default     : tag_dirty_write_idx = (mem_preq_dly && mem_we_dly) ? write_buffer.idx : tag_idx_dly;
    endcase


  //registered version, for tag_valid/dirty
  always @(posedge clk_i)
    tag_idx_dly <= tag_idx;


  //hold tag-idx; prevent new mem_vreq_i from messing up tag during filling
  always @(posedge clk_i)
    unique case (memfsm_state)
      ARMED   : if (mem_vreq_dly && !cache_hit) tag_idx_hold <= vadr_dly_idx;
      RECOVER : tag_idx_hold <= mem_vreq_dly ? vadr_dly_idx  //pending access
                                             : vadr_idx;     //current access
       default: ;
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
          ARMED  : tag_we_dirty[way] = way_hit[way] & ((mem_vreq_dly & mem_we_dly & mem_preq_i) | (mem_preq_dly & mem_we_dly));
          default: tag_we_dirty[way] = (filling & fill_way_select_hold[way] & biufsm_ack) |
                                       (flushing & write_evict_buffer & (get_dirty_way_idx(tag_dirty,flush_idx) == way) );
        endcase
  end


  //TAG Write Data
  for (way=0; way < WAYS; way++)
  begin: gen_tag
      //clear valid tag during cache-coherency checks
      assign tag_in[way].valid = 1'b1; //~flushing;

      //set dirty bit when
      // 1. read new line from memory and data in new line is overwritten
      // 2. during a write to a valid line
      //clear dirty bit when flushing
      always_comb
        unique case (biufsm_ack)
          1: tag_in[way].dirty = biu_buffer_dirty | (mem_we_dly & biu_adro_eq_cache_adr_dly);
          0: tag_in[way].dirty = ~flushing & mem_we_dly;
        endcase

      assign tag_in[way].tag   = core_tag_hold;
  end
endgenerate



  //Shift amount for data
  assign dat_offset = mem_vadr_dly[BLK_OFF_BITS-1 -: DAT_OFF_BITS];


//Riviera bug workaround
wire [PLEN        -1:0] pwb_adr = write_buffer.adr;
wire [DAT_OFF_BITS-1:0] pwb_dat_offset = (write_buffer.was_write && mem_preq_i) ? mem_padr_i[BLK_OFF_BITS-1 -: DAT_OFF_BITS]
                                                                                : pwb_adr   [BLK_OFF_BITS-1 -: DAT_OFF_BITS];
//TODO: Can't we use vadr?

  //DAT Byte Enable
  assign dat_be = biufsm_ack ? {BLK_BITS/8{1'b1}} : write_buffer.be << (pwb_dat_offset * XLEN/8);


  always @(posedge clk_i)
    unique case (memfsm_state)
      ARMED  : dat_in_offset <= dat_offset;
      default: ;
    endcase


  //DAT Index
   always_comb
     unique case (memfsm_state)
       ARMED       : dat_idx = dat_we_enable ? write_buffer.idx   //write old 'write-data'
                                             : vadr_idx;         //read access
       RECOVER     : dat_idx = mem_vreq_dly  ? vadr_dly_idx      //read pending cycle
                                             : vadr_idx;         //read new access
       FLUSH       : dat_idx = flush_idx;
       FLUSHWAYS   : dat_idx = flush_idx;
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
          WAIT4BIUCMD1: dat_we[way] = fill_way_select_hold[way] & biufsm_ack;
          RECOVER     : dat_we[way] = 1'b0;

          //current cycle and previous cycle are writes, no time to write 'hit' into write buffer, use way_hit directly
          //current access is a write and there's still a write request pending (e.g. write during READ_WAY), use way_hit directly
          default     : dat_we[way] = dat_we_enable &
                                     ( (write_buffer.was_write && mem_preq_i) || (mem_preq_dly && mem_we_dly) ? way_hit[way] : write_buffer.hit[way]);
        endcase
  end
endgenerate


  //DAT Write Data
  always_comb
    unique case (biufsm_ack)
      1: begin
             dat_in = biu_buffer;                                                        //dat_in = biu_buffer
             dat_in[ biu_adro_i[BLK_OFF_BITS-1 -: DAT_OFF_BITS] * XLEN +: XLEN] = biu_q; //except for last transaction
         end
      0: dat_in = {BURST_SIZE{write_buffer.data}};                                       //dat_in = write-data over all words
                                                                                         //dat_be gates writing
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


  //handle writing bits in read-cache-line
  assign biu_q = mem_we_dly && biu_adro_eq_cache_adr_dly ? be_mux(mem_be_dly, biu_q_i, mem_d_dly)
                                                         : biu_q_i;

  //write data
  always @(posedge clk_i)
    unique case (biufsm_state)
     IDLE   : begin
                  if (biucmd == WRITE_WAY) biu_buffer <= evict_buffer.data >> XLEN;      //first XLEN bits went out already
                  biu_buffer_valid <=  'h0;
                  biu_buffer_dirty <= 1'b0;
              end

     BURST  : begin
                  if (!biu_we_hold)
                  begin
                      if (biu_ack_i)   //latch incoming data when transfer-acknowledged
                      begin
                          biu_buffer      [ biu_adro_i[BLK_OFF_BITS-1 -: DAT_OFF_BITS] * XLEN +: XLEN ] <= biu_q;
                          biu_buffer_valid[ biu_adro_i[BLK_OFF_BITS-1 -: DAT_OFF_BITS] ]                <= 1'b1;
                          biu_buffer_dirty <= biu_buffer_dirty | (mem_we_dly & biu_adro_eq_cache_adr_dly);
                      end
                  end
                  else
                  begin
                      if (biu_d_ack_i) //present new data when previous transfer acknowledged
                      begin
                          biu_buffer       <= biu_buffer >> XLEN;
                          biu_buffer_valid <=  'h0;
                          biu_buffer_dirty <= 1'b0;
                      end
                  end
              end
      default: ;
    endcase



  //store dirty line in evict buffer
  //TODO: change name
  always @(posedge clk_i)
    is_read_way <= (biucmd       == READ_WAY) ||
                   (memfsm_state == FLUSH   ) ||
                   (memfsm_state == FLUSHWAYS & biufsm_ack & |way_dirty); 

  always @(posedge clk_i)
    is_read_way_dly <= is_read_way;

  //ARMED: write evict buffer 1 cycle after starting READ_WAY. That ensures DAT and TAG are valid
  //        and there no new data from the BIU yet
  //FLUSH: write evict buffer when entering FLUSHWAYS state and as long as current SET has dirty WAYs.
  assign write_evict_buffer = is_read_way & ~is_read_way_dly;

  always @(posedge clk_i)
    if (write_evict_buffer)
    begin
        evict_buffer.adr  <= flushing ? {tag_out[ get_dirty_way_idx(tag_dirty,flush_idx) ].tag, flush_idx,    {BLK_OFF_BITS{1'b0}}}
                                      : {tag_out[ onehot2int(fill_way_select_hold)       ].tag, padr_dly_idx, {BLK_OFF_BITS{1'b0}}};
        evict_buffer.data <= flushing ? dat_out[ get_dirty_way_idx(tag_dirty,flush_idx) ]
                                      : dat_out[ onehot2int(fill_way_select_hold)       ];
    end


  //acknowledge burst to memfsm
  always_comb
    unique case (biufsm_state)
      BURST   : biufsm_ack = (~|burst_cnt & biu_ack_i & (~biu_we_hold | flushing) ) | biu_err_i;
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
                                  biu_adri_o = {mem_padr_dly[PLEN-1 : BURST_LSB],{BURST_LSB{1'b0}}};
                                  biu_d_o    =  'hx;
                              end

                   WRITE_WAY: begin
                                  biu_stb_o  = 1'b1;
                                  biu_we_o   = 1'b1;
                                  biu_adri_o = evict_buffer.adr;
                                  biu_d_o    = evict_buffer.data[XLEN-1:0];
                              end
                endcase

      WAIT4BIU: begin
                    //stretch biu_*_o signals until BIU acknowledges strobe
                    biu_stb_o  = 1'b1;
                    biu_we_o   = biu_we_hold;
                    biu_adri_o = biu_adri_hold;
                    biu_d_o    = evict_buffer.data[XLEN-1:0]; //retain same data
                end

      BURST   : begin
                    biu_stb_o  = 1'b0;
                    biu_we_o   = 1'bx; //don't care
                    biu_adri_o =  'hx; //don't care
                    biu_d_o    = biu_buffer[0 +: XLEN];
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
    if (biufsm_state == IDLE)
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



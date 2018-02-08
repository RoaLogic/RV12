/////////////////////////////////////////////////////////////////
//                                                             //
//    ???????  ???????  ??????                                 //
//    ?????????????????????????                                //
//    ???????????   ???????????                                //
//    ???????????   ???????????                                //
//    ???  ???????????????  ???                                //
//    ???  ??? ??????? ???  ???                                //
//          ???      ???????  ??????? ??? ???????              //
//          ???     ????????????????? ???????????              //
//          ???     ???   ??????  ??????????                   //
//          ???     ???   ??????   ?????????                   //
//          ?????????????????????????????????????              //
//          ???????? ???????  ??????? ??? ???????              //
//                                                             //
//    RISC-V                                                   //
//    Instruction Cache Core                                   //
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

module riscv_icache_core #(
  parameter            XLEN           = 32,
  parameter [XLEN-1:0] PC_INIT        = 'h200,
  parameter            PHYS_ADDR_SIZE = XLEN, //MSB determines cacheable(0) and non-cacheable(1)
  parameter            PARCEL_SIZE    = 32,

  parameter            SIZE           = 64, //KBYTES
  parameter            BLOCK_SIZE     = 32, //Number of BYTES in a block.
  parameter            WAYS           =  2, // 1           : Direct Mapped
                                            //<n>          : n-way set associative
                                            //<n>==<blocks>: fully associative
  parameter            REPLACE_ALG    = 0,  //0: Random
                                            //1: FIFO
                                            //2: LRU

  parameter            TECHNOLOGY     = "GENERIC"
)
(
  input                           rstn,
  input                           clk,
 
  //CPU side
  output reg                      if_stall_nxt_pc,
  input                           if_stall,
  input                           if_flush,
  input				  if_out_order,
  input      [XLEN          -1:0] if_nxt_pc,
  output reg [XLEN          -1:0] if_parcel_pc,
  output reg [PARCEL_SIZE   -1:0] if_parcel,
  output reg [               1:0] if_parcel_valid,
  output                          if_parcel_misaligned,
  input                           bu_cacheflush,
                                  dcflush_rdy,

  //To BIU
  output reg                      biu_stb,
  input                           biu_stb_ack,
  output     [PHYS_ADDR_SIZE-1:0] biu_adri,
  input      [PHYS_ADDR_SIZE-1:0] biu_adro,
  output     [XLEN/8        -1:0] biu_be,       //Byte enables
  output reg [               2:0] biu_type,     //burst type -AHB style
  output                          biu_lock,
  output                          biu_we,
  output     [XLEN          -1:0] biu_di,
  input      [XLEN          -1:0] biu_do,
  input                           biu_rack,      //data acknowledge, 1 per data
  input                           biu_err,      //data error

  output                          biu_is_cacheable,
                                  biu_is_instruction
);

  //////////////////////////////////////////////////////////////////
  //
  // Constants
  //
  import ahb3lite_pkg::*;

  localparam BLK_OFF_LSB  = 1;                                          //Instruction address boundary (min.16bits)
  localparam SETS         = (SIZE*1024) / BLOCK_SIZE / WAYS;            //Number of sets
  localparam BLK_OFF_BITS = $clog2(BLOCK_SIZE);                         //Number of BlockOffset bits
  localparam IDX_BITS     = $clog2(SETS);                               //Number of Index-bits
  localparam TAG_BITS     = PHYS_ADDR_SIZE-1 - IDX_BITS - BLK_OFF_BITS; //Number of TAG-bits. PHYS_ADDR_SIZE-1 because MSB determines (non)cacheable
  localparam LRU_BITS     = $clog2(WAYS);
  localparam BLK_BITS     = 8*BLOCK_SIZE;                               //Total number of bits in a Block
  localparam BURST_SIZE   = BLK_BITS / XLEN;                            //Number of transfers to load 1 Block
  localparam TAG_SIZE     = SETS/WAYS;
  localparam BURST_BITS   = $clog2(BURST_SIZE);
  localparam BURST_OFF    = XLEN/8;
  localparam BURST_LSB    = $clog2(BURST_OFF);

  //partial BLOCK decoding done by Data Memory
  localparam DAT_BITS     = PARCEL_SIZE > XLEN ? PARCEL_SIZE : XLEN;   //datablock size, either XLEN or PARCEL_SIZE whichever is greater
  localparam DAT_ABITS    = $clog2(BLK_BITS / DAT_BITS);               //Number of abits added to Data Memory
  localparam DAT_IDX_LSB  = $clog2(DAT_BITS/8);                        //16bit offset
  localparam DAT_IDX_BITS = IDX_BITS + DAT_ABITS;

  //////////////////////////////////////////////////////////////////
  //
  // Functions
  //
  function integer onehot2int;
    input [WAYS-1:0] a;

    integer i;

    for (i=0; i<WAYS; i++)
      if (a[i]) onehot2int = i;
  endfunction


  function [LRU_BITS-1:0] new_lru;
    input [LRU_BITS-1:0] old_lru;
    input [LRU_BITS-1:0] replaced_lru;

    if (old_lru < replaced_lru) new_lru = old_lru;
    else                        new_lru = old_lru -1;
  endfunction

  //////////////////////////////////////////////////////////////////
  //
  // Typedefs
  //
  typedef struct packed {
    logic [LRU_BITS-1:0] lru;
    logic                valid;
    logic [TAG_BITS-1:0] tag;
  } tag_struct;
  localparam TAG_STRUCT_BITS = (REPLACE_ALG != 0) ? $bits(tag_struct) : $bits(tag_struct) - LRU_BITS;


  typedef struct packed {
    logic                       valid;
    logic [XLEN           -1:0] dat;
    logic [PHYS_ADDR_SIZE -1:0] adr;
  } fifo_struct;


  //////////////////////////////////////////////////////////////////
  //
  // Variables
  //
  genvar way;

  logic [XLEN        -1:0] pc; //program counter
  logic                    is_cacheable,
                           is_cacheable_dly;
  logic [             1:0] biu_stb_cnt;
  fifo_struct              biu_fifo[3];


  logic [IDX_BITS    -1:0] tag_idx,
                           tag_widx; //for LRU
  logic [DAT_IDX_BITS-1:0] dat_idx,
                           dat_widx;
  logic [TAG_BITS    -1:0] core_tag,
                           tag_in_core_tag;

  logic [WAYS        -1:0] way_hit;
  logic [DAT_BITS    -1:0] way_dat [WAYS]; //only read XLEN bits from BLK_BITS
  logic                    tag_re;
  logic [WAYS        -1:0] tag_we,
                           dat_we;
  logic [DAT_BITS/8  -1:0] dat_be;
  logic [DAT_BITS    -1:0] dat_in,
                           dat_out[WAYS];
  tag_struct               tag_in [WAYS],
                           tag_out[WAYS];

  logic                    cache_hit,
                           dcache_hit; //for LRU tag-update
  logic [DAT_BITS    -1:0] cache_dat;

  logic [            19:0] way_random;
  logic [WAYS        -1:0] fill_way_select,
                           fill_way_select_rnd;

  logic                    hold_bu_cacheflush,
                           hold_if_flush,
                           if_flush_dly,
                           flushing,
                           filling;
  logic [IDX_BITS    -1:0] cnt, nxt_cnt;
  
  logic                    active_burst;

  enum logic [2:0] {FLUSH=3'b000,WAIT4DCACHE=3'b001,ARMED=3'b010,FILL=3'b100} wr_state;


  //////////////////////////////////////////////////////////////////
  //
  // Module Body
  //
  import riscv_pkg::*;


  //Is this a cacheable region?
  //MSB=1 non-cacheable (IO region)
  //MSB=0 cacheabel (instruction/data region)
  assign is_cacheable = if_nxt_pc[PHYS_ADDR_SIZE-1];
 
  always @(posedge clk)
    if      ( if_flush_dly                ) is_cacheable_dly <= is_cacheable;
    else if (!if_stall || !if_stall_nxt_pc) is_cacheable_dly <= is_cacheable;

  
  // check if parcel is misaligned, only bit 0 counts when using 16bits
  assign if_parcel_misaligned = pc[0]; //send out together with instruction


  //delay IF-flush
  always @(posedge clk,negedge rstn)
    if      (!rstn    ) if_flush_dly <= 1'b0;
    else if (!if_stall) if_flush_dly <= if_flush;

 //Register fetch pc
  always @(posedge clk,negedge rstn)
    if      (!rstn                         ) pc <= PC_INIT;
    else if ( if_flush_dly                 ) pc <= if_nxt_pc; //if_nxt_pc is updated by if_flush, so valid 1 cycle later
    else if (!if_stall && !if_stall_nxt_pc ) pc <= if_nxt_pc;

 always @(posedge clk)
    if(!filling) tag_in_core_tag <= core_tag;
/*
  //core TAG value
  always_comb
	case(wr_state)
	  FILL    : active_burst = cnt[3] ? 1'b0 : 1'b1;
	  default : active_burst = 1'b0;
	endcase
*/
  assign core_tag = pc[PHYS_ADDR_SIZE-2 -:TAG_BITS];//active_burst ? biu_adro[PHYS_ADDR_SIZE-2  -: TAG_BITS] : pc[PHYS_ADDR_SIZE-2 -: TAG_BITS];


  /*
   * + Generate a Tag and Data memory for each way
   * + Generate a Tag comparison for each way
   */
generate
  for (way=0; way<WAYS; way++)
  begin: gen_ways
      //Tag memory
      rl_ram_1r1w #(
        .ABITS      ( IDX_BITS        ),
        .DBITS      ( TAG_STRUCT_BITS ),
        .TECHNOLOGY ( TECHNOLOGY      ) )
      tag_ram (
        .rstn  ( rstn        ),
        .clk   ( clk         ),
        .waddr ( tag_widx    ),
        .we    ( tag_we [way]),
        .be    ( {(TAG_STRUCT_BITS+7)/8{1'b1}} ),
        .din   ( tag_in [way][TAG_STRUCT_BITS-1:0]),

        .raddr ( tag_idx    ),
        .re    ( 1'b1       ),
        .dout  ( tag_out[way][TAG_STRUCT_BITS-1:0]) );

      //Block memory
      rl_ram_1r1w #(
        .ABITS      ( DAT_IDX_BITS ),
        .DBITS      ( DAT_BITS     ),
        .TECHNOLOGY ( TECHNOLOGY   ) )
      data_ram (
        .rstn  ( rstn             ),
        .clk   ( clk              ),
        .waddr ( dat_widx         ),
        .we    ( dat_we[way]      ),
        .be    ( dat_be           ),
        .din   ( biu_do           ),

        .raddr ( dat_idx          ),
        .re    ( 1'b1             ),
        .dout  ( dat_out[way]     ) );

      //compare way-tag to TAG;
      assign way_hit[way] = tag_out[way].valid & (tag_out[way].tag == core_tag);

      //assign way-block
      //Clear block if not way_hit OR with other ways (implements MUX)
      if (way == 0)
        assign way_dat[way] =  dat_out[way] & {DAT_BITS{way_hit[way]}};
      else
        assign way_dat[way] = (dat_out[way] & {DAT_BITS{way_hit[way]}}) | way_dat[way -1];
  end
endgenerate

//  always @(posedge clk, negedge rstn)
//    $display ("time @%0t ,way = %0d, %0d ",$time, way, {DAT_BITS{way_hit[way]}});


  /*
   * Generate 'hit' and data block
   */
  assign cache_hit = |way_hit;
  assign cache_dat = way_dat[WAYS-1];

  //used by LRU algorithm, to update 'tag' after a cache-hit (read tag, then update)
  always @(posedge clk)
    dcache_hit <= cache_hit;


  /*
   * Statemachines
   */
  always @(posedge clk, negedge rstn)
    if (!rstn) hold_bu_cacheflush <= 1'b0;
    else       hold_bu_cacheflush <= ~flushing & (bu_cacheflush | hold_bu_cacheflush);

  always @(posedge clk, negedge rstn)
    if (!rstn) hold_if_flush <= 1'b0;
    else       hold_if_flush <= if_flush | ( hold_if_flush & (filling | if_stall));


  //Write Statemachine
  always @(posedge clk, negedge rstn)
    if (!rstn)
    begin
        wr_state <= FLUSH;
        flushing <= 1'b1;
        filling  <= 1'b0;
    end
    else
      case (wr_state)
        FLUSH      : if (~|cnt)
                     begin
                         wr_state <= dcflush_rdy ? ARMED : WAIT4DCACHE;
                         flushing <= 1'b0;
                         filling  <= 1'b0;
                     end

        WAIT4DCACHE: if (dcflush_rdy)
                     begin
                         wr_state <= ARMED;
                         flushing <= 1'b0;
                         filling  <= 1'b0;
                     end

        ARMED      : if (bu_cacheflush || hold_bu_cacheflush)
                     begin
                         wr_state <= FLUSH;
                         flushing <= 1'b1;
                         filling  <= 1'b0;
                     end
                     else if (!cache_hit && is_cacheable_dly && !if_flush && !if_flush_dly)
                     begin
                         wr_state <= FILL;
                         flushing <= 1'b0;
                         filling  <= 1'b1;
                     end

        FILL       : if (bu_cacheflush || hold_bu_cacheflush)
                     begin
                         wr_state <= FLUSH;
                         flushing <= 1'b1;
                         filling  <= 1'b0;
                     end
                     else if (~|cnt & biu_rack) //TODO: pre-read 1 line
                     begin
                         wr_state <= ARMED;
                         flushing <= 1'b0;
                         filling  <= 1'b0;
                     end

        default    : begin //OOPS
                         wr_state <= FLUSH;
                         flushing <= 1'b1;
                         filling  <= 1'b0;
                     end
      endcase



  //Random generator for RANDOM replacement algorithm
  always @(posedge clk, negedge rstn)
    if      (!rstn   ) way_random <= 'h0;
    else if (!filling) way_random <= {way_random, way_random[19] ~^ way_random[16]};

  assign fill_way_select_rnd = 1 << way_random[LRU_BITS-1:0];


  //select which way to fill (implement replacement algorithms)
generate
  if (REPLACE_ALG == 0)                             //RANDOM
    assign fill_way_select = fill_way_select_rnd;
  else                                              //FIFO + LRU
    for (way=0; way<WAYS; way++)
    begin: gen_way_select
      if (way == 0)
        assign fill_way_select[way] =  ~tag_out[way].valid | ~|tag_out[way].lru;
      else
        assign fill_way_select[way] = (~tag_out[way].valid | ~|tag_out[way].lru) & ~fill_way_select[way-1];
    end
endgenerate


  //generate Write Enable signals
generate
  for (way=0; way<WAYS; way++)
  begin: gen_way_we
      if      (REPLACE_ALG == 0) //Random
        assign tag_we[way] = flushing | (filling & fill_way_select[way] & biu_rack & ~|cnt);  //update way being filled
      else if (REPLACE_ALG == 1) //FIFO
        assign tag_we[way] = flushing | (filling & biu_rack & (~|cnt));                       //update all ways upon filling
      else if (REPLACE_ALG == 2) //LRU
        assign tag_we[way] = flushing | (filling & biu_rack & (~|cnt)) | dcache_hit;          //update all ways upon filling and reading (1 cycle later)

      assign dat_we[way] = filling & fill_way_select[way] & biu_rack;
  end
endgenerate


  //generate Dat Byte-Enable
  assign dat_be = PARCEL_SIZE > XLEN ? {XLEN/8{1'b1}} << biu_adro[DAT_IDX_LSB-1:0] : {DAT_BITS/8{1'b1}};



  //generate Index
  assign tag_idx = (if_stall || if_stall_nxt_pc) ? pc[ BLK_OFF_BITS +: IDX_BITS ] : if_nxt_pc[ BLK_OFF_BITS +: IDX_BITS ];

  always_comb
    case (wr_state)
      FLUSH  : tag_widx = cnt;
      FILL   : tag_widx = biu_adro [ BLK_OFF_BITS +: IDX_BITS ];
      default: tag_widx = 'hx; //don't care
  endcase

   assign dat_widx = biu_adro [ DAT_IDX_LSB +: DAT_IDX_BITS ];
//  assign dat_idx  = if_stall_nxt_pc ? pc[ DAT_IDX_LSB +: DAT_IDX_BITS ] : if_nxt_pc[ DAT_IDX_LSB +: DAT_IDX_BITS ];
   assign dat_idx  = (if_stall || if_stall_nxt_pc) ? pc[ DAT_IDX_LSB +: DAT_IDX_BITS ] : if_nxt_pc[ DAT_IDX_LSB +: DAT_IDX_BITS ];


/*
initial
begin
   $display ("replace alg : %0d", REPLACE_ALG);  
   $display ("Cache size  : %0d", SIZE);
   $display ("BLK_OFF_BITS: %0d", BLK_OFF_BITS);
   $display ("SETS        : %0d", SETS        );
   $display ("IDX_BITS    : %0d", IDX_BITS    );
   $display ("tag_idx[%0d:%0d]\n", BLK_OFF_BITS+IDX_BITS-1, BLK_OFF_BITS);

   $display ("DAT_IDX_LSB : %0d", DAT_IDX_LSB );
   $display ("DAT_IDX_BITS: %0d", DAT_IDX_BITS);
   $display ("dat_idx[%0d:%0d]\n", DAT_IDX_LSB+DAT_IDX_BITS-1, DAT_IDX_LSB);

   $display ("TAG_BITS: %0d", TAG_BITS);
   $display ("TAG[%0d:%0d]", XLEN-1, XLEN-TAG_BITS-1); // bit 31 for cacheable

   $display ("XLEN = %d",XLEN);
   $display ("PHYS_ADDR_SIZE = %d",PHYS_ADDR_SIZE);

   $display ("BLOCK SIZE = %d", BLOCK_SIZE);
   $display ("BLK_BITS = %d", BLK_BITS);
   $display ("BURST SIZE = %d", BURST_SIZE);
   $display ("TAG_SIZE = %d", TAG_SIZE);
 
end


always @(posedge clk, negedge rstn)
begin
  if(if_parcel_valid[0] & if_parcel_valid[1])    	$display ("Time = %0t, if_parcel = %0h, if_parcel_pc = %0h" ,$time, if_parcel, if_parcel_pc );
   	//$display ("Time = %0t, Tag = %0h, dataIDX = %0h" ,$time, core_tag, dat_idx );
     
end
*/



  //generate TAG data
generate
  for (way=0; way<WAYS; way++)
  begin: gen_tag
      if      (REPLACE_ALG == 0) //random
      begin
          assign tag_in[way].valid = ~flushing;
          assign tag_in[way].lru   = 'h0;
          assign tag_in[way].tag   =  tag_in_core_tag;
      end
      else if (REPLACE_ALG == 1) //FIFO
      begin
          assign tag_in[way].valid = ~flushing & (tag_out[way].valid | fill_way_select[way]);
          assign tag_in[way].lru   = fill_way_select[way] ? {LRU_BITS{1'b1}} : tag_out[way].lru -1;
          assign tag_in[way].tag   = fill_way_select[way] ? tag_in_core_tag  : tag_out[way].tag;
      end
      else if (REPLACE_ALG == 2) //LRU
      begin
          //LRU writes during reads too. So update 'valid' only while filling
          assign tag_in[way].valid = ~flushing & ( tag_out[way].valid | (filling & fill_way_select[way]) );

          //LRU
          assign tag_in[way].lru = filling ? fill_way_select[way] ? {LRU_BITS{1'b1}} : new_lru( tag_out[way].lru, tag_out[ onehot2int(fill_way_select) ].lru )
                                           : way_hit[way]         ? {LRU_BITS{1'b1}} : new_lru( tag_out[way].lru, tag_out[ onehot2int(way_hit        ) ].lru );

          assign tag_in[way].tag = fill_way_select[way] ? tag_in_core_tag : tag_out[way].tag;
      end
  end //next way
endgenerate

  


  /*
   * External Interface
   * TODO: Hit under Miss
   */
  always_comb
    case (wr_state)
        ARMED   : begin
                     biu_stb            = is_cacheable     ? ~(if_flush | if_flush_dly) & ~cache_hit          //TODO: shouldn't this be is_cacheble_dly??
                                                           : ~if_flush & ~if_stall & ~biu_fifo[1].valid;
                     if_stall_nxt_pc    = is_cacheable     ? ~(if_flush | if_flush_dly) & ~cache_hit
                                                           : ~biu_stb_ack | biu_fifo[1].valid;
                     if_parcel_valid[0] = is_cacheable_dly ? ~(if_flush | if_flush_dly) &  cache_hit
                                                           : ~(if_flush | if_flush_dly) & ~if_stall & biu_fifo[0].valid;
                     if_parcel_valid[1] = is_cacheable_dly ? ~(if_flush | if_flush_dly) &  cache_hit & ~pc[1] 
                                                           : ~(if_flush | if_flush_dly) & ~if_stall & biu_fifo[0].valid;
                     if_parcel_pc       = is_cacheable_dly ? pc
                                                           : { {XLEN-PHYS_ADDR_SIZE{1'b0}},biu_fifo[0].adr};
                     nxt_cnt            = !cache_hit ? (bu_cacheflush ? SETS-1 : BURST_SIZE -1) : cnt;
                 end

        FLUSH  : begin
                     biu_stb            = is_cacheable ? 1'b0
                                                    : (~if_flush & ~if_stall) & ~biu_fifo[1].valid;
                     if_stall_nxt_pc    = is_cacheable ? |cnt
                                                    : ~biu_stb_ack | biu_fifo[1].valid;
                     if_parcel_valid[0] = is_cacheable ? 1'b0
                                                    : ~(if_flush | if_flush_dly) & ~if_stall & biu_fifo[0].valid;
                     if_parcel_valid[1] = is_cacheable ? 1'b0
                                                    : ~(if_flush | if_flush_dly) & ~if_stall & biu_fifo[0].valid;
                     if_parcel_pc       = { {XLEN-PHYS_ADDR_SIZE{1'b0}},biu_fifo[0].adr};
                     nxt_cnt            = cnt -1;
                 end

        FILL   : begin
                     biu_stb            = 1'b0;
                     //TODO: if_stall_nxt_pc: what if if_nxt_pc is non-cacheable??
                     if_stall_nxt_pc    = ~(~if_flush_dly & biu_rack &  (biu_adro[PHYS_ADDR_SIZE -1:2] == pc[XLEN -1:2])) & (hold_if_flush ? |cnt : 1'b1);
                     if_parcel_valid[0] = ~(if_flush | if_flush_dly) &  (biu_rack & (biu_adro[PHYS_ADDR_SIZE -1:2] == pc[XLEN -1:2]) );
                     if_parcel_valid[1] = ~(if_flush | if_flush_dly) &  (biu_rack & (biu_adro[PHYS_ADDR_SIZE -1:2] == pc[XLEN -1:2]) & ~pc[1]);
                     if_parcel_pc       =  pc; //{ {XLEN-PHYS_ADDR_SIZE{1'b0}},biu_adro};
                     nxt_cnt            = (bu_cacheflush | hold_bu_cacheflush) ? {IDX_BITS{1'b1}} : biu_rack ? cnt -1 : cnt;
                 end

        default: begin
                     biu_stb            = 1'b0;
                     if_stall_nxt_pc    = 1'b1;
                     if_parcel_valid[0] = 1'b0;
                     if_parcel_valid[1] = 1'b0;
                     if_parcel_pc       = { {XLEN-PHYS_ADDR_SIZE{1'b0}},biu_adro};
                     nxt_cnt            = cnt;
                 end
    endcase


  always @(posedge clk,negedge rstn)
    if (!rstn) cnt <= {IDX_BITS{1'b1}};
    else       cnt <= nxt_cnt;

generate
  if (XLEN > PARCEL_SIZE)
      assign if_parcel = filling ? biu_do[ if_parcel_pc[2:1]*16 +: PARCEL_SIZE ] 
                                 : is_cacheable_dly ? cache_dat[ if_parcel_pc[2:1]*16 +: PARCEL_SIZE ] : biu_fifo[0].dat[ if_parcel_pc[2:1]*16 +: PARCEL_SIZE ] ;
  else
      assign if_parcel = filling ? biu_do[if_parcel_pc[$clog2(XLEN/32)+1:1]*16 +: PARCEL_SIZE ]
                                 : is_cacheable_dly ? cache_dat[if_parcel_pc[$clog2(XLEN/32)+1:1]*16 +: PARCEL_SIZE]  : biu_fifo[0].dat[if_parcel_pc[$clog2(XLEN/32)+1:1]*16 +: PARCEL_SIZE ];
endgenerate




  /*
   * External Interface
   */
  assign biu_adri  = ~is_cacheable ? if_nxt_pc[PHYS_ADDR_SIZE -1:0] : pc[1] ? pc[PHYS_ADDR_SIZE -1:0] - 'h2 : pc[PHYS_ADDR_SIZE -1:0];
  assign biu_be    = {$bits(biu_be){1'b1}};
  assign biu_lock  = 1'b0;
  assign biu_we    = 1'b0; //no writes
  assign biu_di    =  'h0;

  always_comb
    if (!is_cacheable) biu_type = 3'h0; //single access
    else
      case(BURST_SIZE)
         16     : biu_type = 3'b110;    //wrap16
         8      : biu_type = 3'b100;    //wrap8
         default: biu_type = 3'b010;    //wrap4
      endcase

  //Instruction cache..
  assign biu_is_instruction = 1'b1;
  assign biu_lock           = 1'b0;

  always @(posedge clk,negedge rstn)
    if      (!rstn       ) biu_stb_cnt <= 2'h0;
    else if ( if_flush   ) biu_stb_cnt <= 2'h0;
    else if ( biu_stb_ack) biu_stb_cnt <= {1'b1,biu_stb_cnt[1]};



  /*
   * FIFO
   */
  //valid bits
  always @(posedge clk,negedge rstn)
    if (!rstn)
    begin
        biu_fifo[0].valid <= 1'b0;
        biu_fifo[1].valid <= 1'b0;
        biu_fifo[2].valid <= 1'b0;
    end
    else if (!biu_stb_cnt[0])
    begin
        biu_fifo[0].valid <= 1'b0;
        biu_fifo[1].valid <= 1'b0;
        biu_fifo[2].valid <= 1'b0;
    end
    else
      case ({biu_rack,if_parcel_valid[0] | if_parcel_valid[1] })
        2'b00: ; //no action
        2'b10:   //FIFO write
               case ({biu_fifo[1].valid,biu_fifo[0].valid})
                 2'b11  : begin
                              //entry 0,1 full. Fill entry2
                              biu_fifo[2].valid <= 1'b1;
                          end
                 2'b01  : begin
                              //entry 0 full. Fill entry1, clear entry2
                              biu_fifo[1].valid <= 1'b1;
                              biu_fifo[2].valid <= 1'b0;
                          end
                 default: begin
                            //Fill entry0, clear entry1,2
                            biu_fifo[0].valid <= 1'b1;
                            biu_fifo[1].valid <= 1'b0;
                            biu_fifo[2].valid <= 1'b0;
                        end
               endcase
        2'b01: begin  //FIFO read
                   biu_fifo[0].valid <= biu_fifo[1].valid;
                   biu_fifo[1].valid <= biu_fifo[2].valid;
                   biu_fifo[2].valid <= 1'b0;
               end
        2'b11: ; //FIFO read/write, no change
      endcase


  //Address & Data
  always @(posedge clk)
    case ({biu_rack,if_parcel_valid[0] | if_parcel_valid[1]})
        2'b00: ;
        2'b10: case({biu_fifo[1].valid,biu_fifo[0].valid})
                 2'b11 : begin
                             //fill entry2
                             biu_fifo[2].dat <= biu_do;
                             biu_fifo[2].adr <= biu_adro;
                         end
                 2'b01 : begin
                             //fill entry1
                             biu_fifo[1].dat <= biu_do;
                             biu_fifo[1].adr <= biu_adro;
                         end
                 default:begin
                             //fill entry0
                             biu_fifo[0].dat <= biu_do;
                             biu_fifo[0].adr <= biu_adro;
                         end
               endcase
        2'b01: begin
                   biu_fifo[0].dat <= biu_fifo[1].dat;
                   biu_fifo[0].adr <= biu_fifo[1].adr;
                   biu_fifo[1].dat <= biu_fifo[2].dat;
                   biu_fifo[1].adr <= biu_fifo[2].adr;
                   biu_fifo[2].dat <= 'hx;
                   biu_fifo[2].adr <= 'hx;
               end
        2'b11: casex({biu_fifo[2].valid,biu_fifo[1].valid,biu_fifo[0].valid})
                 3'b1?? : begin
                              //fill entry2
                              biu_fifo[2].dat <= biu_do;
                              biu_fifo[2].adr <= biu_adro;

                              //push other entries
                              biu_fifo[0].dat <= biu_fifo[1].dat;
                              biu_fifo[0].adr <= biu_fifo[1].adr;
                              biu_fifo[1].dat <= biu_fifo[2].dat;
                              biu_fifo[1].adr <= biu_fifo[2].adr;
                          end
                 3'b01? : begin
                              //fill entry1
                              biu_fifo[1].dat <= biu_do;
                              biu_fifo[1].adr <= biu_adro;

                              //push entry0
                              biu_fifo[0].dat <= biu_fifo[1].dat;
                              biu_fifo[0].adr <= biu_fifo[1].adr;

                              //don't care
                              biu_fifo[2].dat <= 'hx;
                              biu_fifo[2].adr <= 'hx;
                         end
                 default:begin
                              //fill entry0
                              biu_fifo[0].dat <= biu_do;
                              biu_fifo[0].adr <= biu_adro;

                              //don't care
                              biu_fifo[1].dat <= 'hx;
                              biu_fifo[1].adr <= 'hx;
                              biu_fifo[2].dat <= 'hx;
                              biu_fifo[2].adr <= 'hx;
                         end
               endcase
      endcase

endmodule



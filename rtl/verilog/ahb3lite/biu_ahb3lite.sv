/////////////////////////////////////////////////////////////////////
//   ,------.                    ,--.                ,--.          //
//   |  .--. ' ,---.  ,--,--.    |  |    ,---. ,---. `--' ,---.    //
//   |  '--'.'| .-. |' ,-.  |    |  |   | .-. | .-. |,--.| .--'    //
//   |  |\  \ ' '-' '\ '-'  |    |  '--.' '-' ' '-' ||  |\ `--.    //
//   `--' '--' `---'  `--`--'    `-----' `---' `-   /`--' `---'    //
//                                             `---'               //
//    RISC-V                                                       //
//    Bus Interface Unit - AHB3Lite                                //
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
 * Assert all biu_*_i signals until biu_stb_ack_i is asserted.
 * biu_stb_i must be negated once biu_stb_ack_o is asserted.
 * Upon completion of the transfer biu_ack_o is asserted
 * biu_err_o is asserted if there was a transfer error
 *
 * A TAG can be provided with biu_stb, the TAG will be returned
 * aligned with the data phase
 *
 * DATA_SIZE : size of data buses
 * ADDR_SIZE : size of address buses
<<<<<<< HEAD
=======
 * TAG_SIZE  : size of user tag buses
>>>>>>> dev
 * STRICT_AHB: strictly adhere to the AHB spec.
 *             - do not allow crossing a 1kB address boundary
 */


import ahb3lite_pkg::*;
import biu_constants_pkg::*;

module biu_ahb3lite #(
  parameter DATA_SIZE  = 32,
  parameter ADDR_SIZE  = DATA_SIZE,
  parameter TAG_SIZE   = DATA_SIZE,
  parameter STRICT_AHB = 1
)
(
  input  logic                   HRESETn,
  input  logic                   HCLK,
 
  //AHB3 Lite Bus
  output logic                   HSEL,
  output logic [ADDR_SIZE  -1:0] HADDR,
  input  logic [DATA_SIZE  -1:0] HRDATA,
  output logic [DATA_SIZE  -1:0] HWDATA,
  output logic                   HWRITE,
  output logic [HSIZE_SIZE -1:0] HSIZE,
  output logic [HBURST_SIZE-1:0] HBURST,
  output logic [HPROT_SIZE -1:0] HPROT,
  output logic [HTRANS_SIZE-1:0] HTRANS,
  output logic                   HMASTLOCK,
  input  logic                   HREADY,
  input  logic                   HRESP,

  //BIU Bus (Core ports)
  input  logic                   biu_stb_i,      //strobe
  output logic                   biu_stb_ack_o,  //strobe acknowledge; can send new strobe
  output logic                   biu_d_ack_o,    //data acknowledge (send new biu_d_i); for pipelined buses
  input  logic [ADDR_SIZE  -1:0] biu_adri_i,
  output logic [ADDR_SIZE  -1:0] biu_adro_o,  
  input  biu_size_t              biu_size_i,     //transfer size
  input  biu_type_t              biu_type_i,     //burst type
  input  biu_prot_t              biu_prot_i,     //protection
  input  logic                   biu_lock_i,
  input  logic                   biu_we_i,
  input  logic [DATA_SIZE  -1:0] biu_d_i,
  output logic [DATA_SIZE  -1:0] biu_q_o,
  output logic                   biu_ack_o,      //transfer acknowledge
  output logic                   biu_err_o,      //transfer error
  input  logic [TAG_SIZE   -1:0] biu_tagi_i,     //TAG input
  output logic [TAG_SIZE   -1:0] biu_tago_o      //TAG output
);

  //////////////////////////////////////////////////////////////////
  //
  // Constants
  //


  //////////////////////////////////////////////////////////////////
  //
  // Functions
  //
  function automatic [HSIZE_SIZE-1:0] biu_size2hsize;
    input biu_size_t size;

    case (size)
      BYTE   : biu_size2hsize = HSIZE_BYTE;
      HWORD  : biu_size2hsize = HSIZE_HWORD;
      WORD   : biu_size2hsize = HSIZE_WORD;
      DWORD  : biu_size2hsize = HSIZE_DWORD;
      default: biu_size2hsize = 3'hx; //OOPSS
    endcase
  endfunction: biu_size2hsize


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


  //convert burst type to counter length (actually length -1)
  function automatic [HBURST_SIZE-1:0] biu_type2hburst;
    input biu_type_t biu_type;

    case (biu_type)
      SINGLE : biu_type2hburst = HBURST_SINGLE;
      INCR   : biu_type2hburst = HBURST_INCR;
      WRAP4  : biu_type2hburst = HBURST_WRAP4;
      INCR4  : biu_type2hburst = HBURST_INCR4;
      WRAP8  : biu_type2hburst = HBURST_WRAP8;
      INCR8  : biu_type2hburst = HBURST_INCR8;
      WRAP16 : biu_type2hburst = HBURST_WRAP16;
      INCR16 : biu_type2hburst = HBURST_INCR16;
      default: biu_type2hburst = 3'hx; //OOPS
    endcase
  endfunction: biu_type2hburst


  //convert burst type to counter length (actually length -1)
  function automatic [HPROT_SIZE-1:0] biu_prot2hprot;
    input biu_prot_t biu_prot;

    biu_prot2hprot  = biu_prot & PROT_DATA       ? HPROT_DATA       : HPROT_OPCODE;
    biu_prot2hprot |= biu_prot & PROT_PRIVILEGED ? HPROT_PRIVILEGED : HPROT_USER;
    biu_prot2hprot |= biu_prot & PROT_CACHEABLE  ? HPROT_CACHEABLE  : HPROT_NON_CACHEABLE;
  endfunction: biu_prot2hprot


  //calculate next burst address
  function automatic [ADDR_SIZE-1:0] nxt_addr;
    input [ADDR_SIZE  -1:0] addr;   //current address
    input [HBURST_SIZE-1:0] hburst; //AHB HBURST
    input [HSIZE_SIZE -1:0] hsize;  //AHB HSIZE

    logic [ADDR_SIZE-1:0] mask;


    //next linear address
    nxt_addr = addr + (1 << hsize);

    //align to boundary
    nxt_addr = nxt_addr & ({ADDR_SIZE{1'b1}} << hsize);

    //wrap?
    case (hburst)
      HBURST_WRAP4 : mask = {{ADDR_SIZE-2{1'b1}}, 2'h0} << hsize;
      HBURST_WRAP8 : mask = {{ADDR_SIZE-3{1'b1}}, 3'h0} << hsize;
      HBURST_WRAP16: mask = {{ADDR_SIZE-4{1'b1}}, 4'h0} << hsize;
      default      : mask = {ADDR_SIZE{1'b0}};
    endcase

    //mix linear/wrap address
    nxt_addr = (addr & mask) | (nxt_addr & ~mask);
  endfunction: nxt_addr


  //check if 1kB boundary is crossed
  //The checking works for all incremental bursts, but only INCR is
  //managed here.   //INCR4/8/16 must be managed by the calling module
  function logic cross1kB;
    input [ADDR_SIZE -1:0] addr;
    input [HSIZE_SIZE-1:0] hsize;

    logic [ADDR_SIZE-1:0] nxt_addr;

    //next linear address
    nxt_addr = addr + (1 << hsize);

    //Now check if 1kB border is crossed
    cross1kB = STRICT_AHB == 0 ? 1'b0 : addr[9] ^ nxt_addr[9];
  endfunction: cross1kB


  //////////////////////////////////////////////////////////////////
  //
  // Variables
  //
  logic [          3:0] burst_cnt;
  logic                 data_ena,
                        ddata_ena;

  logic [DATA_SIZE-1:0] biu_di_dly;

  logic                 incr_burst;

  logic [TAG_SIZE -1:0] tag;

  //////////////////////////////////////////////////////////////////
  //
  // Module Body
  //


  /*
   * State Machine
   */
  always @(posedge HCLK, negedge HRESETn)
    if (!HRESETn)
    begin
        data_ena    <= 1'b0;
        biu_err_o   <= 1'b0;
        burst_cnt   <=  'h0;
	incr_burst  <= 1'b0;
	tag         <=  'h0; //dont care

        HSEL        <= 1'b0;
        HADDR       <=  'h0;
        HWRITE      <= 1'b0;
        HSIZE       <=  'hx; //dont care
        HBURST      <=  'hx; //dont care
        HPROT       <= HPROT_DATA | HPROT_PRIVILEGED | HPROT_NON_BUFFERABLE | HPROT_NON_CACHEABLE;
        HTRANS      <= HTRANS_IDLE;
        HMASTLOCK   <= 1'b0;
    end
    else
    begin
        //strobe/ack signals
        biu_err_o   <= 1'b0;
        incr_burst  <= incr_burst & biu_stb_i; // kill incr_burst when biu_stb_i drops

        if (HREADY)
        begin
            if (~|burst_cnt && !incr_burst)  //burst complete or start of INCR burst
            begin
                if (biu_stb_i && !biu_err_o)
                begin
                    data_ena    <= 1'b1;
                    burst_cnt   <= biu_type2cnt(biu_type_i);
                    incr_burst  <= biu_type2hburst(biu_type_i) == INCR;
                    tag         <= biu_tagi_i;

                    HSEL        <= 1'b1;
                    HTRANS      <= HTRANS_NONSEQ; //start of burst
                    HADDR       <= biu_adri_i;
                    HWRITE      <= biu_we_i;
                    HSIZE       <= biu_size2hsize (biu_size_i);
                    HBURST      <= biu_type2hburst(biu_type_i);
                    HPROT       <= biu_prot2hprot (biu_prot_i);
                    HMASTLOCK   <= biu_lock_i;
                end
                else
                begin
                    data_ena   <= 1'b0;
                    incr_burst <= 1'b0;

                    HSEL       <= 1'b0;
                    HTRANS     <= HTRANS_IDLE; //no new transfer
                    HMASTLOCK  <= biu_lock_i;
                end
            end
            else //continue burst
            begin
                if (biu_type_i == INCR)
                begin
                    data_ena   <= biu_stb_i;
                    burst_cnt  <= 'h0; //continuous incrementing burst
                    incr_burst <= biu_stb_i;
                    tag        <= biu_tagi_i;

                    HSEL       <= biu_stb_i;
                    HTRANS     <= biu_stb_i ? cross1kB(HADDR,HSIZE) ? HTRANS_NONSEQ : HTRANS_SEQ
                                            : HTRANS_IDLE;
                    HADDR      <= nxt_addr(HADDR,HBURST,HSIZE);
//for BUSY                    HADDR      <= biu_stb_i ? nxt_addr(HADDR,HBURST,HSIZE) : HADDR;
		end
                else
                begin
                    data_ena   <= 1'b1;
                    burst_cnt  <= burst_cnt -1;
                    incr_burst <= 1'b0;

                    HTRANS     <= cross1kB(HADDR,HSIZE) ? HTRANS_NONSEQ : HTRANS_SEQ; //continue burst
                    HADDR      <= nxt_addr(HADDR,HBURST,HSIZE); //next address
                end
            end
        end
        else
        begin
            //error response
            if (HRESP == HRESP_ERROR)
            begin
                burst_cnt  <= 'h0; //burst done (interrupted)
                incr_burst <= 1'b0;

                HSEL       <= 1'b0;
                HTRANS     <= HTRANS_IDLE;

                data_ena   <= 1'b0;
                biu_err_o  <= 1'b1;
            end
        end
    end


  //Data section
  always @(posedge HCLK) 
    if (HREADY) biu_di_dly <= biu_d_i;

  always @(posedge HCLK)
    if (HREADY)
    begin
        HWDATA     <= biu_di_dly;
        biu_adro_o <= HADDR;
	biu_tago_o <= tag;
    end

  always @(posedge HCLK,negedge HRESETn)
    if      (!HRESETn) ddata_ena <= 1'b0;
    else if ( HREADY ) ddata_ena <= data_ena;


  assign biu_q_o        = HRDATA;
  assign biu_ack_o      = HREADY & ddata_ena;
  assign biu_d_ack_o    = HREADY & data_ena;
  assign biu_stb_ack_o  = HREADY & ~|burst_cnt & biu_stb_i & ~biu_err_o;
endmodule



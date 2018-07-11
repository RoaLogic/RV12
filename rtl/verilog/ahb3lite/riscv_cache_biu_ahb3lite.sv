/////////////////////////////////////////////////////////////////
//                                                             //
//    ██████╗  ██████╗  █████╗                                 //
//    ██╔══██╗██╔═══██╗██╔══██╗                                //
//    ██████╔╝██║   ██║███████║                                //
//    ██╔══██╗██║   ██║██╔══██║                                //
//    ██║  ██║╚██████╔╝██║  ██║                                //
//    ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═╝                                //
//          ██╗      ██████╗  ██████╗ ██╗ ██████╗              //
//          ██║     ██╔═══██╗██╔════╝ ██║██╔════╝              //
//          ██║     ██║   ██║██║  ███╗██║██║                   //
//          ██║     ██║   ██║██║   ██║██║██║                   //
//          ███████╗╚██████╔╝╚██████╔╝██║╚██████╗              //
//          ╚══════╝ ╚═════╝  ╚═════╝ ╚═╝ ╚═════╝              //
//                                                             //
//    RISC-V                                                   //
//    Cache Bus Interface Unit - AHB3Lite                      //
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

module riscv_cache_biu_ahb3lite #(
  parameter XLEN           = 32,
  parameter PHYS_ADDR_SIZE = XLEN
)
(
  input                           HRESETn,
  input                           HCLK,
 
  //AHB3 Lite Bus
  output                          HSEL,
  output reg [PHYS_ADDR_SIZE-1:0] HADDR,
  input  reg [XLEN          -1:0] HRDATA,
  output reg [XLEN          -1:0] HWDATA,
  output reg                      HWRITE,
  output reg [               2:0] HSIZE,
  output reg [               2:0] HBURST,
  output reg [               3:0] HPROT,
  output reg [               1:0] HTRANS,
  output reg                      HMASTLOCK,
  input                           HREADY,
  input                           HRESP,

  //From Cache Controller Core
  input                           biu_stb,
  output                          biu_stb_ack,
  input      [PHYS_ADDR_SIZE-1:0] biu_adri,
  output reg [PHYS_ADDR_SIZE-1:0] biu_adro,  
  input      [XLEN/8        -1:0] biu_be,       //Byte enables
  input      [               2:0] biu_type,     //burst type -AHB style
  input                           biu_lock,
  input                           biu_we,
  input      [XLEN          -1:0] biu_di,
  output     [XLEN          -1:0] biu_do,
  output                          biu_wack,     //data acknowledge, 1 per data
                                  biu_rack,
  output reg                      biu_err,      //data error

  input                           biu_is_cacheable,
                                  biu_is_instruction,
  input       [              1:0] biu_prv
);

  //////////////////////////////////////////////////////////////////
  //
  // Constants
  //
  import ahb3lite_pkg::*;
  import riscv_state_pkg::*;


  //////////////////////////////////////////////////////////////////
  //
  // Typedefs
  //
  function [2:0] be2hsize;
    input [XLEN/8-1:0] be;

    if (XLEN==32)
      case (be)
        4'b0001: be2hsize = HSIZE_BYTE;
        4'b0010: be2hsize = HSIZE_BYTE;
        4'b0100: be2hsize = HSIZE_BYTE;
        4'b1000: be2hsize = HSIZE_BYTE;
        4'b0011: be2hsize = HSIZE_HWORD;
        4'b1100: be2hsize = HSIZE_HWORD;
        4'b1111: be2hsize = HSIZE_WORD;
        default: be2hsize = 'hx; // OOPSSS
      endcase
    else //RV64
      case (be)
        8'b0000_0001: be2hsize = HSIZE_BYTE;
        8'b0000_0010: be2hsize = HSIZE_BYTE;
        8'b0000_0100: be2hsize = HSIZE_BYTE;
        8'b0000_1000: be2hsize = HSIZE_BYTE;
        8'b0001_0000: be2hsize = HSIZE_BYTE;
        8'b0010_0000: be2hsize = HSIZE_BYTE;
        8'b0100_0000: be2hsize = HSIZE_BYTE;
        8'b1000_0000: be2hsize = HSIZE_BYTE;
        8'b0000_0011: be2hsize = HSIZE_HWORD;
        8'b0000_1100: be2hsize = HSIZE_HWORD;
        8'b0011_0000: be2hsize = HSIZE_HWORD;
        8'b1100_0000: be2hsize = HSIZE_HWORD;
        8'b0000_1111: be2hsize = HSIZE_WORD;
        8'b1111_0000: be2hsize = HSIZE_WORD;
        8'b1111_1111: be2hsize = HSIZE_DWORD;
        default     : be2hsize = 'hx; // OOPSSS
      endcase
  endfunction


  //convert burst type to counter length (actually length -1)
  function [3:0] type2cnt;
    input [2:0] btype;

    case (btype)
      3'b000: type2cnt =  0;
      3'b001: type2cnt =  0;
      3'b010: type2cnt =  3;
      3'b011: type2cnt =  3;
      3'b100: type2cnt =  7;
      3'b101: type2cnt =  7;
      3'b110: type2cnt = 15;
      3'b111: type2cnt = 15;
    endcase
  endfunction


  //convert burst type to counter length (actually length -1)
  function [PHYS_ADDR_SIZE-1:0] nxt_addr;
    input [PHYS_ADDR_SIZE-1:0] addr;   //current address
    input [               3:0] hburst; //AHB HBURST


    //next linear address
    if (XLEN==32) nxt_addr = (addr + 'h4) & ~'h3;
    else          nxt_addr = (addr + 'h8) & ~'h7;

    //wrap?
    case (hburst)
      HBURST_WRAP4 : nxt_addr = (XLEN==32) ? {addr[PHYS_ADDR_SIZE-1: 4],nxt_addr[3:0]} : {addr[PHYS_ADDR_SIZE-1:5],nxt_addr[4:0]};
      HBURST_WRAP8 : nxt_addr = (XLEN==32) ? {addr[PHYS_ADDR_SIZE-1: 5],nxt_addr[4:0]} : {addr[PHYS_ADDR_SIZE-1:6],nxt_addr[5:0]};
      HBURST_WRAP16: nxt_addr = (XLEN==32) ? {addr[PHYS_ADDR_SIZE-1: 6],nxt_addr[5:0]} : {addr[PHYS_ADDR_SIZE-1:7],nxt_addr[6:0]};
    endcase
  endfunction


  //////////////////////////////////////////////////////////////////
  //
  // Variables
  //
  logic [     3:0] burst_cnt;
  logic            data_ena,
                   ddata_ena;
  logic [XLEN-1:0] biu_di_dly;
  logic            dHWRITE;


  //////////////////////////////////////////////////////////////////
  //
  // Module Body
  //


  /*
   * State Machine
   */
  assign HSEL = 1'b1;

  always @(posedge HCLK, negedge HRESETn)
    if (!HRESETn)
    begin
        data_ena    <= 1'b0;
        biu_err     <= 1'b0;
        burst_cnt   <= 'h0;

        HADDR       <= 'h0;
        HWRITE      <= 1'b0;
        HSIZE       <= 'h0; //dont care
        HBURST      <= 'h0; //dont care
        HPROT       <= HPROT_DATA | HPROT_PRIVILEGED | HPROT_NON_BUFFERABLE | HPROT_NON_CACHEABLE;
        HTRANS      <= HTRANS_IDLE;
        HMASTLOCK   <= 1'b0;
    end
    else
    begin
        //strobe/ack signals
        biu_err     <= 1'b0;

        if (HREADY)
        begin
            if (~|burst_cnt)  //burst complete
            begin
                if (biu_stb && !biu_err)
                begin
                    data_ena    <= 1'b1;
                    burst_cnt   <= type2cnt(biu_type);

                    HTRANS      <= HTRANS_NONSEQ; //start of burst
                    HADDR       <= biu_adri;
                    HWRITE      <= biu_we;
                    HSIZE       <= be2hsize(biu_be);
                    HBURST      <= biu_type;
                    HPROT       <= (biu_prv==PRV_U     ? HPROT_USER      : HPROT_PRIVILEGED   ) |
                                   (biu_is_instruction ? HPROT_OPCODE    : HPROT_DATA         ) |
                                   (biu_is_cacheable   ? HPROT_CACHEABLE : HPROT_NON_CACHEABLE);
                    HMASTLOCK   <= biu_lock;
                end
                else
                begin
                    data_ena  <= 1'b0;
                    HTRANS    <= HTRANS_IDLE; //no new transfer
                    HMASTLOCK <= biu_lock;
                end
            end
            else //continue burst
            begin
                data_ena  <= 1'b1;
                burst_cnt <= burst_cnt - 'h1;

                HTRANS    <= HTRANS_SEQ; //continue burst
                HADDR     <= nxt_addr(HADDR,HBURST); //next address
            end
        end
        else
        begin
            //error response
            if (HRESP == HRESP_ERROR)
            begin
                burst_cnt <= 'h0; //burst done (interrupted)
                HTRANS    <= HTRANS_IDLE;

                data_ena  <= 1'b0;
                biu_err   <= 1'b1;
            end
        end
    end


  //Data section
  always @(posedge HCLK) 
    if (HREADY) biu_di_dly <= biu_di;

  always @(posedge HCLK)
    if (HREADY)
    begin
        HWDATA    <= biu_di_dly;
        biu_adro  <= HADDR;
    end

  always @(posedge HCLK,negedge HRESETn)
    if      (!HRESETn) ddata_ena <= 1'b0;
    else if ( HREADY ) ddata_ena <= data_ena;

  always @(posedge HCLK)
    if (HREADY) dHWRITE <= HWRITE;

  assign biu_do   = HRDATA;
  assign biu_wack = HREADY &   HWRITE &  data_ena;
  assign biu_rack = HREADY & ~dHWRITE & ddata_ena;
  assign biu_stb_ack = HREADY & ~|burst_cnt & biu_stb & ~biu_err;
endmodule



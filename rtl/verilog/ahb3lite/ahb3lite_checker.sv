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
//    AHB3-Lite Protocol Checker                               //
//                                                             //
/////////////////////////////////////////////////////////////////
//                                                             //
//     Copyright (C) 2015 ROA Logic BV                         //
//                                                             //
//    This confidential and proprietary software is provided   //
//  under license. It may only be used as authorised by a      //
//  licensing agreement from ROA Logic BV.                     //
//  No parts may be copied, reproduced, distributed, modified  //
//  or adapted in any form without prior written consent.      //
//  This entire notice must be reproduced on all authorised    //
//  copies.                                                    //
//                                                             //
//    TO THE MAXIMUM EXTENT PERMITTED BY LAW, IN NO EVENT      //
//  SHALL ROA LOGIC BE LIABLE FOR ANY INDIRECT, SPECIAL,       //
//  CONSEQUENTIAL OR INCIDENTAL DAMAGES WHATSOEVER (INCLUDING, //
//  BUT NOT LIMITED TO, DAMAGES FOR LOSS OF PROFIT, BUSINESS   //
//  INTERRUPTIONS OR LOSS OF INFORMATION) ARISING OUT OF THE   //
//  USE OR INABILITY TO USE THE PRODUCT WHETHER BASED ON A     //
//  CLAIM UNDER CONTRACT, TORT OR OTHER LEGAL THEORY, EVEN IF  //
//  ROA LOGIC WAS ADVISED OF THE POSSIBILITY OF SUCH DAMAGES.  //
//  IN NO EVENT WILL ROA LOGIC BE LIABLE TO ANY AGGREGATED     //
//  CLAIMS MADE AGAINST ROA LOGIC GREATER THAN THE FEES PAID   //
//  FOR THE PRODUCT                                            //
//                                                             //
/////////////////////////////////////////////////////////////////
 
//  CVS Log
//
//  $Id: $
//
//  $Date: $
//  $Revision: $
//  $Author: $
//
// Change History:
//   $Log: $
//


module ahb3lite_checker #(
  parameter ADDR_SIZE     = 32,
  parameter DATA_SIZE     = 32
)
(
  //AHB Interface
  input                        HRESETn,
  input                        HCLK,

  input                        HSEL,
  input      [ ADDR_SIZE -1:0] HADDR,
  input      [ DATA_SIZE -1:0] HWDATA,
  input      [ DATA_SIZE -1:0] HRDATA,
  input                        HWRITE,
  input      [            2:0] HSIZE,
  input      [            2:0] HBURST,
  input      [            3:0] HPROT,
  input      [            1:0] HTRANS,
  input                        HMASTLOCK,
  input                        HREADY,
  input                        HRESP
);
  //////////////////////////////////////////////////////////////////
  //
  // Constants
  //
  import ahb3lite_pkg::*;


  //////////////////////////////////////////////////////////////////
  //
  // Variables
  //
  logic                  is_burst,
                         last_burst_beat;
  logic                  prev_hsel;
  logic [           1:0] prev_htrans;
  logic [           2:0] prev_hburst;
  logic                  prev_hwrite;
  logic [ ADDR_SIZE-1:0] prev_haddr;
  logic [ DATA_SIZE-1:0] prev_hwdata,
                         prev_hrdata;
  logic                  prev_hready,
                         prev_hresp;
  logic	[	    2:0] prev_hsize;  // added

  integer                burst_cnt;



  //////////////////////////////////////////////////////////////////
  //
  // Tasks
  //

  /*
   * Check HTRANS
   */
  task check_htrans;
    if (HTRANS == HTRANS_IDLE)
    begin
        //IDLE after BUSY only during a undefined length burst
        if (is_burst && prev_htrans == HTRANS_BUSY && prev_hburst != HBURST_INCR)
        begin
            $display ("AHB ERROR (%m): Illegal termination of a fixed length burst @%0t", $time);
        end

        //IDLE only when non-incrementing burst terminates
        if (is_burst && prev_hburst != HBURST_INCR && !last_burst_beat)
        begin
            $display ("AHB ERROR (%m): Expected HTRANS=SEQ or BUSY, received IDLE @%0t", $time);
        end
    end

    if (HTRANS == HTRANS_BUSY)
    begin
        //BUSY only during a burst
        if (!is_burst)
          $display ("AHB ERROR (%m): HTRANS=BUSY, but not a burst transfer @%0t", $time);
    end

    if (HTRANS == HTRANS_NONSEQ)
    begin
        //NONSEQ after BUSY only during undefined length burst
        if (is_burst && prev_htrans == HTRANS_BUSY && prev_hburst != HBURST_INCR)
        begin
            $display ("AHB ERROR (%m): Illegal termination of a fixed length burst @%0t", $time);
        end

        //NONSEQ only when burst terminates
        if (is_burst && prev_hburst != HBURST_INCR && !last_burst_beat)
        begin
            $display ("AHB ERROR (%m): Expected HTRANS=SEQ or BUSY, received NONSEQ @%0t", $time);
        end
    end

    if (HTRANS == HTRANS_SEQ)
    begin
        //SEQ only during a burst
        if (!is_burst) // || last_burst_beat)
          $display("AHB ERROR (%m): HTRANS=SEQ, but not a burst transfer @%0t", $time);
    end


    //HTRANS must remain stable when slave not ready
    if (!prev_hready && HTRANS != prev_htrans)
    begin
        $display ("AHB ERROR (%m): HTRANS must remain stable during wait states @%0t", $time);
    end
  endtask //check_htrans



  /*
   * Check HSIZE
   */
  task check_hsize;
    //Check HSIZE versus data bus width
    logic out_of_range;

    case (HSIZE)
       HSIZE_B1024: out_of_range = DATA_SIZE < 1024 ? 1'b1 : 1'b0;
       HSIZE_B512 : out_of_range = DATA_SIZE <  512 ? 1'b1 : 1'b0;
       HSIZE_B256 : out_of_range = DATA_SIZE <  256 ? 1'b1 : 1'b0;
       HSIZE_B128 : out_of_range = DATA_SIZE <  128 ? 1'b1 : 1'b0;
       HSIZE_DWORD: out_of_range = DATA_SIZE <   64 ? 1'b1 : 1'b0;
       HSIZE_WORD : out_of_range = DATA_SIZE <   32 ? 1'b1 : 1'b0;
       HSIZE_HWORD: out_of_range = DATA_SIZE <   16 ? 1'b1 : 1'b0;
       default    : out_of_range = 1'b0;
    endcase

    if (out_of_range)
    begin
        //TODO: Change to ASSERT
        $display ("AHB ERROR (%m): Illegal HSIZE (%0b) @%0t", HSIZE, $time);
    end

    //HSIZE must remain stable during a burst
    if (is_burst && !last_burst_beat && HSIZE != prev_hsize)
    begin
        $display ("AHB ERROR (%m): HSIZE must remain stable during burst @%0t", $time);
    end

    //HSIZE must remain stable when slave not ready
    if (!prev_hready && HSIZE != prev_hsize)
    begin
        $display ("AHB ERROR (%m): HSIZE must remain stable during wait states @%0t", $time);
    end
  endtask //check_hsize



  /*
   * Check HBURST
   */
  task check_hburst;
    //HBURST must remain stable during a burst
    //1st line checks fixed length burst
    //2nd line checks undefinite (INCR) burst
    if ( (is_burst && prev_hburst != HBURST_INCR && !last_burst_beat && HBURST != prev_hburst) ||
         (prev_hburst == HBURST_INCR && HTRANS != HTRANS_IDLE && HTRANS != HTRANS_NONSEQ && HBURST != prev_hburst) )
    begin
        $display ("AHB ERROR (%m): HBURST must remain stable during burst @%0t", $time);
    end

    //HBURST must remain stable when slave not ready
    if (!HREADY && HBURST != prev_hburst)
    begin
        $display ("AHB ERROR (%m): HBURST must remain stable during wait states @%0t", $time);
    end
  endtask //check_hburst



  /*
   * Check HWRITE
   */
  task check_hwrite;
    //HWRITE must remain stable during a burst
    if (is_burst && !last_burst_beat && HWRITE != prev_hwrite)
    begin
        $display ("AHB ERROR (%m): HWRITE must remain stable during burst @%0t", $time);
    end

    //HWRITE must remain stable when slave not ready
    if (!prev_hready && HWRITE != prev_hwrite)
    begin
        $display ("AHB ERROR (%m): HWRITE must remain stable during wait states @%0t", $time);
    end
  endtask //check_hwrite



  /*
   * Check HADDR
   */
  task check_haddr;
    //HADDR should increase by HSIZE during bursts (wrap for wrapping-bursts)
    logic incr_haddr;
    logic [ADDR_SIZE-1:0] nxt_haddr;
    logic [ADDR_SIZE-1:0] nxt_addr;  // added

    //normalize address
    case (HSIZE)
       HSIZE_B1024: nxt_addr = prev_haddr >> 7;
       HSIZE_B512 : nxt_addr = prev_haddr >> 6;
       HSIZE_B256 : nxt_addr = prev_haddr >> 5;
       HSIZE_B128 : nxt_addr = prev_haddr >> 4;
       HSIZE_DWORD: nxt_addr = prev_haddr >> 3;
       HSIZE_WORD : nxt_addr = prev_haddr >> 2;
       HSIZE_HWORD: nxt_addr = prev_haddr >> 1;
       default    : ;
    endcase

    //next address
    nxt_addr = nxt_addr +1;

    //handle normalized wrap
    case (HBURST)
       HBURST_WRAP4 : nxt_addr = {prev_haddr[ADDR_SIZE-1:2],nxt_addr[1:0]};
       HBURST_WRAP8 : nxt_addr = {prev_haddr[ADDR_SIZE-1:3],nxt_addr[2:0]}; 
       HBURST_WRAP16: nxt_addr = {prev_haddr[ADDR_SIZE-1:4],nxt_addr[3:0]};
    endcase

    //move into correct address range
    case (HSIZE)
       HSIZE_B1024: nxt_addr = nxt_addr << 7;
       HSIZE_B512 : nxt_addr = nxt_addr << 6;
       HSIZE_B256 : nxt_addr = nxt_addr << 5;
       HSIZE_B128 : nxt_addr = nxt_addr << 4;
       HSIZE_DWORD: nxt_addr = nxt_addr << 3;
       HSIZE_WORD : nxt_addr = nxt_addr << 2;
       HSIZE_HWORD: nxt_addr = nxt_addr << 1;
       default    : ;
    endcase

    if (is_burst && HREADY && HADDR != nxt_haddr)
    begin
        $display ("AHB ERROR (%m): Received HADDR=%0x, expected %0x @%0t", HADDR, nxt_addr, $time);
    end


    //HADDR must remain stable when slave not ready
    if (!prev_hready && HADDR != prev_haddr)
    begin
        $display ("AHB ERROR (%m): HADDR must remain stable during wait states @%0t", $time);
    end
  endtask //check_haddr



  /*
   * Check HWDATA
   */
  task check_hwdata;
    //HWDATA must remain stable when slave not ready
    if (!prev_hready && HWDATA != prev_hwdata)
    begin
        $display ("AHB ERROR (%m): HWDATA must remain stable during wait states @%0t", $time);
    end
  endtask //check_hwdata



  /*
   * Check slave response
   */
  task check_slave_response;
    //Always zero-wait-state response to IDLE
    //Unless slave already inserted wait-states
    if (prev_hready && (prev_htrans == HTRANS_IDLE) && (!HREADY || (HRESP != HRESP_OKAY)))
    begin
        $display ("AHB ERROR (%m): Slave must provide a zero wait state response to IDLE transfers (HREADY=%0b, HRESP=%0b) @%0t", HREADY, HRESP, $time);
    end

    //always zero-wait-state response to BUSY
    //unless slave already inserted wait-states
    if (prev_hready && (prev_htrans == HTRANS_BUSY) && (!HREADY || (HRESP != HRESP_OKAY)) )
    begin
        $display ("AHB ERROR (%m): Slave must provide a zero wait state response to BUSY transfers (HREADY=%0b, HRESP=%0b) @%0t", HREADY, HRESP, $time);
    end


    //ERROR is a 2 cycle response
    if ( ( ( HREADY      && HRESP     ) && !(!prev_hready && prev_hresp) ) ||
         ( (!prev_hready && prev_hresp) && !( HREADY      && HRESP     ) ) )
    begin
        $display ("AHB ERROR (%m): Incorrect ERROR sequence @%0t", $time);
    end
  endtask //check_slave_response


  //////////////////////////////////////////////////////////////////
  //
  // Functions
  //


  //////////////////////////////////////////////////////////////////
  //
  // Module Body
  //

  /*
   * Check HTRANS
   */
  always @(posedge HCLK,negedge HRESETn)
    if (!HRESETn) prev_htrans <= HTRANS_IDLE;
    else          prev_htrans <= HTRANS;


  always @(posedge HCLK,negedge HRESETn)
    if      (!HRESETn) is_burst <= 1'b0;
    else if ( HREADY )
    begin
        if      ( HTRANS == HTRANS_IDLE   ) is_burst <= 1'b0;
        else if ( HTRANS == HTRANS_NONSEQ &&
                  HBURST != HBURST_SINGLE ) is_burst <= 1'b1;
        else if ( HBURST == HTRANS_NONSEQ &&
                  HBURST == HBURST_SINGLE ) is_burst <= 1'b0; //terminated INCR burst
        else if ( last_burst_beat         ) is_burst <= 1'b0; //terminated regular burst
    end

  always @(posedge HCLK) check_htrans();


  /*
   * Check HSIZE
   */
  always @(posedge HCLK) prev_hsize <= HSIZE;
  always @(posedge HCLK) check_hsize();


  /*
   * Check HBURST
   */
  always @(posedge HCLK)
    if (HREADY)
    begin
        if (HTRANS == HTRANS_NONSEQ)
        begin
            case (HBURST)
               HBURST_WRAP4 : burst_cnt <=  2; // 4
               HBURST_INCR4 : burst_cnt <=  2; // 4
               HBURST_WRAP8 : burst_cnt <=  6; // 8
               HBURST_INCR8 : burst_cnt <=  6; // 8
               HBURST_WRAP16: burst_cnt <= 14; //16
               HBURST_INCR16: burst_cnt <= 14; //16
               default      : burst_cnt <= -1;
            endcase
        end
        else if (HTRANS == HTRANS_SEQ)
        begin
            burst_cnt <= burst_cnt -1;
        end
    end

  assign last_burst_beat = ~|burst_cnt;

  always @(posedge HCLK) prev_hburst <= HBURST;
  always @(posedge HCLK) check_hburst();


  /*
   * Check HADDR
   */
  always @(posedge HCLK) prev_haddr <= HADDR;
  always @(posedge HCLK) check_haddr();


  /*
   * Check HWDATA
   */
  always @(posedge HCLK) prev_hwdata <= HWDATA;
  always @(posedge HCLK) check_hwdata();


  /*
   * Check HWRITE
   */
  always @(posedge HCLK) prev_hwrite <= HWRITE;
  always @(posedge HCLK) check_hwrite();


  /*
   * Check Slave response
   */
  always @(posedge HCLK) prev_hready <= HREADY;
  always @(posedge HCLK) prev_hresp <= HRESP;
  always @(posedge HCLK) check_slave_response();
endmodule



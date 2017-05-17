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
//    Testbench Top Level AHB3-Lite Interfaces                 //
//                                                             //
/////////////////////////////////////////////////////////////////
//                                                             //
//     Copyright (C) 2014-2015 ROA Logic BV                    //
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

// Change History:
//   2017-02-22: Updated to new memory map
//

module testbench_top; 

//core parameters
parameter XLEN             = 64;
parameter PHYS_ADDR_SIZE   = 32;           //32bit address bus. Also sets non-cacheable range
parameter PC_INIT          = 'h8000_0000;  //Start here after reset
parameter BASE             = PC_INIT;      //offset where to load program in memory
parameter INIT_FILE        = "test.hex";
parameter MEM_LATENCY      = 1;
parameter WRITEBUFFER_SIZE = 8;
parameter HAS_U            = 1;
parameter HAS_S            = 1;
parameter HAS_H            = 0;
parameter HAS_MMU          = 0;
parameter HAS_FPU          = 0;
parameter HAS_AMO          = 0;
parameter HAS_MULDIV       = 0;
parameter MULT_LATENCY     = 0;
parameter CORES            = 1;
parameter HTIF             = 0; //Host-interface

//caches
parameter ICACHE_SIZE      = 0;
parameter DCACHE_SIZE      = 0;


//////////////////////////////////////////////////////////////////
//
// Constants
//
import ahb3lite_pkg::*;

localparam MULLAT = MULT_LATENCY > 4 ? 4 : MULT_LATENCY;


//////////////////////////////////////////////////////////////////
//
// Variables
//
logic                      HCLK, HRESETn;

//Instruction interface
logic                      ins_HSEL;
logic [PHYS_ADDR_SIZE-1:0] ins_HADDR;
logic [XLEN          -1:0] ins_HRDATA;
logic [XLEN          -1:0] ins_HWDATA; //always 0
logic                      ins_HWRITE; //always 0
logic [               2:0] ins_HSIZE;
logic [               2:0] ins_HBURST;
logic [               3:0] ins_HPROT;
logic [               1:0] ins_HTRANS;
logic                      ins_HMASTLOCK;
logic                      ins_HREADY;
logic                      ins_HRESP;

//Data interface
logic                      dat_HSEL;
logic [PHYS_ADDR_SIZE-1:0] dat_HADDR;
logic [XLEN          -1:0] dat_HWDATA;
logic [XLEN          -1:0] dat_HRDATA;
logic                      dat_HWRITE;
logic [               2:0] dat_HSIZE;
logic [               2:0] dat_HBURST;
logic [               3:0] dat_HPROT;
logic [               1:0] dat_HTRANS;
logic                      dat_HMASTLOCK;
logic                      dat_HREADY;
logic                      dat_HRESP;

//Debug Interface
logic              dbp_bp,
                   dbg_stall,
                   dbg_strb,
                   dbg_ack,
                   dbg_we;
logic [      15:0] dbg_addr;
logic [XLEN  -1:0] dbg_dati,
                   dbg_dato;



//Host Interface
logic                      host_csr_req,
                           host_csr_ack,
                           host_csr_we;
logic [XLEN          -1:0] host_csr_tohost,
                           host_csr_fromhost;


//Unified memory interface
logic [               1:0] mem_htrans[2];
logic [               3:0] mem_hburst[2];
logic                      mem_hready[2],
                           mem_hresp[2];
logic [PHYS_ADDR_SIZE-1:0] mem_haddr[2];
logic [XLEN          -1:0] mem_hwdata[2],
                           mem_hrdata[2];
logic [               2:0] mem_hsize[2];
logic                      mem_hwrite[2];


////////////////////////////////////////////////////////////////
//
// Module Body
//
//Hookup Device Under Test


riscv_top_ahb3lite #(
  .XLEN             ( XLEN             ),
  .PHYS_ADDR_SIZE   ( PHYS_ADDR_SIZE   ), //31bit address bus
  .PC_INIT          ( PC_INIT          ),
  .HAS_USER         ( HAS_U            ),
  .HAS_SUPER        ( HAS_S            ),
  .HAS_HYPER        ( HAS_H            ),
  .HAS_AMO          ( HAS_AMO          ),
  .HAS_MULDIV       ( HAS_MULDIV       ),
  .MULT_LATENCY     ( MULLAT           ),

  .WRITEBUFFER_SIZE ( WRITEBUFFER_SIZE ),
  .ICACHE_SIZE      ( ICACHE_SIZE      ),
  .DCACHE_SIZE      ( DCACHE_SIZE      ),

  .MTVEC_DEFAULT    ( 32'h80000004     )
)
dut (
  .ext_nmi  ( 1'b0 ),
  .ext_tint ( 1'b0 ),
  .ext_sint ( 1'b0 ),
  .ext_int  ( 4'h0 ),

  .*
 ); 

//Hookup Debug Unit
dbg_bfm #(
  .DATA_WIDTH ( XLEN ),
  .ADDR_WIDTH ( 16   )
)
dbg_ctrl (
  .rstn ( HRESETn ),
  .clk  ( HCLK    ),

  .cpu_bp_i    ( dbg_bp    ),
  .cpu_stall_o ( dbg_stall ),
  .cpu_stb_o   ( dbg_strb  ),
  .cpu_we_o    ( dbg_we    ),
  .cpu_adr_o   ( dbg_addr  ),
  .cpu_dat_o   ( dbg_dati  ),
  .cpu_dat_i   ( dbg_dato  ),
  .cpu_ack_i   ( dbg_ack   )
);


//bus <-> memory model connections
assign mem_htrans[0] = ins_HTRANS;
assign mem_hburst[0] = ins_HBURST;
assign mem_haddr[0]  = ins_HADDR;
assign mem_hwrite[0] = ins_HWRITE;
assign mem_hsize[0]  = 4'h0;
assign mem_hwdata[0] = {XLEN{1'b0}};
assign ins_HRDATA    = mem_hrdata[0];
assign ins_HREADY    = mem_hready[0];
assign ins_HRESP     = mem_hresp[0];

assign mem_htrans[1] = dat_HTRANS;
assign mem_hburst[1] = dat_HBURST;
assign mem_haddr[1]  = dat_HADDR;
assign mem_hwrite[1] = dat_HWRITE;
assign mem_hsize[1]  = dat_HSIZE;
assign mem_hwdata[1] = dat_HWDATA;
assign dat_HRDATA    = mem_hrdata[1];
assign dat_HREADY    = mem_hready[1];
assign dat_HRESP     = mem_hresp[1];


//hookup memory model
memory_model_ahb3lite #(
  .DATA_WIDTH ( XLEN           ),
  .ADDR_WIDTH ( PHYS_ADDR_SIZE ),
  .BASE       ( BASE           ),
  .PORTS      (              2 ),
  .LATENCY    ( MEM_LATENCY    ) )
unified_memory (
  .HRESETn ( HRESETn ),
  .HCLK   ( HCLK       ),
  .HTRANS ( mem_htrans ),
  .HREADY ( mem_hready ),
  .HRESP  ( mem_hresp  ),
  .HADDR  ( mem_haddr  ),
  .HWRITE ( mem_hwrite ),
  .HSIZE  ( mem_hsize  ),
  .HBURST ( mem_hburst ),
  .HWDATA ( mem_hwdata ),
  .HRDATA ( mem_hrdata ) );


//Front-End Server
generate
  if (HTIF)
  begin
      //Old HTIF interface
      htif #(XLEN)
      htif_inst (
        .rstn              ( HRESETn           ),
        .clk               ( HCLK              ),
        .host_csr_req      ( host_csr_req      ),
        .host_csr_ack      ( host_csr_ack      ),
        .host_csr_we       ( host_csr_we       ),
        .host_csr_tohost   ( host_csr_tohost   ),
        .host_csr_fromhost ( host_csr_fromhost ) );
  end
  else
  begin
      //New MMIO interface
      mmio_if #(XLEN, PHYS_ADDR_SIZE, 32'h80001000)
      mmio_if_inst (
        .HRESETn ( HRESETn ),
        .HCLK    ( HCLK    ),
        .HTRANS  ( dat_HTRANS  ),
        .HWRITE  ( dat_HWRITE  ),
        .HSIZE   ( dat_HSIZE   ),
        .HBURST  ( dat_HBURST  ),
        .HADDR   ( dat_HADDR   ),
        .HWDATA  ( dat_HWDATA  ) );
  end
endgenerate


//Generate clock
always #1 HCLK = ~HCLK;


initial
begin
    $display("\n\n");
    $display ("------------------------------------------------------------");
    $display (" ,------.                    ,--.                ,--.       ");
    $display (" |  .--. ' ,---.  ,--,--.    |  |    ,---. ,---. `--' ,---. ");
    $display (" |  '--'.'| .-. |' ,-.  |    |  |   | .-. | .-. |,--.| .--' ");
    $display (" |  |\\  \\ ' '-' '\\ '-'  |    |  '--.' '-' ' '-' ||  |\\ `--. ");
    $display (" `--' '--' `---'  `--`--'    `-----' `---' `-   /`--' `---' ");
    $display ("- RISC-V Regression Testbench -----------  `---'  ----------");
    $display ("  XLEN | PRIV | MMU | FPU | AMO | MDU | MULLAT | CORES  ");
    $display ("   %3d | %C%C%C%C | %3d | %3d | %3d | %3d | %6d | %3d   ", 
               XLEN, "M", HAS_H > 0 ? "H" : " ", HAS_S > 0 ? "S" : " ", HAS_U > 0 ? "U" : " ",
               HAS_MMU, HAS_FPU, HAS_AMO, HAS_MULDIV, MULLAT, CORES);
    $display ("-------------------------------------------------------------");
    $display ("  Test   = %s", INIT_FILE);
    $display ("  ICache = %0dkB", ICACHE_SIZE);
    $display ("  DCache = %0dkB", DCACHE_SIZE);
    $display ("-------------------------------------------------------------");
    $display ("\n");

`ifdef WAVES
    $shm_open("waves");
    $shm_probe("AS",testbench_top,"AS");
    $display("INFO: Signal dump enabled ...\n\n");
`endif

  unified_memory.read_elf2hex(INIT_FILE);

  HCLK  = 'b0;

  HRESETn = 'b1;
  repeat (5) @(negedge HCLK);
  HRESETn = 'b0;
  repeat (5) @(negedge HCLK);
  HRESETn = 'b1;


  #100;
  //stall CPU
  dbg_ctrl.stall;

  //Enable BREAKPOINT to call external debugger
//  dbg_ctrl.write('h27D4,'h0008);

  //Enable Single Stepping
  dbg_ctrl.write('h27D0,'h1000);

  //single step through 10 instructions
  repeat (100)
  begin
      while (!dbg_ctrl.stall_cpu) @(posedge HCLK);
      repeat(15) @(posedge HCLK);
      dbg_ctrl.unstall;
  end

  //last time ...
  @(posedge HCLK);
  while (!dbg_ctrl.stall_cpu) @(posedge HCLK);
  //disable Single Stepping
  dbg_ctrl.write('h27D0,'h0000);
  dbg_ctrl.unstall;

end		

endmodule



/*
 * MMIO Interface
 */
module mmio_if #(
  parameter HDATA_SIZE = 32,
  parameter HADDR_SIZE = 32,
  parameter CATCH_ADDR = 80001000
)
(
  input                       HRESETn,
  input                       HCLK,

  input      [           1:0] HTRANS,
  input      [HADDR_SIZE-1:0] HADDR,
  input                       HWRITE,
  input      [           2:0] HSIZE,
  input      [           2:0] HBURST,
  input      [HDATA_SIZE-1:0] HWDATA,
  output reg [HDATA_SIZE-1:0] HRDATA,

  output reg                  HREADYOUT,
  output                      HRESP
);
  //
  // Variables
  //
  logic [HDATA_SIZE-1:0] data_reg;
  logic                  catch;

  logic [           1:0] dHTRANS;
  logic [HADDR_SIZE-1:0] dHADDR;
  logic                  dHWRITE;


  //
  // Functions
  //
  function string hostcode_to_string;
    input integer hostcode;

    case (hostcode)
      1337: hostcode_to_string = "OTHER EXCEPTION";
    endcase
  endfunction


  //
  // Module body
  //
  import ahb3lite_pkg::*;


  //Generate watchdog counter
  integer watchdog_cnt;
  always @(posedge HCLK,negedge HRESETn)
    if (!HRESETn) watchdog_cnt <= 0;
    else          watchdog_cnt <= watchdog_cnt +1;


  //Catch write to host address
  assign HRESP = HRESP_OKAY;


  always @(posedge HCLK)
  begin
      dHTRANS <= HTRANS;
      dHADDR  <= HADDR;
      dHWRITE <= HWRITE;
  end


  always @(posedge HCLK,negedge HRESETn)
    if (!HRESETn)
    begin
        HREADYOUT  <= 1'b1;
    end
    else if (HTRANS == HTRANS_IDLE)
    begin
    end


  always @(posedge HCLK,negedge HRESETn)
    if (!HRESETn) catch     <= 1'b0;
    else
    begin
        catch <= dHTRANS == HTRANS_NONSEQ && dHWRITE && dHADDR == CATCH_ADDR;
        data_reg  <= HWDATA;
    end


  //Generate output
  always @(posedge HCLK)
  begin
      if (watchdog_cnt > 200_000 || catch)
      begin
          $display("\n\n");
          $display("-------------------------------------------------------------");
          $display("* RISC-V test bench finished");
          if (data_reg[0] == 1'b1)
          begin
              if (~|data_reg[HDATA_SIZE-1:1])
                $display("* PASSED %0d", data_reg);
              else
                $display ("* FAILED: code: 0x%h (%0d: %s)", data_reg >> 1, data_reg >> 1, hostcode_to_string(data_reg >> 1) );
          end
          else
            $display ("* FAILED: watchdog count reached (%0d) @%0t", watchdog_cnt, $time);
            $display("-------------------------------------------------------------");
          $display("\n");

          $finish();
      end
  end
endmodule



/*
 * HTIF Interface
 */
module htif #(
  parameter XLEN=32
)
(
  input             rstn,
  input             clk,

  output            host_csr_req,
  input             host_csr_ack,
  output            host_csr_we,
  input  [XLEN-1:0] host_csr_tohost,
  output [XLEN-1:0] host_csr_fromhost
);
  function string hostcode_to_string;
    input integer hostcode;

    case (hostcode)
      1337: hostcode_to_string = "OTHER EXCEPTION";
    endcase
  endfunction


  //Generate watchdog counter
  integer watchdog_cnt;
  always @(posedge clk,negedge rstn)
    if (!rstn) watchdog_cnt <= 0;
    else       watchdog_cnt <= watchdog_cnt +1;


  always @(posedge clk)
  begin
      if (watchdog_cnt > 200_000 || host_csr_tohost[0] == 1'b1)
      begin
          $display("\n\n");
          $display("*****************************************************");
          $display("* RISC-V test bench finished");
          if (host_csr_tohost[0] == 1'b1)
          begin
              if (~|host_csr_tohost[XLEN-1:1])
                $display("* PASSED %0d", host_csr_tohost);
              else
                $display ("* FAILED: code: 0x%h (%0d: %s)", host_csr_tohost >> 1, host_csr_tohost >> 1, hostcode_to_string(host_csr_tohost >> 1) );
          end
          else
            $display ("* FAILED: watchdog count reached (%0d) @%0t", watchdog_cnt, $time);
          $display("*****************************************************");
          $display("\n");

          $finish();
      end
  end
endmodule






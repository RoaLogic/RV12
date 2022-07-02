/////////////////////////////////////////////////////////////////////
//   ,------.                    ,--.                ,--.          //
//   |  .--. ' ,---.  ,--,--.    |  |    ,---. ,---. `--' ,---.    //
//   |  '--'.'| .-. |' ,-.  |    |  |   | .-. | .-. |,--.| .--'    //
//   |  |\  \ ' '-' '\ '-'  |    |  '--.' '-' ' '-' ||  |\ `--.    //
//   `--' '--' `---'  `--`--'    `-----' `---' `-   /`--' `---'    //
//                                             `---'               //
//   Roa Logic RISC-V CPU                                          //
//   Testbench Top Level AHB3-Lite Interfaces                      //
//                                                                 //
/////////////////////////////////////////////////////////////////////
//                                                                 //
//             Copyright (C) 2014-2021 ROA Logic BV                //
//             www.roalogic.com                                    //
//                                                                 //
//   This source file may be used and distributed without          //
//   restriction provided that this copyright statement is not     //
//   removed from the file and that any derivative work contains   //
//   the original copyright notice and the associated disclaimer.  //
//                                                                 //
//      THIS SOFTWARE IS PROVIDED ``AS IS'' AND WITHOUT ANY        //
//   EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED     //
//   TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS     //
//   FOR A PARTICULAR PURPOSE. IN NO EVENT SHALL THE AUTHOR OR     //
//   CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,  //
//   SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT  //
//   NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;  //
//   LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)      //
//   HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN     //
//   CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR  //
//   OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS          //
//   SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.  //
//                                                                 //
/////////////////////////////////////////////////////////////////////

// Change History:
//   2017-02-22: Updated to new memory map
//   2017-10-06: Changed header, logo, copyright notice
//

import riscv_pma_pkg::*;
import riscv_state_pkg::*;
import ahb3lite_pkg::*;
import biu_constants_pkg::*;


module testbench_top; 

//core parameters
parameter XLEN             = 64;           //CPU data size
parameter ALEN             = XLEN;         //address bus size
parameter PC_INIT          = 'h8000_0000;  //Start here after reset
parameter BASE             = PC_INIT;      //offset where to load program in memory
parameter INIT_FILE        = "test.hex";
parameter MEM_LATENCY      = 1;
parameter WRITEBUFFER_SIZE = 4;
parameter HAS_U            = 1;
parameter HAS_S            = 1;
parameter HAS_H            = 0;
parameter HAS_MMU          = 0;
parameter HAS_FPU          = 0;
parameter HAS_RVA          = 0;
parameter HAS_RVM          = 0;
parameter HAS_RVC          = 1;
parameter MULT_LATENCY     = 0;
parameter CORES            = 1;

parameter HTIF             = 0; //Host-interface
parameter TOHOST           = 32'h80001000; //HAS_RVC ? 32'h80003000 : 32'h80001000;
parameter UART_TX          = 32'h80001080;


//caches
parameter ICACHE_SIZE      = 0;
parameter DCACHE_SIZE      = 0;

parameter PMA_CNT          = 4;


//////////////////////////////////////////////////////////////////
//
// Constants
//
localparam MULLAT = MULT_LATENCY > 4 ? 4 : MULT_LATENCY;


//////////////////////////////////////////////////////////////////
//
// Variables
//
logic            HCLK, HRESETn;

//PMA configuration
pmacfg_t         pma_cfg [PMA_CNT];
logic [ALEN-1:0] pma_adr [PMA_CNT];

//Instruction interface
logic            ins_HSEL;
logic [ALEN-1:0] ins_HADDR;
logic [XLEN-1:0] ins_HRDATA;
logic [XLEN-1:0] ins_HWDATA; //always 0
logic            ins_HWRITE; //always 0
logic [     2:0] ins_HSIZE;
logic [     2:0] ins_HBURST;
logic [     3:0] ins_HPROT;
logic [     1:0] ins_HTRANS;
logic            ins_HMASTLOCK;
logic            ins_HREADY;
logic            ins_HRESP;

//Data interface
logic            dat_HSEL;
logic [ALEN-1:0] dat_HADDR;
logic [XLEN-1:0] dat_HWDATA;
logic [XLEN-1:0] dat_HRDATA;
logic            dat_HWRITE;
logic [     2:0] dat_HSIZE;
logic [     2:0] dat_HBURST;
logic [     3:0] dat_HPROT;
logic [     1:0] dat_HTRANS;
logic            dat_HMASTLOCK;
logic            dat_HREADY;
logic            dat_HRESP;

//Debug Interface
logic            dbp_bp,
                 dbg_stall,
                 dbg_strb,
                 dbg_ack,
                 dbg_we;
logic [    15:0] dbg_addr;
logic [XLEN-1:0] dbg_dati,
                 dbg_dato;



//Host Interface
logic            host_csr_req,
                 host_csr_ack,
                 host_csr_we;
logic [XLEN-1:0] host_csr_tohost,
                 host_csr_fromhost;


//Unified memory interface
logic            mem_hsel  [2];
logic [     1:0] mem_htrans[2];
logic [     2:0] mem_hburst[2];
logic            mem_hready[2],
                 mem_hresp [2];
logic [ALEN-1:0] mem_haddr [2];
logic [XLEN-1:0] mem_hwdata[2],
                 mem_hrdata[2];
logic [     2:0] mem_hsize [2];
logic            mem_hwrite[2];


////////////////////////////////////////////////////////////////
//
// Module Body
//


//Define PMA regions

//crt.0 (ROM) region
assign pma_adr[0]          = TOHOST >> 2;
assign pma_cfg[0].mem_type = MEM_TYPE_MAIN;
assign pma_cfg[0].r        = 1'b1;
assign pma_cfg[0].w        = 1'b1; //this causes fence_i test to fail, which is expected/correct.
                                   //Set to '1' for fence_i test
assign pma_cfg[0].x        = 1'b1;
assign pma_cfg[0].c        = 1'b1; //Should be '0'. Set to '1' to test dcache fence_i
assign pma_cfg[0].cc       = 1'b0;
assign pma_cfg[0].ri       = 1'b0;
assign pma_cfg[0].wi       = 1'b0;
assign pma_cfg[0].m        = 1'b0;
assign pma_cfg[0].amo_type = AMO_TYPE_NONE;
assign pma_cfg[0].a        = TOR;

//TOHOST region
assign pma_adr[1]          = (TOHOST | ('h7 >>1)) >> 2;
assign pma_cfg[1].mem_type = MEM_TYPE_IO;
assign pma_cfg[1].r        = 1'b0;
assign pma_cfg[1].w        = 1'b1;
assign pma_cfg[1].x        = 1'b0;
assign pma_cfg[1].c        = 1'b0;
assign pma_cfg[1].cc       = 1'b0;
assign pma_cfg[1].ri       = 1'b0;
assign pma_cfg[1].wi       = 1'b0;
assign pma_cfg[1].m        = 1'b0;
assign pma_cfg[1].amo_type = AMO_TYPE_NONE;
assign pma_cfg[1].a        = NAPOT;

//UART-Tx region
assign pma_adr[2]          = UART_TX >> 2;
assign pma_cfg[2].mem_type = MEM_TYPE_IO;
assign pma_cfg[2].r        = 1'b0;
assign pma_cfg[2].w        = 1'b1;
assign pma_cfg[2].x        = 1'b0;
assign pma_cfg[2].c        = 1'b0;
assign pma_cfg[2].cc       = 1'b0;
assign pma_cfg[2].ri       = 1'b0;
assign pma_cfg[2].wi       = 1'b0;
assign pma_cfg[2].m        = 1'b0;
assign pma_cfg[2].amo_type = AMO_TYPE_NONE;
assign pma_cfg[2].a        = NA4;

//RAM region
assign pma_adr[3]          = (1 << 31 | ({32{1'b1}} >> 1)) >> 2;
assign pma_cfg[3].mem_type = MEM_TYPE_MAIN;
assign pma_cfg[3].r        = 1'b1;
assign pma_cfg[3].w        = 1'b1;
assign pma_cfg[3].x        = 1'b1;
assign pma_cfg[3].c        = 1'b1; //1'b1;
assign pma_cfg[3].cc       = 1'b0;
assign pma_cfg[3].ri       = 1'b0;
assign pma_cfg[3].wi       = 1'b0;
assign pma_cfg[3].m        = 1'b0;
assign pma_cfg[3].amo_type = AMO_TYPE_NONE;
assign pma_cfg[3].a        = NAPOT;


//Hookup Device Under Test
riscv_top_ahb3lite #(
  .XLEN             ( XLEN             ),
  .ALEN             ( ALEN             ),
  .PC_INIT          ( PC_INIT          ),
  .HAS_USER         ( HAS_U            ),
  .HAS_SUPER        ( HAS_S            ),
  .HAS_HYPER        ( HAS_H            ),
  .HAS_RVA          ( HAS_RVA          ),
  .HAS_RVM          ( HAS_RVM          ),
  .HAS_RVC          ( HAS_RVC          ),
  .MULT_LATENCY     ( MULLAT           ),

  .PMA_CNT          ( PMA_CNT          ),
  .ICACHE_SIZE      ( ICACHE_SIZE      ),
  .ICACHE_WAYS      ( 2                ),
  .DCACHE_SIZE      ( DCACHE_SIZE      ),
  .DCACHE_WAYS      ( 2                ),
  .WRITEBUFFER_SIZE ( WRITEBUFFER_SIZE ),

  .MTVEC_DEFAULT    ( 32'h80000004     )
)
dut (
  .HRESETn   ( HRESETn ),
  .HCLK      ( HCLK    ),

  .pma_cfg_i ( pma_cfg ),
  .pma_adr_i ( pma_adr ),

  .ext_nmi   ( 1'b0    ),
  .ext_tint  ( 1'b0    ),
  .ext_sint  ( 1'b0    ),
  .ext_int   ( 4'h0    ),

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
assign mem_hsel  [0] = ins_HSEL;
assign mem_htrans[0] = ins_HTRANS;
assign mem_hburst[0] = ins_HBURST;
assign mem_haddr [0] = ins_HADDR;
assign mem_hwrite[0] = ins_HWRITE;
assign mem_hsize [0] = 4'h0;
assign mem_hwdata[0] = {XLEN{1'b0}};
assign ins_HRDATA    = mem_hrdata[0];
assign ins_HREADY    = mem_hready[0];
assign ins_HRESP     = mem_hresp [0];

assign mem_hsel  [1] = dat_HSEL;
assign mem_htrans[1] = dat_HTRANS;
assign mem_hburst[1] = dat_HBURST;
assign mem_haddr [1] = dat_HADDR;
assign mem_hwrite[1] = dat_HWRITE;
assign mem_hsize [1] = dat_HSIZE;
assign mem_hwdata[1] = dat_HWDATA;
assign dat_HRDATA    = mem_hrdata[1];
assign dat_HREADY    = mem_hready[1];
assign dat_HRESP     = mem_hresp [1];


//hookup memory model
memory_model_ahb3lite #(
  .DATA_WIDTH ( XLEN        ),
  .ADDR_WIDTH ( ALEN        ),
  .BASE       ( BASE        ),
  .PORTS      (           2 ),
  .LATENCY    ( MEM_LATENCY ) )
unified_memory (
  .HRESETn ( HRESETn ),
  .HCLK      ( HCLK       ),
  .HSEL      ( mem_hsel   ),
  .HTRANS    ( mem_htrans ),
  .HREADYOUT ( mem_hready ),
  .HREADY    ( mem_hready ),
  .HRESP     ( mem_hresp  ),
  .HADDR     ( mem_haddr  ),
  .HWRITE    ( mem_hwrite ),
  .HSIZE     ( mem_hsize  ),
  .HBURST    ( mem_hburst ),
  .HWDATA    ( mem_hwdata ),
  .HRDATA    ( mem_hrdata ) );


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
      mmio_if #(XLEN, ALEN, TOHOST, UART_TX)
      mmio_if_inst (
        .HRESETn ( HRESETn ),
        .HCLK    ( HCLK        ),
        .HTRANS  ( dat_HTRANS  ),
        .HWRITE  ( dat_HWRITE  ),
        .HSIZE   ( dat_HSIZE   ),
        .HBURST  ( dat_HBURST  ),
        .HADDR   ( dat_HADDR   ),
        .HWDATA  ( dat_HWDATA  ) );
  end
endgenerate


//Hookup Data Memory Access Validator
`define RV_CORE dut.core
dmav #(
  .XLEN          ( XLEN      ),
  .INIT_FILE     ( INIT_FILE )
//  ,.CHECK_CREATE ( 0         )
)
dmav_inst (
  .clk_i        ( HCLK                       ),
  .req_i        ( `RV_CORE.dmem_req_o        ),
  .adr_i        ( `RV_CORE.dmem_adr_o        ),
  .d_i          ( `RV_CORE.dmem_d_o          ),
  .q_i          ( `RV_CORE.dmem_q_i          ),
  .we_i         ( `RV_CORE.dmem_we_o         ),
  .size_i       ( `RV_CORE.dmem_size_o       ),
  .lock_i       ( `RV_CORE.dmem_lock_o       ),
  .ack_i        ( `RV_CORE.dmem_ack_i        ),
  .err_i        ( `RV_CORE.dmem_err_i        ),
  .misaligned_i ( `RV_CORE.dmem_misaligned_i ),
  .page_fault_i ( `RV_CORE.dmem_page_fault_i ) );

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
    $display ("  XLEN | PRIV | MMU | FPU | RVA | RVM | MULLAT | CORES  ");
    $display ("   %3d | %C%C%C%C | %3d | %3d | %3d | %3d | %6d | %3d   ", 
               XLEN, "M", HAS_H > 0 ? "H" : " ", HAS_S > 0 ? "S" : " ", HAS_U > 0 ? "U" : " ",
               HAS_MMU, HAS_FPU, HAS_RVA, HAS_RVM, MULLAT, CORES);
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

//  unified_memory.read_elf2hex(INIT_FILE);
  unified_memory.read_ihex(INIT_FILE);
//  unified_memory.dump;

  HCLK  = 'b0;

  HRESETn = 'b1;
  repeat (5) @(negedge HCLK);
  HRESETn = 'b0;
  repeat (5) @(negedge HCLK);
  HRESETn = 'b1;

/*
  #112;
  //stall CPU
  dbg_ctrl.stall;

  //Enable BREAKPOINT to call external debugger
//  dbg_ctrl.write('h0004,'h0008);

  //Enable Single Stepping
  dbg_ctrl.write('h0000,'h0001);

  //single step through 10 instructions
  repeat (100)
  begin
      while (!dbg_ctrl.stall_cpu) @(posedge HCLK);
      repeat(15) @(posedge HCLK);
      dbg_ctrl.write('h0001,'h0000); //clear single-step-hit
      dbg_ctrl.unstall;
  end

  //last time ...
  @(posedge HCLK);
  while (!dbg_ctrl.stall_cpu) @(posedge HCLK);
  //disable Single Stepping
  dbg_ctrl.write('h0000,'h0000);
  dbg_ctrl.write('h0001,'h0000);
  dbg_ctrl.unstall;
*/
end		

initial
begin
//  #20  ; unified_memory.dump();
//  #1000; unified_memory.dump();
//  #1000; unified_memory.dump();
end

endmodule



/*
 * MMIO Interface
 */
module mmio_if #(
  parameter HDATA_SIZE    = 32,
  parameter HADDR_SIZE    = 32,
  parameter CATCH_TEST    = 80001000,
  parameter CATCH_UART_TX = 80001080
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
  logic                  catch_test,
                         catch_uart_tx;


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
    if (!HRESETn)
    begin
         catch_test    <= 1'b0;
         catch_uart_tx <= 1'b0;
    end
    else
    begin
        catch_test    <= dHTRANS == HTRANS_NONSEQ && dHWRITE && dHADDR == CATCH_TEST;
        catch_uart_tx <= dHTRANS == HTRANS_NONSEQ && dHWRITE && dHADDR == CATCH_UART_TX;
        data_reg      <= HWDATA;
    end


  /*
   * Generate output
   */

  //Simulated UART Tx (prints characters on screen)
  always @(posedge HCLK)
    if (catch_uart_tx) $write ("%0c", data_reg);


  //Tests ...
  always @(posedge HCLK)
  begin
      if (watchdog_cnt > 1000_000 || catch_test)
      begin
          $display("\n\n");
          $display("-------------------------------------------------------------");
          $display("* RISC-V test bench finished");
          if (data_reg[0])
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

	  $root.testbench_top.dmav_inst.golden_finish();
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

	  $root.testbench_top.dmav_inst.golden_finish();
          $finish();
      end
  end
endmodule




/*
 * Data Memory Access Validation
 */
module dmav #(
  parameter XLEN         = 32,
  parameter INIT_FILE    = "inifile",
  parameter CHECK_CREATE = 1
)
(
  input            clk_i,
  input            req_i,
  input [XLEN-1:0] adr_i,
  input [XLEN-1:0] d_i,
  input [XLEN-1:0] q_i,
  input            we_i,
  input biu_size_t size_i,
  input            lock_i,
  input            ack_i,
                   err_i,
                   misaligned_i,
                   page_fault_i
);

 /////////////////////////////////////////////////////////////////
 //
 // Typedef
 //
 typedef struct {
   logic [XLEN-1:0] adr;
   logic [XLEN-1:0] data;
   logic            we;
   biu_size_t       size;
   logic            lock;
   logic            ack,
                    err,
                    misaligned,
                    page_fault;
   string           comment;
 } data_t;


  /////////////////////////////////////////////////////////////////
  //
  // Functions/Tasks
  //

  //Open golden file, either for reading or writing
  function int golden_open (input string filename, input bit rw);
    golden_open = $fopen(filename, rw ? "r" : "w");

    if (!golden_open) $warning("Failed to open: %s", filename);
    else              $info   ("Opened %s (%0d)", filename, golden_open);
  endfunction: golden_open

  //Close golden file
  //TODO: fd should be argument
  //      call when closing simulator (callback?)
  task golden_close();
    $fclose(fd);
  endtask: golden_close

  //Write datablob to golden file
  //TODO: why doesn't $fwrite work?
  //      why can't a typedef be written at once with %z?
  task golden_write (input int fd, input data_t blob);
//    $display ("fwrite %0t %z", $realtime, blob);
//    $fdisplay (fd, "%z", blob);
    $fdisplay (fd, "%h %h %b %h %b %h %s",
                   blob.adr,
                   blob.data,
                   blob.we,
                   blob.size,
                   blob.lock,
                   {blob.ack, blob.err, blob.misaligned, blob.page_fault},
                   "-" );
  endtask: golden_write

  //Read golden file
  //TODO: ideally would want to read a type_def with %z
  function data_t golden_read(input int fd);
    int err;
    data_t tmp;
    err = $fscanf (fd, "%h %h %b %h %b %h %s",
                       tmp.adr,
                       tmp.data,
                       tmp.we,
                       tmp.size,
                       tmp.lock,
                       {tmp.ack, tmp.err, tmp.misaligned, tmp.page_fault},
                       tmp.comment );

    if (err != 7)
    begin
        $error ("golden_read");
        return data_t'(-1);
    end
    else
    begin
        return tmp;
    end
  endfunction: golden_read


  //Compare results
  //g=golden
  //r=reference
  function int golden_compare(input data_t g, r);
    r.comment = "-";
    if (r !== g && g.comment[0] !== "+")
    begin
        $display ("ERROR  : golden_compare error @%0t %s", $realtime, g.comment);
        $display ("        | golden %s| reference", {XLEN/4-6{" "}} );
        $display ("adr     | %h | %h",   g.adr,  r.adr);
        $display ("data    | %h | %h",   g.data, r.data);
        $display ("size    | %h  %s| %h",   g.size, {XLEN/4-2{" "}}, r.size);
        $display ("we/lock | %b%b %s| %b%b", g.we, g.lock, {XLEN/4-2{" "}}, r.we, r.lock);
        $display ("aemp    | %b%b%b%b %s| %b%b%b%b", g.ack, g.err, g.misaligned, g.page_fault, {XLEN/4-4{" "}},
                                                   r.ack, r.err, r.misaligned, r.page_fault);
        return -1;
    end
    else
        return 0;
  endfunction: golden_compare


  task golden_finish();
    //close file
    golden_close();

    //display notice
    $info ("dmav errors: %0d", golden_errors);
  endtask: golden_finish

  /////////////////////////////////////////////////////////////////
  //
  // Variables
  //
  int fd;
  
  data_t queue[$],
	 queue_d,
         queue_q;

  int golden_errors=0;

  /////////////////////////////////////////////////////////////////
  //
  // Module body
  //

  //open file
  initial fd = golden_open({INIT_FILE, ".golden"}, CHECK_CREATE);


  //store access request
  assign queue_d.adr  = adr_i;
  assign queue_d.we   = we_i;
  assign queue_d.size = size_i;
  assign queue_d.lock = lock_i;
  assign queue_d.data = d_i; //gets overwritten for a read


  //push access request into queue
  always @(posedge clk_i)
    if (req_i) queue.push_front(queue_d);


  //wait for acknowledge and write to file
  always @(posedge clk_i)
    if (ack_i || err_i || page_fault_i)
    begin
        //pop request from queue
        queue_q = queue.pop_back();

        //store response
        queue_q.ack        = ack_i;
        queue_q.err        = err_i;
        queue_q.misaligned = misaligned_i;
        queue_q.page_fault = page_fault_i;

        if (!queue_q.we) queue_q.data = q_i;

        if (CHECK_CREATE)
        begin
            //read from file and compare
            //if (golden_compare(golden_read(fd), queue_q) ) golden_errors++;
        end
        else
        begin
            //write to file
            golden_write(fd, queue_q);
        end
    end


endmodule



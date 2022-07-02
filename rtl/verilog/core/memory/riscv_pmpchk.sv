/////////////////////////////////////////////////////////////////////
//   ,------.                    ,--.                ,--.          //
//   |  .--. ' ,---.  ,--,--.    |  |    ,---. ,---. `--' ,---.    //
//   |  '--'.'| .-. |' ,-.  |    |  |   | .-. | .-. |,--.| .--'    //
//   |  |\  \ ' '-' '\ '-'  |    |  '--.' '-' ' '-' ||  |\ `--.    //
//   `--' '--' `---'  `--`--'    `-----' `---' `-   /`--' `---'    //
//                                             `---'               //
//    RISC-V                                                       //
//    Physical Memory Protection Checker                           //
//                                                                 //
/////////////////////////////////////////////////////////////////////
//                                                                 //
//             Copyright (C) 2018-2022 ROA Logic BV                //
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


import riscv_state_pkg::*;
import biu_constants_pkg::*;

module riscv_pmpchk #(
  parameter XLEN    = 32,
  parameter PLEN    = XLEN == 32 ? 34 : 56,
  parameter PMP_CNT = 16
)
(
  input  logic                     clk_i,
  input  logic                     stall_i,

  //From State
  input  pmpcfg_t [15:0]           st_pmpcfg_i,
  input  logic    [15:0][XLEN-1:0] st_pmpaddr_i,
  input  logic          [     1:0] st_prv_i,

  //Memory Access
  input  logic                     instruction_i,   //This is an instruction access
  input  logic          [PLEN-1:0] adr_i,           //Physical Memory address (i.e. after translation)
  input  biu_size_t                size_i,          //Transfer size
  input  logic                     we_i,            //Read/Write enable

  //Output
  output logic                     exception_o
);

  //////////////////////////////////////////////////////////////////
  //
  // Functions
  //

  //convert transfer size in number of bytes in transfer
  function automatic int size2bytes;
    input biu_size_t size;

    case (size)
      BYTE   : size2bytes =  1;
      HWORD  : size2bytes =  2;
      WORD   : size2bytes =  4;
      DWORD  : size2bytes =  8;
      QWORD  : size2bytes = 16;
      default: begin
                   size2bytes = -1;
                   $error("Illegal biu_size_t");
               end
    endcase
  endfunction: size2bytes

  //Lower and Upper bounds for NA4/NAPOT
  function int napot_boundary;
    input na4; //special case na4
    input [XLEN-1:0] pmaddr;

    int n;
    bit true;

    //find 'n' boundary = 2^(n+2) bytes
    n = 2;
    if (!na4)
    begin
        true = 1'b1;
        for (int i=0; (i < $bits(pmaddr)) && true; i++)
          if (pmaddr[i]) n++;
          else           true = 1'b0;
	 
        n++;
    end

    return n;
  endfunction: napot_boundary


  function automatic [PLEN-1:0] napot_lb;
    input            na4; //special case na4
    input [XLEN-1:0] pmaddr;

    int n;
    logic [PLEN-1:0] mask;

    //find 'n' boundary = 2^(n+2) bytes
    n = napot_boundary(na4, pmaddr);

    //create mask
    mask = {$bits(mask){1'b1}} << n;

    //lower bound address
    napot_lb = pmaddr;
    napot_lb <<= 2;
    napot_lb &= mask;
  endfunction: napot_lb


  function automatic [PLEN-1:0] napot_ub;
    input            na4; //special case na4
    input [XLEN-1:0] pmaddr;

    int n;
    logic [PLEN-1:0] mask,
                     range;

    //find 'n' boundary = 2^(n+2) bytes
    n = napot_boundary(na4, pmaddr);

    //create mask and increment
    mask = {$bits(mask){1'b1}} << n;
    range = 1 << n;

    //upper bound address
    napot_ub = pmaddr;
    napot_ub <<= 2;
    napot_ub &= mask;
    napot_ub += range;
  endfunction: napot_ub


  //Is ANY byte of 'access' in pmp range?
  function automatic match_any;
    input [PLEN-1:0] access_lb, access_ub,
                     pmp_lb   , pmp_ub;

    /* Check if ANY byte of the access lies within the PMP range
     *   pmp_lb <= range < pmp_ub
     * 
     *   match_none = (access_lb >= pmp_ub) OR (access_ub < pmp_lb)  (1)
     *   match_any  = !match_none                                    (2)
     */
     match_any = (access_lb[PLEN-1:2] >= pmp_ub[PLEN-1:2]) || (access_ub[PLEN-1:2] <  pmp_lb[PLEN-1:2]) ? 1'b0 : 1'b1;
  endfunction: match_any


  //Are ALL bytes of 'access' in pmp range?
  function automatic match_all;
    input [PLEN-1:0] access_lb, access_ub,
                     pmp_lb   , pmp_ub;

    match_all = (access_lb[PLEN-1:2] >= pmp_lb[PLEN-1:2]) && (access_ub[PLEN-1:2] < pmp_ub[PLEN-1:2]) ? 1'b1 : 1'b0;
  endfunction: match_all


  //get highest priority (==lowest number) PMP that matches
  function automatic int highest_priority_match;
    input [PMP_CNT-1:0] m;

    int n;

    for (n=PMP_CNT-1; n >= 0; n--)
      if (m[n]) highest_priority_match = n;
  endfunction: highest_priority_match


  //////////////////////////////////////////////////////////////////
  //
  // Variables
  //
  genvar i;

  logic [PLEN   -1:0] access_ub,
                      access_lb;
  logic [PLEN   -1:0] pmp_ub [16],
                      pmp_lb [16];
  logic [PMP_CNT-1:0] pmp_match,
                      pmp_match_all;
  int                 matched_pmp;
  pmpcfg_t            matched_pmpcfg;


  logic               we;



  //////////////////////////////////////////////////////////////////
  //
  // Module Body
  //

  /*
   * Address Range Matching
   * Access Exception
   * Cacheable
   */
  assign access_lb = adr_i;
  assign access_ub = adr_i + size2bytes(size_i) -1;

generate
  for (i=0; i < PMP_CNT; i++)
  begin: gen_pmp_bounds
      //lower bounds
      always_comb
      case (st_pmpcfg_i[i].a)
        TOR    : pmp_lb[i] = (i==0) ? {PLEN{1'b0}} : pmp_ub[i-1];
        NA4    : pmp_lb[i] = napot_lb(1'b1, st_pmpaddr_i[i]);
        NAPOT  : pmp_lb[i] = napot_lb(1'b0, st_pmpaddr_i[i]);
        default: pmp_lb[i] = 'hx;
      endcase

      //upper bounds
      always_comb
      case (st_pmpcfg_i[i].a)
        TOR    : pmp_ub[i] = st_pmpaddr_i[i];
        NA4    : pmp_ub[i] = napot_ub(1'b1, st_pmpaddr_i[i]);
        NAPOT  : pmp_ub[i] = napot_ub(1'b0, st_pmpaddr_i[i]);
        default: pmp_ub[i] = 'hx;
      endcase

      //match-any
      assign pmp_match    [i] = match_any(access_lb, access_ub, pmp_lb[i], pmp_ub[i]) & (st_pmpcfg_i[i].a != OFF);
//     assign pmp_match_all[i] = match_all(access_lb, access_ub, pmp_lb[i], pmp_ub[i]);

      always @(posedge clk_i)
        if (!stall_i) pmp_match_all[i] <= match_all(access_lb, access_ub, pmp_lb[i], pmp_ub[i]);
  end
endgenerate

  //TODO: where to insert register stage
  //for now pick matched_pmp
//  assign matched_pmp    = highest_priority_match(pmp_match);
  always @(posedge clk_i)
    if (!stall_i) matched_pmp <= highest_priority_match(pmp_match);

  assign matched_pmpcfg = st_pmpcfg_i[ matched_pmp ];


  //delay we; same delay as matched_pmpcfg and pmp_match_all;
  always @(posedge clk_i)
    if (!stall_i) we <= we_i;


  /* Access FAIL when:
   * 1. some bytes matched highest priority PMP, but not the entire transfer range OR
   * 2. pmpcfg.l is set AND privilegel level is S or U AND pmpcfg.rwx tests fail OR
   * 3. privilegel level is S or U AND no PMPs matched AND PMPs are implemented
   */
  assign exception_o = (~|pmp_match ? (st_prv_i != PRV_M) & (PMP_CNT > 0)          //Prv.Lvl != M-Mode, no PMP matched, but PMPs implemented -> FAIL
                                    : ~pmp_match_all[ matched_pmp ]     |
                                     (
                                      ((st_prv_i != PRV_M) | matched_pmpcfg.l ) &  //pmpcfg.l set or privilege level != M-mode
                                      ((~matched_pmpcfg.r & ~we             ) |    // read-access while not allowed          -> FAIL
                                       (~matched_pmpcfg.w &  we             ) |    // write-access while not allowed         -> FAIL
                                       (~matched_pmpcfg.x &  instruction_i  ) )    // instruction read, but not instruction  -> FAIL
                                     )
                       );
endmodule


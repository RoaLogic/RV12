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
//             Copyright (C) 2018 ROA Logic BV                     //
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
  //From State
  input pmpcfg_t [15:0]           st_pmpcfg_i,
  input          [15:0][XLEN-1:0] st_pmpaddr_i,
  input                [     1:0] st_prv_i,

  //Memory Access
  input                           instruction_i,   //This is an instruction access
  input                           req_i,           //Memory access requested
  input                [PLEN-1:0] adr_i,           //Physical Memory address (i.e. after translation)
  input  biu_size_t               size_i,          //Transfer size
  input                           we_i,            //Read/Write enable

  //Output
  output reg                      exception_o
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
  function automatic [PLEN-1:2] napot_lb;
    input            na4; //special case na4
    input [PLEN-1:2] pmaddr;

    int n, i;
    bit true;
    logic [PLEN-1:2] mask;

    //find 'n' boundary = 2^(n+2) bytes
    n = 0;
    if (!na4)
    begin
//        while ((n < $bits(pmaddr)) && (pmaddr[n+2])) n++; //Quartus doesn't like this
		  
        true = 1'b1;
        for (i=0; (i < $bits(pmaddr)) && true; i++)
          if (pmaddr[i+2]) n++;
          else             true = 1'b0;

        n++;
    end

    //create mask
    mask = {XLEN{1'b1}} << n;

    //lower bound address
    napot_lb = pmaddr & mask;
  endfunction: napot_lb


  function automatic [PLEN-1:2] napot_ub;
    input            na4; //special case na4
    input [PLEN-1:2] pmaddr;

    int n, i;
    bit true;
    logic [PLEN-1:2] mask,
                     incr;

    //find 'n' boundary = 2^(n+2) bytes
    n = 0;
    if (!na4)
    begin
//        while ((n < $bits(pmaddr)) && pmaddr[n+2]) n++; //Quartus doesn't like this

        true = 1;
        for (i=0; (i < $bits(pmaddr)) && true; i++)
          if (pmaddr[i+2]) n++;
          else             true = 1'b0;

        n++;
    end

    //create mask and increment
    mask = {XLEN{1'b1}} << n;
    incr = 1 << n;

    //upper bound address
    napot_ub = (pmaddr + incr) & mask;
  endfunction: napot_ub


  //Is ANY byte of 'access' in pmp range?
  function automatic match_any;
    input [PLEN-1:2] access_lb, access_ub,
                     pmp_lb   , pmp_ub;

    /* Check if ANY byte of the access lies within the PMP range
     *   pmp_lb <= range < pmp_ub
     * 
     *   match_none = (access_lb >= pmp_ub) OR (access_ub < pmp_lb)  (1)
     *   match_any  = !match_none                                    (2)
     */
     match_any = (access_lb >= pmp_ub) || (access_ub <  pmp_lb) ? 1'b0 : 1'b1;
  endfunction: match_any


  //Are ALL bytes of 'access' in pmp range?
  function automatic match_all;
    input [PLEN-1:2] access_lb, access_ub,
                     pmp_lb   , pmp_ub;

    match_all = (access_lb >= pmp_lb) && (access_ub < pmp_ub) ? 1'b1 : 1'b0;
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
  logic [PLEN   -1:2] pmp_ub [16],
                      pmp_lb [16];
  logic [PMP_CNT-1:0] pmp_match,
                      pmp_match_all;
  int                 matched_pmp;
  pmpcfg_t            matched_pmpcfg;


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
        /* TOR after NAPOT ...
         * email discussion suggested TOR after NAPOT is not a real-life configuration
         * RoaLogic opts to implement this anyways for full flexibility
         * RoaLogic's implementation uses pmp[i-1]'s upper bound address
         */
        TOR    : pmp_lb[i] = (i==0) ? 0 : st_pmpcfg_i[i-1].a != TOR ? pmp_ub[i-1] : st_pmpaddr_i[i-1][PLEN-2 -1:0];
        NA4    : pmp_lb[i] = napot_lb(1'b1, st_pmpaddr_i[i]);
        NAPOT  : pmp_lb[i] = napot_lb(1'b0, st_pmpaddr_i[i]);
        default: pmp_lb[i] = 'hx;
      endcase

      //upper bounds
      always_comb
      case (st_pmpcfg_i[i].a)
        TOR    : pmp_ub[i] = st_pmpaddr_i[i][PLEN-2 -1:0];
        NA4    : pmp_ub[i] = napot_ub(1'b1, st_pmpaddr_i[i]);
        NAPOT  : pmp_ub[i] = napot_ub(1'b0, st_pmpaddr_i[i]);
        default: pmp_ub[i] = 'hx;
      endcase

      //match-any
      assign pmp_match    [i] = match_any(access_lb[PLEN-1:2], access_ub[PLEN-1:2], pmp_lb[i], pmp_ub[i]) & (st_pmpcfg_i[i].a != OFF);
      assign pmp_match_all[i] = match_all(access_lb[PLEN-1:2], access_ub[PLEN-1:2], pmp_lb[i], pmp_ub[i]);
  end
endgenerate

  assign matched_pmp    = highest_priority_match(pmp_match);
  assign matched_pmpcfg = st_pmpcfg_i[ matched_pmp ];


  /* Access FAIL when:
   * 1. some bytes matched highest priority PMP, but not the entire transfer range OR
   * 2. pmpcfg.l is set AND privilegel level is S or U AND pmpcfg.rwx tests fail OR
   * 3. privilegel level is S or U AND no PMPs matched AND PMPs are implemented
   */
  assign exception_o = req_i & (~|pmp_match ? (st_prv_i != PRV_M) & (PMP_CNT > 0)          //Prv.Lvl != M-Mode, no PMP matched, but PMPs implemented -> FAIL
                                            : ~pmp_match_all[ matched_pmp ]     |
                                             (
                                              ((st_prv_i != PRV_M) | matched_pmpcfg.l ) &  //pmpcfg.l set or privilege level != M-mode
                                              ((~matched_pmpcfg.r & ~we_i           ) |    // read-access while not allowed          -> FAIL
                                               (~matched_pmpcfg.w &  we_i           ) |    // write-access while not allowed         -> FAIL
                                               (~matched_pmpcfg.x &  instruction_i  ) )    // instruction read, but not instruction  -> FAIL
                                             )
                               );
endmodule


/////////////////////////////////////////////////////////////////////
//   ,------.                    ,--.                ,--.          //
//   |  .--. ' ,---.  ,--,--.    |  |    ,---. ,---. `--' ,---.    //
//   |  '--'.'| .-. |' ,-.  |    |  |   | .-. | .-. |,--.| .--'    //
//   |  |\  \ ' '-' '\ '-'  |    |  '--.' '-' ' '-' ||  |\ `--.    //
//   `--' '--' `---'  `--`--'    `-----' `---' `-   /`--' `---'    //
//                                             `---'               //
//    Bus-Interface-Unit Mux                                       //
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

/*
 * Memory Access Multiplexer
 * Switched 'PORTS' input BIUs onto single output BIU
 * Lowest port has highest priority; i.e. PORT0 has highest priority
 */

import biu_constants_pkg::*;

module biu_mux #(
  parameter ADDR_SIZE   = 32,
  parameter DATA_SIZE   = 32,
  parameter PORTS       = 2,
  parameter QUEUE_DEPTH = 2
)
(
  input  logic                 rst_ni,
  input  logic                 clk_i,
 
  //Input Ports
  input  logic                 biu_req_i     [PORTS], //access request
  output logic                 biu_req_ack_o [PORTS], //biu access acknowledge
  output logic                 biu_d_ack_o   [PORTS], //biu early data acknowledge
  input  logic [ADDR_SIZE-1:0] biu_adri_i    [PORTS], //access start address
  output logic [ADDR_SIZE-1:0] biu_adro_o    [PORTS], //biu response address
  input  biu_size_t            biu_size_i    [PORTS], //access data size
  input  biu_type_t            biu_type_i    [PORTS], //access burst type
  input  logic                 biu_lock_i    [PORTS], //access locked access
  input  biu_prot_t            biu_prot_i    [PORTS], //access protection
  input  logic                 biu_we_i      [PORTS], //access write enable
  input  logic [DATA_SIZE-1:0] biu_d_i       [PORTS], //access write data
  output logic [DATA_SIZE-1:0] biu_q_o       [PORTS], //access read data
  output logic                 biu_ack_o     [PORTS], //access acknowledge
                               biu_err_o     [PORTS], //access error

  //Output (to BIU)
  output logic                 biu_req_o,             //BIU access request
  input  logic                 biu_req_ack_i,         //BIU ackowledge
  input  logic                 biu_d_ack_i,           //BIU early data acknowledge
  output logic [ADDR_SIZE-1:0] biu_adri_o,            //address into BIU
  input  logic [ADDR_SIZE-1:0] biu_adro_i,            //address from BIU
  output biu_size_t            biu_size_o,            //transfer size
  output biu_type_t            biu_type_o,            //burst type
  output logic                 biu_lock_o,
  output biu_prot_t            biu_prot_o,
  output logic                 biu_we_o,
  output logic [DATA_SIZE-1:0] biu_d_o,               //data into BIU
  input  logic [DATA_SIZE-1:0] biu_q_i,               //data from BIU
  input  logic                 biu_ack_i,             //data acknowledge, 1 per data
                               biu_err_i              //data error
);
/*
  PORT0 has highest priority
 */

  //////////////////////////////////////////////////////////////////
  //
  // Typedefs
  //


  //////////////////////////////////////////////////////////////////
  //
  // Functions
  //
  //convert burst type to counter length (actually length -1)
  function [3:0] biu_type2cnt;
    input biu_type_t biu_type;

    case (biu_type)
      SINGLE: biu_type2cnt =  0;
      INCR  : biu_type2cnt =  0;
      WRAP4 : biu_type2cnt =  3;
      INCR4 : biu_type2cnt =  3;
      WRAP8 : biu_type2cnt =  7;
      INCR8 : biu_type2cnt =  7;
      WRAP16: biu_type2cnt = 15;
      INCR16: biu_type2cnt = 15;
    endcase
  endfunction: biu_type2cnt


  function automatic busor;
    input req[PORTS];

    busor = 0;
    for (int n=0; n < PORTS; n++)
      busor |= req[n];
  endfunction: busor


  function automatic port_select;
    input req [PORTS];

    //default port
    port_select = 0;

    //check other ports
    for (int n=PORTS-1; n > 0; n--)
      if (req[n]) port_select = n;
  endfunction: port_select


  //////////////////////////////////////////////////////////////////
  //
  // Variables
  //

  enum logic [1:0] {IDLE=0,BURST=1, WAIT4BIU=2} fsm_state;

  logic                     pending_req;
  logic [$clog2(PORTS)-1:0] pending_port,
                            selected_port;
  biu_size_t                pending_size;

  logic [              3:0] pending_burst_cnt,
                            burst_cnt;
  
  genvar p;


  //////////////////////////////////////////////////////////////////
  //
  // Module Body
  //

  assign pending_req       = busor(biu_req_i);
  assign pending_port      = port_select(biu_req_i);
  assign pending_size      = biu_size_i[ pending_port ];
  assign pending_burst_cnt = biu_type2cnt( biu_type_i[ pending_port ] );


  /* Access Statemachine
   */
  always @(posedge clk_i, negedge rst_ni)
    if (!rst_ni)
    begin
        fsm_state <= IDLE;
        burst_cnt <= 'h0;
    end
    else
      unique case (fsm_state)
        IDLE    : if (pending_req && |pending_burst_cnt)
                  begin
                      fsm_state     <= BURST;
                      burst_cnt     <= pending_burst_cnt;
                      selected_port <= pending_port;
                  end
                  else
                      selected_port <= pending_port;

        BURST   : if (biu_ack_i)
                  begin
                      burst_cnt <= burst_cnt -1;

                      if (~|burst_cnt)                             //Burst done
                        if (pending_req && |pending_burst_cnt)
                        begin
                            burst_cnt     <= pending_burst_cnt;
                            selected_port <= pending_port;
                        end
                        else
                        begin
                            fsm_state     <= IDLE;
                            selected_port <= pending_port;
                        end
                  end

        WAIT4BIU: ;
      endcase                   


  /* Mux BIU ports
   */
  always_comb
    unique case (fsm_state)
      IDLE    : begin
                    biu_req_o  = pending_req;
                    biu_adri_o = biu_adri_i [ pending_port ];
                    biu_size_o = biu_size_i [ pending_port ];
                    biu_type_o = biu_type_i [ pending_port ];
                    biu_lock_o = biu_lock_i [ pending_port ];
                    biu_we_o   = biu_we_i   [ pending_port ];
                    biu_d_o    = biu_d_i    [ pending_port ];
                end

      BURST   : begin
                    biu_req_o  = biu_ack_i & ~|burst_cnt & pending_req;
                    biu_adri_o = biu_adri_i [ pending_port ];
                    biu_size_o = biu_size_i [ pending_port ];
                    biu_type_o = biu_type_i [ pending_port ];
                    biu_lock_o = biu_lock_i [ pending_port ];
                    biu_we_o   = biu_we_i   [ pending_port ];
                    biu_d_o    = biu_ack_i & ~|burst_cnt ? biu_d_i[ pending_port ] : biu_d_i[ selected_port ]; //TODO ~|burst_cnt & biu_ack_i ??
                end

      WAIT4BIU: begin
                    biu_req_o  = 1'b1;
                    biu_adri_o = biu_adri_i [ selected_port ];
                    biu_size_o = biu_size_i [ selected_port ];
                    biu_type_o = biu_type_i [ selected_port ];
                    biu_lock_o = biu_lock_i [ selected_port ];
                    biu_we_o   = biu_we_i   [ selected_port ];
                    biu_d_o    = biu_d_i    [ selected_port ];
                end

      default : begin
                    biu_req_o  = 'bx;
                    biu_adri_o = 'hx;
                    biu_size_o = biu_size_t'('hx);
                    biu_type_o = biu_type_t'('hx);
                    biu_lock_o = 'bx;
                    biu_we_o   = 'bx;
                    biu_d_o    = 'hx;
                end
    endcase



  /* Decode MEM ports
   */
generate
  for (p=0; p < PORTS; p++)
  begin: decode_ports
      assign biu_req_ack_o [p] = (p == pending_port ) ? biu_req_ack_i : 1'b0;
      assign biu_d_ack_o   [p] = (p == selected_port) ? biu_d_ack_i   : 1'b0;
      assign biu_adro_o    [p] = biu_adro_i;
      assign biu_q_o       [p] = biu_q_i;
      assign biu_ack_o     [p] = (p == selected_port) ? biu_ack_i     : 1'b0;
      assign biu_err_o     [p] = (p == selected_port) ? biu_err_i     : 1'b0;
  end
endgenerate

endmodule



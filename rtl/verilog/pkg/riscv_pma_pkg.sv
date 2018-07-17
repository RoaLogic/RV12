/////////////////////////////////////////////////////////////////////
//   ,------.                    ,--.                ,--.          //
//   |  .--. ' ,---.  ,--,--.    |  |    ,---. ,---. `--' ,---.    //
//   |  '--'.'| .-. |' ,-.  |    |  |   | .-. | .-. |,--.| .--'    //
//   |  |\  \ ' '-' '\ '-'  |    |  '--.' '-' ' '-' ||  |\ `--.    //
//   `--' '--' `---'  `--`--'    `-----' `---' `-   /`--' `---'    //
//                                             `---'               //
//    RISC-V                                                       //
//    Physical Memory Attributes Package                           //
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


//Load only pmpcfg_a_t from state package
import riscv_state_pkg::pmpcfg_a_t;

package riscv_pma_pkg;
  //3.5.1 Memory type. Used for target-decoding
  typedef enum logic [1:0] {
    MEM_TYPE_EMPTY = 2'h0,
    MEM_TYPE_MAIN  = 2'h1,
    MEM_TYPE_IO    = 2'h2,
    MEM_TYPE_TCM   = 2'h3
  } pma_memory_t;


  //3.5.2 Access Type - Not used

  //3.5.3 Atomicity PMAs
  typedef enum logic [1:0] {
    AMO_TYPE_NONE       = 2'h0,
    AMO_TYPE_SWAP       = 2'h1,
    AMO_TYPE_LOGICAL    = 2'h2,
    AMO_TYPE_ARITHMETIC = 2'h3
  } pma_amo_t;


  //Address Decoder
  // same as PMPCFG ?
  // simple Address/Mask/Size ?
  typedef struct packed {
    pma_memory_t mem_type;    

    logic        r,           //read
                 w,           //write
                 x,           //execute
                 c,           //cacheable        (MEMORY_TYPE_MAIN)
                 cc,          //cache-coherent   (MEMORY_TYPE_MAIN)
                 ri,          //read-idempotent  (MEMORY_TYPE_IO)
                 wi,          //write-idempotent (MEMORY_TYPE_IO)
                 m;           //misaligned access supported
    pma_amo_t    amo_type;    //                 (MEMORY_TYPE_IO)

    pmpcfg_a_t   a;           //Address map method, same as for PMP
  } pmacfg_t;

endpackage


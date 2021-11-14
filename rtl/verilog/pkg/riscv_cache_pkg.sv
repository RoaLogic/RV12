/////////////////////////////////////////////////////////////////////
//   ,------.                    ,--.                ,--.          //
//   |  .--. ' ,---.  ,--,--.    |  |    ,---. ,---. `--' ,---.    //
//   |  '--'.'| .-. |' ,-.  |    |  |   | .-. | .-. |,--.| .--'    //
//   |  |\  \ ' '-' '\ '-'  |    |  '--.' '-' ' '-' ||  |\ `--.    //
//   `--' '--' `---'  `--`--'    `-----' `---' `-   /`--' `---'    //
//                                             `---'               //
//    RISC-V                                                       //
//    Cache Package                                                //
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

package riscv_cache_pkg;

  /* Functions to calculate various sizes used in the cache */
  
  //RISC-V defines a 4KB Page
  function automatic integer riscv_page_size ();
    riscv_page_size = 4*1024;
  endfunction : riscv_page_size


  //Maximum number of index bits, based on page-size and block-size
  function automatic integer max_index_bits (input integer page_size, block_size);
    max_index_bits = $clog2(page_size) - $clog2(block_size);
  endfunction : max_index_bits


  //Number of sets, based on cache-size (in KB), block size, and number of ways
  function automatic integer no_of_sets (input integer cache_size, block_size, ways);
    no_of_sets = cache_size * 1024 / block_size / ways;
  endfunction : no_of_sets
  

  //Number of index bits
  function automatic integer no_of_index_bits (input integer no_of_sets);
    no_of_index_bits = $clog2(no_of_sets);
  endfunction : no_of_index_bits


  //Number of Block Offset Bits; that is the number of bits in the address that reference the block
  function automatic integer no_of_block_offset_bits (input integer block_size);
    no_of_block_offset_bits = $clog2(block_size);
  endfunction : no_of_block_offset_bits


  //Number of Data Offset Bits; that is the number of bits to reference data in the Block 
  function automatic integer no_of_data_offset_bits (input integer xlen, no_of_block_bits);
    no_of_data_offset_bits = $clog2(no_of_block_bits / xlen); //==$clog2(burst_size);
  endfunction : no_of_data_offset_bits

  //Number of bits in a block; the total number of bits in a block
  function automatic integer no_of_block_bits (input integer block_size);
    no_of_block_bits = 8* block_size;
  endfunction : no_of_block_bits


  //Number of bits in a tag, based on xlen, no_of_index_bits, and block_offset_bits
  function automatic integer no_of_tag_bits (input integer xlen, no_of_index_bits, no_of_block_offset_bits);
    no_of_tag_bits = xlen - no_of_index_bits - no_of_block_offset_bits;
  endfunction : no_of_tag_bits


  //Burst size; number of transfers required to transfer 1 block
  function automatic integer burst_size (input integer xlen, no_of_block_bits);
    burst_size = no_of_block_bits / xlen;
  endfunction : burst_size



  //Statemachine (commands)
  typedef enum logic [1:0] {BIUCMD_NOP=0, BIUCMD_READWAY=1, BIUCMD_WRITEWAY=2} biucmd_t;

  
endpackage



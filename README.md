# RV12
The RV12 is a highly configurable single-issue, single-core RV32I, RV64I compliant RISC CPU intended for the embedded market. The RV12 is a member of the Roa Logic’s 32/64bit CPU family based on the industry standard RISC-V instruction set

## Compatibility
- User Mode Specifications 2.1
- Privilege Mode Specifications 1.9.1

## Features:
- Single issue, single thread
- RV32I or RV64I core (parameterized)
- Optional Multiplier and Divider Units (RVM extensions)
- Optional Branch Predict Unit
- Optional Instruction Cache
- Optional Data Cache

## License
Released under the RoaLogic [Non-Commerical license](https://roalogic.com/wp-content/licenses/Non-Commercial_License_Agreement.html).

## Regression tests
The release contains regression tests for the supported modules, based on the official riscv-tests.

## Dependencies
Requires the RoaLogic Memories IPs and AHB3Lite Package. These are included as submodules.
After cloning the RV12 git repository do a 'git submodule init' to download the submodules.

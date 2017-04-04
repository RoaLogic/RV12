# RV12
RISC-V CPU Core

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
Released under the RoaLogic Non-Commerical license.

## Regression tests
The release contains regression tests for the supported modules, based on the official riscv-tests.

## Dependencies
Requires the RoaLogic Memories IPs and AHB3Lite Package. These are included as submodules.
After cloning the RV12 git repository do a 'git submodule init' to download the submodules.



# RV12 RISC-V CPU Core

![RV12 RISC-V Architecture](https://roalogic.com/wp-content/uploads/2017/02/RISC-V-Arch-Small.png)

## Compatibility
- User Mode Specifications 2.2
- Privilege Mode Specifications 1.9.1

## Features:
- Single issue, single thread
- RV32I or RV64I core (parameterized)
- Optional Multiplier and Divider Units (RVM extensions)
- Optional Branch Predict Unit
- Optional Instruction Cache
- Optional Data Cache

## Documentation
[RV12 Datasheet](https://roalogic.com/wp-content/licenses/Non-Commercial_License_Agreement.html)

## License
Released under the RoaLogic [Non-Commerical License](/LICENSE.md)

## Regression tests
The release contains regression tests for the supported modules, based on the official riscv-tests.

## Dependencies
Requires the RoaLogic Memories IPs and AHB3Lite Package. These are included as submodules.
After cloning the RV12 git repository do a 'git submodule init' to download the submodules.
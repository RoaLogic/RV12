# rvl
RISC-V for Lattice EPC5


# GNU Toolchain
clone github.com/riscv/riscv-gnutoolchain

export RISCV=<install_dir>

./configure --prefix=$RISCV --enable-multilib --with_cmodel=medany


# Trade-offs / Enhancements / ChangeLog
Target: 100MHz operation in Lattice ECP5-6

RV12 Synplify Pro results: 94MHz. Critical path is from RF to EX
Slow BRAMs require Register File with registered outputs
This requires modifications to the pipeline

Updated pipeline with RF-registered output
Synplify Pro results: ~104MHz
Pipeline modifications broke a few options

Added RVC to reduce program memory footprint. This increases IF stage logic, but provides room for
- Branch Prediction
- Branch-Target-Buffers
- Return Address Stack
- Opcode Fusion (selective SuperScalar)

## Benchmarks
Use DHRYSTONE v2.2 as reference/benchmark

- RVL (rv64imc), no caches, no pipeline optimizations, no predictions, AHB bus, no latency external memory
  - Dhyrstones: 1135 (0.65DMIPS)

- Added PD-pipeline stage to reduce critical path. This results in 1 additional cycle branch/jump penalty.
  - Dhrystones: 1048 (0.60DMIPS) -7.7%

- Added Correlating Branch Predictor. Correct prediction reduces branch/jump penalty from 3 to 1 cycles (excluding external bus latency)
  - Dhrystones: 1184 (0.67DMIPS) + 13%


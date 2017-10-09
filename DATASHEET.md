Product Brief
=============

Introduction
------------

The RV12 is a highly configurable single-issue, single-core RV32I, RV64I compliant RISC CPU intended for the embedded market. The RV12 is a member of the Roa Logic’s 32/64bit CPU family based on the industry standard RISC-V instruction set.

![RV12 Architecture](assets/img/RV12_Arch.png)

The RV12 implements a Harvard architecture for simultaneous instruction and data memory accesses. It features an optimizing folded 4-stage pipeline, which optimizes overlaps between the execution and memory accesses, thereby reducing stalls and improving efficiency.

Optional features include Branch Prediction, Instruction Cache, Data Cache, Debug Unit and optional Multiplier/Divider Units. Parameterized and configurable features include the instruction and data interfaces, the branch-prediction-unit configuration, and the cache size, associativity, replacement algorithms and multiplier latency. Providing the user with trade offs between performance, power, and area to optimize the core for the application.

RV12 is compliant with the RISC-V User Level ISA v2.2 and Privileged Architecture v1.9.1 specifications published by the RISC-V Foundation (https://riscv.org).

Features
--------

**High Performance 32/64bit CPU**

-   Royalty Free Industry standard instruction set (www.riscv.org)

-   Parameterized 32/64bit data

-   Fast, precise interrupts

-   Custom instructions enable integration of proprietary hardware accelerators

-   Single cycle execution

-   Optimizing folded 4-stage pipeline

-   Optional/Parameterized branch-prediction-unit

-   Optional/Parameterized caches

**Highly Parameterized**

-   User selectable 32 or 64bit data

-   User selectable Branch Prediction Unit

-   User selectable instruction and/or data caches

-   User selectable cache size, structure, and architecture

-   Hardware Multiplier/Divider Support with user defined latency

-   Flexible bus architecture supporting AHB, Wishbone

**Size and power optimized design**

-   Fully parameterized design provides power/performance tradeoffs

-   Gated clock design to reduce power

-   Small silicon footprint; 30kgates for full featured implementation

**Industry standard software support**

-   Eclipse IDE for Windows/Linux

-   GNU Compiler Collection, debugger, linker, assembler

-   Architectural simulator

Introduction to the RV12
========================

The RISC-V specification provides for multi-threading and multi-core implementations. A core is defined as an implementation with its own instruction fetch unit. A hardware thread, or *hart*, is defined as a processing engine with its own state. A core may contain multiple hardware threads. See [www.riscv.org](http://www.riscv.org) for the specifications[1].

The RV12 implements a single core 32/64bit Reduced Instruction Set Computing (RISC) Central Processing Unit (CPU) with a single hardware thread, based on the RISC-V User Instruction Set Architecture v2.2 and Supervisor Instruction Set Architecture v1.9.1 specifications. The core is highly configurable, providing the user with a trade-off between area, power, and performance, thus allowing it to be optimized for the intended task.

See Configurations section for a description of the configuration options and parameters.

Privilege Levels
----------------

At any time, a hardware thread (*hart*) is running at some privilege level. The current privilege level is encoded in one or more Control and Status Registers (CSRs). The RISC-V specification defines four privilege levels, where each level provides its own protection and isolation..

| Level | Encoding | Name             | Abbreviation |
|:-----:|:--------:|:-----------------|:------------:|
|   0   |   `00`   | User/Application |       U      |
|   1   |   `01`   | Supervisor       |       S      |
|   2   |   `10`   | Hypervisor       |       H      |
|   3   |   `11`   | Machine          |       M      |

The highest privilege level is the Machine level. This is an inherent trusted level and has access to, and can alter, the whole machine. The lowest level is the User/Application level and is considered the least trusted level. It is used to protect the rest of the system from malicious applications.

Supervisor mode is used to provide isolation between an operating system and the machine and user levels. Hypervisor mode is used to virtualize operating systems.

The RV12 always implements Machine mode and optionally implements User mode and parts of the Supervisor Mode.

Execution Pipeline
------------------

The RV12 implements an optimizing 4-stage folded pipeline. The classic RISC pipeline consists of 5 stages; instruction fetch (IF), instruction decode (ID), execute (EX), memory access (MEM), and register write-back (WB).

![Classic RISC Pipeline](assets/img/Pipeline-Reg.png)

The RV12 implements a modified form of the classic RISC pipeline where the Fetch stage takes 2 cycles to allow time to recode 16bit-compressed instructions and predict branches and jumps. The Memory stage is folded into the Execute and Write-Back stages. The Decode stage optimizes the instruction stream to allow CPU stalls, instruction execution, and memory accesses to overlap, thereby effectively hiding CPU stalls and improving the CPU’s cycles per instruction CPI.

![Modified RV12 Pipeline](assets/img/Pipeline-RV12.png)

The RV12 pipeline is capable of executing one instruction per clock cycle by overlapping the execution stages. The figure below shows how 5 instructions are being operated on at the same time; this is referred to as ‘being in flight’. Instruction A is the oldest instruction and it’s in the Write Back (WB) stage, whereas Instruction E is the newest instruction and it’s in the Instruction Fetch (IF) stage.

![Overlapping Execution Stages](assets/img/Pipeline-Overlap.png)

### Instruction Fetch/Pre-Decode(IF/PD)

During the instruction fetch stage one instruction is read from the instruction memory, a 16bit-compressed instruction is decoded, and the program counter is updated to point to the next instruction.

### Instruction Decode (ID)

During the instruction decode stage the Register File is accessed and the bypass controls are determined.

### Execute (EX)

During the Execute stage the result is calculated for an ALU, MUL, DIV instruction, the memory accessed for a Load/Store instruction, and branches and jumps are calculated and checked against their predicted outcomes.

### Write Back (WB)

During the Write Back stage the result from the Execution stage is written into the Register File.

Branch Prediction Unit
----------------------

The RV12 can execute one instruction every clock cycle. However due to the pipeline architecture each instruction takes several clock cycles to complete. When a branch instruction is decoded its conditions and outcome are not known and waiting for the branch outcome before continuing fetching new instructions would cause excessive processor stalls, affecting the processor’s performance.

Instead of waiting the processor predicts the branch’s outcome and continues fetching instructions from the predicted address. When a branch is predicted wrong, the processor must flush its pipeline and restart fetching from the calculated branch address. The processor’s state is not affected because the pipeline is flushed and therefore none of the incorrectly fetched instructions is actually executed. However the branch prediction may have forced the Instruction Cache to load new instructions. The Instruction Cache state is NOT restored, meaning the predicted instructions remain in the Instruction Cache.

The RV12 has an optional Branch Prediction Unit (BPU) that stores historical data to guide the processor in deciding if a particular branch is taken or not-taken. The BPU data is updated as soon as the branch executes.

The BPU has a number of parameters that determine its behavior. `HAS_BPU` determines if a BPU is present, `BPU_LOCAL_BITS` determines how many of the program counter’s LSB must be used and `BPU_GLOBAL_BITS` determines how many history bits must be used.

The combination of `BPU_GLOBAL_BITS` and `BPU_LOCAL_BITS` creates a vector that is used to address the Branch-Prediction-Table. Increasing the `BPU_LOCAL_BITS` increases the number of program counter entries, thereby reducing aliasing of the branch predictor at the expense of a larger Branch Prediction Table.

Setting `BPU_GLOBAL_BITS` to zero creates a local-predictor. Setting `BPU_GLOBAL_BITS` to any non-zero value adds history (previous branch prediction results) to the vector. This allows the branch predictor to handle nested branches. Increasing the number of `BPU_GLOBAL_BITS` adds more history to the vector at the expense of a larger Branch Prediction Table.

If no BPU is present, then all forward branches are predicted taken and all backward branches are predicted not-taken.

Control & Status Registers (CSRs)
---------------------------------

The Control & Status Registers, or CSRs for short, provide information about the current state of the processor. See section “Control & Status Registers”, for a description of the registers and their purpose.

Debug Unit
----------

The Debug Unit allows the Debug Environment to stall and inspect the CPU. Provided features include Single Step Tracing, Branch Tracing, and up to 8 Hardware Breakpoints.

Data Cache
----------

The Data Cache is used to speed up data memory accesses by buffering recently accessed memory locations. The data cache is capable of handling, byte, half-word, and word accesses when `XLEN=32`, as long as they are on their respective boundaries. It is capable of handling byte, half-word, word, and double-word accesses when `XLEN=64`, as long as they are on their respective boundaries. Accessing a memory location on a non-natural boundary (e.g. a word access on address 0x003) causes a data-load trap.

During a cache miss a complete block is written back to memory, if required, and a new block loaded is loaded into the cache. Setting `DCACHE_SIZE` to zero disables the Data Cache. Memory locations are then directly access via the Data Interface.

Instruction Cache
-----------------

The Instruction Cache is used to speed up instruction fetching by buffering recently fetched instructions. The Instruction Cache is capable of fetching one parcel per cycle on any 16bit boundary, but it cannot fetch across a block boundary. During a cache miss a complete block is loaded from instruction memory.

The Instruction Cache can be configured according to the user’s needs. The cache size, block length, associativity, and replacement algorithm are configurable.

Setting `ICACHE_SIZE` to zero disables the Instruction Cache. Parcels are then directly fetched from the memory via the Instruction Interface.

Integer Pipeline
----------------

The RV12 has a single integer pipeline that can execute one instruction per cycle. The pipeline handles all logical, integer arithmetic, CSR access, and PC modifying instructions.

Register File
-------------

The Register File is made up of 32 register locations (X0-X31) each XLEN bits wide. Register X0 is always zero. The Register File has two read ports and one write port.

RV12 Execution Pipeline
=======================

The RV12 implements a 32/64bit Integer modified form of the classic RISC pipeline. The pipeline consists of the Instruction Fetch, Pre-Decode, Instruction Decode, Execution, and Write Back stages as highlighted in the figure below.

![RV12 Execution Pipeline](assets/img/Pipeline-Overview.png)

Instruction Fetch (IF)
----------------------

![Instruction Fetch Stage Implementation](assets/img/Pipeline-IF.png)

The Instruction Fetch unit loads a new parcel from the program memory. A parcel is a code field that contains one or more instructions. The address of the parcel to load is held by the Program Counter (PC). The Program Counter is either 32 or 64bits wide, depending on the XLEN parameter. The Program Counter is updated whenever the Instruction Pipeline is not stalled.

In case the pipeline must be flushed the Program Counter is restarted from the given address.

| **Signal**     | **Direction** |  **To/From**  | **Description**                              |
|:---------------|:-------------:|:-------------:|:---------------------------------------------|
| `if_nxt_pc`    |       to      | Bus Interface | Next address to fetch parcel from            |
| `parcel_pc`    |      from     | Bus Interface | Fetch parcel’s address                       |
| `parcel_valid` |      from     | Bus Interface | Valid indicators for parcel                  |
| `parcel`       |      from     | Bus Interface | Fetched parcel                               |
|                |               |               |                                              |
| `Flush`        |      from     |    EX/State   | When asserted flushes the pipe               |
| `Stall`        |      from     |       PD      | When asserted stalls the pipe                |
| `pd_branch_pc` |      from     |       PD      | New program counter for a branch instruction |
| `if_pc`        |       to      |       PD      | Instruction Fetch program counter            |
| `if_instr`     |       to      |       PD      | Instruction Fetch instruction                |
| `if_bubble`    |       to      |       PD      | Instruction Fetch bubble                     |

Pre-Decode (PD)
---------------

The Pre-Decode unti translates 16-bit compressed instructions to the base 32bit RISC-V instructions and then processes Program Counter modifying instructions. Jump-And-Link and Branch instructions modify the Program Counter in the Instruction Fetch stage. This avoids waiting for the Execution stage to trigger the update and reduces the demand for pipeline flushes. The destination address for branches is predicted based on the data provided by the optional Branch Prediction Unit or determined statically based on the offset.

![Instruction Pre-Decode Stage](assets/img/Pipeline-PD.png)

| **Signal**     | **Direction** | **To/From** | **Description**                               |
|:---------------|:-------------:|:-----------:|:----------------------------------------------|
| `if_pc`        |      from     |      IF     | Instruction\_fetch program counter            |
| `if_instr`     |      from     |      IF     | Instruction\_fetch instruction                |
| `if_bubble`    |      from     |      IF     | Instruction\_fetch bubble                     |
| `pd_branch_pc` |       to      |      IF     | New PC (for a branch instruction)             |
|                |               |             |                                               |
| `bu_predict`   |      from     |      BP     | Branch prediction from Branch Prediction Unit |
| `pd_predict `  |       to      |      ID     | Forwarded branch prediction                   |
| `pd_pc`        |       to      |      ID     | Pre-Decode program counter                    |
| `pd_instr`     |       to      |      ID     | Pre-Decode instruction                        |
| `pd_bubble`    |       to      |      ID     | Pre-Decode bubble                             |

Instruction Decode (ID)
-----------------------

The Instruction Decode unit ensures the operands for the execution units are available. It accesses the Register File, calculates immediate values, and sets bypasses.

![Instruction Decode Stage Implementation](assets/img/Pipeline-ID.png)

| **Signal**   | **Direction** | **To/From** | **Description**                    |
|:-------------|:-------------:|:-----------:|:-----------------------------------|
| `pd_pc`      |      from     |      PD     | Pre-Decode program counter         |
| `pd_instr`   |      from     |      PD     | Pre-Decode instruction             |
| `pd_bubble`  |      from     |      PD     | Pre-Decode bubble                  |
|              |               |             |                                    |
| `src1`       |       to      |      RF     | Source Register1 index             |
| `src2`       |       to      |      RF     | Source Register2 Index             |
|              |               |             |                                    |
| `id_bypassA` |       to      |      EX     | Bypass signals for srcA            |
| `id_bypassB` |       to      |      EX     | Bypass signals for srcB            |
| `id_opA`     |       to      |      EX     | Calculated operandA                |
| `id_opB`     |       to      |      EX     | Calculated operandB                |
| `id_pc`      |       to      |      EX     | Instruction Decode program counter |
| `id_instr`   |       to      |      EX     | Instruction Decode instruction     |
| `id_bubble`  |       to      |      EX     | Instruction Decode bubble          |

Execute (EX)
------------

The Execute stage performs the required operation on the data provided by the Instruction Decode stage. The Execution stage has multiple execution units, each with a unique function. The ALU performs logical and arithmetic operations. The Multiplier unit calculates signed/unsigned multiplications. The Divider unit calculates signed/unsigned division and remainder. The Load-Store Unit accesses the data memory. The Branch Unit calculates jump and branch addresses and validates the predicted branches.

Only one operation can be executed per clock cycle. Most operations complete in one clock cycle, except for the divide instructions, which always take multiple clock cycles to complete. The multiplier supports configurable latencies, to improve performance.

![Execute Stage Implementation](assets/img/Pipeline-EX.png)

| **Signal**  | **Direction** | **To/From** | **Description**                    |
|:------------|:-------------:|:-----------:|:-----------------------------------|
| id\_pc      |      from     |      ID     | Instruction Decode program counter |
| id\_instr   |      from     |      ID     | Instruction Decode instruction     |
| id\_bubble  |      from     |      ID     | Instruction Decode bubble          |
|             |               |             |                                    |
| opA         |      from     |      RF     | Source Register1 value             |
| opB         |      from     |      RF     | Source Register2 value             |
|             |               |             |                                    |
| id\_bypassA |      from     |      ID     | Bypass signals for srcA            |
| id\_bypassB |      from     |      ID     | Bypass signals for srcB            |
| id\_opA     |      from     |      ID     | Calculated operandA                |
| id\_opB     |      from     |      ID     | Calculated operandB                |
| ex\_stall   |       to      |      ID     | Stall ID (and higher) stages       |
| ex\_flush   |       to      |   ID/PD/IF  | Flush ID (and higher) pipe stages  |
| ex\_r       |       to      |      WB     | Result from execution units        |
| ex\_pc      |       to      |      WB     | Execute program counter            |
| ex\_instr   |       to      |      WB     | Execute instruction                |
| ex\_bubble  |       to      |      WB     | Execute bubble                     |

Write-Back (WB)
---------------

The Write-Back stage writes the results from the Execution Unit into the Register File.

![Write-back Stage Implementation](assets/img/Pipeline-WB.png)

| **Signal**  | **Direction** | **To/From** | **Description**             |
|:------------|:-------------:|:-----------:|:----------------------------|
| `ex_pc`     |      from     |      EX     | Execute program counter     |
| `ex_instr`  |      from     |      EX     | Execute instruction         |
| `ex_bubble` |      from     |      EX     | Execute bubble              |
| `ex_r`      |      from     |      EX     | Result from execution units |
|             |               |             |                             |
| `wb_r`      |       to      |      RF     | Result to be written to RF  |
| `wb_dst`    |       to      |      RF     | Destination register index  |
| `wb_we`     |       to      |      RF     | Write enable                |
| `wb_pc`     |       to      |      WB     | WriteBack program counter   |
| `wb_instr`  |       to      |      WB     | WriteBack instruction       |

Control & Status Registers
==========================

Introduction
------------

The state of the CPU is maintained by the Control & Status Registers (CSRs). They determine the feature set, set interrupts and interrupt masks, and determine the privilege level. The CSRs are mapped into an internal 12bit address space and are accessible using special commands.

Accessing the CSRs
------------------

The CSRRW (Atomic Read/Write CSR) instruction atomically swaps values in the CSRs and integer registers. CSRRW reads the old value of the CSR, zero-extends the value to XLEN bits, and writes it to register *rd*. The initial value in register *rs1* is written to the CSR.

The CSRRS (Atomic Read and Set CSR) instruction reads the old value of the CSR, zero-extends the value to XLEN bits, and writes it to register *rd*. The initial value in register *rs1* specifies the bit positions to be set in the CSR. Any bit that is high in *rs1* will be set in the CSR, assuming that bit can be set. The effect is a logic OR between the old value in the CSR and the new value in *rs1*.

If *rs1*=X0, then the CSR is not written to.

The CSRRC (Atomic Read and Clear CSR) instruction reads the old value of the CSR, zero-extends the value to XLEN bits, and writes it to register *rd*. The initial value in register *rs1* specifies the bit positions to be cleared in the CSR. Any bit that is high in *rs1* will be cleared in the CSR, assuming that bit can be cleared. If *rs1*=X0, then the CSR is not written to.

The CSRRWI, CSRRSI, and CSRRCI commands are similar in behavior. Except that they update the CSR using an immediate value, instead of referencing a source register. The immediate value is obtained by zero-extending the 5bit *zimm* field. If *zimm\[4:0\]* is zero, then the CSR is not written to.

Illegal CSR accesses
--------------------

Depending on the privilege level some CSRs may not be accessible. Attempts to access a non-existing CSR raise an illegal-instruction exception. Attempts to access a privileged CSR or write a read-only CSR raise an illegal-instruction exception. Machine Mode can access all CSRs, whereas User Mode can only access a few.

Timers and Counters
-------------------

The RV12 provides a number of 64-bit read-only user-level counters, which are mapped into the 12-bit CSR address space and accessed in 32-bit pieces using CSRRS instructions.

The RDCYCLE pseudo-instruction reads the low XLEN bits of the cycle CSR that holds a count of the number of clock cycles executed by the processor on which the hardware thread is running from an arbitrary start time in the past. RDCYCLEH is an RV32I-only instruction that reads bits 63–32 of the same cycle counter. The rate at which the cycle counter advances will depend on the implementation and operating environment.

The RDTIME pseudo-instruction reads the low XLEN bits of the time CSR, which counts wall-clock real time that has passed from an arbitrary start time in the past. RDTIMEH is an RV32I-only instruction that reads bits 63–32 of the same real-time counter. The underlying 64-bit counter should never overflow in practice. The execution environment should provide a means of determining the period of the real-time counter (seconds/tick). The period must be constant. The real-time clocks of all hardware threads in a single user application should be synchronized to within one tick of the real-time clock. The environment should provide a means to determine the accuracy of the clock.

The RDINSTRET pseudo-instruction reads the low XLEN bits of the instret CSR, which counts the number of instructions retired by this hardware thread from some arbitrary start point in the past. RDINSTRETH is an RV32I-only instruction that reads bits 63–32 of the same instruction counter.

In RV64I, the CSR instructions can manipulate 64-bit CSRs. In particular, the RDCYCLE, RDTIME, and RDINSTRET pseudo-instructions read the full 64 bits of the cycle, time, and instret counters. Hence, the RDCYCLEH, RDTIMEH, and RDINSTRETH instructions are not necessary and are illegal in RV64I.

CSR Listing
-----------

The following sections describe each of the register functions as specifically implemented in RV12.

Note: These descriptions are derived from “The RISC-V Instruction Set Manual, Volume II: Privileged Architecture, Version 1.9.1", Editors Andrew Waterman and Krste Asanović, RISC-V Foundation, November 4, 2016, and released under the Creative Commons Attribution 4.0 International License

| **Address** | **Privilege** |   **Name**  | **Description**                           |
|:-----------:|:-------------:|:-----------:|:------------------------------------------|
|    0xF11    |      MRO      | `mvendorid` | Vendor ID                                 |
|    0xF12    |      MRO      |  `marchid`  | Architecture ID                           |
|    0xF13    |      MRO      |   `mimpid`  | Implementation ID                         |
|    0xF14    |      MRO      |  `mhartid`  | Hardware thread ID                        |
|    0x300    |      MRW      |  `mstatus`  | Machine status register                   |
|    0x301    |      MRW      |    `misa`   | ISA and extensions                        |
|    0x302    |      MRW      |  `medeleg`  | Machine exception delegation register     |
|    0x303    |      MRW      |  `mideleg`  | Machine interrupt delegation register     |
|    0x304    |      MRW      |    `mie`    | Machine interrupt-enable register         |
|    0x305    |      MRW      |   `mtvec`   | Machine trap-handler base address         |
|    0x7c0    |      MRW      |  `mnmivec`  | Machine non-maskable interrupt vector     |
|    0x340    |      MRW      |  `mscratch` | Scratch register for machine trap handler |
|    0x341    |      MRW      |    `mepc`   | Machine exception program counter         |
|    0x342    |      MRW      |   `mcause`  | Machine trap cause                        |
|    0x343    |      MRW      |  `mbadaddr` | Machine bad address                       |
|    0x344    |      MRW      |    `mip`    | Machine interrupt pending                 |
|    0xB00    |      MRW      |   `mcycle`  | Machine cycle counter                     |
|    0xB02    |      MRW      |  `minstret` | Machine instructions-retired counter      |
|    0xB80    |      MRW      |  `mcycleh`  | Upper 32 bits of `mcycle`, RV32I only     |
|    0xB82    |      MRW      | `minstreth` | Upper 32 bits of `minstret`, RV32I only   |

| **Address** | **Privilege** |  **Name**  | **Description**                          |
|:-----------:|:-------------:|:----------:|:-----------------------------------------|
|    0x100    |      SRW      |  `sstatus` | Supervisor status register               |
|    0x102    |      SRW      |  `sedeleg` | Supervisor exception delegation register |
|    0x103    |      SRW      |  `sideleg` | Supervisor interrupt delegation register |
|    0x104    |      SRW      |    `sie`   | Supervisor interrupt-enable register     |
|    0x105    |      SRW      |   `stvec`  | Supervisor trap handler base address     |
|    0x140    |      SRW      | `sscratch` | Scratch register for trap handler        |
|    0x141    |      SRW      |   `sepc`   | Supervisor exception program counter     |
|    0x142    |      SRO      |  `scause`  | Supervisor trap cause                    |
|    0x143    |      SRO      | `sbadaddr` | Supervisor bad address                   |
|    0x144    |      SRW      |    `sip`   | Supervisor interrupt pending register    |

| **Address** | **Privilege** |   **Name**  | **Description**                            |
|:-----------:|:-------------:|:-----------:|:-------------------------------------------|
|    0xC00    |      URO      |   `cycle`   | Cycle counter for `RDCYCLE` instruction    |
|    0xC02    |      URO      |  `instret`  | Instruction-retire counter for `RDINSTRET` |
|    0xC80    |      URO      |   `cycleh`  | Upper 32bits of `cycle`, RV32I only        |
|    0xC82    |      URO      | `instret` h | Upper 32bit of `instret`, RV32I only       |

Machine Level CSRs
------------------

In addition to the machine-level CSRs described in this section, M-mode can access all CSRs at lower privilege levels.

### Machine ISA Register (`misa`)

The `misa` register is an XLEN-bit WARL read-write register reporting the ISA supported by the hart.

The extensions field encodes the presence of the standard extensions, with a single bit per letter of the alphabet (bit 0 encodes the presence of extension “A”, bit 1 encodes the presence of extension “B”, through to bit 25 that encodes the presence of extension “Z”).

The “I” bit will be set for RV32I and RV64I base ISAs, and the “E” bit will be set for RV32E.

The Base field encodes the native base integer ISA width as shown:

| Value | Description |
|:-----:|:-----------:|
|   1   |      32     |
|   2   |      64     |

### Vendor ID Register (`mvendorid`)

The `mvendorid` read-only register is an XLEN-bit register encoding the manufacturer of the device.

Non-Zero vendor IDs will be allocated by the RISC-V Foundation.

### Architecture ID Register (`marchid`)

The `marched` CSR is an XLEN-bit read-only register encoding the base microarchitecture of the hart. For the RV12 CPU this is defined as:

Note: Open-source project architecture IDs are allocated globally by the RISC-V Foundation, and have non-zero architecture IDs with a zero most-significant-bit (MSB). Commercial architecture IDs are allocated by each commercial vendor independently and have the MSB set.

### Implementation ID Register (`mimpid`)

The `mimpid` read-only register provides hardware version information for the CPU. In the Roa Logic implementation, the 2 least significant bytes encode the major and minor code revisions.

The `mimpid` register is an XLEN size register, but the RV12 only implements the lower 32 bits. For an RV64 implementation the MSBs are zero extended.

### Hardware Thread ID Register (`mhartid`)

The `mhartid` read-only register indicates the hardware thread that is running the code. The RV12 implements a single thread, therefore this register always reads zero.

### Machine Status Register (`mstatus`)

The `mstatus` register is an `XLEN`-bit read/write register that keeps track of and controls the *hart’s* current operating state.

#### Privilege and Global Interrupt-Enable Stack in mstatus register

Interrupt-enable bits, `MIE`, `SIE`, and `UIE`, are provided for each privilege mode. These bits are primarily used to guarantee atomicity with respect to interrupt handlers at the current privilege level. When a hart is executing in privilege mode *x*, interrupts are enabled when `xIE=1`. Interrupts for lower privilege modes are always disabled, whereas interrupts for higher privilege modes are always enabled. Higher-privilege-level code can use separate per-interrupt enable bits to disable selected interrupts before ceding control to a lower privilege level.

The `MRET`, `SRET`, or `URET` instructions are used to return from traps in M-mode, S-mode, or U-mode respectively. When executing an `xRET` instruction, supposing `xPP` holds the value `y`, `yIE` is set to `xPIE`; the privilege mode is changed to `y`; `xPIE` is set to 1; and `xPP` is set to U.

#### Memory Privilege in `mstatus` Register 

The `MPRV` bit modifies the privilege level at which loads and stores execute. When `MPRV`=’0’, translation and protection behave as normal. When `MPRV`=’1’, data memory addresses are translated and protected as though `PRV` were set to the current value of the `PRV1` field. Instruction address-translation and protection are unaffected. When an exception occurs, `MPRV` is reset to 0.

#### Virtualization Management & Context Extension Fields in `mstatus` Register 

Virtualization and Context Extensions are not supported by the RV12 v1.0 implementation. The value of these fields will therefore be permanently set to 0.

### Machine Delegation Registers (`medeleg` & `mideleg`)

Individual read/write bits within `medeleg` and `mideleg` registers indicate that lower privilege levels should directly process certain exceptions and interrupts.

When a trap is delegated to a less-privileged mode `x`, the `xcause` register is written with the trap cause; the `xepc` register is written with the virtual address of the instruction that took the trap; the `xPP` field of `mstatus` is written with the active privilege mode at the time of the trap; the `xPIE` field of `mstatus` is written with the value of the active interrupt-enable bit at the time of the trap; and the `xIE` field of `mstatus` is cleared. The `mcause` and `mepc` registers and the `MPP` and `MPIE` fields of `mstatus` are not written.

`medeleg` has a bit position allocated for every synchronous exception with the index of the bit position equal to the value returned in the `mcause` register (I.e. setting bit 8 allows user-mode environment calls to be delegated to a lower-privilege trap handler).

`mideleg` holds trap delegation bits for individual interrupts, with the layout of bits matching those in the `mip` register (I.e. `STIP` interrupt delegation control is located in bit 5).

### Machine Interrupt Registers (`mie`, `mip`)

The `mip` register is an `XLEN`-bit read/write register containing information on pending interrupts, while `mie` is the corresponding `XLEN`-bit read/write register containing interrupt enable bits. Only the bits corresponding to lower-privilege software interrupts (`USIP`, `SSIP`) and timer interrupts (`UTIP`, `STIP`) in `mip` are writable through this CSR address; the remaining bits are read-only.

Restricted views of the `mip` and `mie` registers appear as the `sip/sie`, and `uip/uie` registers in S-mode, and U-mode respectively. If an interrupt is delegated to privilege mode `x` by setting a bit in the `mideleg` register, it becomes visible in the `xip` register and is maskable using the `xie`register. Otherwise, the corresponding bits in `xip` and `x`ie appear to be hardwired to zero.

The `MTIP`, `STIP`, `UTIP` bits correspond to timer interrupt-pending bits for machine, supervisor, and user timer interrupts, respectively. The `MTIP` bit is read-only and is cleared by writing to the memory-mapped machine-mode timer compare register. The `UTIP` and `STIP` bits may be written by M-mode software to deliver timer interrupts to lower privilege levels. User and supervisor software may clear the `UTIP` and `STIP` bits with calls to the AEE or SEE respectively.

There is a separate timer interrupt-enable bit, named `MTIE`, `STIE`, and `UTIE` for M-mode, S-mode, and U-mode timer interrupts respectively.

Each lower privilege level has a separate software interrupt-pending bit (`SSIP`, `USIP`), which can be both read and written by CSR accesses from code running on the local hart at the associated or any higher privilege level. The machine-level `MSIP` bits are written by accesses to memory-mapped control registers, which are used by remote harts to provide machine-mode interprocessor interrupts. Interprocessor interrupts for lower privilege levels are implemented through ABI or SBI calls to the AEE or SEE respectively, which might ultimately result in a machine- mode write to the receiving hart’s `MSIP` bit. A hart can write its own `MSIP` bit using the same memory-mapped control register.

The `MEIP`, `SEIP`, `UEIP` bits correspond to external interrupt-pending bits for machine, supervisor, and user external interrupts, respectively. These bits are read-only and are set and cleared by a platform-specific interrupt controller. There is a separate external interrupt-enable bit, named `MEIE`, `SEIE`, and `UEIE` for M-mode, S-mode, and U-mode external interrupts respectively.

An interrupt` i` will be taken if bit `i` is set in both `mip` and `mie`, and if interrupts are globally enabled. By default, M-mode interrupts are globally enabled if the hart’s current privilege mode is less than M, or if the current privilege mode is M and the `MIE` bit in the `mstatus` register is set. If bit `i` in `mideleg` is set, however, interrupts are considered to be globally enabled if the hart’s current privilege mode equals the delegated privilege mode (S, or U) and that mode’s interrupt enable bit (`SIE` or `UIE` in `mstatus`) is set, or if the current privilege mode is less than the delegated privilege mode.

Multiple simultaneous interrupts and traps at the same privilege level are handled in the following decreasing priority order: external interrupts, software interrupts, timer interrupts, and then finally any synchronous traps.

### Machine Trap-Handler Base Address Register (`mtvec`)

The mtvec register is an XLEN-bit read/write register that holds the base address of the M-mode trap vector.

All traps into machine mode cause the pc to be set to the value in `mtvec`. Additional trap vector entry points can be defined by implementations to allow more rapid identification and service of certain trap causes.

### Machine Non-Maskable Interrupt Vector (`mnmivec`)

The mnmivec register is an XLEN-bit read/write register that holds the base address of the non-maskable interrupt trap vector. When an exception occurs, the pc is set to mnmivec.

### Machine Trap Handler Scratch Register (`mscratch`)

The `mscratch` register is an XLEN-bit read/write register dedicated for use by machine mode. It is used to hold a pointer to a machine-mode hart-local context space and swapped with a user register upon entry to an M-mode trap handler.

### Machine Exception Program Counter Register (`mepc`)

`mepc` is an XLEN-bit read/write register. The two low bits (mepc\[1:0\]) are always zero.

When a trap is taken, `mepc` is written with the virtual address of the instruction that encountered the exception.

### Machine Trap Cause Register (`mcause`)

The `mcause` register is an XLEN-bit read-write register. The Interrupt bit is set if the exception was caused by an interrupt. The Exception Code field contains a code identifying the last exception. The remaining center bits will read zero

See PDF Datasheet for further details

### Machine Bad Address Register (`mbadaddr`)

`mbadaddr` is an XLEN-bit read-write register. When a hardware breakpoint is triggered, or an instruction-fetch, load, or store address-misaligned or access exception occurs, `mbadaddr` is written with the faulting address. `mbadaddr` is not modified for other exceptions.

For instruction-fetch access faults with variable-length instructions, `mbadaddr` will point to the portion of the instruction that caused the fault while `mepc` will point to the beginning of the instruction.

### Machine Cycle Counter (mcycle, `mcycleh`)

The `mcycle` CSR holds a count of the number of cycles the hart has executed since some arbitrary time in the past. The `mcycle` register has 64-bit precision on all RV32 and RV64 systems.

On RV32 only, reads of the `mcycle` CSR returns the low 32 bits, while reads of the `mcycleh` CSR returns bits 63–32.

### Machine Instructions-Retired counter (minstret, `minstreth`)

The `minstret` CSR holds a count of the number of instructions the hart has retired since some arbitrary time in the past. The `minstret` register has 64-bit precision on all RV32 and RV64 systems.

On RV32 only, reads of the `minstret` CSR returns the low 32 bits, while reads of the `minstreth` CSR returns bits 63–32.

Supervisor Mode CSRs
--------------------

### Supervisor Status Register (sstatus) 

The sstatus register is an XLEN-bit read/write register. The sstatus register keeps track of the processor’s current operating state.

The `SPP` bit indicates the privilege level at which a *hart* was executing before entering supervisor mode. When a trap is taken, `SPP` is set to 0 if the trap originated from user mode, or 1 otherwise. When an `SRET` instruction is executed to return from the trap handler, the privilege level is set to user mode if the `SPP` bit is 0, or supervisor mode if the `SPP` bit is 1; `SPP` is then set to 0.

The `SIE` bit enables or disables all interrupts in supervisor mode. When `SIE` is clear, interrupts are not taken while in supervisor mode. When the *hart* is running in user-mode, the value in `SIE` is ignored, and supervisor-level interrupts are enabled. The supervisor can disable indivdual interrupt sources using the `sie` register.

The `SPIE` bit indicates whether interrupts were enabled before entering supervisor mode. When a trap is taken into supervisor mode, `SPIE` is set to either `SIE` or `UIE` depending on whether the trap was taken in supervisor or user mode respectively, and `SIE` is set to 0. When an `SRET` instruction is executed, if `SPP=S`, then `SIE` is set to `SPIE`; or if `SPP=U`, then `UIE` is set to `SPIE`. In either case, `SPIE` is then set to 1.

The `UIE` bit enables or disables user-mode interrupts. User-level interrupts are enabled only if `UIE` is set and the *hart* is running in user-mode. The `UPIE` bit indicates whether user-level interrupts were enabled prior to taking a user-level trap. When a `URET` instruction is executed, `UIE` is set to `UPIE`, and `UPIE` is set to 1.

#### Memory Privilege in `sstatus` Register 

The `PUM` (Protect User Memory) bit modifies the privilege with which S-mode loads, stores, and instruction fetches access virtual memory. When `PUM=0`, translation and protection behave as normal. When `PUM=1`, S-mode memory accesses to pages that are accessible by U-mode will fault. `PUM` has no effect when executing in U-mode.

### Supervisor Trap Delegation Registers (`sedeleg`, `sideleg`)

The machine exception delegation register (`sedeleg`) and machine interrupt delegation register (`sideleg`) are XLEN-bit read/write registers.

### Supervisor Interrupt Registers (sip, sie)

The `sip` register is an XLEN-bit read/write register containing information on pending interrupts; `sie` is the corresponding XLEN-bit read/write register containing interrupt enable bits.

Three types of interrupts are defined: software interrupts, timer interrupts, and external interrupts. A supervisor-level software interrupt is triggered on the current *hart* by writing 1 to its supervisor software interrupt-pending (`SSIP`) bit in the `sip` register. A pending supervisor-level software interrupt can be cleared by writing 0 to the `SSIP` bit in `sip`. Supervisor-level software interrupts are disabled when the `SSIE` bit in the `sie` register is clear.

Interprocessor interrupts are sent to other harts by means of *SBI* calls, which will ultimately cause the `SSIP` bit to be set in the recipient *hart’s* `sip` register.

A user-level software interrupt is triggered on the current *hart* by writing 1 to its user software interrupt-pending (`USIP`) bit in the sip register. A pending user-level software interrupt can be cleared by writing 0 to the `USIP` bit in `sip`. User-level software interrupts are disabled when the `USIE` bit in the `sie` register is clear.

All bits besides `SSIP` and `USIP` in the `sip` register are read-only.

A supervisor-level timer interrupt is pending if the `STIP` bit in the `sip` register is set. Supervisor-level timer interrupts are disabled when the `STIE` bit in the `sie` register is clear. An *SBI* call to the SEE may be used to clear the pending timer interrupt.

A user-level timer interrupt is pending if the `UTIP` bit in the `sip` register is set. User-level timer interrupts are disabled when the `UTIE` bit in the `sie` register is clear. If user-level interrupts are supported, the *ABI* should provide a facility for scheduling timer interrupts in terms of real-time counter values.

A supervisor-level external interrupt is pending if the `SEIP` bit in the `sip` register is set. Supervisor-level external interrupts are disabled when the `SEIE` bit in the `sie` register is clear. The *SBI* should provide facilities to mask, unmask, and query the cause of external interrupts.

A user-level external interrupt is pending if the `UEIP` bit in the `sip` register is set. User-level external interrupts are disabled when the UEIE bit in the `sie` register is clear.

### Supervisor Trap Vector Register (`stvec`)

The `stvec` register is an XLEN-bit read/write register that holds the base address of the S-mode trap vector. When an exception occurs, the pc is set to `stvec`. The `stvec` register is always aligned to a 4-byte boundary.

### Supervisor Scratch Register (`sscratch`) 

The `sscratch` register is an XLEN-bit read/write register, dedicated for use by the supervisor. Typically, `sscratch` is used to hold a pointer to the hart-local supervisor context while the hart is executing user code. At the beginning of a trap handler, `sscratch` is swapped with a user register to provide an initial working register.

### Supervisor Exception Program Counter (`sepc`)

`sepc` is an XLEN-bit read/write register formatted as shown in Figure 7‑24. The low bit of `sepc` (`sepc[0]`) is always zero. On implementations that do not support instruction-set extensions with 16-bit instruction alignment, the two low bits (`sepc[1:0]`) are always zero. When a trap is taken, `sepc` is written with the virtual address of the instruction that encountered the exception.

### Supervisor Cause Register (`scause`) 

The `scause` register is an XLEN-bit read-only register. The Interrupt bit is set if the exception was caused by an interrupt. The Exception Code field contains a code identifying the last exception.

| Interrupt | Exception Code | Description                    |
|:---------:|:--------------:|:-------------------------------|
|     1     |        0       | User software interrupt        |
|     1     |        1       | Supervisor software interrupt  |
|     1     |       2-3      | *Reserved*                     |
|     1     |        4       | User timer interrupt           |
|     1     |        5       | Supervisor timer interrupt     |
|     1     |       6-7      | *Reserved*                     |
|     1     |        8       | User external interrupt        |
|     1     |        9       | Supervisor external interrupt  |
|     1     |       ≤10      | *Reserved*                     |
|     0     |        0       | Instruction address misaligned |
|     0     |        1       | Instruction access fault       |
|     0     |        2       | Illegal Instruction            |
|     0     |        3       | Breakpoint                     |
|     0     |        4       | *Reserved*                     |
|     0     |        5       | Load access fault              |
|     0     |        6       | AMO address misaligned         |
|     0     |        7       | Store/AMO access fault         |
|     0     |        8       | Environment call               |
|     0     |       ≤9       | *Reserved*                     |

### Supervisor Bad Address Register (`sbadaddr`)

`sbadaddr` is an XLEN-bit read/write register. When a hardware breakpoint is triggered, or an instruction-fetch, load, or store access exception occurs, or an instruction-fetch or AMO address-misaligned exception occurs, `sbadaddr` is written with the faulting address. `sbadaddr` is not modified for other exceptions.

For instruction fetch access faults on RISC-V systems with variable-length instructions, `sbadaddr` will point to the portion of the instruction that caused the fault while `sepc` will point to the beginning of the instruction.

User Mode CSRs
--------------

### Cycle counter for RDCYCLE instruction (`cycle`)

`cycle` is an XLEN-bit read-only register. The `RDCYCLE` pseudo-instruction reads the low XLEN bits of the `cycle` CSR that holds a count of the number of clock cycles executed by the processor on which the hardware thread is running from an arbitrary start time in the past.

### Instruction-retire counter for RDINSTRET instruction (`instret`)

`instret` is an XLEN-bit read-only register. The RDINSTRET pseudo-instruction reads the low XLEN bits of the `instret` CSR, which counts the number of instructions retired by this hardware thread from some arbitrary start point in the past.

### Upper 32bits of cycle (`cycleh` - RV32I only)

`cycleh` is a read-only register that contains bits 63-32 of the counter of the number of clock cycles executed by the processor.

`RDCYCLEH` is an RV32I-only instruction providing access to this register.

### Upper 32bit of instret (`instreth` - RV32I only)

`instreth` is a read-only register that contains bits 63-32 of the instruction counter.

`RDINSTRETH` is an RV32I-only instruction providing access to this register

External Interfaces
===================

The RV12 CPU is designed to support a variety of external bus interfaces. The following sections define the default AMBA3 AHB-Lite and Interrupt Interfaces.

AMBA3 AHB-Lite
--------------

| Port         |  Size  | Direction | Description                                           |
|:-------------|:------:|:---------:|:------------------------------------------------------|
| `HRESETn`    |    1   |   Input   | Asynchronous active low reset                         |
| `HCLK`       |    1   |   Input   | System clock input                                    |
|              |        |           |                                                       |
| `IHSEL`      |    1   |   Output  | Provided for AHB-Lite compatibility – tied high (‘1’) |
| `IHADDR`     | `XLEN` |   Output  | Instruction address                                   |
| `IHRDATA`    |   32   |   Input   | Instruction data                                      |
| `IHWRITE`    |    1   |   Output  | Instruction write                                     |
| `IHSIZE`     |    3   |   Output  | Transfer size                                         |
| `IHBURST`    |    3   |   Output  | Transfer burst size                                   |
| `IHPROT`     |    4   |   Output  | Transfer protection level                             |
| `IHTRANS`    |    2   |   Output  | Transfer type                                         |
| `IHMASTLOCK` |    1   |   Output  | Transfer master lock                                  |
| `IHREADY`    |    1   |   Input   | Slave Ready Indicator                                 |
| `IHRESP`     |    1   |   Input   | Instruction Transfer Response                         |
|              |        |           |                                                       |
| `DHSEL`      |    1   |   Output  | Provided for AHB-Lite compatibility – tied high (‘1’) |
| `DHADDR`     | `XLEN` |   Output  | Data address                                          |
| `DHRDATA`    | `XLEN` |   Input   | Data read data                                        |
| `DHWDATA`    | `XLEN` |   Output  | Data write data                                       |
| `DHWRITE`    |    1   |   Output  | Instruction write                                     |
| `DHSIZE`     |    3   |   Output  | Transfer size                                         |
| `DHBURST`    |    3   |   Output  | Transfer burst size                                   |
| `DHPROT`     |    4   |   Output  | Transfer protection level                             |
| `DHTRANS`    |    2   |   Output  | Transfer type                                         |
| `DHMASTLOCK` |    1   |   Output  | Transfer master lock                                  |
| `DHREADY`    |    1   |   Input   | Slave Ready Indicator                                 |
| `DHRESP`     |    1   |   Input   | Data Transfer Response                                |

### HRESETn

When the active low asynchronous `HRESETn` input is asserted (‘0’), the core is put into its initial reset state.

### HCLK

`HCLK` is the system clock. All internal logic operates at the rising edge of the system clock. All AHB bus timings are related to the rising edge of `HCLK`.

### IHSEL

`IHSEL` is a *slave* selection signal and therefore provided for AHB-Lite completeness. This signal is tied permanently high (‘1’)

### IHADDR

`IHADDR` is the instruction address bus. Its size is determined by `PHYS_ADDR_SIZE`.

### IHRDATA

`IHRDATA` transfers the instruction from memory to the CPU. Its size is determined by XLEN. ` `

### IHWRITE

`IHWRITE` indicates whether the current transfer is a read or a write transfer. The instruction write is always negated (‘0’).

### IHSIZE

The instruction transfer size is indicated by `IHSIZE`. Its value depends on the `XLEN` parameter and if the current transfer is a cache-line fill or non-cacheable instruction read.

| `IHSIZE` |  Type | Description                                                                             |
|:--------:|:-----:|:----------------------------------------------------------------------------------------|
|   `010`  |  Word | Non-cacheable instruction read. `XLEN=32`                                               |
|   `011`  | Dword | Non-cacheable instruction read. `XLEN=64`                                               |
|   `1--`  |       | Cache line fill. The actual size depends on the Instruction cache parameters and `XLEN` |

### IHBURST

The instruction burst type indicates if the transfer is a single transfer or part of a burst.

| `IHBURST` | Type   | Description                     |
|:---------:|:-------|:--------------------------------|
|   `000`   | Single | *Not used*                      |
|   `001`   | INCR   | Non-cacheable instruction reads |
|   `010`   | WRAP4  | 4-beat wrapping burst           |
|   `011`   | INCR4  | *Not used*                      |
|   `100`   | WRAP8  | 8-beat wrapping burst           |
|   `101`   | INCR8  | *Not used*                      |
|   `110`   | WRAP16 | 16-bear wrapping burst          |
|   `111`   | INCR16 | *Not used*                      |

### IHPROT

The instruction protection signals provide information about the bus transfer. They are intended to implement some level of protection.

| Bit\# | Value | Description                                |
|:-----:|:-----:|:-------------------------------------------|
|   3   |   1   | Cacheable region addressed                 |
|       |   0   | Non-cacheable region addressed             |
|   2   |   1   | Bufferable                                 |
|       |   0   | Non-bufferable                             |
|   1   |   1   | Privileged access. CPU is not in User Mode |
|       |   0   | User access. CPU is in User Mode           |
|   0   |   0   | Opcode fetch, always ‘0’                   |

### IHTRANS

`IHTRANS` indicates the type of the current instruction transfer.

| `IHTRANS` | Type   | Description                                           |
|:---------:|:-------|:------------------------------------------------------|
|    `00`   | IDLE   | No transfer required                                  |
|    `01`   | BUSY   | CPU inserts wait states during instruction burst read |
|    `10`   | NONSEQ | First transfer of an instruction read burst           |
|    `11`   | SEQ    | Remaining transfers of an instruction readburst       |

### IHMASTLOCK

The instruction master lock signal indicates if the current transfer is part of a locked sequence, commonly used for Read-Modify-Write cycles. The instruction master lock is always negated (‘0’).

### IHREADY

`IHREADY` indicates whether the addressed slave is ready to transfer data or not. When `IHREADY` is negated (‘0’) the slave is not ready, forcing wait states. When `IHREADY` is asserted (‘0’) the slave is ready and the transfer completed.

### IHRESP

`IHRESP` is the instruction transfer response; it can either be `OKAY` (‘0’) or `ERROR` (‘1’). An error response causes a Bus Error exception.

### DHSEL

`DHSEL` is a *slave* selection signal and therefore provided for AHB-Lite completeness. This signal is tied permanently high (‘1’)

### DHADDR

`DHADDR` is the data address bus. Its size is determined by `PHYS_ADDR_SIZE`.

### DHRDATA

`DHRDATA` transfers the data from memory to the CPU. Its size is determined by `XLEN`.

### DHWDATA

`DHWDATA` transfers the data from the CPU to memory. Its size is determined by `XLEN`.

### DHWRITE

`DHWRITE` indicates whether the current transfer is a read or a write transfer. It is asserted (‘1’) during a write and negated (‘0’) during a read transfer.

### DHSIZE

The data transfer size is indicated by DHSIZE. Its value depends on the `XLEN` parameter and if the current transfer is a cache-line fill/write-back or a non-cacheable data transfer.

| `DHSIZE` | Type     | Description                                                                             |
|:--------:|:---------|:----------------------------------------------------------------------------------------|
|   `000`  | Byte     | Non-cacheable data transfer                                                             |
|   `001`  | Halfword | Non-cacheable data transfer                                                             |
|   `010`  | Word     | Non-cacheable data transfer                                                             |
|   `011`  | Dword    | Non-cacheable data transfer                                                             |
|   `1--`  |          | Cache line fill. The actual size depends on the Instruction cache parameters and `XLEN` |

### DHBURST

The instruction burst type indicates if the transfer is a single transfer or part of a burst.

| `DHBURST` |  Type  | Description                                    |
|:---------:|:------:|:-----------------------------------------------|
|    000    | Single | Single transfer. E.g. non-cacheable read/write |
|    001    |  INCR  | *Not used*                                     |
|    010    |  WRAP4 | 4-beat wrapping burst                          |
|    011    |  INCR4 | *Not used*                                     |
|    100    |  WRAP8 | 8-beat wrapping burst                          |
|    101    |  INCR8 | *Not used*                                     |
|    110    | WRAP16 | 16-bear wrapping burst                         |
|    111    | INCR16 | *Not used*                                     |

### DHPROT

The data protection signals provide information about the bus transfer. They are intended to implement some level of protection.

| Bit\# | Value | Description                                |
|:-----:|:-----:|:-------------------------------------------|
|   3   |   1   | Cacheable region addressed                 |
|       |   0   | Non-cacheable region addressed             |
|   2   |   1   | Bufferable                                 |
|       |   0   | Non-bufferable                             |
|   1   |   1   | Privileged access. CPU is not in User Mode |
|       |   0   | User access. CPU is in User Mode           |
|   0   |   1   | Data transfer, always ‘1’                  |

### DHTRANS

`DHTRANS` indicates the type of the current data transfer.

| `DHTRANS` |  Type  | Description                          |
|:---------:|:------:|:-------------------------------------|
|     00    |  IDLE  | No transfer required                 |
|     01    |  BUSY  | *Not used*                           |
|     10    | NONSEQ | First transfer of an data burst      |
|     11    |   SEQ  | Remaining transfers of an data burst |

### DHMASTLOCK

The data master lock signal indicates if the current transfer is part of a locked sequence, commonly used for Read-Modify-Write cycles. The data master lock is always negated (‘0’).

### DHREADY

`DHREADY` indicates whether the addressed slave is ready to transfer data or not. When `DHREADY` is negated (‘0’) the slave is not ready, forcing wait states. When `DHREADY` is asserted (‘0’) the slave is ready and the transfer completed.

### DHRESP

`DHRESP` is the data transfer response; it can either be `OKAY` (‘0’) or `ERROR` (‘1’). An error response causes a Bus Error exception.

Interrupts
----------

The RV12 supports multiple external interrupts and is designed to operate in conjunction with an external Platform Level Interrupt Controller (PLIC) as defined in Chapter 7 of the RISC-V Privilege Level specification v1.9.1.

Dedicated pins on the RV12 core present the interrupt to the CPU which then expects the Identifier of the Source Interrupt to be presented by the PLIC at the appropriate interrupt vector upon a claim of the interrupt.

|    Port   | Size | Direction | Description            |
|:---------:|:----:|:---------:|:-----------------------|
|  EXT\_NMI |   1  |   Input   | Non-Maskable Interrupt |
| EXT\_TINT |   1  |   Input   | Timer Interrupt        |
| EXT\_SINT |   1  |   Input   | Software Interrupt     |
|  EXT\_INT |   4  |   Input   | External Interrupts    |

### EXT\_NMI

The RV12 supports a single external non-maskable interrupt, accessible in Machine Mode only. The interrupt vector for `EXT_NMI` is defined as an RV12 core parameter `MNMIVEC_DEFAULT` (see section \[core-parameters\] )

### EXT\_TINT

The RV12 supports a single Machine-Mode timer interrupt `EXT_TINT`.

The interrupt may be delegated to other operating modes via software manipulation of `mip` and `sip` registers. Alternatively, higher performance interrupt redirection may be implemented via use of the `mideleg` and `sideleg` configuration registers

The interrupt vector used to service the interrupt is determined based on the mode the interrupt is delegated to via the `MTVEC_DEFAULT`, `STVEC_DEFAULT` and `UTVEC_DEFAULT` parameters.

### EXT\_SINT

The RV12 supports a single Machine-Mode timer interrupt `EXT_SINT`.

The interrupt may be delegated to other operating modes via software manipulation of `mip` and `sip` registers. Alternatively, higher performance interrupt redirection may be implemented via use of the `mideleg` and `sideleg` configuration registers

The interrupt vector used to service the interrupt is determined based on the mode the interrupt is delegated to via the `MTVEC_DEFAULT`, `STVEC_DEFAULT` and `UTVEC_DEFAULT` parameters.

### EXT\_INT

RV12 supports one general-purpose external interrupt input per operating mode, as defined in Table \[tab:external-interrupt-inputs\]:

| Interrupt     | Priority | Mode Supported  |
|:--------------|:--------:|:----------------|
| EXT\_INT\[3\] |     3    | Machine Mode    |
| EXT\_INT\[2\] |     2    | Reserved        |
| EXT\_INT\[1\] |     1    | Supervisor Mode |
| EXT\_INT\[0\] |     0    | User Mode       |

Each interrupt will be serviced by the operating mode it corresponds to, or alternatively a higher priority mode depending on the system configuration and specific operating conditions at the time the interrupt is handled. This includes if interrupt delegation is enabled, if a specific is implemented, or the specific operating mode at the time of servicing for example.

Notes:

1.  An external interrupt will never be serviced by a lower priority mode than that corresponding to the input pin. For example, an interrupt presented to `EXT_INT[1]` – corresponding to supervisor mode – cannot be serviced by a user mode ISR.

2.  Conversely, Machine Mode may service interrupts arriving on any of the interrupt inputs due to it have the highest priority.

Debug Unit
==========

Introduction
------------

The Debug Unit is a separate unit in the CPU. It’s not directly related to any instruction execution or support functions, like Cache or Branch Prediction. Instead it provides a means to halt the CPU and inspect its internal registers and state as a means of debugging the execution program.

The Debug Unit has its own interfaces and must be connected to an external debug controller that provides the actual interfacing to the external Debug Tools. The Debug Unit does not stall the CPU, instead it relies on the external debug controller to stall the CPU when the Debug Unit requests it.

Debug Controller Interface 
---------------------------

The Debug Unit has two interfaces; one to communicate with the CPU and one to communicate with the external debug controller. The CPU interface is an internal interface and therefore not described here.

The Debug Controller Interface is an SRAM like synchronous interface. The connected Debug Controller must use the same clock as the CPU.

| Port        |  Size  | Direction | Description           |
|:------------|:------:|:---------:|:----------------------|
| `dbg_stall` |    1   |   Input   | Stall CPU             |
| `dbg_strb`  |    1   |   Input   | Access Request/Strobe |
| `dbg_we`    |    1   |   Input   | Write Enable          |
| `dbg_addr`  |   13   |   Input   | Address Bus           |
| `dbg_dati`  | `XLEN` |   Input   | Write Data Bus        |
| `dbg_dato`  | `XLEN` |   Output  | Read Data Bus         |
| `dbg_ack`   |    1   |   Output  | Access Acknowledge    |
| `dbg_bp`    |    1   |   Output  | BreakPoint            |

### dbg\_stall

The CPU is halted when `dbg_stall` is asserted (‘1’). No new instructions are fed into the execution units. Any instructions already issued are finished.

The Debug Unit can use this signal to pause program execution and inspect the CPU’s state and registers. The Debug Controller must assert `dbg_stall` immediate (combinatorial) when the Debug Unit asserts `dbg_bp`.

### dbg\_strb

The Debug Controller asserts (‘1’) the Access Strobe signal when it wants to read from or write to the Debug Unit or the CPU’s registers. It must remain asserted until the Debug Unit acknowledges completion of the access by asserting (‘1’) `dbg_ack`.

### dbg\_we

The Debug Controller asserts (‘1’) the Write Enable signal when it wants to write to the Debug Unit or the CPU’s registers. It must remain asserted until the Debug Unit acknowledges completion of the access by asserting (‘1’) `dbg_ack`. It is valid only when `dbg_strb` is asserted as well.

### dbg\_addr

The address bus carries the register-address that is is read from or written to. See Register Map for the details.

### dbg\_dati

The write data bus carries the data to be written to the Debug Unit’s or CPU’s registers.

### dbg\_dato

The read data bus carries the data read from the Debug Unit’s or CPU’s registers.

### dbg\_bp

The Debug Unit asserts (‘1’) BreakPoint when a hardware breakpoint, single-step, branch-trace, or exception hit occurred. This is the CPU stall request from the Debug Unit to the external debug controller. The Debug Controller must assert (‘1’) `dbg_stall` immediately (combinatorial) upon detecting `dbg_bp` asserted.

Register Map
------------

The Debug Unit’s address map provides access to the Debug Unit’s internal registers, the Register Files, and the Control-and-Status-Registers.

The internal registers can be always accessed, whereas the Register Files and the CSRs can only be access when the CPU is stalled.

| **addr\[12:0\]** |  **Register** | **Description**                                                        |
|:-----------------|:-------------:|:-----------------------------------------------------------------------|
| 0x0000           |   `DBG_CTRL`  | Debug Control                                                          |
| 0x0001           |   `DBG_HIT`   | Debug Hit                                                              |
| 0x0002           |    `DBG_IE`   | Debug Interrupt Enable                                                 |
| 0x0003           |  `DBG_CAUSE`  | Debug Interrupt Cause                                                  |
| 0x0004-0x000F    |               | *Reserved*                                                             |
| 0x0010           | `DBG_BPCTRL0` | Hardware Breakpoint0 Control                                           |
| 0x0011           | `DBG_BPDATA0` | Hardware Breakpoint0 Data                                              |
| 0x0012           | `DBG_BPCTRL1` | Hardware Breakpoint1 Control                                           |
| 0x0013           | `DBG_BPDATA1` | Hardware Breakpoint1 Data                                              |
| 0x0014           | `DBG_BPCTRL2` | Hardware Breakpoint2 Control                                           |
| 0x0015           | `DBG_BPDATA2` | Hardware Breakpoint2 Data                                              |
| 0x0016           | `DBG_BPCTRL3` | Hardware Breakpoint3 Control                                           |
| 0x0017           | `DBG_BPDATA3` | Hardware Breakpoint3 Data                                              |
| 0x0018           | `DBG_BPCTRL4` | Hardware Breakpoint4 Control                                           |
| 0x0019           | `DBG_BPDATA4` | Hardware Breakpoint4 Data                                              |
| 0x001A           | `DBG_BPCTRL5` | Hardware Breakpoint5 Control                                           |
| 0x001B           | `DBG_BPDATA5` | Hardware Breakpoint5 Data                                              |
| 0x001C           | `DBG_BPCTRL6` | Hardware Breakpoint6 Control                                           |
| 0x001D           | `DBG_BPDATA6` | Hardware Breakpoint6 Data                                              |
| 0x001E           | `DBG_BPCTRL7` | Hardware Breakpoint7 Control                                           |
| 0x001F           | `DBG_BPDATA7` | Hardware Breakpoint7 Data                                              |
| 0x0020-0x00FF    |               | *Reserved*                                                             |
| 0x0100-0x011F    |      `RF`     | Integer Register File                                                  |
| 0x0120-0x03FF    |               | *Reserved*                                                             |
| 0x0140-0x051F    |     `FRF`     | Floating Point Register File                                           |
| 0x0160-0x071F    |  `FRF` (MSBs) | MSBs of the Floating Point Register, for 64bit `FRF` with 32bit `XLEN` |
| 0x0180-0x07FF    |               | *Reserved*                                                             |
| 0x0800           |     `NPC`     | Next Program Counter                                                   |
| 0x0801           |     `PPC`     | Current Program Counter                                                |
| 0x0802-0x0FFF    |               | *Reserved*                                                             |
| 0x1000-0x1FFF    |      CSR      | CPU Control and Status                                                 |

Internal Register Map
---------------------

The Debug Unit’s internal register map can be accessed when the CPU is stalled or running. These registers control the hardware breakpoints and conditions and report the reason why the Debug Unit stalled the CPU.

### Debug Control Register `DBG_CTRL`

The `XLEN` size `DBG_CTRL` controls the single-step and branch-tracing functions.

When the Single-Step-Trace-Enable bit is ‘1’ the Single-Step-Trace function is enabled. The CPU will assert (‘1’) `dbg_bp` each time a non-NOP instruction is about to be executed.

| **sste** | **Description**            |
|:--------:|:---------------------------|
|     0    | Single-Step-Trace disabled |
|     1    | Single-Step-Trace enabled  |

When the Branch-Trace-Enable bit is ‘1’ the Branch-Step-Trace function is enabled. The CPU will assert `dbg_bp` each time a branch instruction is about to be executed.

| **bte** | **Description**            |
|:-------:|:---------------------------|
|    0    | Branch-Step-Trace disabled |
|    1    | Branch-Step-Trace enabled  |

### Debug Breakpoint Hit Register `DBG_HIT`

The Debug Breakpoint Hit register contains the reason(s) why the Debug Unit requested to stall the CPU.

The Single-Step-Trace-Hit field is asserted (‘1’) when the Single-Step-Trace function requests to stall the CPU. This is a sticky bit. It is set by the Debug Unit, but must be cleared by the Debug Environment.

The Branch-Trace-Hit field is asserted (‘1’) when the Branch-Trace function requests to stall the CPU. This is a sticky bit. It is set by the Debug Unit, but must be cleared by the Debug Environment.

The Breakpoint-Hit fields are asserted (‘1’) when the respective hardware breakpoint triggered and requests to stall the CPU. There is one bit for each implemented hardware breakpoint. These are sticky bits. They are set by the Debug Unit, but must be cleared by the Debug Environment.

### Debug Interrupt Enable Register `DBG_IE`

| **Bit\#** | **Description**                       |
|:---------:|:--------------------------------------|
|   31-18   | External Interrupts                   |
|     17    | Timer Interrupt                       |
|     16    | Software Interrupt                    |
|     11    | Environment call from Machine Mode    |
|     10    | Environment call from Hypervisor Mode |
|     9     | Environment call from Supervisor Mode |
|     8     | Environment call from User Mode       |
|     7     | Store Access Fault                    |
|     6     | Store Address Misaligned              |
|     5     | Load Access Fault                     |
|     4     | Load Address Misaligned               |
|     3     | Breakpoint                            |
|     2     | Illegal Instruction                   |
|     1     | Instruction Access Fault              |
|     0     | Instruction Address Misaligned        |

The `dbg_ie` register determines what exceptions cause the Debug Unit to assert `dbg_bp`. Normally an exception causes the CPU to load the trap-vector and enter the trap routine, but if the applicable bit in the `dbg_ie` bit is set, then the CPU does not load the trap-vector, does not change `mcause` and `mepc`, and does not enter the trap vector routine when that exception is triggered. Instead the CPU sets `DBG_CAUSE` and asserts `dbg_bp`, thereby handing over control to the external debug controller.

The lower 16bits of the register represent the trap causes as defined in the `mcause` register. The upper 16bits represent the interrupt causes as defined in the `mcause` register.

Logic ‘1’ indicates the CPU hands over execution to the debug controller when the corresponding exception is triggered. For example setting bit-2 to ‘1’ causes the `BREAKPOINT` trap to assert `dbg_bp` and hand over control to the debug controller. At least the `BREAKPOINT` exception must be set in the `dbg_ie` register.

### Debug Exception Cause Register `DBG_CAUSE`

The `DBG_CAUSE` register contains the exception number that caused the CPU to hand over control to the external Debug Controller. See the `mcause` register description for a description of all exceptions.

| **DBG\_CAUSE** | **Description**                | **GDB Sigval** |
|:--------------:|:-------------------------------|:--------------:|
|     &gt;15     | Interrupts                     |       INT      |
|                | Timer Interrupt                |      ALRM      |
|       11       | ECALL from Machine Mode        |      TRAP      |
|       10       | ECALL from Hypervisor Mode     |      TRAP      |
|        9       | ECALL from Supervisor Mode     |      TRAP      |
|        8       | ECALL from User Mode           |      TRAP      |
|        7       | Store Access Fault             |      SEGV      |
|        6       | Store Address Misaligned       |       BUS      |
|        5       | Load Access Fault              |      SEGV      |
|        4       | Load Address Misaligned        |       BUS      |
|        3       | Breakpoint                     |      TRAP      |
|        2       | Illegal Instruction            |       ILL      |
|        1       | Instruction Access Fault       |      SEGV      |
|        0       | Instruction Address Misaligned |       BUS      |

Because the RISC-V defines the cause register as an integer value, there is no easy way to detect if there was no cause. It’s recommended that the Debug Environment writes ‘-1’ into the `dbg_cause` register upon starting the debug session and after handling each exception.

The debug controller’s software layer must translate the value in the `DBG_CAUSE` register to the debugger’s control signal. The table below shows the basic mapping of the `DBG_CAUSE` register to GDB Signals.

### Debug Breakpoint Control Registers `DBG_CTRLx`

The `DBG_BPCTRL` registers control the functionality of the hardware breakpoints. There is a Breakpoint Control Register for each implemented hardware breakpoint. The `BREAKPOINTS` parameter defines the amount of hardware breakpoints that are implemented.

The Breakpoint Implemented field informs the Debug Environment if the hardware breakpoint is implemented. The bit is set (‘1’) when the hardware breakpoint is implemented and (‘0’) when it is not. The Debug Environment should read the `DBG_BPCTRL` registers and examine the Breakpoint Implemented fields to determine the amount of hardware breakpoints implemented.

| impl | Description                         |
|:----:|:------------------------------------|
|   0  | Hardware Breakpoint not implemented |
|   1  | Hardware Breakpoint implemented     |

The Breakpoint Enable bit enables or disables the breakpoint. The hardware breakpoint is enabled when the bit is set (‘1’) and disabled when the bit is cleared (‘0’). When the hardware breakpoint is disabled it will not generate a breakpoint hit, even if the breakpoint conditions are met. Clearing the breakpoint enable bit does not clear any pending hits. These must be cleared in the `DBG_HIT` register.

| ena | Description                     |
|:---:|:--------------------------------|
|  0  | Hardware Breakpoint is disabled |
|  1  | Hardware Breakpoint is enabled  |

The Breakpoint Condition Code bits determine what condition triggers the hardware breakpoint.

|   cc   | Description       |
|:------:|:------------------|
| 3’b000 | Instruction Fetch |
| 3’b001 | Data Load         |
| 3’b010 | Data Store        |
| 3’b011 | Data Access       |
| 3’b1-- | Reserved          |

#### Instruction Fetch

The hardware breakpoint will trigger a breakpoint exception when the CPU is about to execute the instruction at the address specified in the `DBG_DATA` register.

#### Data Load

The hardware breakpoint will trigger a breakpoint exception when the CPU reads from the address specified in the `DBG_DATA` register.

#### Data Store

The hardware breakpoint will trigger a breakpoint exception when the CPU writes to the address specified in the `DBG_DATA` register.

#### Data Access

The hardware breakpoint will trigger a breakpoint exception when the CPU accesses (either reads from or writes to) the address specified in the `DBG_DATA` register.

### Debug Breakpoint Data Registers `DBG_DATAx`

The `DBG_DATA` registers contain the data/value that trigger a breakpoint hit. There is a Breakpoint Data Register for each implemented hardware breakpoint. The meaning of the `DBG_DATA` register depends on the condition code set in the associated `DBG_BPCTRL` register. See the `DBG_CTRL` register for the meaning of the `DBG_DATA` register.

Resources
=========

Below are some example implementations for various platforms. All implementations are push button, no effort has been undertaken to reduce area or improve performance.

| Platform | DFF | Logic Cells | Memory | Performance (MHz) |
|:---------|:---:|:-----------:|:------:|:------------------|
| lfxp3c-5 |  51 |      85     |    0   | 235MHz            |
|          |     |             |        |                   |
|          |     |             |        |                   |
|          |     |             |        |                   |

Acknowledgements
================

The RV12 CPU is designed to be compliant with the specifications listed below. This datasheet also includes documentation derived from these specifications as permitted under the Creative Commons Attribution 4.0 International License:

> “The [RISC-V Instruction Set Manual, Volume I: User-Level ISA, Document Version 2.2](https://github.com/riscv/riscv-isa-manual/blob/master/release/riscv-spec-v2.2.pdf)", Editors Andrew Waterman and Krste Asanović,RISC-V Foundation, May 2017.

> “The [RISC-VInstruction Set Manual, Volume II: Privileged Architecture, Version 1.9.1](https://github.com/riscv/riscv-isa-manual/blob/master/release/riscv-privileged-v1.9.1.pdf)",Editors Andrew Waterman and Krste Asanović, RISC-V Foundation, November 2016

Revision History
================

| Date        | Rev. | Comments        |
|:------------|:-----|:----------------|
| 01-Feb-2017 | 1.0  | Initial Release |
|             |      |                 |
|             |      |                 |
|             |      |                 |

[1] Full reference details of the specifications are documented in section 11

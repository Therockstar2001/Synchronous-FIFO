# Reusable UVM Verification Environment for a Parameterized Synchronous FIFO with Coverage-Driven and Assertion-Based Verification

## Overview
This project implements a **parameterized synchronous FIFO** in SystemVerilog along with a **UVM-based verification environment** developed in multiple phases.  

The focus of this project is **functional verification**, emphasizing:
- Directed and constrained-random stimulus
- Functional coverage for observability
- Assertion-based verification for protocol correctness
- Progressive verification maturity across phases

---

## FIFO Design Features

- Parameterized **data width (DATA_W)** and **depth (DEPTH)**
- Status signals:
  - `full`, `empty`
  - `overflow`, `underflow`
  - `count` (occupancy tracking)
- Supports:
  - **Simultaneous read and write operations**
  - **Pointer wrap-around behavior**
- Registered read data:
  - Output valid **one cycle after accepted read**
- Safe operation control:
  - Write accepted only when `!full`
  - Read accepted only when `!empty`

---

## Design Architecture

- Memory: `mem[0:DEPTH-1]`
- Pointers:
  - Write pointer (`wptr`)
  - Read pointer (`rptr`)
- Control signals:
  - `do_write = wr_en && !full`
  - `do_read  = rd_en && !empty`
- Count update:
  - Increment on write-only
  - Decrement on read-only
  - Stable on simultaneous read/write

---

## Verification Environment (UVM)

The verification environment is built using **UVM methodology** with modular and reusable components.

### Components
- Driver
- Monitor
- Scoreboard
- Sequence/Sequencer

### Interface
- fifo_if with clocking blocks:
  - cb_drv
  - cb_mon

---

## Functional Coverage (Phase 3)

- Operation types: Idle, Write, Read, Simultaneous
- Accepted transactions
- Overflow/Underflow attempts
- FIFO occupancy tracking
- Transition coverage
- Cross coverage (operation × occupancy)

---

## Assertion-Based Verification (Phase 4)

### Safety
- No read when empty
- No write when full
- Count consistency checks

### Behavioral
- Count increment/decrement correctness
- Stability during simultaneous/no ops
- Reset correctness
- Overflow/underflow validation

### Cover Properties
- Empty ↔ Non-empty transitions
- Full reachability
- Simultaneous operations

---

## Test Strategy

- Baseline: Initial UVM setup
- Phase 1: Structured environment
- Phase 2: Directed boundary testing
- Phase 3: Functional coverage
- Phase 4: Assertion-based verification

---

## Results

- Zero test failures
- Strong verification confidence using:
  - Directed + random testing
  - Functional coverage
  - Assertions

---

## Tools Used

- SystemVerilog
- UVM
- EDA Playground

---

## Repository Structure

```
├── design.sv
├── fifo_if.sv
├── fifo_assertions.sv
├── fifo_pkg.sv
├── testbench.sv
└── README.md
```

---

## Key Learnings

- UVM architecture design
- Coverage-driven verification
- Assertion-based verification
- FIFO behavior validation

---

## Future Work

- Port to Questa/VCS
- Add advanced constraints
- Extend to asynchronous FIFO

---

## Keywords

SystemVerilog • UVM • Functional Verification • Assertions • Coverage • FIFO

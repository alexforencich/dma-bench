# PCIe DMA Benchmark for the BittWare 520N-MX

## Introduction

This design targets the BittWare 520N-MX FPGA board.

*  FPGA: 1SM21CHU2F53E2VG

## How to build

Run `make` to build.  Ensure that the Intel Quartus Prime Pro components are in PATH.

Run `make` to build the driver.  Ensure the headers for the running kernel are installed, otherwise the driver cannot be compiled.

## How to test

Run `make program` to program the board with Quartus Prime Pro.  Then load the driver with `insmod dma_bench.ko`.  Check dmesg for the output.

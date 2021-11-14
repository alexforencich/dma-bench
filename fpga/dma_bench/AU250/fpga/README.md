# DMA Benchmark for Alveo U250

## Introduction

This design targets the Xilinx Alveo U250 FPGA board.

* FPGA: xcu250-figd2104-2-e

## How to build

Run `make` to build.  Ensure that the Xilinx Vivado toolchain components are in PATH.

Run `make` to build the driver.  Ensure the headers for the running kernel are installed, otherwise the driver cannot be compiled.

## How to test

Run `make program` to program the Alveo U250 board with Vivado.  Then load the driver with `insmod example.ko`.  Check dmesg for the output.

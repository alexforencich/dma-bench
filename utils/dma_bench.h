/*

Copyright (c) 2021 Alex Forencich

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

*/

#ifndef DMA_BENCH_H
#define DMA_BENCH_H

#include <stdint.h>
#include <unistd.h>

#include "dma_bench_hw.h"
#include "dma_bench_ioctl.h"

#define dma_bench_reg_read32(base, reg) (((volatile uint32_t *)(base))[(reg)/4])
#define dma_bench_reg_write32(base, reg, val) (((volatile uint32_t *)(base))[(reg)/4]) = val

struct dma_bench {
    int fd;

    size_t regs_size;
    volatile uint8_t *regs;
};

struct dma_bench *dma_bench_open(const char *dev_name);
void dma_bench_close(struct dma_bench *dev);

#endif /* DMA_BENCH_H */

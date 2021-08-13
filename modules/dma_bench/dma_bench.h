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

#include <linux/kernel.h>

#define DRIVER_NAME "dma_bench"
#define DRIVER_VERSION "0.1"

#include "dma_bench_hw.h"

struct dma_bench_dev {
    struct pci_dev *pdev;

    size_t hw_regs_size;
    phys_addr_t hw_regs_phys;
    void * __iomem hw_addr;

    // DMA buffer
    size_t dma_region_len;
    void *dma_region;
    dma_addr_t dma_region_addr;

    int irqcount;
};

#endif /* DMA_BENCH_H */

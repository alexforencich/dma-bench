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

#include "dma_bench.h"

#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/stat.h>

struct dma_bench *dma_bench_open(const char *dev_name)
{
    struct dma_bench *dev = calloc(1, sizeof(struct dma_bench));
    struct stat st;

    if (!dev)
    {
        perror("memory allocation failed");
        goto fail_alloc;
    }

    dev->fd = open(dev_name, O_RDWR);

    if (dev->fd < 0)
    {
        perror("open device failed");
        goto fail_open;
    }

    if (fstat(dev->fd, &st) == -1)
    {
        perror("fstat failed");
        goto fail_fstat;
    }

    dev->regs_size = st.st_size;

    if (dev->regs_size == 0)
    {
        struct dma_bench_ioctl_info info;
        if (ioctl(dev->fd, DMA_BENCH_IOCTL_INFO, &info) != 0)
        {
            perror("DMA_BENCH_IOCTL_INFO ioctl failed");
            goto fail_ioctl;
        }

        dev->regs_size = info.regs_size;
    }

    dev->regs = (volatile uint8_t *)mmap(NULL, dev->regs_size, PROT_READ | PROT_WRITE, MAP_SHARED, dev->fd, 0);
    if (dev->regs == MAP_FAILED)
    {
        perror("mmap regs failed");
        goto fail_mmap_regs;
    }

    if (dma_bench_reg_read32(dev->regs, 0) == 0xffffffff)
    {
        // if we were given a PCIe resource, then we may need to enable the device
        char path[PATH_MAX+32];
        char *ptr;

        strcpy(path, dev_name);
        ptr = strrchr(path, '/');
        if (ptr)
        {
            strcpy(++ptr, "enable");
        }

        if (access(path, F_OK) != -1)
        {
            FILE *fp = fopen(path, "w");

            if (fp)
            {
                fputc('1', fp);
                fclose(fp);
            }
        }
    }

    if (dma_bench_reg_read32(dev->regs, 0) == 0xffffffff)
    {
        fprintf(stderr, "Error: device needs to be reset\n");
        goto fail_reset;
    }

    return dev;

fail_range:
    fprintf(stderr, "Error: computed pointer out of range\n");
fail_reset:
    munmap((void *)dev->regs, dev->regs_size);
fail_mmap_regs:
fail_ioctl:
fail_fstat:
    close(dev->fd);
fail_open:
    free(dev);
fail_alloc:
    return NULL;
}

void dma_bench_close(struct dma_bench *dev)
{
    if (!dev)
        return;

    munmap((void *)dev->regs, dev->regs_size);
    close(dev->fd);
    free(dev);
}


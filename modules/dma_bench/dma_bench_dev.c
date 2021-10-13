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
#include "dma_bench_ioctl.h"

#include <linux/uaccess.h>

static int dma_bench_open(struct inode *inode, struct file *file)
{
	// struct miscdevice *miscdev = file->private_data;
	// struct dma_bench_dev *dma_bench_dev = container_of(miscdev, struct dma_bench_dev, misc_dev);

	return 0;
}

static int dma_bench_release(struct inode *inode, struct file *file)
{
	// struct miscdevice *miscdev = file->private_data;
	// struct dma_bench_dev *dma_bench_dev = container_of(miscdev, struct dma_bench_dev, misc_dev);

	return 0;
}

static int dma_bench_map_registers(struct dma_bench_dev *dma_bench, struct vm_area_struct *vma)
{
	size_t map_size = vma->vm_end - vma->vm_start;
	int ret;

	if (map_size > dma_bench->hw_regs_size) {
		dev_err(dma_bench->dev, "dma_bench_map_registers: Tried to map registers region with wrong size %lu (expected <=%zu)",
		        vma->vm_end - vma->vm_start, dma_bench->hw_regs_size);
		return -EINVAL;
	}

	ret = remap_pfn_range(vma, vma->vm_start, dma_bench->hw_regs_phys >> PAGE_SHIFT,
	                      map_size, pgprot_noncached(vma->vm_page_prot));

	if (ret)
		dev_err(dma_bench->dev, "dma_bench_map_registers: remap_pfn_range failed for registers region");
	else
		dev_dbg(dma_bench->dev, "dma_bench_map_registers: Mapped registers region at phys: 0x%pap, virt: 0x%p",
		        &dma_bench->hw_regs_phys, (void *)vma->vm_start);

	return ret;
}

static int dma_bench_mmap(struct file *file, struct vm_area_struct *vma)
{
	struct miscdevice *miscdev = file->private_data;
	struct dma_bench_dev *dma_bench = container_of(miscdev, struct dma_bench_dev, misc_dev);

	if (vma->vm_pgoff == 0)
		return dma_bench_map_registers(dma_bench, vma);

	dev_err(dma_bench->dev, "dma_bench_mmap: Tried to map an unknown region at page offset %lu",
	        vma->vm_pgoff);
	return -EINVAL;
}

static long dma_bench_ioctl(struct file *file, unsigned int cmd, unsigned long arg)
{
	struct miscdevice *miscdev = file->private_data;
	struct dma_bench_dev *dma_bench = container_of(miscdev, struct dma_bench_dev, misc_dev);

	if (_IOC_TYPE(cmd) != DMA_BENCH_IOCTL_TYPE)
		return -ENOTTY;

	switch (cmd) {
	case DMA_BENCH_IOCTL_INFO:
		{
			struct dma_bench_ioctl_info ctl;

			ctl.regs_size = dma_bench->hw_regs_size;

			if (copy_to_user((void __user *)arg, &ctl, sizeof(ctl)) != 0)
				return -EFAULT;

			return 0;
		}
	default:
		return -ENOTTY;
	}
}

const struct file_operations dma_bench_fops = {
	.owner = THIS_MODULE,
	.open = dma_bench_open,
	.release = dma_bench_release,
	.mmap = dma_bench_mmap,
	.unlocked_ioctl = dma_bench_ioctl,
};

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
#include <linux/module.h>
#include <linux/pci.h>
#include <linux/version.h>
#include <linux/delay.h>

#if LINUX_VERSION_CODE < KERNEL_VERSION(5,4,0)
#include <linux/pci-aspm.h>
#endif

MODULE_DESCRIPTION("DMA benchmark driver");
MODULE_AUTHOR("Alex Forencich");
MODULE_LICENSE("Dual MIT/GPL");
MODULE_VERSION(DRIVER_VERSION);
MODULE_SUPPORTED_DEVICE(DRIVER_NAME);

static const struct pci_device_id pci_ids[] = {
    { PCI_DEVICE(0x1234, 0x0002) },
    { 0 /* end */ }
};

MODULE_DEVICE_TABLE(pci, pci_ids);

static LIST_HEAD(dma_bench_devices);
static DEFINE_SPINLOCK(dma_bench_devices_lock);

static unsigned int dma_bench_get_free_id(void)
{
    struct dma_bench_dev *dma_bench_dev;
    unsigned int id = 0;
    bool available = false;

    while (!available)
    {
        available = true;
        list_for_each_entry(dma_bench_dev, &dma_bench_devices, dev_list_node)
        {
            if (dma_bench_dev->id == id)
            {
                available = false;
                id++;
                break;
            }
        }
    }

    return id;
}

static irqreturn_t dma_bench_intr(int irq, void *data)
{
    struct dma_bench_dev *dma_bench_dev = data;
    struct device *dev = dma_bench_dev->dev;

    dma_bench_dev->irqcount++;

    dev_info(dev, "Interrupt");

    return IRQ_HANDLED;
}

static void print_counters(struct dma_bench_dev *dma_bench_dev)
{
    struct device *dev = dma_bench_dev->dev;

    int index = 0;

    while (dma_bench_stats_names[index])
    {
        if (strlen(dma_bench_stats_names[index]) > 0)
        {
            dev_info(dev, "%s: %d", dma_bench_stats_names[index], ioread32(dma_bench_dev->hw_addr+0x010000+index*4));
        }
        index++;
    }
}

static void dma_read(struct dma_bench_dev *dma_bench_dev, dma_addr_t dma_addr, int ram_addr, int len)
{
    int tag = 0;
    int new_tag = 0;
    unsigned long t;

    tag = ioread32(dma_bench_dev->hw_addr+0x000118); // dummy read
    tag = (ioread32(dma_bench_dev->hw_addr+0x000118) & 0x7f) + 1;
    iowrite32(dma_addr&0xffffffff, dma_bench_dev->hw_addr+0x000100);
    iowrite32((dma_addr >> 32)&0xffffffff, dma_bench_dev->hw_addr+0x000104);
    iowrite32(ram_addr, dma_bench_dev->hw_addr+0x000108);
    iowrite32(0, dma_bench_dev->hw_addr+0x00010C);
    iowrite32(len, dma_bench_dev->hw_addr+0x000110);
    iowrite32(tag, dma_bench_dev->hw_addr+0x000114);

    // wait for transfer to complete
    t = jiffies + msecs_to_jiffies(200);
    while (time_before(jiffies, t)){
        new_tag = (ioread32(dma_bench_dev->hw_addr+0x000118) & 0xff);
        if (new_tag==tag) break;
    }

    if (tag != new_tag)
        dev_warn(dma_bench_dev->dev, "dma_read: DMA read received tag %d (expected %d)", new_tag, tag);
}

static void dma_write(struct dma_bench_dev *dma_bench_dev, dma_addr_t dma_addr, int ram_addr, int len)
{
    int tag = 0;
    int new_tag = 0;
    unsigned long t;

    tag = ioread32(dma_bench_dev->hw_addr+0x000218); // dummy read
    tag = (ioread32(dma_bench_dev->hw_addr+0x000218) & 0x7f) + 1;
    iowrite32(dma_addr&0xffffffff, dma_bench_dev->hw_addr+0x000200);
    iowrite32((dma_addr >> 32)&0xffffffff, dma_bench_dev->hw_addr+0x000204);
    iowrite32(ram_addr, dma_bench_dev->hw_addr+0x000208);
    iowrite32(0, dma_bench_dev->hw_addr+0x00020C);
    iowrite32(len, dma_bench_dev->hw_addr+0x000210);
    iowrite32(tag, dma_bench_dev->hw_addr+0x000214);

    // wait for transfer to complete
    t = jiffies + msecs_to_jiffies(200);
    while (time_before(jiffies, t)){
        new_tag = (ioread32(dma_bench_dev->hw_addr+0x000218) & 0xff);
        if (new_tag==tag) break;
    }

    if (tag != new_tag)
        dev_warn(dma_bench_dev->dev, "dma_write: DMA write received tag %d (expected %d)", new_tag, tag);
}

static int dma_bench_probe(struct pci_dev *pdev, const struct pci_device_id *ent)
{
    int ret = 0;
    struct dma_bench_dev *dma_bench_dev;
    struct device *dev = &pdev->dev;

    int k;

    dev_info(dev, "DMA bench probe");
    dev_info(dev, " vendor: 0x%04x", pdev->vendor);
    dev_info(dev, " device: 0x%04x", pdev->device);
    dev_info(dev, " class: 0x%06x", pdev->class);
    dev_info(dev, " pci id: %02x:%02x.%02x", pdev->bus->number, PCI_SLOT(pdev->devfn), PCI_FUNC(pdev->devfn));

    if (!(dma_bench_dev = devm_kzalloc(dev, sizeof(struct dma_bench_dev), GFP_KERNEL))) {
        return -ENOMEM;
    }

    dma_bench_dev->dev = dev;
    pci_set_drvdata(pdev, dma_bench_dev);

    // assign ID and add to list
    spin_lock(&dma_bench_devices_lock);
    dma_bench_dev->id = dma_bench_get_free_id();
    list_add_tail(&dma_bench_dev->dev_list_node, &dma_bench_devices);
    spin_unlock(&dma_bench_devices_lock);

    snprintf(dma_bench_dev->name, sizeof(dma_bench_dev->name), DRIVER_NAME "%d", dma_bench_dev->id);

    // Allocate DMA buffer
    dma_bench_dev->dma_region_len = 16*1024;
    dma_bench_dev->dma_region = dma_alloc_coherent(dev, dma_bench_dev->dma_region_len, &dma_bench_dev->dma_region_addr, GFP_KERNEL | __GFP_ZERO);
    if (!dma_bench_dev->dma_region)
    {
        dev_err(dev, "Failed to allocate DMA buffer");
        ret = -ENOMEM;
        goto fail_dma_alloc;
    }

    dev_info(dev, "Allocated DMA region virt %p, phys %p", dma_bench_dev->dma_region, (void *)dma_bench_dev->dma_region_addr);

    // Disable ASPM
    pci_disable_link_state(pdev, PCIE_LINK_STATE_L0S | PCIE_LINK_STATE_L1 | PCIE_LINK_STATE_CLKPM);

    // Enable device
    ret = pci_enable_device_mem(pdev);
    if (ret)
    {
        dev_err(dev, "Failed to enable PCI device");
        //ret = -ENODEV;
        goto fail_enable_device;
    }

    // Reserve regions
    ret = pci_request_regions(pdev, DRIVER_NAME);
    if (ret)
    {
        dev_err(dev, "Failed to reserve regions");
        //ret = -EBUSY;
        goto fail_regions;
    }

    dma_bench_dev->hw_regs_size = pci_resource_len(pdev, 0);
    dma_bench_dev->hw_regs_phys = pci_resource_start(pdev, 0);

    // Map BARs
    dma_bench_dev->hw_addr = pci_ioremap_bar(pdev, 0);
    if (!dma_bench_dev->hw_addr)
    {
        dev_err(dev, "Failed to map BARs");
        goto fail_map_bars;
    }

    // Allocate MSI IRQs
    ret = pci_alloc_irq_vectors(pdev, 1, 32, PCI_IRQ_MSI);
    if (ret < 0)
    {
        dev_err(dev, "Failed to allocate IRQs");
        goto fail_map_bars;
    }

    // Set up interrupt
    ret = pci_request_irq(pdev, 0, dma_bench_intr, 0, dma_bench_dev, "dma_bench_dev");
    if (ret < 0)
    {
        dev_err(dev, "Failed to request IRQ");
        goto fail_irq;
    }

    // Enable bus mastering for DMA
    pci_set_master(pdev);

    // Register misc device
    dma_bench_dev->misc_dev.minor = MISC_DYNAMIC_MINOR;
    dma_bench_dev->misc_dev.name = dma_bench_dev->name;
    dma_bench_dev->misc_dev.fops = &dma_bench_fops;
    dma_bench_dev->misc_dev.parent = dev;

    ret = misc_register(&dma_bench_dev->misc_dev);
    if (ret)
    {
        dev_err(dev, "misc_register failed: %d\n", ret);
        goto fail_miscdev;
    }

    dev_info(dev, "Registered device %s", dma_bench_dev->name);

    // Dump counters
    dev_info(dev, "Statistics counters");
    print_counters(dma_bench_dev);

    // PCIe DMA test
    dev_info(dev, "write test data");
    for (k = 0; k < 256; k++)
    {
        ((char *)dma_bench_dev->dma_region)[k] = k;
    }

    dev_info(dev, "read test data");
    print_hex_dump(KERN_INFO, "", DUMP_PREFIX_NONE, 16, 1, dma_bench_dev->dma_region, 256, true);

    dev_info(dev, "check DMA enable");
    dev_info(dev, "%08x", ioread32(dma_bench_dev->hw_addr+0x000000));

    dev_info(dev, "enable DMA");
    iowrite32(0x1, dma_bench_dev->hw_addr+0x000000);

    dev_info(dev, "check DMA enable");
    dev_info(dev, "%08x", ioread32(dma_bench_dev->hw_addr+0x000000));

    dev_info(dev, "start copy to card");
    dma_read(dma_bench_dev, dma_bench_dev->dma_region_addr+0x0000, 0x100, 0x100);

    dev_info(dev, "start copy to host");
    dma_write(dma_bench_dev, dma_bench_dev->dma_region_addr+0x0200, 0x100, 0x100);

    dev_info(dev, "read test data");
    print_hex_dump(KERN_INFO, "", DUMP_PREFIX_NONE, 16, 1, dma_bench_dev->dma_region+0x0200, 256, true);

    if (memcmp(dma_bench_dev->dma_region+0x0000, dma_bench_dev->dma_region+0x0200, 256) == 0)
    {
        dev_info(dev, "test data matches");
    }
    else
    {
        dev_warn(dev, "test data mismatch");
    }

    // Dump counters
    dev_info(dev, "Statistics counters");
    print_counters(dma_bench_dev);

    // probe complete
    return 0;

    // error handling
fail_miscdev:
    pci_clear_master(pdev);
fail_irq:
    pci_free_irq_vectors(pdev);
fail_map_bars:
    pci_iounmap(pdev, dma_bench_dev->hw_addr);
    pci_release_regions(pdev);
fail_regions:
    pci_disable_device(pdev);
fail_enable_device:
    dma_free_coherent(dev, dma_bench_dev->dma_region_len, dma_bench_dev->dma_region, dma_bench_dev->dma_region_addr);
fail_dma_alloc:
    spin_lock(&dma_bench_devices_lock);
    list_del(&dma_bench_dev->dev_list_node);
    spin_unlock(&dma_bench_devices_lock);
    return ret;
}

static void dma_bench_remove(struct pci_dev *pdev)
{
    struct dma_bench_dev *dma_bench_dev;
    struct device *dev = &pdev->dev;

    dev_info(dev, "dma_bench_dev remove");

    if (!(dma_bench_dev = pci_get_drvdata(pdev))) {
        return;
    }

    misc_deregister(&dma_bench_dev->misc_dev);

    pci_clear_master(pdev);
    pci_free_irq(pdev, 0, dma_bench_dev);
    pci_free_irq_vectors(pdev);
    pci_iounmap(pdev, dma_bench_dev->hw_addr);
    pci_release_regions(pdev);
    pci_disable_device(pdev);
    dma_free_coherent(dev, dma_bench_dev->dma_region_len, dma_bench_dev->dma_region, dma_bench_dev->dma_region_addr);
    spin_lock(&dma_bench_devices_lock);
    list_del(&dma_bench_dev->dev_list_node);
    spin_unlock(&dma_bench_devices_lock);
}

static void dma_bench_shutdown(struct pci_dev *pdev)
{
    dev_info(&pdev->dev, "dma_bench_dev shutdown");

    dma_bench_remove(pdev);
}

static struct pci_driver pci_driver = {
    .name = DRIVER_NAME,
    .id_table = pci_ids,
    .probe = dma_bench_probe,
    .remove = dma_bench_remove,
    .shutdown = dma_bench_shutdown
};

static int __init dma_bench_init(void)
{
    return pci_register_driver(&pci_driver);
}

static void __exit dma_bench_exit(void)
{
    pci_unregister_driver(&pci_driver);
}

module_init(dma_bench_init);
module_exit(dma_bench_exit);

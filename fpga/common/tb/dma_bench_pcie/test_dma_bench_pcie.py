"""

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

"""

import logging
import os
import sys

import cocotb_test.simulator
import pytest

import cocotb
from cocotb.log import SimLog
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from cocotbext.pcie.core import RootComplex
from cocotbext.axi.utils import hexdump_str

try:
    from pcie_if import PcieIfDevice, PcieIfRxBus, PcieIfTxBus
except ImportError:
    # attempt import from current directory
    sys.path.insert(0, os.path.join(os.path.dirname(__file__)))
    try:
        from pcie_if import PcieIfDevice, PcieIfRxBus, PcieIfTxBus
    finally:
        del sys.path[0]


class TB(object):
    def __init__(self, dut):
        self.dut = dut

        self.log = SimLog("cocotb.tb")
        self.log.setLevel(logging.DEBUG)

        cocotb.fork(Clock(dut.clk, 4, units="ns").start())

        # PCIe
        self.rc = RootComplex()

        self.dev = PcieIfDevice(
            clk=dut.clk,
            rst=dut.rst,

            rx_req_tlp_bus=PcieIfRxBus.from_prefix(dut, "rx_req_tlp"),

            tx_cpl_tlp_bus=PcieIfTxBus.from_prefix(dut, "tx_cpl_tlp"),

            tx_wr_req_tlp_bus=PcieIfTxBus.from_prefix(dut, "tx_wr_req_tlp"),
            wr_req_tx_seq_num=dut.s_axis_wr_req_tx_seq_num,
            wr_req_tx_seq_num_valid=dut.s_axis_wr_req_tx_seq_num_valid,

            tx_rd_req_tlp_bus=PcieIfTxBus.from_prefix(dut, "tx_rd_req_tlp"),
            rd_req_tx_seq_num=dut.s_axis_rd_req_tx_seq_num,
            rd_req_tx_seq_num_valid=dut.s_axis_rd_req_tx_seq_num_valid,

            cfg_max_payload=dut.max_payload_size,
            rx_cpl_tlp_bus=PcieIfRxBus.from_prefix(dut, "rx_cpl_tlp"),

            cfg_max_read_req=dut.max_read_request_size,
            cfg_ext_tag_enable=dut.ext_tag_enable,

            tx_fc_ph_av=dut.pcie_tx_fc_ph_av,
            tx_fc_pd_av=dut.pcie_tx_fc_pd_av,
            tx_fc_nph_av=dut.pcie_tx_fc_nph_av,
        )

        self.dev.log.setLevel(logging.DEBUG)

        self.rc.make_port().connect(self.dev)

        self.dev.functions[0].msi_multiple_message_capable = 5

        self.dev.functions[0].configure_bar(0, 2**24)

        dut.bus_num.setimmediatevalue(0)

        # monitor error outputs
        self.status_error_cor_asserted = False
        self.status_error_uncor_asserted = False
        cocotb.fork(self._run_monitor_status_error_cor())
        cocotb.fork(self._run_monitor_status_error_uncor())

    async def _run_monitor_status_error_cor(self):
        while True:
            await RisingEdge(self.dut.status_error_cor)
            self.log.info("status_error_cor (correctable error) was asserted")
            self.status_error_cor_asserted = True

    async def _run_monitor_status_error_uncor(self):
        while True:
            await RisingEdge(self.dut.status_error_uncor)
            self.log.info("status_error_uncor (uncorrectable error) was asserted")
            self.status_error_uncor_asserted = True

    async def cycle_reset(self):
        self.dut.rst.setimmediatevalue(0)
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)
        self.dut.rst <= 1
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)
        self.dut.rst <= 0
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)


@cocotb.test()
async def run_test(dut):

    tb = TB(dut)

    await tb.cycle_reset()

    await tb.rc.enumerate(enable_bus_mastering=True, configure_msi=True)

    mem_base, mem_data = tb.rc.alloc_region(16*1024*1024)

    dev_pf0_bar0 = tb.rc.tree[0][0].bar_addr[0]

    tb.dut.bus_num <= tb.dev.bus_num

    tb.log.info("Test DMA")

    # write packet data
    mem_data[0:1024] = bytearray([x % 256 for x in range(1024)])

    # enable DMA
    await tb.rc.mem_write_dword(dev_pf0_bar0+0x000000, 1)
    # enable interrupts
    await tb.rc.mem_write_dword(dev_pf0_bar0+0x000008, 0x3)

    # write pcie read descriptor
    await tb.rc.mem_write_dword(dev_pf0_bar0+0x000100, (mem_base+0x0000) & 0xffffffff)
    await tb.rc.mem_write_dword(dev_pf0_bar0+0x000104, (mem_base+0x0000 >> 32) & 0xffffffff)
    await tb.rc.mem_write_dword(dev_pf0_bar0+0x000108, 0x100)
    await tb.rc.mem_write_dword(dev_pf0_bar0+0x000110, 0x400)
    await tb.rc.mem_write_dword(dev_pf0_bar0+0x000114, 0xAA)

    await Timer(2000, 'ns')

    # read status
    val = await tb.rc.mem_read_dword(dev_pf0_bar0+0x000118)
    tb.log.info("Status: 0x%x", val)
    assert val == 0x800000AA

    # write pcie write descriptor
    await tb.rc.mem_write_dword(dev_pf0_bar0+0x000200, (mem_base+0x1000) & 0xffffffff)
    await tb.rc.mem_write_dword(dev_pf0_bar0+0x000204, (mem_base+0x1000 >> 32) & 0xffffffff)
    await tb.rc.mem_write_dword(dev_pf0_bar0+0x000208, 0x100)
    await tb.rc.mem_write_dword(dev_pf0_bar0+0x000210, 0x400)
    await tb.rc.mem_write_dword(dev_pf0_bar0+0x000214, 0x55)

    await Timer(2000, 'ns')

    # read status
    val = await tb.rc.mem_read_dword(dev_pf0_bar0+0x000218)
    tb.log.info("Status: 0x%x", val)
    assert val == 0x80000055

    tb.log.info("%s", hexdump_str(mem_data, 0x1000, 64))

    assert mem_data[0:1024] == mem_data[0x1000:0x1000+1024]

    tb.log.info("Test DMA block operations")

    # write packet data
    mem_data[0:1024] = bytearray([x % 256 for x in range(1024)])

    # enable DMA
    await tb.rc.mem_write_dword(dev_pf0_bar0+0x000000, 1)
    # disable interrupts
    await tb.rc.mem_write_dword(dev_pf0_bar0+0x000008, 0)

    # configure operation (read)
    # DMA base address
    await tb.rc.mem_write_dword(dev_pf0_bar0+0x001080, (mem_base+0x0000) & 0xffffffff)
    await tb.rc.mem_write_dword(dev_pf0_bar0+0x001084, (mem_base+0x0000 >> 32) & 0xffffffff)
    # DMA offset address
    await tb.rc.mem_write_dword(dev_pf0_bar0+0x001088, 0)
    await tb.rc.mem_write_dword(dev_pf0_bar0+0x00108c, 0)
    # DMA offset mask
    await tb.rc.mem_write_dword(dev_pf0_bar0+0x001090, 0x000003ff)
    await tb.rc.mem_write_dword(dev_pf0_bar0+0x001094, 0)
    # DMA stride
    await tb.rc.mem_write_dword(dev_pf0_bar0+0x001098, 256)
    await tb.rc.mem_write_dword(dev_pf0_bar0+0x00109c, 0)
    # RAM base address
    await tb.rc.mem_write_dword(dev_pf0_bar0+0x0010c0, 0)
    await tb.rc.mem_write_dword(dev_pf0_bar0+0x0010c4, 0)
    # RAM offset address
    await tb.rc.mem_write_dword(dev_pf0_bar0+0x0010c8, 0)
    await tb.rc.mem_write_dword(dev_pf0_bar0+0x0010cc, 0)
    # RAM offset mask
    await tb.rc.mem_write_dword(dev_pf0_bar0+0x0010d0, 0x000003ff)
    await tb.rc.mem_write_dword(dev_pf0_bar0+0x0010d4, 0)
    # RAM stride
    await tb.rc.mem_write_dword(dev_pf0_bar0+0x0010d8, 256)
    await tb.rc.mem_write_dword(dev_pf0_bar0+0x0010dc, 0)
    # clear cycle count
    await tb.rc.mem_write_dword(dev_pf0_bar0+0x001008, 0)
    await tb.rc.mem_write_dword(dev_pf0_bar0+0x00100c, 0)
    # block length
    await tb.rc.mem_write_dword(dev_pf0_bar0+0x001010, 256)
    # block count
    await tb.rc.mem_write_dword(dev_pf0_bar0+0x001018, 32)
    await tb.rc.mem_write_dword(dev_pf0_bar0+0x00101c, 0)
    # start
    await tb.rc.mem_write_dword(dev_pf0_bar0+0x001000, 1)

    await Timer(2000, 'ns')

    # configure operation (write)
    # DMA base address
    await tb.rc.mem_write_dword(dev_pf0_bar0+0x001180, (mem_base+0x0000) & 0xffffffff)
    await tb.rc.mem_write_dword(dev_pf0_bar0+0x001184, (mem_base+0x0000 >> 32) & 0xffffffff)
    # DMA offset address
    await tb.rc.mem_write_dword(dev_pf0_bar0+0x001188, 0)
    await tb.rc.mem_write_dword(dev_pf0_bar0+0x00118c, 0)
    # DMA offset mask
    await tb.rc.mem_write_dword(dev_pf0_bar0+0x001190, 0x000003ff)
    await tb.rc.mem_write_dword(dev_pf0_bar0+0x001194, 0)
    # DMA stride
    await tb.rc.mem_write_dword(dev_pf0_bar0+0x001198, 256)
    await tb.rc.mem_write_dword(dev_pf0_bar0+0x00119c, 0)
    # RAM base address
    await tb.rc.mem_write_dword(dev_pf0_bar0+0x0011c0, 0)
    await tb.rc.mem_write_dword(dev_pf0_bar0+0x0011c4, 0)
    # RAM offset address
    await tb.rc.mem_write_dword(dev_pf0_bar0+0x0011c8, 0)
    await tb.rc.mem_write_dword(dev_pf0_bar0+0x0011cc, 0)
    # RAM offset mask
    await tb.rc.mem_write_dword(dev_pf0_bar0+0x0011d0, 0x000003ff)
    await tb.rc.mem_write_dword(dev_pf0_bar0+0x0011d4, 0)
    # RAM stride
    await tb.rc.mem_write_dword(dev_pf0_bar0+0x0011d8, 256)
    await tb.rc.mem_write_dword(dev_pf0_bar0+0x0011dc, 0)
    # clear cycle count
    await tb.rc.mem_write_dword(dev_pf0_bar0+0x001108, 0)
    await tb.rc.mem_write_dword(dev_pf0_bar0+0x00110c, 0)
    # block length
    await tb.rc.mem_write_dword(dev_pf0_bar0+0x001110, 256)
    # block count
    await tb.rc.mem_write_dword(dev_pf0_bar0+0x001118, 32)
    await tb.rc.mem_write_dword(dev_pf0_bar0+0x00111c, 0)
    # start
    await tb.rc.mem_write_dword(dev_pf0_bar0+0x001100, 1)

    tb.log.info("Read statistics counters")

    await Timer(2000, 'ns')

    lst = []

    for k in range(64):
        lst.append(await tb.rc.mem_read_dword(dev_pf0_bar0+0x010000+k*8))

    print(lst)

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)


# cocotb-test

tests_dir = os.path.dirname(__file__)
rtl_dir = os.path.abspath(os.path.join(tests_dir, '..', '..', 'rtl'))
lib_dir = os.path.abspath(os.path.join(rtl_dir, '..', 'lib'))
axi_rtl_dir = os.path.abspath(os.path.join(lib_dir, 'axi', 'rtl'))
axis_rtl_dir = os.path.abspath(os.path.join(lib_dir, 'axis', 'rtl'))
pcie_rtl_dir = os.path.abspath(os.path.join(lib_dir, 'pcie', 'rtl'))


@pytest.mark.parametrize("pcie_data_width", [64, 128, 256, 512])
def test_dma_bench_pcie(request, pcie_data_width):
    dut = "dma_bench_pcie"
    module = os.path.splitext(os.path.basename(__file__))[0]
    toplevel = dut

    verilog_sources = [
        os.path.join(rtl_dir, f"{dut}.v"),
        os.path.join(rtl_dir, "dma_bench.v"),
        os.path.join(rtl_dir, "stats_counter.v"),
        os.path.join(rtl_dir, "stats_collect.v"),
        os.path.join(rtl_dir, "stats_pcie_if.v"),
        os.path.join(rtl_dir, "stats_pcie_tlp.v"),
        os.path.join(rtl_dir, "stats_dma_if_pcie.v"),
        os.path.join(rtl_dir, "stats_dma_latency.v"),
        os.path.join(axi_rtl_dir, "axil_interconnect.v"),
        os.path.join(axis_rtl_dir, "axis_arb_mux.v"),
        os.path.join(pcie_rtl_dir, "pcie_axil_master.v"),
        os.path.join(pcie_rtl_dir, "dma_if_pcie.v"),
        os.path.join(pcie_rtl_dir, "dma_if_pcie_rd.v"),
        os.path.join(pcie_rtl_dir, "dma_if_pcie_wr.v"),
        os.path.join(pcie_rtl_dir, "dma_psdpram.v"),
        os.path.join(pcie_rtl_dir, "arbiter.v"),
        os.path.join(pcie_rtl_dir, "priority_encoder.v"),
        os.path.join(pcie_rtl_dir, "pulse_merge.v"),
    ]

    parameters = {}

    # segmented interface parameters
    tlp_seg_count = 1
    tlp_seg_data_width = pcie_data_width // tlp_seg_count
    tlp_seg_strb_width = tlp_seg_data_width // 32

    parameters['TLP_SEG_COUNT'] = tlp_seg_count
    parameters['TLP_SEG_DATA_WIDTH'] = tlp_seg_data_width
    parameters['TLP_SEG_STRB_WIDTH'] = tlp_seg_strb_width
    parameters['TLP_SEG_HDR_WIDTH'] = 128
    parameters['TX_SEQ_NUM_COUNT'] = 1
    parameters['TX_SEQ_NUM_WIDTH'] = 6
    parameters['TX_SEQ_NUM_ENABLE'] = 1
    parameters['PCIE_TAG_COUNT'] = 256
    parameters['PCIE_DMA_READ_OP_TABLE_SIZE'] = parameters['PCIE_TAG_COUNT']
    parameters['PCIE_DMA_READ_TX_LIMIT'] = 2**parameters['TX_SEQ_NUM_WIDTH']
    parameters['PCIE_DMA_READ_TX_FC_ENABLE'] = 1
    parameters['PCIE_DMA_WRITE_OP_TABLE_SIZE'] = 2**parameters['TX_SEQ_NUM_WIDTH']
    parameters['PCIE_DMA_WRITE_TX_LIMIT'] = 2**parameters['TX_SEQ_NUM_WIDTH']
    parameters['PCIE_DMA_WRITE_TX_FC_ENABLE'] = 1
    parameters['TLP_FORCE_64_BIT_ADDR'] = 0
    parameters['CHECK_BUS_NUMBER'] = 1
    parameters['BAR0_APERTURE'] = 24

    extra_env = {f'PARAM_{k}': str(v) for k, v in parameters.items()}

    sim_build = os.path.join(tests_dir, "sim_build",
        request.node.name.replace('[', '-').replace(']', ''))

    cocotb_test.simulator.run(
        python_search=[tests_dir],
        verilog_sources=verilog_sources,
        toplevel=toplevel,
        module=module,
        parameters=parameters,
        sim_build=sim_build,
        extra_env=extra_env,
    )

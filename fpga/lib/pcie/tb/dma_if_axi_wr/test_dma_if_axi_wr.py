#!/usr/bin/env python
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

import itertools
import logging
import os
import sys

import cocotb_test.simulator
import pytest

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge
from cocotb.regression import TestFactory

from cocotbext.axi import AxiWriteBus, AxiRamWrite
from cocotbext.axi.stream import define_stream

try:
    from dma_psdp_ram import PsdpRamRead, PsdpRamReadBus
except ImportError:
    # attempt import from current directory
    sys.path.insert(0, os.path.join(os.path.dirname(__file__)))
    try:
        from dma_psdp_ram import PsdpRamRead, PsdpRamReadBus
    finally:
        del sys.path[0]

DescBus, DescTransaction, DescSource, DescSink, DescMonitor = define_stream("Desc",
    signals=["axi_addr", "ram_addr", "ram_sel", "len", "tag", "valid", "ready"],
    optional_signals=["imm", "imm_en"]
)

DescStatusBus, DescStatusTransaction, DescStatusSource, DescStatusSink, DescStatusMonitor = define_stream("DescStatus",
    signals=["tag", "error", "valid"]
)


class TB(object):
    def __init__(self, dut):
        self.dut = dut

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)

        cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

        # AXI RAM
        self.axi_ram = AxiRamWrite(AxiWriteBus.from_prefix(dut, "m_axi"), dut.clk, dut.rst, size=2**16)

        # DMA RAM
        self.dma_ram = PsdpRamRead(PsdpRamReadBus.from_prefix(dut, "ram"), dut.clk, dut.rst, size=2**16)

        # Control
        self.write_desc_source = DescSource(DescBus.from_prefix(dut, "s_axis_write_desc"), dut.clk, dut.rst)
        self.write_desc_status_sink = DescStatusSink(DescStatusBus.from_prefix(dut, "m_axis_write_desc_status"), dut.clk, dut.rst)

        dut.enable.setimmediatevalue(0)

    def set_idle_generator(self, generator=None):
        if generator:
            self.axi_ram.b_channel.set_pause_generator(generator())

    def set_backpressure_generator(self, generator=None):
        if generator:
            self.axi_ram.aw_channel.set_pause_generator(generator())
            self.axi_ram.w_channel.set_pause_generator(generator())
            self.dma_ram.set_pause_generator(generator())

    async def cycle_reset(self):
        self.dut.rst.setimmediatevalue(0)
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)
        self.dut.rst.value = 1
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)
        self.dut.rst.value = 0
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)


async def run_test_write(dut, idle_inserter=None, backpressure_inserter=None):

    tb = TB(dut)

    axi_byte_lanes = tb.axi_ram.byte_lanes
    ram_byte_lanes = tb.dma_ram.byte_lanes
    tag_count = 2**len(tb.write_desc_source.bus.tag)

    cur_tag = 1

    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)

    await tb.cycle_reset()

    tb.dut.enable.value = 1

    for length in list(range(0, ram_byte_lanes+3))+list(range(128-4, 128+4))+[1024]:
        for axi_offset in list(range(axi_byte_lanes+1))+list(range(4096-axi_byte_lanes, 4096)):
            for ram_offset in range(ram_byte_lanes+1):
                tb.log.info("length %d, axi_offset %d, ram_offset %d", length, axi_offset, ram_offset)
                axi_addr = axi_offset+0x1000
                ram_addr = ram_offset+0x1000
                test_data = bytearray([x % 256 for x in range(length)])

                tb.dma_ram.write(ram_addr & 0xffff80, b'\x55'*(len(test_data)+256))
                tb.axi_ram.write(axi_addr-128, b'\xaa'*(len(test_data)+256))
                tb.dma_ram.write(ram_addr, test_data)

                tb.log.debug("%s", tb.dma_ram.hexdump_str((ram_addr & ~0xf)-16, (((ram_addr & 0xf)+length-1) & ~0xf)+48, prefix="RAM "))

                desc = DescTransaction(axi_addr=axi_addr, ram_addr=ram_addr, ram_sel=0, len=len(test_data), tag=cur_tag)
                await tb.write_desc_source.send(desc)

                status = await tb.write_desc_status_sink.recv()

                tb.log.info("status: %s", status)

                assert int(status.tag) == cur_tag
                assert int(status.error) == 0

                tb.log.debug("%s", tb.axi_ram.hexdump_str((axi_addr & ~0xf)-16, (((axi_addr & 0xf)+length-1) & ~0xf)+48, prefix="AXI "))

                assert tb.axi_ram.read(axi_addr-1, len(test_data)+2) == b'\xaa'+test_data+b'\xaa'

                cur_tag = (cur_tag + 1) % tag_count

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)


async def run_test_write_imm(dut, idle_inserter=None, backpressure_inserter=None):

    tb = TB(dut)

    axi_byte_lanes = tb.axi_ram.byte_lanes
    tag_count = 2**len(tb.write_desc_source.bus.tag)

    cur_tag = 1

    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)

    await tb.cycle_reset()

    tb.dut.enable.value = 1

    for length in list(range(1, len(dut.s_axis_write_desc_imm) // 8)):
        for axi_offset in list(range(axi_byte_lanes+1))+list(range(4096-axi_byte_lanes, 4096)):
            tb.log.info("length %d, axi_offset %d", length, axi_offset)
            axi_addr = axi_offset+0x1000
            test_data = bytearray([x % 256 for x in range(length)])
            imm = int.from_bytes(test_data, 'little')

            tb.axi_ram.write(axi_addr-128, b'\xaa'*(len(test_data)+256))

            tb.log.debug("Immediate: 0x%x", imm)

            desc = DescTransaction(axi_addr=axi_addr, ram_addr=0, ram_sel=0, imm=imm, imm_en=1, len=len(test_data), tag=cur_tag)
            await tb.write_desc_source.send(desc)

            status = await tb.write_desc_status_sink.recv()

            tb.log.info("status: %s", status)

            assert int(status.tag) == cur_tag
            assert int(status.error) == 0

            tb.log.debug("%s", tb.axi_ram.hexdump_str((axi_addr & ~0xf)-16, (((axi_addr & 0xf)+length-1) & ~0xf)+48, prefix="AXI "))

            assert tb.axi_ram.read(axi_addr-1, len(test_data)+2) == b'\xaa'+test_data+b'\xaa'

            cur_tag = (cur_tag + 1) % tag_count

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)


def cycle_pause():
    return itertools.cycle([1, 1, 1, 0])


if cocotb.SIM_NAME:

    for test in [run_test_write, run_test_write_imm]:

        factory = TestFactory(test)
        factory.add_option("idle_inserter", [None, cycle_pause])
        factory.add_option("backpressure_inserter", [None, cycle_pause])
        factory.generate_tests()


# cocotb-test

tests_dir = os.path.dirname(__file__)
rtl_dir = os.path.abspath(os.path.join(tests_dir, '..', '..', 'rtl'))


@pytest.mark.parametrize("axi_data_width", [64, 128])
def test_dma_if_axi_wr(request, axi_data_width):
    dut = "dma_if_axi_wr"
    module = os.path.splitext(os.path.basename(__file__))[0]
    toplevel = dut

    verilog_sources = [
        os.path.join(rtl_dir, f"{dut}.v"),
    ]

    parameters = {}

    parameters['AXI_DATA_WIDTH'] = axi_data_width
    parameters['AXI_ADDR_WIDTH'] = 16
    parameters['AXI_STRB_WIDTH'] = parameters['AXI_DATA_WIDTH'] // 8
    parameters['AXI_ID_WIDTH'] = 8
    parameters['RAM_SEL_WIDTH'] = 2
    parameters['RAM_ADDR_WIDTH'] = 16
    parameters['RAM_SEG_COUNT'] = 2
    parameters['RAM_SEG_DATA_WIDTH'] = parameters['AXI_DATA_WIDTH']*2 // parameters['RAM_SEG_COUNT']
    parameters['RAM_SEG_BE_WIDTH'] = parameters['RAM_SEG_DATA_WIDTH'] // 8
    parameters['RAM_SEG_ADDR_WIDTH'] = parameters['RAM_ADDR_WIDTH'] - (parameters['RAM_SEG_COUNT']*parameters['RAM_SEG_BE_WIDTH']-1).bit_length()
    parameters['IMM_ENABLE'] = 1
    parameters['IMM_WIDTH'] = parameters['AXI_DATA_WIDTH']
    parameters['LEN_WIDTH'] = 16
    parameters['TAG_WIDTH'] = 8
    parameters['OP_TABLE_SIZE'] = 2**parameters['AXI_ID_WIDTH']
    parameters['USE_AXI_ID'] = 1

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

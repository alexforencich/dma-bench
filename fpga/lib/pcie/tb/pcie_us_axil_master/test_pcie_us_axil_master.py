#!/usr/bin/env python
"""

Copyright (c) 2020 Alex Forencich

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
import re
from contextlib import contextmanager

import cocotb_test.simulator
import pytest

import cocotb
from cocotb.triggers import RisingEdge, FallingEdge, Timer
from cocotb.regression import TestFactory

from cocotbext.axi import AxiStreamBus
from cocotbext.pcie.core import RootComplex
from cocotbext.pcie.xilinx.us import UltraScalePlusPcieDevice
from cocotbext.axi import AxiLiteBus, AxiLiteRam


@contextmanager
def assert_raises(exc_type, pattern=None):
    try:
        yield
    except exc_type as e:
        if pattern:
            assert re.match(pattern, str(e)), \
                "Correct exception type caught, but message did not match pattern"
        pass
    else:
        raise AssertionError("{} was not raised".format(exc_type.__name__))


class TB(object):
    def __init__(self, dut):
        self.dut = dut

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)

        # PCIe
        self.rc = RootComplex()

        self.dev = UltraScalePlusPcieDevice(
            # configuration options
            pcie_generation=3,
            # pcie_link_width=2,
            # user_clk_frequency=250e6,
            alignment="dword",
            cq_cc_straddle=False,
            rq_rc_straddle=False,
            rc_4tlp_straddle=False,
            enable_pf1=False,
            enable_client_tag=True,
            enable_extended_tag=False,
            enable_parity=False,
            enable_rx_msg_interface=False,
            enable_sriov=False,
            enable_extended_configuration=False,

            enable_pf0_msi=True,
            enable_pf1_msi=False,

            # signals
            user_clk=dut.clk,
            user_reset=dut.rst,

            cq_bus=AxiStreamBus.from_prefix(dut, "s_axis_cq"),

            cc_bus=AxiStreamBus.from_prefix(dut, "m_axis_cc")
        )

        self.dev.log.setLevel(logging.DEBUG)

        self.dev.functions[0].configure_bar(0, 16*1024*1024)
        self.dev.functions[0].configure_bar(1, 16*1024, io=True)

        self.rc.make_port().connect(self.dev)

        # AXI
        self.axil_ram = AxiLiteRam(AxiLiteBus.from_prefix(dut, "m_axil"), dut.clk, dut.rst, size=2**16)

        dut.completer_id.setimmediatevalue(0)
        dut.completer_id_enable.setimmediatevalue(0)

        # monitor error outputs
        self.status_error_cor_asserted = False
        self.status_error_uncor_asserted = False
        cocotb.start_soon(self._run_monitor_status_error_cor())
        cocotb.start_soon(self._run_monitor_status_error_uncor())

    def set_idle_generator(self, generator=None):
        if generator:
            self.dev.cq_source.set_pause_generator(generator())
            self.axil_ram.write_if.b_channel.set_pause_generator(generator())
            self.axil_ram.read_if.r_channel.set_pause_generator(generator())

    def set_backpressure_generator(self, generator=None):
        if generator:
            self.dev.cc_sink.set_pause_generator(generator())
            self.axil_ram.write_if.aw_channel.set_pause_generator(generator())
            self.axil_ram.write_if.w_channel.set_pause_generator(generator())
            self.axil_ram.read_if.ar_channel.set_pause_generator(generator())

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


async def run_test_write(dut, idle_inserter=None, backpressure_inserter=None):

    tb = TB(dut)

    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)

    await FallingEdge(dut.rst)
    await Timer(100, 'ns')

    await tb.rc.enumerate()

    dev_bar0 = tb.rc.tree[0][0].bar_window[0]
    dev_bar1 = tb.rc.tree[0][0].bar_window[1]

    for length in range(0, 5):
        for pcie_offset in range(4-length+1):
            tb.log.info("length %d, pcie_offset %d", length, pcie_offset)
            pcie_addr = pcie_offset+0x1000
            test_data = bytearray([x % 256 for x in range(length)])

            tb.axil_ram.write(pcie_addr-128, b'\x55'*(len(test_data)+256))

            await dev_bar0.write(pcie_addr, test_data)

            await Timer(100, 'ns')

            tb.log.debug("%s", tb.axil_ram.hexdump_str((pcie_addr & ~0xf)-16, (((pcie_addr & 0xf)+length-1) & ~0xf)+48))

            assert tb.axil_ram.read(pcie_addr-1, len(test_data)+2) == b'\x55'+test_data+b'\x55'

            assert not tb.status_error_cor_asserted
            assert not tb.status_error_uncor_asserted

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)


async def run_test_read(dut, idle_inserter=None, backpressure_inserter=None):

    tb = TB(dut)

    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)

    await FallingEdge(dut.rst)
    await Timer(100, 'ns')

    await tb.rc.enumerate()

    dev_bar0 = tb.rc.tree[0][0].bar_window[0]
    dev_bar1 = tb.rc.tree[0][0].bar_window[1]

    for length in range(0, 5):
        for pcie_offset in range(4-length+1):
            tb.log.info("length %d, pcie_offset %d", length, pcie_offset)
            pcie_addr = pcie_offset+0x1000
            test_data = bytearray([x % 256 for x in range(length)])

            tb.axil_ram.write(pcie_addr-128, b'\x55'*(len(test_data)+256))
            tb.axil_ram.write(pcie_addr, test_data)

            tb.log.debug("%s", tb.axil_ram.hexdump_str((pcie_addr & ~0xf)-16, (((pcie_addr & 0xf)+length-1) & ~0xf)+48))

            val = await dev_bar0.read(pcie_addr, len(test_data), timeout=1000, timeout_unit='ns')

            tb.log.debug("read data: %s", val)

            assert val == test_data

            assert not tb.status_error_cor_asserted
            assert not tb.status_error_uncor_asserted

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)


async def run_test_io_write(dut, idle_inserter=None, backpressure_inserter=None):

    tb = TB(dut)

    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)

    await FallingEdge(dut.rst)
    await Timer(100, 'ns')

    await tb.rc.enumerate()

    dev_bar0 = tb.rc.tree[0][0].bar_window[0]
    dev_bar1 = tb.rc.tree[0][0].bar_window[1]

    for length in range(1, 5):
        for pcie_offset in range(4-length+1):
            tb.log.info("length %d, pcie_offset %d", length, pcie_offset)
            pcie_addr = pcie_offset+0x1000
            test_data = bytearray([x % 256 for x in range(length)])

            tb.axil_ram.write(pcie_addr-128, b'\x55'*(len(test_data)+256))

            await dev_bar1.write(pcie_addr, test_data, timeout=1000, timeout_unit='ns')

            tb.log.debug("%s", tb.axil_ram.hexdump_str((pcie_addr & ~0xf)-16, (((pcie_addr & 0xf)+length-1) & ~0xf)+48, prefix="AXI "))

            assert tb.axil_ram.read(pcie_addr-1, len(test_data)+2) == b'\x55'+test_data+b'\x55'

            assert not tb.status_error_cor_asserted
            assert not tb.status_error_uncor_asserted

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)


async def run_test_io_read(dut, idle_inserter=None, backpressure_inserter=None):

    tb = TB(dut)

    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)

    await FallingEdge(dut.rst)
    await Timer(100, 'ns')

    await tb.rc.enumerate()

    dev_bar0 = tb.rc.tree[0][0].bar_window[0]
    dev_bar1 = tb.rc.tree[0][0].bar_window[1]

    for length in range(1, 5):
        for pcie_offset in range(4-length+1):
            tb.log.info("length %d, pcie_offset %d", length, pcie_offset)
            pcie_addr = pcie_offset+0x1000
            test_data = bytearray([x % 256 for x in range(length)])

            tb.axil_ram.write(pcie_addr-128, b'\x55'*(len(test_data)+256))
            tb.axil_ram.write(pcie_addr, test_data)

            tb.log.debug("%s", tb.axil_ram.hexdump_str((pcie_addr & ~0xf)-16, (((pcie_addr & 0xf)+length-1) & ~0xf)+48, prefix="AXI "))

            val = await dev_bar1.read(pcie_addr, len(test_data), timeout=1000, timeout_unit='ns')

            tb.log.debug("read data: %s", val)

            assert val == test_data

            assert not tb.status_error_cor_asserted
            assert not tb.status_error_uncor_asserted

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)


async def run_test_bad_ops(dut, idle_inserter=None, backpressure_inserter=None):

    tb = TB(dut)

    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)

    await FallingEdge(dut.rst)
    await Timer(100, 'ns')

    await tb.rc.enumerate()

    dev_bar0 = tb.rc.tree[0][0].bar_window[0]
    dev_bar1 = tb.rc.tree[0][0].bar_window[1]

    tb.log.info("Test bad write")

    length = 32
    pcie_addr = 0x1000
    test_data = bytearray([x % 256 for x in range(length)])

    tb.axil_ram.write(pcie_addr-128, b'\x55'*(len(test_data)+256))

    await dev_bar0.write(pcie_addr, test_data)

    await Timer(100, 'ns')

    tb.log.debug("%s", tb.axil_ram.hexdump_str((pcie_addr & ~0xf)-16, (((pcie_addr & 0xf)+length-1) & ~0xf)+48, prefix="AXI "))

    assert tb.axil_ram.read(pcie_addr-1, len(test_data)+2) == b'\x55'*(len(test_data)+2)

    assert not tb.status_error_cor_asserted
    assert tb.status_error_uncor_asserted

    tb.status_error_cor_asserted = False
    tb.status_error_uncor_asserted = False

    tb.log.info("Test bad read")

    length = 32
    pcie_addr = 0x1000
    test_data = bytearray([x % 256 for x in range(length)])

    tb.axil_ram.write(pcie_addr-128, b'\x55'*(len(test_data)+256))
    tb.axil_ram.write(pcie_addr, test_data)

    tb.log.debug("%s", tb.axil_ram.hexdump_str((pcie_addr & ~0xf)-16, (((pcie_addr & 0xf)+length-1) & ~0xf)+48, prefix="AXI "))

    with assert_raises(Exception, "Unsuccessful completion"):
        val = await dev_bar0.read(pcie_addr, len(test_data), timeout=1000, timeout_unit='ns')

    assert tb.status_error_cor_asserted
    assert not tb.status_error_uncor_asserted

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)


def cycle_pause():
    return itertools.cycle([1, 1, 1, 0])


if cocotb.SIM_NAME:

    for test in [
                run_test_write,
                run_test_read,
                run_test_io_write,
                run_test_io_read,
                run_test_bad_ops
            ]:

        factory = TestFactory(test)
        factory.add_option("idle_inserter", [None, cycle_pause])
        factory.add_option("backpressure_inserter", [None, cycle_pause])
        factory.generate_tests()


# cocotb-test

tests_dir = os.path.dirname(__file__)
rtl_dir = os.path.abspath(os.path.join(tests_dir, '..', '..', 'rtl'))


@pytest.mark.parametrize("axis_pcie_data_width", [64, 128, 256, 512])
def test_pcie_us_axil_master(request, axis_pcie_data_width):
    dut = "pcie_us_axil_master"
    module = os.path.splitext(os.path.basename(__file__))[0]
    toplevel = dut

    verilog_sources = [
        os.path.join(rtl_dir, f"{dut}.v"),
    ]

    parameters = {}

    parameters['AXIS_PCIE_DATA_WIDTH'] = axis_pcie_data_width
    parameters['AXIS_PCIE_KEEP_WIDTH'] = parameters['AXIS_PCIE_DATA_WIDTH'] // 32
    parameters['AXIS_PCIE_CQ_USER_WIDTH'] = 88 if parameters['AXIS_PCIE_DATA_WIDTH'] < 512 else 183
    parameters['AXIS_PCIE_CC_USER_WIDTH'] = 33 if parameters['AXIS_PCIE_DATA_WIDTH'] < 512 else 81
    parameters['AXI_DATA_WIDTH'] = 32
    parameters['AXI_ADDR_WIDTH'] = 64
    parameters['AXI_STRB_WIDTH'] = (parameters['AXI_DATA_WIDTH'] // 8)
    parameters['ENABLE_PARITY'] = 0

    extra_env = {f'PARAM_{k}': str(v) for k, v in parameters.items()}

    extra_env['COCOTB_RESOLVE_X'] = 'RANDOM'

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

#!/usr/bin/env python
"""

Copyright (c) 2022 Alex Forencich

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

from cocotbext.axi import AxiStreamBus
from cocotbext.pcie.core.tlp import Tlp, TlpType
from cocotbext.pcie.xilinx.us.interface import CqSource
from cocotbext.pcie.xilinx.us.tlp import Tlp_us

try:
    from pcie_if import PcieIfSink, PcieIfRxBus
except ImportError:
    # attempt import from current directory
    sys.path.insert(0, os.path.join(os.path.dirname(__file__)))
    try:
        from pcie_if import PcieIfSink, PcieIfRxBus
    finally:
        del sys.path[0]


class TB(object):
    def __init__(self, dut, msix=False):
        self.dut = dut

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)

        cocotb.start_soon(Clock(dut.clk, 4, units="ns").start())

        self.source = CqSource(AxiStreamBus.from_prefix(dut, "s_axis_cq"), dut.clk, dut.rst)
        self.sink = PcieIfSink(PcieIfRxBus.from_prefix(dut, "rx_req_tlp"), dut.clk, dut.rst)

    def set_idle_generator(self, generator=None):
        if generator:
            self.source.set_pause_generator(generator())

    def set_backpressure_generator(self, generator=None):
        if generator:
            self.sink.set_pause_generator(generator())

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


async def run_test(dut, payload_lengths=None, payload_data=None, idle_inserter=None, backpressure_inserter=None):

    tb = TB(dut)

    seq_count = 32

    cur_seq = 1

    await tb.cycle_reset()

    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)

    test_tlps = []
    test_frames = []

    for test_data in [payload_data(x) for x in payload_lengths()]:
        test_tlp = Tlp()

        if len(test_data):
            test_tlp.fmt_type = TlpType.MEM_WRITE_64
            test_tlp.set_addr_be_data(cur_seq*4, test_data)
        else:
            test_tlp.fmt_type = TlpType.MEM_READ_64
            test_tlp.set_addr_be(cur_seq*4, 4)

        test_frame = Tlp_us(test_tlp).pack_us_cq()

        test_tlps.append(test_tlp)
        test_frames.append(test_frame)
        await tb.source.send(test_frame)

        cur_seq = (cur_seq + 1) % seq_count

    for test_tlp in test_tlps:
        rx_frame = await tb.sink.recv()

        rx_tlp = rx_frame.to_tlp()

        assert test_tlp == rx_tlp

    assert tb.sink.empty()

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)


def cycle_pause():
    return itertools.cycle([1, 1, 1, 0])


def size_list():
    return list(range(0, 512+1, 4))+[4]*64


def incrementing_payload(length):
    return bytearray(itertools.islice(itertools.cycle(range(256)), length))


if cocotb.SIM_NAME:

    factory = TestFactory(run_test)
    factory.add_option("payload_lengths", [size_list])
    factory.add_option("payload_data", [incrementing_payload])
    factory.add_option("idle_inserter", [None, cycle_pause])
    factory.add_option("backpressure_inserter", [None, cycle_pause])
    factory.generate_tests()


# cocotb-test

tests_dir = os.path.dirname(__file__)
rtl_dir = os.path.abspath(os.path.join(tests_dir, '..', '..', 'rtl'))


@pytest.mark.parametrize("axis_pcie_data_width", [64, 128, 256, 512])
def test_pcie_us_if_cq(request, axis_pcie_data_width):
    dut = "pcie_us_if_cq"
    module = os.path.splitext(os.path.basename(__file__))[0]
    toplevel = dut

    verilog_sources = [
        os.path.join(rtl_dir, f"{dut}.v"),
    ]

    parameters = {}

    parameters['AXIS_PCIE_DATA_WIDTH'] = axis_pcie_data_width
    parameters['AXIS_PCIE_KEEP_WIDTH'] = parameters['AXIS_PCIE_DATA_WIDTH'] // 32
    parameters['AXIS_PCIE_CQ_USER_WIDTH'] = 88 if parameters['AXIS_PCIE_DATA_WIDTH'] < 512 else 183
    parameters['TLP_DATA_WIDTH'] = axis_pcie_data_width
    parameters['TLP_STRB_WIDTH'] = parameters['TLP_DATA_WIDTH'] // 32
    parameters['TLP_HDR_WIDTH'] = 128
    parameters['TLP_SEG_COUNT'] = 1

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

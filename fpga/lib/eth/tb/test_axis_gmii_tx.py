#!/usr/bin/env python
"""

Copyright (c) 2015-2018 Alex Forencich

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

from myhdl import *
import os

import axis_ep
import eth_ep
import gmii_ep

module = 'axis_gmii_tx'
testbench = 'test_%s' % module

srcs = []

srcs.append("../rtl/%s.v" % module)
srcs.append("../rtl/lfsr.v")
srcs.append("%s.v" % testbench)

src = ' '.join(srcs)

build_cmd = "iverilog -o %s.vvp %s" % (testbench, src)

def bench():

    # Parameters
    DATA_WIDTH = 8
    ENABLE_PADDING = 1
    MIN_FRAME_LENGTH = 64
    PTP_TS_ENABLE = 0
    PTP_TS_WIDTH = 96
    PTP_TAG_ENABLE = PTP_TS_ENABLE
    PTP_TAG_WIDTH = 16
    USER_WIDTH = (PTP_TAG_WIDTH if PTP_TAG_ENABLE else 0) + 1

    # Inputs
    clk = Signal(bool(0))
    rst = Signal(bool(0))
    current_test = Signal(intbv(0)[8:])

    s_axis_tdata = Signal(intbv(0)[DATA_WIDTH:])
    s_axis_tvalid = Signal(bool(0))
    s_axis_tlast = Signal(bool(0))
    s_axis_tuser = Signal(intbv(0)[USER_WIDTH:])
    ptp_ts = Signal(intbv(0)[PTP_TS_WIDTH:])
    clk_enable = Signal(bool(1))
    mii_select = Signal(bool(0))
    ifg_delay = Signal(intbv(0)[8:])

    # Outputs
    s_axis_tready = Signal(bool(0))
    gmii_txd = Signal(intbv(0)[DATA_WIDTH:])
    gmii_tx_en = Signal(bool(0))
    gmii_tx_er = Signal(bool(0))
    m_axis_ptp_ts = Signal(intbv(0)[PTP_TS_WIDTH:])
    m_axis_ptp_ts_tag = Signal(intbv(0)[PTP_TAG_WIDTH:])
    m_axis_ptp_ts_valid = Signal(bool(0))
    start_packet = Signal(bool(0))
    error_underflow = Signal(bool(0))

    # sources and sinks
    source_pause = Signal(bool(0))

    source = axis_ep.AXIStreamSource()

    source_logic = source.create_logic(
        clk,
        rst,
        tdata=s_axis_tdata,
        tvalid=s_axis_tvalid,
        tready=s_axis_tready,
        tlast=s_axis_tlast,
        tuser=s_axis_tuser,
        pause=source_pause,
        name='source'
    )

    sink = gmii_ep.GMIISink()

    sink_logic = sink.create_logic(
        clk,
        rst,
        rxd=gmii_txd,
        rx_dv=gmii_tx_en,
        rx_er=gmii_tx_er,
        clk_enable=clk_enable,
        mii_select=mii_select,
        name='sink'
    )

    # DUT
    if os.system(build_cmd):
        raise Exception("Error running build command")

    dut = Cosimulation(
        "vvp -m myhdl %s.vvp -lxt2" % testbench,
        clk=clk,
        rst=rst,
        current_test=current_test,

        s_axis_tdata=s_axis_tdata,
        s_axis_tvalid=s_axis_tvalid,
        s_axis_tready=s_axis_tready,
        s_axis_tlast=s_axis_tlast,
        s_axis_tuser=s_axis_tuser,

        gmii_txd=gmii_txd,
        gmii_tx_en=gmii_tx_en,
        gmii_tx_er=gmii_tx_er,

        ptp_ts=ptp_ts,
        m_axis_ptp_ts=m_axis_ptp_ts,
        m_axis_ptp_ts_tag=m_axis_ptp_ts_tag,
        m_axis_ptp_ts_valid=m_axis_ptp_ts_valid,

        clk_enable=clk_enable,
        mii_select=mii_select,

        ifg_delay=ifg_delay,

        start_packet=start_packet,
        error_underflow=error_underflow
    )

    @always(delay(4))
    def clkgen():
        clk.next = not clk

    clk_enable_rate = Signal(int(1))
    clk_enable_div = Signal(int(0))

    @always(clk.posedge)
    def clk_enable_gen():
        if clk_enable_div.next > 0:
            clk_enable.next = 0
            clk_enable_div.next = clk_enable_div - 1
        else:
            clk_enable.next = 1
            clk_enable_div.next = clk_enable_rate - 1

    @instance
    def check():
        yield delay(100)
        yield clk.posedge
        rst.next = 1
        yield clk.posedge
        rst.next = 0
        yield clk.posedge
        yield delay(100)
        yield clk.posedge

        ifg_delay.next = 12

        # testbench stimulus

        for rate, mii in [(1, 0), (10, 0), (5, 1)]:
            clk_enable_rate.next = rate
            mii_select.next = mii

            yield delay(100)

            for payload_len in list(range(1,18))+list(range(64,82)):
                yield clk.posedge
                print("test 1: test packet, length %d" % payload_len)
                current_test.next = 1

                test_frame = eth_ep.EthFrame()
                test_frame.eth_dest_mac = 0xDAD1D2D3D4D5
                test_frame.eth_src_mac = 0x5A5152535455
                test_frame.eth_type = 0x8000
                test_frame.payload = bytearray(range(payload_len))
                test_frame.update_fcs()

                axis_frame = test_frame.build_axis()

                source.send(axis_frame)

                yield sink.wait()
                rx_frame = sink.recv()

                assert rx_frame.data[0:8] == bytearray(b'\x55\x55\x55\x55\x55\x55\x55\xD5')

                eth_frame = eth_ep.EthFrame()
                eth_frame.parse_axis_fcs(rx_frame.data[8:])

                print(hex(eth_frame.eth_fcs))
                print(hex(eth_frame.calc_fcs()))

                assert len(eth_frame.payload.data) == max(payload_len, 46)
                assert eth_frame.eth_fcs == eth_frame.calc_fcs()
                assert eth_frame.eth_dest_mac == test_frame.eth_dest_mac
                assert eth_frame.eth_src_mac == test_frame.eth_src_mac
                assert eth_frame.eth_type == test_frame.eth_type
                assert eth_frame.payload.data.index(test_frame.payload.data) == 0

                assert sink.empty()

                yield delay(100)

                yield clk.posedge
                print("test 2: back-to-back packets, length %d" % payload_len)
                current_test.next = 2

                test_frame1 = eth_ep.EthFrame()
                test_frame1.eth_dest_mac = 0xDAD1D2D3D4D5
                test_frame1.eth_src_mac = 0x5A5152535455
                test_frame1.eth_type = 0x8000
                test_frame1.payload = bytearray(range(payload_len))
                test_frame1.update_fcs()
                test_frame2 = eth_ep.EthFrame()
                test_frame2.eth_dest_mac = 0xDAD1D2D3D4D5
                test_frame2.eth_src_mac = 0x5A5152535455
                test_frame2.eth_type = 0x8000
                test_frame2.payload = bytearray(range(payload_len))
                test_frame2.update_fcs()

                axis_frame1 = test_frame1.build_axis()
                axis_frame2 = test_frame2.build_axis()

                source.send(axis_frame1)
                source.send(axis_frame2)

                yield sink.wait()
                rx_frame = sink.recv()

                assert rx_frame.data[0:8] == bytearray(b'\x55\x55\x55\x55\x55\x55\x55\xD5')

                eth_frame = eth_ep.EthFrame()
                eth_frame.parse_axis_fcs(rx_frame.data[8:])

                print(hex(eth_frame.eth_fcs))
                print(hex(eth_frame.calc_fcs()))

                assert len(eth_frame.payload.data) == max(payload_len, 46)
                assert eth_frame.eth_fcs == eth_frame.calc_fcs()
                assert eth_frame.eth_dest_mac == test_frame1.eth_dest_mac
                assert eth_frame.eth_src_mac == test_frame1.eth_src_mac
                assert eth_frame.eth_type == test_frame1.eth_type
                assert eth_frame.payload.data.index(test_frame1.payload.data) == 0

                yield sink.wait()
                rx_frame = sink.recv()

                assert rx_frame.data[0:8] == bytearray(b'\x55\x55\x55\x55\x55\x55\x55\xD5')

                eth_frame = eth_ep.EthFrame()
                eth_frame.parse_axis_fcs(rx_frame.data[8:])

                print(hex(eth_frame.eth_fcs))
                print(hex(eth_frame.calc_fcs()))

                assert len(eth_frame.payload.data) == max(payload_len, 46)
                assert eth_frame.eth_fcs == eth_frame.calc_fcs()
                assert eth_frame.eth_dest_mac == test_frame2.eth_dest_mac
                assert eth_frame.eth_src_mac == test_frame2.eth_src_mac
                assert eth_frame.eth_type == test_frame2.eth_type
                assert eth_frame.payload.data.index(test_frame2.payload.data) == 0

                assert sink.empty()

                yield delay(100)

                yield clk.posedge
                print("test 3: tuser assert, length %d" % payload_len)
                current_test.next = 3

                test_frame1 = eth_ep.EthFrame()
                test_frame1.eth_dest_mac = 0xDAD1D2D3D4D5
                test_frame1.eth_src_mac = 0x5A5152535455
                test_frame1.eth_type = 0x8000
                test_frame1.payload = bytearray(range(payload_len))
                test_frame1.update_fcs()
                test_frame2 = eth_ep.EthFrame()
                test_frame2.eth_dest_mac = 0xDAD1D2D3D4D5
                test_frame2.eth_src_mac = 0x5A5152535455
                test_frame2.eth_type = 0x8000
                test_frame2.payload = bytearray(range(payload_len))
                test_frame2.update_fcs()

                axis_frame1 = test_frame1.build_axis()
                axis_frame2 = test_frame2.build_axis()

                axis_frame1.user = 1

                source.send(axis_frame1)
                source.send(axis_frame2)

                yield sink.wait()
                rx_frame = sink.recv()

                assert rx_frame.data[0:8] == bytearray(b'\x55\x55\x55\x55\x55\x55\x55\xD5')
                assert rx_frame.error[-1]

                # bad packet

                yield sink.wait()
                rx_frame = sink.recv()

                assert rx_frame.data[0:8] == bytearray(b'\x55\x55\x55\x55\x55\x55\x55\xD5')

                eth_frame = eth_ep.EthFrame()
                eth_frame.parse_axis_fcs(rx_frame.data[8:])

                print(hex(eth_frame.eth_fcs))
                print(hex(eth_frame.calc_fcs()))

                assert len(eth_frame.payload.data) == max(payload_len, 46)
                assert eth_frame.eth_fcs == eth_frame.calc_fcs()
                assert eth_frame.eth_dest_mac == test_frame2.eth_dest_mac
                assert eth_frame.eth_src_mac == test_frame2.eth_src_mac
                assert eth_frame.eth_type == test_frame2.eth_type
                assert eth_frame.payload.data.index(test_frame2.payload.data) == 0

                assert sink.empty()

                yield delay(100)

        raise StopSimulation

    return instances()

def test_bench():
    sim = Simulation(bench())
    sim.run()

if __name__ == '__main__':
    print("Running test...")
    test_bench()

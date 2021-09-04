#!/usr/bin/env python
"""

Copyright (c) 2019 Alex Forencich

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

module = 'axis_frame_len'
testbench = 'test_%s_8' % module

srcs = []

srcs.append("../rtl/%s.v" % module)
srcs.append("%s.v" % testbench)

src = ' '.join(srcs)

build_cmd = "iverilog -o %s.vvp %s" % (testbench, src)

def bench():

    # Parameters
    DATA_WIDTH = 8
    KEEP_ENABLE = (DATA_WIDTH>8)
    KEEP_WIDTH = (DATA_WIDTH/8)
    LEN_WIDTH = 16

    # Inputs
    clk = Signal(bool(0))
    rst = Signal(bool(0))
    current_test = Signal(intbv(0)[8:])

    monitor_axis_tdata = Signal(intbv(0)[DATA_WIDTH:])
    monitor_axis_tkeep = Signal(intbv(1)[KEEP_WIDTH:])
    monitor_axis_tvalid = Signal(bool(0))
    monitor_axis_tready = Signal(bool(0))
    monitor_axis_tlast = Signal(bool(0))

    # Outputs
    frame_len = Signal(intbv(0)[LEN_WIDTH:])
    frame_len_valid = Signal(bool(0))

    # sources and sinks
    source_pause = Signal(bool(0))
    sink_pause = Signal(bool(0))

    source = axis_ep.AXIStreamSource()

    source_logic = source.create_logic(
        clk,
        rst,
        tdata=monitor_axis_tdata,
        tkeep=monitor_axis_tkeep,
        tvalid=monitor_axis_tvalid,
        tready=monitor_axis_tready,
        tlast=monitor_axis_tlast,
        pause=source_pause,
        name='source'
    )

    sink = axis_ep.AXIStreamSink()

    sink_logic = sink.create_logic(
        clk,
        rst,
        tdata=monitor_axis_tdata,
        tkeep=monitor_axis_tkeep,
        tvalid=monitor_axis_tvalid,
        tready=monitor_axis_tready,
        tlast=monitor_axis_tlast,
        pause=sink_pause,
        name='sink'
    )

    frame_len_sink = axis_ep.AXIStreamSink()

    frame_len_sink_logic = frame_len_sink.create_logic(
        clk,
        rst,
        tdata=frame_len,
        tvalid=frame_len_valid,
        name='frame_len_sink'
    )

    # DUT
    if os.system(build_cmd):
        raise Exception("Error running build command")

    dut = Cosimulation(
        "vvp -m myhdl %s.vvp -lxt2" % testbench,
        clk=clk,
        rst=rst,
        current_test=current_test,

        monitor_axis_tkeep=monitor_axis_tkeep,
        monitor_axis_tvalid=monitor_axis_tvalid,
        monitor_axis_tready=monitor_axis_tready,
        monitor_axis_tlast=monitor_axis_tlast,

        frame_len=frame_len,
        frame_len_valid=frame_len_valid
    )

    @always(delay(4))
    def clkgen():
        clk.next = not clk

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

        yield clk.posedge
        print("test 1: test packet")
        current_test.next = 1

        test_frame = axis_ep.AXIStreamFrame(
            b'\xDA\xD1\xD2\xD3\xD4\xD5' +
            b'\x5A\x51\x52\x53\x54\x55' +
            b'\x80\x00' +
            b'\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10'
        )

        source.send(test_frame)
        yield clk.posedge

        while monitor_axis_tvalid:
            yield clk.posedge

        yield sink.wait()
        f = sink.recv()

        yield frame_len_sink.wait()
        l = frame_len_sink.recv()

        assert len(f.data) == l.data[0]

        yield delay(100)

        yield clk.posedge
        print("test 4: longer packet")
        current_test.next = 4

        test_frame = axis_ep.AXIStreamFrame(
            b'\xDA\xD1\xD2\xD3\xD4\xD5' +
            b'\x5A\x51\x52\x53\x54\x55' +
            b'\x80\x00' +
            bytearray(range(256))
        )

        source.send(test_frame)
        yield clk.posedge

        while monitor_axis_tvalid:
            yield clk.posedge

        yield sink.wait()
        f = sink.recv()

        yield frame_len_sink.wait()
        l = frame_len_sink.recv()

        assert len(f.data) == l.data[0]

        yield delay(100)

        yield clk.posedge
        print("test 5: test packet with pauses")
        current_test.next = 5

        test_frame = axis_ep.AXIStreamFrame(
            b'\xDA\xD1\xD2\xD3\xD4\xD5' +
            b'\x5A\x51\x52\x53\x54\x55' +
            b'\x80\x00' +
            bytearray(range(256))
        )

        source.send(test_frame)
        yield clk.posedge

        yield delay(64)
        yield clk.posedge
        source_pause.next = True
        yield delay(32)
        yield clk.posedge
        source_pause.next = False

        yield delay(64)
        yield clk.posedge
        sink_pause.next = True
        yield delay(32)
        yield clk.posedge
        sink_pause.next = False

        while monitor_axis_tvalid:
            yield clk.posedge

        yield sink.wait()
        f = sink.recv()

        yield frame_len_sink.wait()
        l = frame_len_sink.recv()

        assert len(f.data) == l.data[0]

        yield delay(100)

        yield clk.posedge
        print("test 6: back-to-back packets")
        current_test.next = 6

        test_frame1 = axis_ep.AXIStreamFrame(
            b'\xDA\xD1\xD2\xD3\xD4\xD5' +
            b'\x5A\x51\x52\x53\x54\x55' +
            b'\x80\x00' +
            b'\x01\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10'
        )
        test_frame2 = axis_ep.AXIStreamFrame(
            b'\xDA\xD1\xD2\xD3\xD4\xD5' +
            b'\x5A\x51\x52\x53\x54\x55' +
            b'\x80\x00' +
            b'\x02\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10'
        )

        source.send(test_frame1)
        source.send(test_frame2)
        yield clk.posedge

        while monitor_axis_tvalid:
            yield clk.posedge

        yield sink.wait()
        f = sink.recv()

        yield frame_len_sink.wait()
        l = frame_len_sink.recv()

        assert len(f.data) == l.data[0]

        yield sink.wait()
        f = sink.recv()

        yield frame_len_sink.wait()
        l = frame_len_sink.recv()

        assert len(f.data) == l.data[0]

        yield delay(100)

        yield clk.posedge
        print("test 7: alternate pause source")
        current_test.next = 7

        test_frame1 = axis_ep.AXIStreamFrame(
            b'\xDA\xD1\xD2\xD3\xD4\xD5' +
            b'\x5A\x51\x52\x53\x54\x55' +
            b'\x80\x00' +
            b'\x01\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10'
        )
        test_frame2 = axis_ep.AXIStreamFrame(
            b'\xDA\xD1\xD2\xD3\xD4\xD5' +
            b'\x5A\x51\x52\x53\x54\x55' +
            b'\x80\x00' +
            b'\x02\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10'
        )

        source.send(test_frame1)
        source.send(test_frame2)
        yield clk.posedge

        while monitor_axis_tvalid:
            yield clk.posedge
            yield clk.posedge
            source_pause.next = False
            yield clk.posedge
            source_pause.next = True
            yield clk.posedge
        
        source_pause.next = False

        yield sink.wait()
        f = sink.recv()

        yield frame_len_sink.wait()
        l = frame_len_sink.recv()

        assert len(f.data) == l.data[0]

        yield sink.wait()
        f = sink.recv()

        yield frame_len_sink.wait()
        l = frame_len_sink.recv()

        assert len(f.data) == l.data[0]

        yield delay(100)

        yield clk.posedge
        print("test 8: alternate pause sink")
        current_test.next = 8

        test_frame1 = axis_ep.AXIStreamFrame(
            b'\xDA\xD1\xD2\xD3\xD4\xD5' +
            b'\x5A\x51\x52\x53\x54\x55' +
            b'\x80\x00' +
            b'\x01\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10'
        )
        test_frame2 = axis_ep.AXIStreamFrame(
            b'\xDA\xD1\xD2\xD3\xD4\xD5' +
            b'\x5A\x51\x52\x53\x54\x55' +
            b'\x80\x00' +
            b'\x02\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10'
        )

        source.send(test_frame1)
        source.send(test_frame2)
        yield clk.posedge

        while monitor_axis_tvalid:
            sink_pause.next = True
            yield clk.posedge
            yield clk.posedge
            yield clk.posedge
            sink_pause.next = False
            yield clk.posedge

        yield sink.wait()
        f = sink.recv()

        yield frame_len_sink.wait()
        l = frame_len_sink.recv()

        assert len(f.data) == l.data[0]

        yield sink.wait()
        f = sink.recv()

        yield frame_len_sink.wait()
        l = frame_len_sink.recv()

        assert len(f.data) == l.data[0]

        yield delay(100)

        yield clk.posedge
        print("test 9: various length packets")
        current_test.next = 9

        lens = [32, 48, 96, 128, 256]
        test_frame = []

        for i in lens:
            test_frame.append(axis_ep.AXIStreamFrame(
                b'\xDA\xD1\xD2\xD3\xD4\xD5' +
                b'\x5A\x51\x52\x53\x54\x55' +
                b'\x80\x00' +
                bytearray(range(i)))
            )

        for f in test_frame:
            source.send(f)
        yield clk.posedge

        while monitor_axis_tvalid:
            yield clk.posedge

        for i in lens:
            yield sink.wait()
            f = sink.recv()

            yield frame_len_sink.wait()
            l = frame_len_sink.recv()

            assert len(f.data) == l.data[0]

        yield delay(100)

        raise StopSimulation

    return instances()

def test_bench():
    os.chdir(os.path.dirname(os.path.abspath(__file__)))
    sim = Simulation(bench())
    sim.run()

if __name__ == '__main__':
    print("Running test...")
    test_bench()


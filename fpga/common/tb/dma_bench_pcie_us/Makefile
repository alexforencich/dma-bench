# Copyright (c) 2021 Alex Forencich
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

TOPLEVEL_LANG = verilog

SIM ?= icarus
WAVES ?= 0

COCOTB_HDL_TIMEUNIT = 1ns
COCOTB_HDL_TIMEPRECISION = 1ps

DUT      = dma_bench_pcie_us
TOPLEVEL = $(DUT)
MODULE   = test_$(DUT)
VERILOG_SOURCES += ../../rtl/$(DUT).v
VERILOG_SOURCES += ../../rtl/dma_bench_pcie.v
VERILOG_SOURCES += ../../rtl/dma_bench.v
VERILOG_SOURCES += ../../rtl/stats_counter.v
VERILOG_SOURCES += ../../rtl/stats_collect.v
VERILOG_SOURCES += ../../rtl/stats_pcie_if.v
VERILOG_SOURCES += ../../rtl/stats_pcie_tlp.v
VERILOG_SOURCES += ../../lib/axi/rtl/axil_interconnect.v
VERILOG_SOURCES += ../../lib/pcie/rtl/pcie_us_if.v
VERILOG_SOURCES += ../../lib/pcie/rtl/pcie_us_if_rc.v
VERILOG_SOURCES += ../../lib/pcie/rtl/pcie_us_if_rq.v
VERILOG_SOURCES += ../../lib/pcie/rtl/pcie_us_if_cq.v
VERILOG_SOURCES += ../../lib/pcie/rtl/pcie_us_if_cc.v
VERILOG_SOURCES += ../../lib/pcie/rtl/pcie_us_cfg.v
VERILOG_SOURCES += ../../lib/pcie/rtl/pcie_us_msi.v
VERILOG_SOURCES += ../../lib/pcie/rtl/pcie_axil_master.v
VERILOG_SOURCES += ../../lib/pcie/rtl/dma_if_pcie.v
VERILOG_SOURCES += ../../lib/pcie/rtl/dma_if_pcie_rd.v
VERILOG_SOURCES += ../../lib/pcie/rtl/dma_if_pcie_wr.v
VERILOG_SOURCES += ../../lib/pcie/rtl/dma_psdpram.v
VERILOG_SOURCES += ../../lib/pcie/rtl/arbiter.v
VERILOG_SOURCES += ../../lib/pcie/rtl/priority_encoder.v
VERILOG_SOURCES += ../../lib/pcie/rtl/pulse_merge.v

# module parameters
export PARAM_AXIS_PCIE_DATA_WIDTH ?= 512
export PARAM_AXIS_PCIE_KEEP_WIDTH ?= $(shell expr $(PARAM_AXIS_PCIE_DATA_WIDTH) / 32 )
export PARAM_AXIS_PCIE_RQ_USER_WIDTH ?= $(if $(filter-out 512,$(PARAM_AXIS_PCIE_DATA_WIDTH)),62,137)
export PARAM_AXIS_PCIE_RC_USER_WIDTH ?= $(if $(filter-out 512,$(PARAM_AXIS_PCIE_DATA_WIDTH)),75,161)
export PARAM_AXIS_PCIE_CQ_USER_WIDTH ?= $(if $(filter-out 512,$(PARAM_AXIS_PCIE_DATA_WIDTH)),88,183)
export PARAM_AXIS_PCIE_CC_USER_WIDTH ?= $(if $(filter-out 512,$(PARAM_AXIS_PCIE_DATA_WIDTH)),33,81)
export PARAM_RQ_SEQ_NUM_WIDTH ?= 6

ifeq ($(SIM), icarus)
	PLUSARGS += -fst

	COMPILE_ARGS += -P $(TOPLEVEL).AXIS_PCIE_DATA_WIDTH=$(PARAM_AXIS_PCIE_DATA_WIDTH)
	COMPILE_ARGS += -P $(TOPLEVEL).AXIS_PCIE_KEEP_WIDTH=$(PARAM_AXIS_PCIE_KEEP_WIDTH)
	COMPILE_ARGS += -P $(TOPLEVEL).AXIS_PCIE_RQ_USER_WIDTH=$(PARAM_AXIS_PCIE_RQ_USER_WIDTH)
	COMPILE_ARGS += -P $(TOPLEVEL).AXIS_PCIE_RC_USER_WIDTH=$(PARAM_AXIS_PCIE_RC_USER_WIDTH)
	COMPILE_ARGS += -P $(TOPLEVEL).AXIS_PCIE_CQ_USER_WIDTH=$(PARAM_AXIS_PCIE_CQ_USER_WIDTH)
	COMPILE_ARGS += -P $(TOPLEVEL).AXIS_PCIE_CC_USER_WIDTH=$(PARAM_AXIS_PCIE_CC_USER_WIDTH)
	COMPILE_ARGS += -P $(TOPLEVEL).RQ_SEQ_NUM_WIDTH=$(PARAM_RQ_SEQ_NUM_WIDTH)

	ifeq ($(WAVES), 1)
		VERILOG_SOURCES += iverilog_dump.v
		COMPILE_ARGS += -s iverilog_dump
	endif
else ifeq ($(SIM), verilator)
	COMPILE_ARGS += -Wno-SELRANGE -Wno-WIDTH

	COMPILE_ARGS += -GAXIS_PCIE_DATA_WIDTH=$(PARAM_AXIS_PCIE_DATA_WIDTH)
	COMPILE_ARGS += -GAXIS_PCIE_KEEP_WIDTH=$(PARAM_AXIS_PCIE_KEEP_WIDTH)
	COMPILE_ARGS += -GAXIS_PCIE_RQ_USER_WIDTH=$(PARAM_AXIS_PCIE_RQ_USER_WIDTH)
	COMPILE_ARGS += -GAXIS_PCIE_RC_USER_WIDTH=$(PARAM_AXIS_PCIE_RC_USER_WIDTH)
	COMPILE_ARGS += -GAXIS_PCIE_CQ_USER_WIDTH=$(PARAM_AXIS_PCIE_CQ_USER_WIDTH)
	COMPILE_ARGS += -GAXIS_PCIE_CC_USER_WIDTH=$(PARAM_AXIS_PCIE_CC_USER_WIDTH)
	COMPILE_ARGS += -GRQ_SEQ_NUM_WIDTH=$(PARAM_RQ_SEQ_NUM_WIDTH)

	ifeq ($(WAVES), 1)
		COMPILE_ARGS += --trace-fst
	endif
endif

include $(shell cocotb-config --makefiles)/Makefile.sim

iverilog_dump.v:
	echo 'module iverilog_dump();' > $@
	echo 'initial begin' >> $@
	echo '    $$dumpfile("$(TOPLEVEL).fst");' >> $@
	echo '    $$dumpvars(0, $(TOPLEVEL));' >> $@
	echo 'end' >> $@
	echo 'endmodule' >> $@

clean::
	@rm -rf iverilog_dump.v
	@rm -rf dump.fst $(TOPLEVEL).fst

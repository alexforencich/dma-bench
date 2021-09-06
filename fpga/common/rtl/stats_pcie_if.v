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

// Language: Verilog 2001

`timescale 1ns / 1ps

/*
 * Statistics for PCIe interface
 */
module stats_pcie_if #
(
    // TLP segment count
    parameter TLP_SEG_COUNT = 1,
    // TLP segment header width
    parameter TLP_SEG_HDR_WIDTH = 128,
    // Statistics counter increment width (bits)
    parameter STAT_INC_WIDTH = 24,
    // Statistics counter ID width (bits)
    parameter STAT_ID_WIDTH = 5,
    // Statistics counter update period (cycles)
    parameter UPDATE_PERIOD = 1024
)
(
    input  wire                                        clk,
    input  wire                                        rst,

    /*
     * monitor input (request to BAR)
     */
    input  wire [TLP_SEG_COUNT*TLP_SEG_HDR_WIDTH-1:0]  rx_req_tlp_hdr,
    input  wire [TLP_SEG_COUNT-1:0]                    rx_req_tlp_valid,
    input  wire [TLP_SEG_COUNT-1:0]                    rx_req_tlp_sop,
    input  wire [TLP_SEG_COUNT-1:0]                    rx_req_tlp_eop,

    /*
     * monitor input (completion to DMA)
     */
    input  wire [TLP_SEG_COUNT*TLP_SEG_HDR_WIDTH-1:0]  rx_cpl_tlp_hdr,
    input  wire [TLP_SEG_COUNT-1:0]                    rx_cpl_tlp_valid,
    input  wire [TLP_SEG_COUNT-1:0]                    rx_cpl_tlp_sop,
    input  wire [TLP_SEG_COUNT-1:0]                    rx_cpl_tlp_eop,

    /*
     * monitor input (read request from DMA)
     */
    input  wire [TLP_SEG_COUNT*TLP_SEG_HDR_WIDTH-1:0]  tx_rd_req_tlp_hdr,
    input  wire [TLP_SEG_COUNT-1:0]                    tx_rd_req_tlp_valid,
    input  wire [TLP_SEG_COUNT-1:0]                    tx_rd_req_tlp_sop,
    input  wire [TLP_SEG_COUNT-1:0]                    tx_rd_req_tlp_eop,

    /*
     * monitor input (write request from DMA)
     */
    input  wire [TLP_SEG_COUNT*TLP_SEG_HDR_WIDTH-1:0]  tx_wr_req_tlp_hdr,
    input  wire [TLP_SEG_COUNT-1:0]                    tx_wr_req_tlp_valid,
    input  wire [TLP_SEG_COUNT-1:0]                    tx_wr_req_tlp_sop,
    input  wire [TLP_SEG_COUNT-1:0]                    tx_wr_req_tlp_eop,

    /*
     * monitor input (completion from BAR)
     */
    input  wire [TLP_SEG_COUNT*TLP_SEG_HDR_WIDTH-1:0]  tx_cpl_tlp_hdr,
    input  wire [TLP_SEG_COUNT-1:0]                    tx_cpl_tlp_valid,
    input  wire [TLP_SEG_COUNT-1:0]                    tx_cpl_tlp_sop,
    input  wire [TLP_SEG_COUNT-1:0]                    tx_cpl_tlp_eop,

    /*
     * Statistics output
     */
    output wire [STAT_INC_WIDTH-1:0]                   m_axis_stat_tdata,
    output wire [STAT_ID_WIDTH-1:0]                    m_axis_stat_tid,
    output wire                                        m_axis_stat_tvalid,
    input  wire                                        m_axis_stat_tready,

    /*
     * Control inputs
     */
    input  wire                                        update
);

wire stat_rx_req_tlp_mem_rd;
wire stat_rx_req_tlp_mem_wr;
wire stat_rx_req_tlp_io;
wire stat_rx_req_tlp_cfg;
wire stat_rx_req_tlp_msg;
wire stat_rx_req_tlp_cpl;
wire stat_rx_req_tlp_cpl_ur;
wire stat_rx_req_tlp_cpl_ca;
wire stat_rx_req_tlp_atomic;
wire stat_rx_req_tlp_ep;
wire [2:0] stat_rx_req_tlp_hdr_dw;
wire [10:0] stat_rx_req_tlp_req_dw;
wire [10:0] stat_rx_req_tlp_payload_dw;
wire [10:0] stat_rx_req_tlp_cpl_dw;

stats_pcie_tlp #(
    .TLP_SEG_COUNT(TLP_SEG_COUNT),
    .TLP_SEG_HDR_WIDTH(TLP_SEG_HDR_WIDTH)
)
stats_pcie_rx_req_tlp_inst (
    .clk(clk),
    .rst(rst),

    /*
     * TLP monitor input
     */
    .tlp_hdr(rx_req_tlp_hdr),
    .tlp_valid(rx_req_tlp_valid),
    .tlp_sop(rx_req_tlp_sop),
    .tlp_eop(rx_req_tlp_eop),

    /*
     * Statistics outputs
     */
    .stat_tlp_mem_rd(stat_rx_req_tlp_mem_rd),
    .stat_tlp_mem_wr(stat_rx_req_tlp_mem_wr),
    .stat_tlp_io(stat_rx_req_tlp_io),
    .stat_tlp_cfg(stat_rx_req_tlp_cfg),
    .stat_tlp_msg(stat_rx_req_tlp_msg),
    .stat_tlp_cpl(stat_rx_req_tlp_cpl),
    .stat_tlp_cpl_ur(stat_rx_req_tlp_cpl_ur),
    .stat_tlp_cpl_ca(stat_rx_req_tlp_cpl_ca),
    .stat_tlp_atomic(stat_rx_req_tlp_atomic),
    .stat_tlp_ep(stat_rx_req_tlp_ep),
    .stat_tlp_hdr_dw(stat_rx_req_tlp_hdr_dw),
    .stat_tlp_req_dw(stat_rx_req_tlp_req_dw),
    .stat_tlp_payload_dw(stat_rx_req_tlp_payload_dw),
    .stat_tlp_cpl_dw(stat_rx_req_tlp_cpl_dw)
);

wire stat_rx_cpl_tlp_mem_rd;
wire stat_rx_cpl_tlp_mem_wr;
wire stat_rx_cpl_tlp_io;
wire stat_rx_cpl_tlp_cfg;
wire stat_rx_cpl_tlp_msg;
wire stat_rx_cpl_tlp_cpl;
wire stat_rx_cpl_tlp_cpl_ur;
wire stat_rx_cpl_tlp_cpl_ca;
wire stat_rx_cpl_tlp_atomic;
wire stat_rx_cpl_tlp_ep;
wire [2:0] stat_rx_cpl_tlp_hdr_dw;
wire [10:0] stat_rx_cpl_tlp_req_dw;
wire [10:0] stat_rx_cpl_tlp_payload_dw;
wire [10:0] stat_rx_cpl_tlp_cpl_dw;

stats_pcie_tlp #(
    .TLP_SEG_COUNT(TLP_SEG_COUNT),
    .TLP_SEG_HDR_WIDTH(TLP_SEG_HDR_WIDTH)
)
stats_pcie_rx_cpl_tlp_inst (
    .clk(clk),
    .rst(rst),

    /*
     * TLP monitor input
     */
    .tlp_hdr(rx_cpl_tlp_hdr),
    .tlp_valid(rx_cpl_tlp_valid),
    .tlp_sop(rx_cpl_tlp_sop),
    .tlp_eop(rx_cpl_tlp_eop),

    /*
     * Statistics outputs
     */
    .stat_tlp_mem_rd(stat_rx_cpl_tlp_mem_rd),
    .stat_tlp_mem_wr(stat_rx_cpl_tlp_mem_wr),
    .stat_tlp_io(stat_rx_cpl_tlp_io),
    .stat_tlp_cfg(stat_rx_cpl_tlp_cfg),
    .stat_tlp_msg(stat_rx_cpl_tlp_msg),
    .stat_tlp_cpl(stat_rx_cpl_tlp_cpl),
    .stat_tlp_cpl_ur(stat_rx_cpl_tlp_cpl_ur),
    .stat_tlp_cpl_ca(stat_rx_cpl_tlp_cpl_ca),
    .stat_tlp_atomic(stat_rx_cpl_tlp_atomic),
    .stat_tlp_ep(stat_rx_cpl_tlp_ep),
    .stat_tlp_hdr_dw(stat_rx_cpl_tlp_hdr_dw),
    .stat_tlp_req_dw(stat_rx_cpl_tlp_req_dw),
    .stat_tlp_payload_dw(stat_rx_cpl_tlp_payload_dw),
    .stat_tlp_cpl_dw(stat_rx_cpl_tlp_cpl_dw)
);

wire [12:0] stat_rx_tlp_mem_rd_inc = stat_rx_req_tlp_mem_rd;
wire [12:0] stat_rx_tlp_mem_wr_inc = stat_rx_req_tlp_mem_wr;
wire [12:0] stat_rx_tlp_io_inc = stat_rx_req_tlp_io;
wire [12:0] stat_rx_tlp_cfg_inc = stat_rx_req_tlp_cfg;
wire [12:0] stat_rx_tlp_msg_inc = stat_rx_req_tlp_msg;
wire [12:0] stat_rx_tlp_cpl_inc = stat_rx_cpl_tlp_cpl;
wire [12:0] stat_rx_tlp_cpl_ur_inc = stat_rx_cpl_tlp_cpl_ur;
wire [12:0] stat_rx_tlp_cpl_ca_inc = stat_rx_cpl_tlp_cpl_ca;
wire [12:0] stat_rx_tlp_atomic_inc = stat_rx_req_tlp_atomic;
wire [12:0] stat_rx_tlp_ep_inc = stat_rx_req_tlp_ep + stat_rx_cpl_tlp_ep;
wire [12:0] stat_rx_tlp_hdr_dw_inc = stat_rx_req_tlp_hdr_dw + stat_rx_cpl_tlp_hdr_dw;
wire [12:0] stat_rx_tlp_req_dw_inc = stat_rx_req_tlp_req_dw;
wire [12:0] stat_rx_tlp_payload_dw_inc = stat_rx_req_tlp_payload_dw;
wire [12:0] stat_rx_tlp_cpl_dw_inc = stat_rx_cpl_tlp_cpl_dw;

wire stat_tx_rd_req_tlp_mem_rd;
wire stat_tx_rd_req_tlp_mem_wr;
wire stat_tx_rd_req_tlp_io;
wire stat_tx_rd_req_tlp_cfg;
wire stat_tx_rd_req_tlp_msg;
wire stat_tx_rd_req_tlp_cpl;
wire stat_tx_rd_req_tlp_cpl_ur;
wire stat_tx_rd_req_tlp_cpl_ca;
wire stat_tx_rd_req_tlp_atomic;
wire stat_tx_rd_req_tlp_ep;
wire [2:0] stat_tx_rd_req_tlp_hdr_dw;
wire [10:0] stat_tx_rd_req_tlp_req_dw;
wire [10:0] stat_tx_rd_req_tlp_payload_dw;
wire [10:0] stat_tx_rd_req_tlp_cpl_dw;

stats_pcie_tlp #(
    .TLP_SEG_COUNT(TLP_SEG_COUNT),
    .TLP_SEG_HDR_WIDTH(TLP_SEG_HDR_WIDTH)
)
stats_pcie_tx_rd_req_tlp_inst (
    .clk(clk),
    .rst(rst),

    /*
     * TLP monitor input
     */
    .tlp_hdr(tx_rd_req_tlp_hdr),
    .tlp_valid(tx_rd_req_tlp_valid),
    .tlp_sop(tx_rd_req_tlp_sop),
    .tlp_eop(tx_rd_req_tlp_eop),

    /*
     * Statistics outputs
     */
    .stat_tlp_mem_rd(stat_tx_rd_req_tlp_mem_rd),
    .stat_tlp_mem_wr(stat_tx_rd_req_tlp_mem_wr),
    .stat_tlp_io(stat_tx_rd_req_tlp_io),
    .stat_tlp_cfg(stat_tx_rd_req_tlp_cfg),
    .stat_tlp_msg(stat_tx_rd_req_tlp_msg),
    .stat_tlp_cpl(stat_tx_rd_req_tlp_cpl),
    .stat_tlp_cpl_ur(stat_tx_rd_req_tlp_cpl_ur),
    .stat_tlp_cpl_ca(stat_tx_rd_req_tlp_cpl_ca),
    .stat_tlp_atomic(stat_tx_rd_req_tlp_atomic),
    .stat_tlp_ep(stat_tx_rd_req_tlp_ep),
    .stat_tlp_hdr_dw(stat_tx_rd_req_tlp_hdr_dw),
    .stat_tlp_req_dw(stat_tx_rd_req_tlp_req_dw),
    .stat_tlp_payload_dw(stat_tx_rd_req_tlp_payload_dw),
    .stat_tlp_cpl_dw(stat_tx_rd_req_tlp_cpl_dw)
);

wire stat_tx_wr_req_tlp_mem_rd;
wire stat_tx_wr_req_tlp_mem_wr;
wire stat_tx_wr_req_tlp_io;
wire stat_tx_wr_req_tlp_cfg;
wire stat_tx_wr_req_tlp_msg;
wire stat_tx_wr_req_tlp_cpl;
wire stat_tx_wr_req_tlp_cpl_ur;
wire stat_tx_wr_req_tlp_cpl_ca;
wire stat_tx_wr_req_tlp_atomic;
wire stat_tx_wr_req_tlp_ep;
wire [2:0] stat_tx_wr_req_tlp_hdr_dw;
wire [10:0] stat_tx_wr_req_tlp_req_dw;
wire [10:0] stat_tx_wr_req_tlp_payload_dw;
wire [10:0] stat_tx_wr_req_tlp_cpl_dw;

stats_pcie_tlp #(
    .TLP_SEG_COUNT(TLP_SEG_COUNT),
    .TLP_SEG_HDR_WIDTH(TLP_SEG_HDR_WIDTH)
)
stats_pcie_tx_wr_req_tlp_inst (
    .clk(clk),
    .rst(rst),

    /*
     * TLP monitor input
     */
    .tlp_hdr(tx_wr_req_tlp_hdr),
    .tlp_valid(tx_wr_req_tlp_valid),
    .tlp_sop(tx_wr_req_tlp_sop),
    .tlp_eop(tx_wr_req_tlp_eop),

    /*
     * Statistics outputs
     */
    .stat_tlp_mem_rd(stat_tx_wr_req_tlp_mem_rd),
    .stat_tlp_mem_wr(stat_tx_wr_req_tlp_mem_wr),
    .stat_tlp_io(stat_tx_wr_req_tlp_io),
    .stat_tlp_cfg(stat_tx_wr_req_tlp_cfg),
    .stat_tlp_msg(stat_tx_wr_req_tlp_msg),
    .stat_tlp_cpl(stat_tx_wr_req_tlp_cpl),
    .stat_tlp_cpl_ur(stat_tx_wr_req_tlp_cpl_ur),
    .stat_tlp_cpl_ca(stat_tx_wr_req_tlp_cpl_ca),
    .stat_tlp_atomic(stat_tx_wr_req_tlp_atomic),
    .stat_tlp_ep(stat_tx_wr_req_tlp_ep),
    .stat_tlp_hdr_dw(stat_tx_wr_req_tlp_hdr_dw),
    .stat_tlp_req_dw(stat_tx_wr_req_tlp_req_dw),
    .stat_tlp_payload_dw(stat_tx_wr_req_tlp_payload_dw),
    .stat_tlp_cpl_dw(stat_tx_wr_req_tlp_cpl_dw)
);

wire stat_tx_cpl_tlp_mem_rd;
wire stat_tx_cpl_tlp_mem_wr;
wire stat_tx_cpl_tlp_io;
wire stat_tx_cpl_tlp_cfg;
wire stat_tx_cpl_tlp_msg;
wire stat_tx_cpl_tlp_cpl;
wire stat_tx_cpl_tlp_cpl_ur;
wire stat_tx_cpl_tlp_cpl_ca;
wire stat_tx_cpl_tlp_atomic;
wire stat_tx_cpl_tlp_ep;
wire [2:0] stat_tx_cpl_tlp_hdr_dw;
wire [10:0] stat_tx_cpl_tlp_req_dw;
wire [10:0] stat_tx_cpl_tlp_payload_dw;
wire [10:0] stat_tx_cpl_tlp_cpl_dw;

stats_pcie_tlp #(
    .TLP_SEG_COUNT(TLP_SEG_COUNT),
    .TLP_SEG_HDR_WIDTH(TLP_SEG_HDR_WIDTH)
)
stats_pcie_tx_cpl_tlp_inst (
    .clk(clk),
    .rst(rst),

    /*
     * TLP monitor input
     */
    .tlp_hdr(tx_cpl_tlp_hdr),
    .tlp_valid(tx_cpl_tlp_valid),
    .tlp_sop(tx_cpl_tlp_sop),
    .tlp_eop(tx_cpl_tlp_eop),

    /*
     * Statistics outputs
     */
    .stat_tlp_mem_rd(stat_tx_cpl_tlp_mem_rd),
    .stat_tlp_mem_wr(stat_tx_cpl_tlp_mem_wr),
    .stat_tlp_io(stat_tx_cpl_tlp_io),
    .stat_tlp_cfg(stat_tx_cpl_tlp_cfg),
    .stat_tlp_msg(stat_tx_cpl_tlp_msg),
    .stat_tlp_cpl(stat_tx_cpl_tlp_cpl),
    .stat_tlp_cpl_ur(stat_tx_cpl_tlp_cpl_ur),
    .stat_tlp_cpl_ca(stat_tx_cpl_tlp_cpl_ca),
    .stat_tlp_atomic(stat_tx_cpl_tlp_atomic),
    .stat_tlp_ep(stat_tx_cpl_tlp_ep),
    .stat_tlp_hdr_dw(stat_tx_cpl_tlp_hdr_dw),
    .stat_tlp_req_dw(stat_tx_cpl_tlp_req_dw),
    .stat_tlp_payload_dw(stat_tx_cpl_tlp_payload_dw),
    .stat_tlp_cpl_dw(stat_tx_cpl_tlp_cpl_dw)
);

wire [12:0] stat_tx_tlp_mem_rd_inc = stat_tx_rd_req_tlp_mem_rd;
wire [12:0] stat_tx_tlp_mem_wr_inc = stat_tx_wr_req_tlp_mem_wr;
wire [12:0] stat_tx_tlp_io_inc = 0;
wire [12:0] stat_tx_tlp_cfg_inc = 0;
wire [12:0] stat_tx_tlp_msg_inc = 0;
wire [12:0] stat_tx_tlp_cpl_inc = stat_tx_cpl_tlp_cpl;
wire [12:0] stat_tx_tlp_cpl_ur_inc = stat_tx_cpl_tlp_cpl_ur;
wire [12:0] stat_tx_tlp_cpl_ca_inc = stat_tx_cpl_tlp_cpl_ca;
wire [12:0] stat_tx_tlp_atomic_inc = 0;
wire [12:0] stat_tx_tlp_ep_inc = 0;
wire [12:0] stat_tx_tlp_hdr_dw_inc = stat_tx_rd_req_tlp_hdr_dw + stat_tx_wr_req_tlp_hdr_dw + stat_tx_cpl_tlp_hdr_dw;
wire [12:0] stat_tx_tlp_req_dw_inc = stat_tx_rd_req_tlp_req_dw;
wire [12:0] stat_tx_tlp_payload_dw_inc = stat_tx_wr_req_tlp_payload_dw;
wire [12:0] stat_tx_tlp_cpl_dw_inc = stat_tx_cpl_tlp_cpl_dw;

stats_collect #(
    .COUNT(32),
    .INC_WIDTH(13),
    .STAT_INC_WIDTH(STAT_INC_WIDTH),
    .STAT_ID_WIDTH(5),
    .UPDATE_PERIOD(UPDATE_PERIOD)
)
stats_collect_inst (
    .clk(clk),
    .rst(rst),

    /*
     * Increment inputs
     */
    .stat_inc({
        13'd0,                       // index 31
        13'd0,                       // index 30
        stat_tx_tlp_cpl_dw_inc,      // index 29
        stat_tx_tlp_payload_dw_inc,  // index 28
        stat_tx_tlp_req_dw_inc,      // index 27
        stat_tx_tlp_hdr_dw_inc,      // index 26
        stat_tx_tlp_ep_inc,          // index 25
        stat_tx_tlp_atomic_inc,      // index 24
        stat_tx_tlp_cpl_ca_inc,      // index 23
        stat_tx_tlp_cpl_ur_inc,      // index 22
        stat_tx_tlp_cpl_inc,         // index 21
        stat_tx_tlp_msg_inc,         // index 20
        stat_tx_tlp_cfg_inc,         // index 19
        stat_tx_tlp_io_inc,          // index 18
        stat_tx_tlp_mem_wr_inc,      // index 17
        stat_tx_tlp_mem_rd_inc,      // index 16
        13'd0,                       // index 15
        13'd0,                       // index 14
        stat_rx_tlp_cpl_dw_inc,      // index 13
        stat_rx_tlp_payload_dw_inc,  // index 12
        stat_rx_tlp_req_dw_inc,      // index 11
        stat_rx_tlp_hdr_dw_inc,      // index 10
        stat_rx_tlp_ep_inc,          // index 9
        stat_rx_tlp_atomic_inc,      // index 8
        stat_rx_tlp_cpl_ca_inc,      // index 7
        stat_rx_tlp_cpl_ur_inc,      // index 6
        stat_rx_tlp_cpl_inc,         // index 5
        stat_rx_tlp_msg_inc,         // index 4
        stat_rx_tlp_cfg_inc,         // index 3
        stat_rx_tlp_io_inc,          // index 2
        stat_rx_tlp_mem_wr_inc,      // index 1
        stat_rx_tlp_mem_rd_inc       // index 0
    }),
    .stat_valid({32{1'b1}}),

    /*
     * Statistics increment output
     */
    .m_axis_stat_tdata(m_axis_stat_tdata),
    .m_axis_stat_tid(m_axis_stat_tid),
    .m_axis_stat_tvalid(m_axis_stat_tvalid),
    .m_axis_stat_tready(m_axis_stat_tready),

    /*
     * Control inputs
     */
    .update(update)
);

endmodule

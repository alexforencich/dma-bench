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
 * PCIe DMA benchmark
 */
module dma_bench_pcie #
(
    // TLP segment count
    parameter TLP_SEG_COUNT = 1,
    // TLP segment data width
    parameter TLP_SEG_DATA_WIDTH = 256,
    // TLP segment strobe width
    parameter TLP_SEG_STRB_WIDTH = TLP_SEG_DATA_WIDTH/32,
    // TLP segment header width
    parameter TLP_SEG_HDR_WIDTH = 128,
    // TX sequence number count
    parameter TX_SEQ_NUM_COUNT = 1,
    // TX sequence number width
    parameter TX_SEQ_NUM_WIDTH = 5,
    // TX sequence number tracking enable
    parameter TX_SEQ_NUM_ENABLE = 0,
    // PCIe tag count
    parameter PCIE_TAG_COUNT = 256,
    // Operation table size (read)
    parameter PCIE_DMA_READ_OP_TABLE_SIZE = PCIE_TAG_COUNT,
    // In-flight transmit limit (read)
    parameter PCIE_DMA_READ_TX_LIMIT = 2**TX_SEQ_NUM_WIDTH,
    // Transmit flow control (read)
    parameter PCIE_DMA_READ_TX_FC_ENABLE = 0,
    // Operation table size (write)
    parameter PCIE_DMA_WRITE_OP_TABLE_SIZE = 2**TX_SEQ_NUM_WIDTH,
    // In-flight transmit limit (write)
    parameter PCIE_DMA_WRITE_TX_LIMIT = 2**TX_SEQ_NUM_WIDTH,
    // Transmit flow control (write)
    parameter PCIE_DMA_WRITE_TX_FC_ENABLE = 0,
    // Force 64 bit address
    parameter TLP_FORCE_64_BIT_ADDR = 0,
    // Requester ID mash
    parameter CHECK_BUS_NUMBER = 1,
    // BAR0 aperture (log2 size)
    parameter BAR0_APERTURE = 24
)
(
    input  wire                                          clk,
    input  wire                                          rst,

    /*
     * TLP input (request)
     */
    input  wire [TLP_SEG_COUNT*TLP_SEG_DATA_WIDTH-1:0]   rx_req_tlp_data,
    input  wire [TLP_SEG_COUNT*TLP_SEG_HDR_WIDTH-1:0]    rx_req_tlp_hdr,
    input  wire [TLP_SEG_COUNT-1:0]                      rx_req_tlp_valid,
    input  wire [TLP_SEG_COUNT-1:0]                      rx_req_tlp_sop,
    input  wire [TLP_SEG_COUNT-1:0]                      rx_req_tlp_eop,
    output wire                                          rx_req_tlp_ready,

    /*
     * TLP output (completion)
     */
    output wire [TLP_SEG_COUNT*TLP_SEG_DATA_WIDTH-1:0]   tx_cpl_tlp_data,
    output wire [TLP_SEG_COUNT*TLP_SEG_STRB_WIDTH-1:0]   tx_cpl_tlp_strb,
    output wire [TLP_SEG_COUNT*TLP_SEG_HDR_WIDTH-1:0]    tx_cpl_tlp_hdr,
    output wire [TLP_SEG_COUNT-1:0]                      tx_cpl_tlp_valid,
    output wire [TLP_SEG_COUNT-1:0]                      tx_cpl_tlp_sop,
    output wire [TLP_SEG_COUNT-1:0]                      tx_cpl_tlp_eop,
    input  wire                                          tx_cpl_tlp_ready,

    /*
     * TLP input (completion)
     */
    input  wire [TLP_SEG_COUNT*TLP_SEG_DATA_WIDTH-1:0]   rx_cpl_tlp_data,
    input  wire [TLP_SEG_COUNT*TLP_SEG_HDR_WIDTH-1:0]    rx_cpl_tlp_hdr,
    input  wire [TLP_SEG_COUNT*4-1:0]                    rx_cpl_tlp_error,
    input  wire [TLP_SEG_COUNT-1:0]                      rx_cpl_tlp_valid,
    input  wire [TLP_SEG_COUNT-1:0]                      rx_cpl_tlp_sop,
    input  wire [TLP_SEG_COUNT-1:0]                      rx_cpl_tlp_eop,
    output wire                                          rx_cpl_tlp_ready,

    /*
     * TLP output (read request)
     */
    output wire [TLP_SEG_COUNT*TLP_SEG_HDR_WIDTH-1:0]    tx_rd_req_tlp_hdr,
    output wire [TLP_SEG_COUNT*TX_SEQ_NUM_WIDTH-1:0]     tx_rd_req_tlp_seq,
    output wire [TLP_SEG_COUNT-1:0]                      tx_rd_req_tlp_valid,
    output wire [TLP_SEG_COUNT-1:0]                      tx_rd_req_tlp_sop,
    output wire [TLP_SEG_COUNT-1:0]                      tx_rd_req_tlp_eop,
    input  wire                                          tx_rd_req_tlp_ready,

    /*
     * TLP output (write request)
     */
    output wire [TLP_SEG_COUNT*TLP_SEG_DATA_WIDTH-1:0]   tx_wr_req_tlp_data,
    output wire [TLP_SEG_COUNT*TLP_SEG_STRB_WIDTH-1:0]   tx_wr_req_tlp_strb,
    output wire [TLP_SEG_COUNT*TLP_SEG_HDR_WIDTH-1:0]    tx_wr_req_tlp_hdr,
    output wire [TLP_SEG_COUNT*TX_SEQ_NUM_WIDTH-1:0]     tx_wr_req_tlp_seq,
    output wire [TLP_SEG_COUNT-1:0]                      tx_wr_req_tlp_valid,
    output wire [TLP_SEG_COUNT-1:0]                      tx_wr_req_tlp_sop,
    output wire [TLP_SEG_COUNT-1:0]                      tx_wr_req_tlp_eop,
    input  wire                                          tx_wr_req_tlp_ready,

    /*
     * Transmit sequence number input
     */
    input  wire [TX_SEQ_NUM_COUNT*TX_SEQ_NUM_WIDTH-1:0]  s_axis_rd_req_tx_seq_num,
    input  wire [TX_SEQ_NUM_COUNT-1:0]                   s_axis_rd_req_tx_seq_num_valid,
    input  wire [TX_SEQ_NUM_COUNT*TX_SEQ_NUM_WIDTH-1:0]  s_axis_wr_req_tx_seq_num,
    input  wire [TX_SEQ_NUM_COUNT-1:0]                   s_axis_wr_req_tx_seq_num_valid,

    /*
     * Transmit flow control
     */
    input  wire [7:0]                                    pcie_tx_fc_ph_av,
    input  wire [11:0]                                   pcie_tx_fc_pd_av,
    input  wire [7:0]                                    pcie_tx_fc_nph_av,

    /*
     * Configuration
     */
    input  wire [7:0]                                    bus_num,
    input  wire                                          ext_tag_enable,
    input  wire [2:0]                                    max_read_request_size,
    input  wire [2:0]                                    max_payload_size,

    /*
     * Status
     */
    output wire                                          status_error_cor,
    output wire                                          status_error_uncor,

    /*
     * MSI request outputs
     */
    output wire [31:0]                                   msi_irq
);

parameter AXIL_DATA_WIDTH = 32;
parameter AXIL_ADDR_WIDTH = BAR0_APERTURE;
parameter AXIL_STRB_WIDTH = (AXIL_DATA_WIDTH/8);

parameter RAM_SEG_COUNT = TLP_SEG_COUNT*2;
parameter RAM_SEG_DATA_WIDTH = (TLP_SEG_COUNT*TLP_SEG_DATA_WIDTH)*2/RAM_SEG_COUNT;
parameter RAM_SEG_ADDR_WIDTH = 10;
parameter RAM_SEG_BE_WIDTH = RAM_SEG_DATA_WIDTH/8;
parameter RAM_SEL_WIDTH = 2;
parameter RAM_ADDR_WIDTH = RAM_SEG_ADDR_WIDTH+$clog2(RAM_SEG_COUNT)+$clog2(RAM_SEG_BE_WIDTH);

parameter PCIE_ADDR_WIDTH = 64;
parameter DMA_LEN_WIDTH = 16;
parameter DMA_TAG_WIDTH = 8;

wire [AXIL_ADDR_WIDTH-1:0]  axil_ctrl_awaddr;
wire [2:0]                  axil_ctrl_awprot;
wire                        axil_ctrl_awvalid;
wire                        axil_ctrl_awready;
wire [AXIL_DATA_WIDTH-1:0]  axil_ctrl_wdata;
wire [AXIL_STRB_WIDTH-1:0]  axil_ctrl_wstrb;
wire                        axil_ctrl_wvalid;
wire                        axil_ctrl_wready;
wire [1:0]                  axil_ctrl_bresp;
wire                        axil_ctrl_bvalid;
wire                        axil_ctrl_bready;
wire [AXIL_ADDR_WIDTH-1:0]  axil_ctrl_araddr;
wire [2:0]                  axil_ctrl_arprot;
wire                        axil_ctrl_arvalid;
wire                        axil_ctrl_arready;
wire [AXIL_DATA_WIDTH-1:0]  axil_ctrl_rdata;
wire [1:0]                  axil_ctrl_rresp;
wire                        axil_ctrl_rvalid;
wire                        axil_ctrl_rready;

wire [PCIE_ADDR_WIDTH-1:0]  axis_dma_read_desc_dma_addr;
wire [RAM_SEL_WIDTH-1:0]    axis_dma_read_desc_ram_sel;
wire [RAM_ADDR_WIDTH-1:0]   axis_dma_read_desc_ram_addr;
wire [DMA_LEN_WIDTH-1:0]    axis_dma_read_desc_len;
wire [DMA_TAG_WIDTH-1:0]    axis_dma_read_desc_tag;
wire                        axis_dma_read_desc_valid;
wire                        axis_dma_read_desc_ready;

wire [DMA_TAG_WIDTH-1:0]    axis_dma_read_desc_status_tag;
wire [3:0]                  axis_dma_read_desc_status_error;
wire                        axis_dma_read_desc_status_valid;

wire [PCIE_ADDR_WIDTH-1:0]  axis_dma_write_desc_dma_addr;
wire [RAM_SEL_WIDTH-1:0]    axis_dma_write_desc_ram_sel;
wire [RAM_ADDR_WIDTH-1:0]   axis_dma_write_desc_ram_addr;
wire [DMA_LEN_WIDTH-1:0]    axis_dma_write_desc_len;
wire [DMA_TAG_WIDTH-1:0]    axis_dma_write_desc_tag;
wire                        axis_dma_write_desc_valid;
wire                        axis_dma_write_desc_ready;

wire [DMA_TAG_WIDTH-1:0]    axis_dma_write_desc_status_tag;
wire [3:0]                  axis_dma_write_desc_status_error;
wire                        axis_dma_write_desc_status_valid;

wire [RAM_SEG_COUNT*RAM_SEL_WIDTH-1:0]       ram_rd_cmd_sel;
wire [RAM_SEG_COUNT*RAM_SEG_ADDR_WIDTH-1:0]  ram_rd_cmd_addr;
wire [RAM_SEG_COUNT-1:0]                     ram_rd_cmd_valid;
wire [RAM_SEG_COUNT-1:0]                     ram_rd_cmd_ready;
wire [RAM_SEG_COUNT*RAM_SEG_DATA_WIDTH-1:0]  ram_rd_resp_data;
wire [RAM_SEG_COUNT-1:0]                     ram_rd_resp_valid;
wire [RAM_SEG_COUNT-1:0]                     ram_rd_resp_ready;
wire [RAM_SEG_COUNT*RAM_SEL_WIDTH-1:0]       ram_wr_cmd_sel;
wire [RAM_SEG_COUNT*RAM_SEG_BE_WIDTH-1:0]    ram_wr_cmd_be;
wire [RAM_SEG_COUNT*RAM_SEG_ADDR_WIDTH-1:0]  ram_wr_cmd_addr;
wire [RAM_SEG_COUNT*RAM_SEG_DATA_WIDTH-1:0]  ram_wr_cmd_data;
wire [RAM_SEG_COUNT-1:0]                     ram_wr_cmd_valid;
wire [RAM_SEG_COUNT-1:0]                     ram_wr_cmd_ready;
wire [RAM_SEG_COUNT-1:0]                     ram_wr_done;

wire [1:0] status_error_cor_int;
wire [1:0] status_error_uncor_int;

pcie_axil_master #(
    .TLP_SEG_COUNT(TLP_SEG_COUNT),
    .TLP_SEG_DATA_WIDTH(TLP_SEG_DATA_WIDTH),
    .TLP_SEG_STRB_WIDTH(TLP_SEG_STRB_WIDTH),
    .TLP_SEG_HDR_WIDTH(TLP_SEG_HDR_WIDTH),
    .AXIL_DATA_WIDTH(AXIL_DATA_WIDTH),
    .AXIL_ADDR_WIDTH(AXIL_ADDR_WIDTH),
    .AXIL_STRB_WIDTH(AXIL_STRB_WIDTH),
    .TLP_FORCE_64_BIT_ADDR(TLP_FORCE_64_BIT_ADDR)
)
pcie_axil_master_inst (
    .clk(clk),
    .rst(rst),

    /*
     * TLP input (request)
     */
    .rx_req_tlp_data(rx_req_tlp_data),
    .rx_req_tlp_hdr(rx_req_tlp_hdr),
    .rx_req_tlp_valid(rx_req_tlp_valid),
    .rx_req_tlp_sop(rx_req_tlp_sop),
    .rx_req_tlp_eop(rx_req_tlp_eop),
    .rx_req_tlp_ready(rx_req_tlp_ready),

    /*
     * TLP output (completion)
     */
    .tx_cpl_tlp_data(tx_cpl_tlp_data),
    .tx_cpl_tlp_strb(tx_cpl_tlp_strb),
    .tx_cpl_tlp_hdr(tx_cpl_tlp_hdr),
    .tx_cpl_tlp_valid(tx_cpl_tlp_valid),
    .tx_cpl_tlp_sop(tx_cpl_tlp_sop),
    .tx_cpl_tlp_eop(tx_cpl_tlp_eop),
    .tx_cpl_tlp_ready(tx_cpl_tlp_ready),

    /*
     * AXI Lite Master output
     */
    .m_axil_awaddr(axil_ctrl_awaddr),
    .m_axil_awprot(axil_ctrl_awprot),
    .m_axil_awvalid(axil_ctrl_awvalid),
    .m_axil_awready(axil_ctrl_awready),
    .m_axil_wdata(axil_ctrl_wdata),
    .m_axil_wstrb(axil_ctrl_wstrb),
    .m_axil_wvalid(axil_ctrl_wvalid),
    .m_axil_wready(axil_ctrl_wready),
    .m_axil_bresp(axil_ctrl_bresp),
    .m_axil_bvalid(axil_ctrl_bvalid),
    .m_axil_bready(axil_ctrl_bready),
    .m_axil_araddr(axil_ctrl_araddr),
    .m_axil_arprot(axil_ctrl_arprot),
    .m_axil_arvalid(axil_ctrl_arvalid),
    .m_axil_arready(axil_ctrl_arready),
    .m_axil_rdata(axil_ctrl_rdata),
    .m_axil_rresp(axil_ctrl_rresp),
    .m_axil_rvalid(axil_ctrl_rvalid),
    .m_axil_rready(axil_ctrl_rready),

    /*
     * Configuration
     */
    .completer_id({bus_num, 5'd0, 3'd0}),

    /*
     * Status
     */
    .status_error_cor(status_error_cor_int[0]),
    .status_error_uncor(status_error_uncor_int[0])
);

wire [$clog2(PCIE_DMA_READ_OP_TABLE_SIZE)-1:0] stat_rd_op_start_tag;
wire [DMA_LEN_WIDTH-1:0] stat_rd_op_start_len;
wire stat_rd_op_start_valid;
wire [$clog2(PCIE_DMA_READ_OP_TABLE_SIZE)-1:0] stat_rd_op_finish_tag;
wire [3:0] stat_rd_op_finish_status;
wire stat_rd_op_finish_valid;
wire [$clog2(PCIE_TAG_COUNT)-1:0] stat_rd_req_start_tag;
wire [12:0] stat_rd_req_start_len;
wire stat_rd_req_start_valid;
wire [$clog2(PCIE_TAG_COUNT)-1:0] stat_rd_req_finish_tag;
wire [3:0] stat_rd_req_finish_status;
wire stat_rd_req_finish_valid;
wire stat_rd_req_timeout;
wire stat_rd_op_table_full;
wire stat_rd_no_tags;
wire stat_rd_tx_no_credit;
wire stat_rd_tx_limit;
wire stat_rd_tx_stall;
wire [$clog2(PCIE_DMA_WRITE_OP_TABLE_SIZE)-1:0] stat_wr_op_start_tag;
wire [DMA_LEN_WIDTH-1:0] stat_wr_op_start_len;
wire stat_wr_op_start_valid;
wire [$clog2(PCIE_DMA_WRITE_OP_TABLE_SIZE)-1:0] stat_wr_op_finish_tag;
wire [3:0] stat_wr_op_finish_status;
wire stat_wr_op_finish_valid;
wire [$clog2(PCIE_DMA_WRITE_OP_TABLE_SIZE)-1:0] stat_wr_req_start_tag;
wire [12:0] stat_wr_req_start_len;
wire stat_wr_req_start_valid;
wire [$clog2(PCIE_DMA_WRITE_OP_TABLE_SIZE)-1:0] stat_wr_req_finish_tag;
wire [3:0] stat_wr_req_finish_status;
wire stat_wr_req_finish_valid;
wire stat_wr_op_table_full;
wire stat_wr_tx_no_credit;
wire stat_wr_tx_limit;
wire stat_wr_tx_stall;

dma_if_pcie #(
    .TLP_SEG_COUNT(TLP_SEG_COUNT),
    .TLP_SEG_DATA_WIDTH(TLP_SEG_DATA_WIDTH),
    .TLP_SEG_STRB_WIDTH(TLP_SEG_STRB_WIDTH),
    .TLP_SEG_HDR_WIDTH(TLP_SEG_HDR_WIDTH),
    .TX_SEQ_NUM_COUNT(TX_SEQ_NUM_COUNT),
    .TX_SEQ_NUM_WIDTH(TX_SEQ_NUM_WIDTH),
    .TX_SEQ_NUM_ENABLE(TX_SEQ_NUM_ENABLE),
    .RAM_SEG_COUNT(RAM_SEG_COUNT),
    .RAM_SEG_DATA_WIDTH(RAM_SEG_DATA_WIDTH),
    .RAM_SEG_ADDR_WIDTH(RAM_SEG_ADDR_WIDTH),
    .RAM_SEG_BE_WIDTH(RAM_SEG_BE_WIDTH),
    .RAM_SEL_WIDTH(RAM_SEL_WIDTH),
    .RAM_ADDR_WIDTH(RAM_ADDR_WIDTH),
    .PCIE_ADDR_WIDTH(PCIE_ADDR_WIDTH),
    .PCIE_TAG_COUNT(PCIE_TAG_COUNT),
    .LEN_WIDTH(DMA_LEN_WIDTH),
    .TAG_WIDTH(DMA_TAG_WIDTH),
    .READ_OP_TABLE_SIZE(PCIE_DMA_READ_OP_TABLE_SIZE),
    .READ_TX_LIMIT(PCIE_DMA_READ_TX_LIMIT),
    .READ_TX_FC_ENABLE(PCIE_DMA_READ_TX_FC_ENABLE),
    .WRITE_OP_TABLE_SIZE(PCIE_DMA_WRITE_OP_TABLE_SIZE),
    .WRITE_TX_LIMIT(PCIE_DMA_WRITE_TX_LIMIT),
    .WRITE_TX_FC_ENABLE(PCIE_DMA_WRITE_TX_FC_ENABLE),
    .TLP_FORCE_64_BIT_ADDR(TLP_FORCE_64_BIT_ADDR),
    .CHECK_BUS_NUMBER(CHECK_BUS_NUMBER)
)
dma_if_pcie_inst (
    .clk(clk),
    .rst(rst),

    /*
     * TLP input (completion)
     */
    .rx_cpl_tlp_data(rx_cpl_tlp_data),
    .rx_cpl_tlp_hdr(rx_cpl_tlp_hdr),
    .rx_cpl_tlp_error(rx_cpl_tlp_error),
    .rx_cpl_tlp_valid(rx_cpl_tlp_valid),
    .rx_cpl_tlp_sop(rx_cpl_tlp_sop),
    .rx_cpl_tlp_eop(rx_cpl_tlp_eop),
    .rx_cpl_tlp_ready(rx_cpl_tlp_ready),

    /*
     * TLP output (read request)
     */
    .tx_rd_req_tlp_hdr(tx_rd_req_tlp_hdr),
    .tx_rd_req_tlp_seq(tx_rd_req_tlp_seq),
    .tx_rd_req_tlp_valid(tx_rd_req_tlp_valid),
    .tx_rd_req_tlp_sop(tx_rd_req_tlp_sop),
    .tx_rd_req_tlp_eop(tx_rd_req_tlp_eop),
    .tx_rd_req_tlp_ready(tx_rd_req_tlp_ready),

    /*
     * TLP output (write request)
     */
    .tx_wr_req_tlp_data(tx_wr_req_tlp_data),
    .tx_wr_req_tlp_strb(tx_wr_req_tlp_strb),
    .tx_wr_req_tlp_hdr(tx_wr_req_tlp_hdr),
    .tx_wr_req_tlp_seq(tx_wr_req_tlp_seq),
    .tx_wr_req_tlp_valid(tx_wr_req_tlp_valid),
    .tx_wr_req_tlp_sop(tx_wr_req_tlp_sop),
    .tx_wr_req_tlp_eop(tx_wr_req_tlp_eop),
    .tx_wr_req_tlp_ready(tx_wr_req_tlp_ready),

    /*
     * Transmit sequence number input
     */
    .s_axis_rd_req_tx_seq_num(s_axis_rd_req_tx_seq_num),
    .s_axis_rd_req_tx_seq_num_valid(s_axis_rd_req_tx_seq_num_valid),
    .s_axis_wr_req_tx_seq_num(s_axis_wr_req_tx_seq_num),
    .s_axis_wr_req_tx_seq_num_valid(s_axis_wr_req_tx_seq_num_valid),

    /*
     * Transmit flow control
     */
    .pcie_tx_fc_ph_av(pcie_tx_fc_ph_av),
    .pcie_tx_fc_pd_av(pcie_tx_fc_pd_av),
    .pcie_tx_fc_nph_av(pcie_tx_fc_nph_av),

    /*
     * AXI read descriptor input
     */
    .s_axis_read_desc_pcie_addr(axis_dma_read_desc_dma_addr),
    .s_axis_read_desc_ram_sel(axis_dma_read_desc_ram_sel),
    .s_axis_read_desc_ram_addr(axis_dma_read_desc_ram_addr),
    .s_axis_read_desc_len(axis_dma_read_desc_len),
    .s_axis_read_desc_tag(axis_dma_read_desc_tag),
    .s_axis_read_desc_valid(axis_dma_read_desc_valid),
    .s_axis_read_desc_ready(axis_dma_read_desc_ready),

    /*
     * AXI read descriptor status output
     */
    .m_axis_read_desc_status_tag(axis_dma_read_desc_status_tag),
    .m_axis_read_desc_status_error(axis_dma_read_desc_status_error),
    .m_axis_read_desc_status_valid(axis_dma_read_desc_status_valid),

    /*
     * AXI write descriptor input
     */
    .s_axis_write_desc_pcie_addr(axis_dma_write_desc_dma_addr),
    .s_axis_write_desc_ram_sel(axis_dma_write_desc_ram_sel),
    .s_axis_write_desc_ram_addr(axis_dma_write_desc_ram_addr),
    .s_axis_write_desc_len(axis_dma_write_desc_len),
    .s_axis_write_desc_tag(axis_dma_write_desc_tag),
    .s_axis_write_desc_valid(axis_dma_write_desc_valid),
    .s_axis_write_desc_ready(axis_dma_write_desc_ready),

    /*
     * AXI write descriptor status output
     */
    .m_axis_write_desc_status_tag(axis_dma_write_desc_status_tag),
    .m_axis_write_desc_status_error(axis_dma_write_desc_status_error),
    .m_axis_write_desc_status_valid(axis_dma_write_desc_status_valid),

    /*
     * RAM interface
     */
    .ram_rd_cmd_sel(ram_rd_cmd_sel),
    .ram_rd_cmd_addr(ram_rd_cmd_addr),
    .ram_rd_cmd_valid(ram_rd_cmd_valid),
    .ram_rd_cmd_ready(ram_rd_cmd_ready),
    .ram_rd_resp_data(ram_rd_resp_data),
    .ram_rd_resp_valid(ram_rd_resp_valid),
    .ram_rd_resp_ready(ram_rd_resp_ready),
    .ram_wr_cmd_sel(ram_wr_cmd_sel),
    .ram_wr_cmd_be(ram_wr_cmd_be),
    .ram_wr_cmd_addr(ram_wr_cmd_addr),
    .ram_wr_cmd_data(ram_wr_cmd_data),
    .ram_wr_cmd_valid(ram_wr_cmd_valid),
    .ram_wr_cmd_ready(ram_wr_cmd_ready),
    .ram_wr_done(ram_wr_done),

    /*
     * Configuration
     */
    .read_enable(1'b1),
    .write_enable(1'b1),
    .ext_tag_enable(ext_tag_enable),
    .requester_id({bus_num, 5'd0, 3'd0}),
    .max_read_request_size(max_read_request_size),
    .max_payload_size(max_payload_size),

    /*
     * Status
     */
    .status_error_cor(status_error_cor_int[1]),
    .status_error_uncor(status_error_uncor_int[1]),

    /*
     * Statistics
     */
    .stat_rd_op_start_tag(stat_rd_op_start_tag),
    .stat_rd_op_start_len(stat_rd_op_start_len),
    .stat_rd_op_start_valid(stat_rd_op_start_valid),
    .stat_rd_op_finish_tag(stat_rd_op_finish_tag),
    .stat_rd_op_finish_status(stat_rd_op_finish_status),
    .stat_rd_op_finish_valid(stat_rd_op_finish_valid),
    .stat_rd_req_start_tag(stat_rd_req_start_tag),
    .stat_rd_req_start_len(stat_rd_req_start_len),
    .stat_rd_req_start_valid(stat_rd_req_start_valid),
    .stat_rd_req_finish_tag(stat_rd_req_finish_tag),
    .stat_rd_req_finish_status(stat_rd_req_finish_status),
    .stat_rd_req_finish_valid(stat_rd_req_finish_valid),
    .stat_rd_req_timeout(stat_rd_req_timeout),
    .stat_rd_op_table_full(stat_rd_op_table_full),
    .stat_rd_no_tags(stat_rd_no_tags),
    .stat_rd_tx_no_credit(stat_rd_tx_no_credit),
    .stat_rd_tx_limit(stat_rd_tx_limit),
    .stat_rd_tx_stall(stat_rd_tx_stall),
    .stat_wr_op_start_tag(stat_wr_op_start_tag),
    .stat_wr_op_start_len(stat_wr_op_start_len),
    .stat_wr_op_start_valid(stat_wr_op_start_valid),
    .stat_wr_op_finish_tag(stat_wr_op_finish_tag),
    .stat_wr_op_finish_status(stat_wr_op_finish_status),
    .stat_wr_op_finish_valid(stat_wr_op_finish_valid),
    .stat_wr_req_start_tag(stat_wr_req_start_tag),
    .stat_wr_req_start_len(stat_wr_req_start_len),
    .stat_wr_req_start_valid(stat_wr_req_start_valid),
    .stat_wr_req_finish_tag(stat_wr_req_finish_tag),
    .stat_wr_req_finish_status(stat_wr_req_finish_status),
    .stat_wr_req_finish_valid(stat_wr_req_finish_valid),
    .stat_wr_op_table_full(stat_wr_op_table_full),
    .stat_wr_tx_no_credit(stat_wr_tx_no_credit),
    .stat_wr_tx_limit(stat_wr_tx_limit),
    .stat_wr_tx_stall(stat_wr_tx_stall)
);

pulse_merge #(
    .INPUT_WIDTH(2),
    .COUNT_WIDTH(4)
)
status_error_cor_pm_inst (
    .clk(clk),
    .rst(rst),

    .pulse_in(status_error_cor_int),
    .count_out(),
    .pulse_out(status_error_cor)
);

pulse_merge #(
    .INPUT_WIDTH(2),
    .COUNT_WIDTH(4)
)
status_error_uncor_pm_inst (
    .clk(clk),
    .rst(rst),

    .pulse_in(status_error_uncor_int),
    .count_out(),
    .pulse_out(status_error_uncor)
);

wire [23:0]  axis_stat_pcie_tdata;
wire [5:0]   axis_stat_pcie_tid;
wire         axis_stat_pcie_tvalid;
wire         axis_stat_pcie_tready;

stats_pcie_if #(
    .TLP_SEG_COUNT(TLP_SEG_COUNT),
    .TLP_SEG_HDR_WIDTH(TLP_SEG_HDR_WIDTH),
    .STAT_INC_WIDTH(24),
    .STAT_ID_WIDTH(5),
    .UPDATE_PERIOD(1024)
)
stats_pcie_if_inst (
    .clk(clk),
    .rst(rst),

    /*
     * monitor input (request to BAR)
     */
    .rx_req_tlp_hdr(rx_req_tlp_hdr),
    .rx_req_tlp_valid(rx_req_tlp_valid && rx_req_tlp_ready),
    .rx_req_tlp_sop(rx_req_tlp_sop),
    .rx_req_tlp_eop(rx_req_tlp_eop),

    /*
     * monitor input (completion to DMA)
     */
    .rx_cpl_tlp_hdr(rx_cpl_tlp_hdr),
    .rx_cpl_tlp_valid(rx_cpl_tlp_valid && rx_cpl_tlp_ready),
    .rx_cpl_tlp_sop(rx_cpl_tlp_sop),
    .rx_cpl_tlp_eop(rx_cpl_tlp_eop),

    /*
     * monitor input (read request from DMA)
     */
    .tx_rd_req_tlp_hdr(tx_rd_req_tlp_hdr),
    .tx_rd_req_tlp_valid(tx_rd_req_tlp_valid && tx_rd_req_tlp_ready),
    .tx_rd_req_tlp_sop(tx_rd_req_tlp_sop),
    .tx_rd_req_tlp_eop(tx_rd_req_tlp_eop),

    /*
     * monitor input (write request from DMA)
     */
    .tx_wr_req_tlp_hdr(tx_wr_req_tlp_hdr),
    .tx_wr_req_tlp_valid(tx_wr_req_tlp_valid && tx_wr_req_tlp_ready),
    .tx_wr_req_tlp_sop(tx_wr_req_tlp_sop),
    .tx_wr_req_tlp_eop(tx_wr_req_tlp_eop),

    /*
     * monitor input (completion from BAR)
     */
    .tx_cpl_tlp_hdr(tx_cpl_tlp_hdr),
    .tx_cpl_tlp_valid(tx_cpl_tlp_valid && tx_cpl_tlp_ready),
    .tx_cpl_tlp_sop(tx_cpl_tlp_sop),
    .tx_cpl_tlp_eop(tx_cpl_tlp_eop),

    /*
     * Statistics output
     */
    .m_axis_stat_tdata(axis_stat_pcie_tdata),
    .m_axis_stat_tid(axis_stat_pcie_tid[4:0]),
    .m_axis_stat_tvalid(axis_stat_pcie_tvalid),
    .m_axis_stat_tready(axis_stat_pcie_tready),

    /*
     * Control inputs
     */
    .update(1'b0)
);

assign axis_stat_pcie_tid[5] = 0;

wire [23:0]  axis_stat_dma_tdata;
wire [5:0]   axis_stat_dma_tid;
wire         axis_stat_dma_tvalid;
wire         axis_stat_dma_tready;

stats_dma_if_pcie #(
    .PCIE_TAG_COUNT(PCIE_TAG_COUNT),
    .LEN_WIDTH(DMA_LEN_WIDTH),
    .READ_OP_TABLE_SIZE(PCIE_DMA_READ_OP_TABLE_SIZE),
    .WRITE_OP_TABLE_SIZE(PCIE_DMA_WRITE_OP_TABLE_SIZE),
    .STAT_INC_WIDTH(24),
    .STAT_ID_WIDTH(5),
    .UPDATE_PERIOD(1024)
)
stats_dma_if_pcie_inst (
    .clk(clk),
    .rst(rst),

    /*
     * Statistics from dma_if_pcie
     */
    .stat_rd_op_start_tag(stat_rd_op_start_tag),
    .stat_rd_op_start_len(stat_rd_op_start_len),
    .stat_rd_op_start_valid(stat_rd_op_start_valid),
    .stat_rd_op_finish_tag(stat_rd_op_finish_tag),
    .stat_rd_op_finish_status(stat_rd_op_finish_status),
    .stat_rd_op_finish_valid(stat_rd_op_finish_valid),
    .stat_rd_req_start_tag(stat_rd_req_start_tag),
    .stat_rd_req_start_len(stat_rd_req_start_len),
    .stat_rd_req_start_valid(stat_rd_req_start_valid),
    .stat_rd_req_finish_tag(stat_rd_req_finish_tag),
    .stat_rd_req_finish_status(stat_rd_req_finish_status),
    .stat_rd_req_finish_valid(stat_rd_req_finish_valid),
    .stat_rd_req_timeout(stat_rd_req_timeout),
    .stat_rd_op_table_full(stat_rd_op_table_full),
    .stat_rd_no_tags(stat_rd_no_tags),
    .stat_rd_tx_no_credit(stat_rd_tx_no_credit),
    .stat_rd_tx_limit(stat_rd_tx_limit),
    .stat_rd_tx_stall(stat_rd_tx_stall),
    .stat_wr_op_start_tag(stat_wr_op_start_tag),
    .stat_wr_op_start_len(stat_wr_op_start_len),
    .stat_wr_op_start_valid(stat_wr_op_start_valid),
    .stat_wr_op_finish_tag(stat_wr_op_finish_tag),
    .stat_wr_op_finish_status(stat_wr_op_finish_status),
    .stat_wr_op_finish_valid(stat_wr_op_finish_valid),
    .stat_wr_req_start_tag(stat_wr_req_start_tag),
    .stat_wr_req_start_len(stat_wr_req_start_len),
    .stat_wr_req_start_valid(stat_wr_req_start_valid),
    .stat_wr_req_finish_tag(stat_wr_req_finish_tag),
    .stat_wr_req_finish_status(stat_wr_req_finish_status),
    .stat_wr_req_finish_valid(stat_wr_req_finish_valid),
    .stat_wr_op_table_full(stat_wr_op_table_full),
    .stat_wr_tx_no_credit(stat_wr_tx_no_credit),
    .stat_wr_tx_limit(stat_wr_tx_limit),
    .stat_wr_tx_stall(stat_wr_tx_stall),

    /*
     * Statistics output
     */
    .m_axis_stat_tdata(axis_stat_dma_tdata),
    .m_axis_stat_tid(axis_stat_dma_tid[4:0]),
    .m_axis_stat_tvalid(axis_stat_dma_tvalid),
    .m_axis_stat_tready(axis_stat_dma_tready),

    /*
     * Control inputs
     */
    .update(1'b0)
);

assign axis_stat_dma_tid[5] = 1;

wire [23:0]  axis_stat_tdata;
wire [5:0]   axis_stat_tid;
wire         axis_stat_tvalid;
wire         axis_stat_tready;

axis_arb_mux #(
    .S_COUNT(2),
    .DATA_WIDTH(24),
    .KEEP_ENABLE(0),
    .ID_ENABLE(1),
    .ID_WIDTH(6),
    .DEST_ENABLE(0),
    .USER_ENABLE(0),
    .LAST_ENABLE(0),
    .ARB_TYPE_ROUND_ROBIN(1),
    .ARB_LSB_HIGH_PRIORITY(1)
)
axis_stat_mux_inst (
    .clk(clk),
    .rst(rst),

    /*
     * AXI Stream inputs
     */
    .s_axis_tdata({axis_stat_dma_tdata, axis_stat_pcie_tdata}),
    .s_axis_tkeep(0),
    .s_axis_tvalid({axis_stat_dma_tvalid, axis_stat_pcie_tvalid}),
    .s_axis_tready({axis_stat_dma_tready, axis_stat_pcie_tready}),
    .s_axis_tlast(0),
    .s_axis_tid({axis_stat_dma_tid, axis_stat_pcie_tid}),
    .s_axis_tdest(0),
    .s_axis_tuser(0),

    /*
     * AXI Stream output
     */
    .m_axis_tdata(axis_stat_tdata),
    .m_axis_tkeep(),
    .m_axis_tvalid(axis_stat_tvalid),
    .m_axis_tready(axis_stat_tready),
    .m_axis_tlast(),
    .m_axis_tid(axis_stat_tid),
    .m_axis_tdest(),
    .m_axis_tuser()
);

dma_bench #(
    .AXIL_DATA_WIDTH(AXIL_DATA_WIDTH),
    .AXIL_ADDR_WIDTH(AXIL_ADDR_WIDTH),
    .AXIL_STRB_WIDTH(AXIL_STRB_WIDTH),
    .DMA_ADDR_WIDTH(PCIE_ADDR_WIDTH),
    .DMA_LEN_WIDTH(DMA_LEN_WIDTH),
    .DMA_TAG_WIDTH(DMA_TAG_WIDTH),
    .RAM_SEG_COUNT(RAM_SEG_COUNT),
    .RAM_SEG_DATA_WIDTH(RAM_SEG_DATA_WIDTH),
    .RAM_SEG_ADDR_WIDTH(RAM_SEG_ADDR_WIDTH),
    .RAM_SEG_BE_WIDTH(RAM_SEG_BE_WIDTH),
    .RAM_SEL_WIDTH(RAM_SEL_WIDTH),
    .RAM_ADDR_WIDTH(RAM_ADDR_WIDTH),
    .STAT_INC_WIDTH(24),
    .STAT_ID_WIDTH(6)
)
dma_bench_inst (
    .clk(clk),
    .rst(rst),

    /*
     * AXI Lite control interface
     */
    .s_axil_ctrl_awaddr(axil_ctrl_awaddr),
    .s_axil_ctrl_awprot(axil_ctrl_awprot),
    .s_axil_ctrl_awvalid(axil_ctrl_awvalid),
    .s_axil_ctrl_awready(axil_ctrl_awready),
    .s_axil_ctrl_wdata(axil_ctrl_wdata),
    .s_axil_ctrl_wstrb(axil_ctrl_wstrb),
    .s_axil_ctrl_wvalid(axil_ctrl_wvalid),
    .s_axil_ctrl_wready(axil_ctrl_wready),
    .s_axil_ctrl_bresp(axil_ctrl_bresp),
    .s_axil_ctrl_bvalid(axil_ctrl_bvalid),
    .s_axil_ctrl_bready(axil_ctrl_bready),
    .s_axil_ctrl_araddr(axil_ctrl_araddr),
    .s_axil_ctrl_arprot(axil_ctrl_arprot),
    .s_axil_ctrl_arvalid(axil_ctrl_arvalid),
    .s_axil_ctrl_arready(axil_ctrl_arready),
    .s_axil_ctrl_rdata(axil_ctrl_rdata),
    .s_axil_ctrl_rresp(axil_ctrl_rresp),
    .s_axil_ctrl_rvalid(axil_ctrl_rvalid),
    .s_axil_ctrl_rready(axil_ctrl_rready),

    /*
     * AXI read descriptor output
     */
    .m_axis_dma_read_desc_dma_addr(axis_dma_read_desc_dma_addr),
    .m_axis_dma_read_desc_ram_sel(axis_dma_read_desc_ram_sel),
    .m_axis_dma_read_desc_ram_addr(axis_dma_read_desc_ram_addr),
    .m_axis_dma_read_desc_len(axis_dma_read_desc_len),
    .m_axis_dma_read_desc_tag(axis_dma_read_desc_tag),
    .m_axis_dma_read_desc_valid(axis_dma_read_desc_valid),
    .m_axis_dma_read_desc_ready(axis_dma_read_desc_ready),

    /*
     * AXI read descriptor status input
     */
    .s_axis_dma_read_desc_status_tag(axis_dma_read_desc_status_tag),
    .s_axis_dma_read_desc_status_error(axis_dma_read_desc_status_error),
    .s_axis_dma_read_desc_status_valid(axis_dma_read_desc_status_valid),

    /*
     * AXI write descriptor output
     */
    .m_axis_dma_write_desc_dma_addr(axis_dma_write_desc_dma_addr),
    .m_axis_dma_write_desc_ram_sel(axis_dma_write_desc_ram_sel),
    .m_axis_dma_write_desc_ram_addr(axis_dma_write_desc_ram_addr),
    .m_axis_dma_write_desc_len(axis_dma_write_desc_len),
    .m_axis_dma_write_desc_tag(axis_dma_write_desc_tag),
    .m_axis_dma_write_desc_valid(axis_dma_write_desc_valid),
    .m_axis_dma_write_desc_ready(axis_dma_write_desc_ready),

    /*
     * AXI write descriptor status input
     */
    .s_axis_dma_write_desc_status_tag(axis_dma_write_desc_status_tag),
    .s_axis_dma_write_desc_status_error(axis_dma_write_desc_status_error),
    .s_axis_dma_write_desc_status_valid(axis_dma_write_desc_status_valid),

    /*
     * RAM interface
     */
    .ram_rd_cmd_sel(ram_rd_cmd_sel),
    .ram_rd_cmd_addr(ram_rd_cmd_addr),
    .ram_rd_cmd_valid(ram_rd_cmd_valid),
    .ram_rd_cmd_ready(ram_rd_cmd_ready),
    .ram_rd_resp_data(ram_rd_resp_data),
    .ram_rd_resp_valid(ram_rd_resp_valid),
    .ram_rd_resp_ready(ram_rd_resp_ready),
    .ram_wr_cmd_sel(ram_wr_cmd_sel),
    .ram_wr_cmd_be(ram_wr_cmd_be),
    .ram_wr_cmd_addr(ram_wr_cmd_addr),
    .ram_wr_cmd_data(ram_wr_cmd_data),
    .ram_wr_cmd_valid(ram_wr_cmd_valid),
    .ram_wr_cmd_ready(ram_wr_cmd_ready),
    .ram_wr_done(ram_wr_done),

    /*
     * MSI request outputs
     */
    .msi_irq(msi_irq),

    /*
     * Statistics input
     */
    .s_axis_stat_tdata(axis_stat_tdata),
    .s_axis_stat_tid(axis_stat_tid),
    .s_axis_stat_tvalid(axis_stat_tvalid),
    .s_axis_stat_tready(axis_stat_tready)
);

endmodule

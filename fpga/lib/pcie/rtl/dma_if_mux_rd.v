/*

Copyright (c) 2019-2021 Alex Forencich

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
 * DMA interface mux (read)
 */
module dma_if_mux_rd #
(
    // Number of ports
    parameter PORTS = 2,
    // RAM segment count
    parameter SEG_COUNT = 2,
    // RAM segment data width
    parameter SEG_DATA_WIDTH = 64,
    // RAM segment address width
    parameter SEG_ADDR_WIDTH = 8,
    // RAM segment byte enable width
    parameter SEG_BE_WIDTH = SEG_DATA_WIDTH/8,
    // Input RAM segment select width
    parameter S_RAM_SEL_WIDTH = 2,
    // Output RAM segment select width
    // Additional bits required for response routing
    parameter M_RAM_SEL_WIDTH = S_RAM_SEL_WIDTH+$clog2(PORTS),
    // RAM address width
    parameter RAM_ADDR_WIDTH = SEG_ADDR_WIDTH+$clog2(SEG_COUNT)+$clog2(SEG_BE_WIDTH),
    // DMA address width
    parameter DMA_ADDR_WIDTH = 64,
    // Length field width
    parameter LEN_WIDTH = 16,
    // Input tag field width
    parameter S_TAG_WIDTH = 8,
    // Output tag field width (towards DMA module)
    // Additional bits required for response routing
    parameter M_TAG_WIDTH = S_TAG_WIDTH+$clog2(PORTS),
    // select round robin arbitration
    parameter ARB_TYPE_ROUND_ROBIN = 0,
    // LSB priority selection
    parameter ARB_LSB_HIGH_PRIORITY = 1
)
(
    input  wire                                       clk,
    input  wire                                       rst,

    /*
     * Read descriptor output (to DMA interface)
     */
    output wire [DMA_ADDR_WIDTH-1:0]                  m_axis_read_desc_dma_addr,
    output wire [M_RAM_SEL_WIDTH-1:0]                 m_axis_read_desc_ram_sel,
    output wire [RAM_ADDR_WIDTH-1:0]                  m_axis_read_desc_ram_addr,
    output wire [LEN_WIDTH-1:0]                       m_axis_read_desc_len,
    output wire [M_TAG_WIDTH-1:0]                     m_axis_read_desc_tag,
    output wire                                       m_axis_read_desc_valid,
    input  wire                                       m_axis_read_desc_ready,

    /*
     * Read descriptor status input (from DMA interface)
     */
    input  wire [M_TAG_WIDTH-1:0]                     s_axis_read_desc_status_tag,
    input  wire [3:0]                                 s_axis_read_desc_status_error,
    input  wire                                       s_axis_read_desc_status_valid,

    /*
     * Read descriptor input
     */
    input  wire [PORTS*DMA_ADDR_WIDTH-1:0]            s_axis_read_desc_dma_addr,
    input  wire [PORTS*S_RAM_SEL_WIDTH-1:0]           s_axis_read_desc_ram_sel,
    input  wire [PORTS*RAM_ADDR_WIDTH-1:0]            s_axis_read_desc_ram_addr,
    input  wire [PORTS*LEN_WIDTH-1:0]                 s_axis_read_desc_len,
    input  wire [PORTS*S_TAG_WIDTH-1:0]               s_axis_read_desc_tag,
    input  wire [PORTS-1:0]                           s_axis_read_desc_valid,
    output wire [PORTS-1:0]                           s_axis_read_desc_ready,

    /*
     * Read descriptor status output
     */
    output wire [PORTS*S_TAG_WIDTH-1:0]               m_axis_read_desc_status_tag,
    output wire [PORTS*4-1:0]                         m_axis_read_desc_status_error,
    output wire [PORTS-1:0]                           m_axis_read_desc_status_valid,

    /*
     * RAM interface (from DMA interface)
     */
    input  wire [SEG_COUNT*M_RAM_SEL_WIDTH-1:0]       if_ram_wr_cmd_sel,
    input  wire [SEG_COUNT*SEG_BE_WIDTH-1:0]          if_ram_wr_cmd_be,
    input  wire [SEG_COUNT*SEG_ADDR_WIDTH-1:0]        if_ram_wr_cmd_addr,
    input  wire [SEG_COUNT*SEG_DATA_WIDTH-1:0]        if_ram_wr_cmd_data,
    input  wire [SEG_COUNT-1:0]                       if_ram_wr_cmd_valid,
    output wire [SEG_COUNT-1:0]                       if_ram_wr_cmd_ready,
    output wire [SEG_COUNT-1:0]                       if_ram_wr_done,

    /*
     * RAM interface
     */
    output wire [PORTS*SEG_COUNT*S_RAM_SEL_WIDTH-1:0] ram_wr_cmd_sel,
    output wire [PORTS*SEG_COUNT*SEG_BE_WIDTH-1:0]    ram_wr_cmd_be,
    output wire [PORTS*SEG_COUNT*SEG_ADDR_WIDTH-1:0]  ram_wr_cmd_addr,
    output wire [PORTS*SEG_COUNT*SEG_DATA_WIDTH-1:0]  ram_wr_cmd_data,
    output wire [PORTS*SEG_COUNT-1:0]                 ram_wr_cmd_valid,
    input  wire [PORTS*SEG_COUNT-1:0]                 ram_wr_cmd_ready,
    input  wire [PORTS*SEG_COUNT-1:0]                 ram_wr_done
);

parameter CL_PORTS = $clog2(PORTS);

parameter S_RAM_SEL_WIDTH_INT = S_RAM_SEL_WIDTH > 0 ? S_RAM_SEL_WIDTH : 1;

parameter FIFO_ADDR_WIDTH = 5;

// check configuration
initial begin
    if (M_TAG_WIDTH < S_TAG_WIDTH+$clog2(PORTS)) begin
        $error("Error: M_TAG_WIDTH must be at least $clog2(PORTS) larger than S_TAG_WIDTH (instance %m)");
        $finish;
    end

    if (M_RAM_SEL_WIDTH < S_RAM_SEL_WIDTH+$clog2(PORTS)) begin
        $error("Error: M_RAM_SEL_WIDTH must be at least $clog2(PORTS) larger than S_RAM_SEL_WIDTH (instance %m)");
        $finish;
    end
end

// descriptor mux
wire [PORTS-1:0] request;
wire [PORTS-1:0] acknowledge;
wire [PORTS-1:0] grant;
wire grant_valid;
wire [CL_PORTS-1:0] grant_encoded;

// internal datapath
reg  [DMA_ADDR_WIDTH-1:0]  m_axis_read_desc_dma_addr_int;
reg  [M_RAM_SEL_WIDTH-1:0] m_axis_read_desc_ram_sel_int;
reg  [RAM_ADDR_WIDTH-1:0]  m_axis_read_desc_ram_addr_int;
reg  [LEN_WIDTH-1:0]       m_axis_read_desc_len_int;
reg  [M_TAG_WIDTH-1:0]     m_axis_read_desc_tag_int;
reg                        m_axis_read_desc_valid_int;
reg                        m_axis_read_desc_ready_int_reg = 1'b0;
wire                       m_axis_read_desc_ready_int_early;

assign s_axis_read_desc_ready = (m_axis_read_desc_ready_int_reg && grant_valid) << grant_encoded;

// mux for incoming packet
wire [DMA_ADDR_WIDTH-1:0]  current_s_desc_dma_addr  = s_axis_read_desc_dma_addr[grant_encoded*DMA_ADDR_WIDTH +: DMA_ADDR_WIDTH];
wire [S_RAM_SEL_WIDTH-1:0] current_s_desc_ram_sel   = s_axis_read_desc_ram_sel[grant_encoded*S_RAM_SEL_WIDTH +: S_RAM_SEL_WIDTH_INT];
wire [RAM_ADDR_WIDTH-1:0]  current_s_desc_ram_addr  = s_axis_read_desc_ram_addr[grant_encoded*RAM_ADDR_WIDTH +: RAM_ADDR_WIDTH];
wire [LEN_WIDTH-1:0]       current_s_desc_len       = s_axis_read_desc_len[grant_encoded*LEN_WIDTH +: LEN_WIDTH];
wire [S_TAG_WIDTH-1:0]     current_s_desc_tag       = s_axis_read_desc_tag[grant_encoded*S_TAG_WIDTH +: S_TAG_WIDTH];
wire                       current_s_desc_valid     = s_axis_read_desc_valid[grant_encoded];
wire                       current_s_desc_ready     = s_axis_read_desc_ready[grant_encoded];

// arbiter instance
arbiter #(
    .PORTS(PORTS),
    .ARB_TYPE_ROUND_ROBIN(ARB_TYPE_ROUND_ROBIN),
    .ARB_BLOCK(1),
    .ARB_BLOCK_ACK(1),
    .ARB_LSB_HIGH_PRIORITY(ARB_LSB_HIGH_PRIORITY)
)
arb_inst (
    .clk(clk),
    .rst(rst),
    .request(request),
    .acknowledge(acknowledge),
    .grant(grant),
    .grant_valid(grant_valid),
    .grant_encoded(grant_encoded)
);

assign request = s_axis_read_desc_valid & ~grant;
assign acknowledge = grant & s_axis_read_desc_valid & s_axis_read_desc_ready;

always @* begin
    // pass through selected packet data
    m_axis_read_desc_dma_addr_int  = current_s_desc_dma_addr;
    if (S_RAM_SEL_WIDTH > 0) begin
        m_axis_read_desc_ram_sel_int = {grant_encoded, current_s_desc_ram_sel};
    end else begin
        m_axis_read_desc_ram_sel_int = grant_encoded;
    end
    m_axis_read_desc_ram_addr_int  = current_s_desc_ram_addr;
    m_axis_read_desc_len_int       = current_s_desc_len;
    m_axis_read_desc_tag_int       = {grant_encoded, current_s_desc_tag};
    m_axis_read_desc_valid_int     = current_s_desc_valid && m_axis_read_desc_ready_int_reg && grant_valid;
end

// output datapath logic
reg [DMA_ADDR_WIDTH-1:0]  m_axis_read_desc_dma_addr_reg  = {DMA_ADDR_WIDTH{1'b0}};
reg [M_RAM_SEL_WIDTH-1:0] m_axis_read_desc_ram_sel_reg   = {M_RAM_SEL_WIDTH{1'b0}};
reg [RAM_ADDR_WIDTH-1:0]  m_axis_read_desc_ram_addr_reg  = {RAM_ADDR_WIDTH{1'b0}};
reg [LEN_WIDTH-1:0]       m_axis_read_desc_len_reg       = {LEN_WIDTH{1'b0}};
reg [M_TAG_WIDTH-1:0]     m_axis_read_desc_tag_reg       = {M_TAG_WIDTH{1'b0}};
reg                       m_axis_read_desc_valid_reg     = 1'b0, m_axis_read_desc_valid_next;

reg [DMA_ADDR_WIDTH-1:0]  temp_m_axis_read_desc_dma_addr_reg  = {DMA_ADDR_WIDTH{1'b0}};
reg [M_RAM_SEL_WIDTH-1:0] temp_m_axis_read_desc_ram_sel_reg   = {M_RAM_SEL_WIDTH{1'b0}};
reg [RAM_ADDR_WIDTH-1:0]  temp_m_axis_read_desc_ram_addr_reg  = {RAM_ADDR_WIDTH{1'b0}};
reg [LEN_WIDTH-1:0]       temp_m_axis_read_desc_len_reg       = {LEN_WIDTH{1'b0}};
reg [M_TAG_WIDTH-1:0]     temp_m_axis_read_desc_tag_reg       = {M_TAG_WIDTH{1'b0}};
reg                       temp_m_axis_read_desc_valid_reg     = 1'b0, temp_m_axis_read_desc_valid_next;

// datapath control
reg store_axis_int_to_output;
reg store_axis_int_to_temp;
reg store_axis_temp_to_output;

assign m_axis_read_desc_dma_addr  = m_axis_read_desc_dma_addr_reg;
assign m_axis_read_desc_ram_sel   = m_axis_read_desc_ram_sel_reg;
assign m_axis_read_desc_ram_addr  = m_axis_read_desc_ram_addr_reg;
assign m_axis_read_desc_len       = m_axis_read_desc_len_reg;
assign m_axis_read_desc_tag       = m_axis_read_desc_tag_reg;
assign m_axis_read_desc_valid     = m_axis_read_desc_valid_reg;

// enable ready input next cycle if output is ready or the temp reg will not be filled on the next cycle (output reg empty or no input)
assign m_axis_read_desc_ready_int_early = m_axis_read_desc_ready || (!temp_m_axis_read_desc_valid_reg && (!m_axis_read_desc_valid_reg || !m_axis_read_desc_valid_int));

always @* begin
    // transfer sink ready state to source
    m_axis_read_desc_valid_next = m_axis_read_desc_valid_reg;
    temp_m_axis_read_desc_valid_next = temp_m_axis_read_desc_valid_reg;

    store_axis_int_to_output = 1'b0;
    store_axis_int_to_temp = 1'b0;
    store_axis_temp_to_output = 1'b0;

    if (m_axis_read_desc_ready_int_reg) begin
        // input is ready
        if (m_axis_read_desc_ready || !m_axis_read_desc_valid_reg) begin
            // output is ready or currently not valid, transfer data to output
            m_axis_read_desc_valid_next = m_axis_read_desc_valid_int;
            store_axis_int_to_output = 1'b1;
        end else begin
            // output is not ready, store input in temp
            temp_m_axis_read_desc_valid_next = m_axis_read_desc_valid_int;
            store_axis_int_to_temp = 1'b1;
        end
    end else if (m_axis_read_desc_ready) begin
        // input is not ready, but output is ready
        m_axis_read_desc_valid_next = temp_m_axis_read_desc_valid_reg;
        temp_m_axis_read_desc_valid_next = 1'b0;
        store_axis_temp_to_output = 1'b1;
    end
end

always @(posedge clk) begin
    if (rst) begin
        m_axis_read_desc_valid_reg <= 1'b0;
        m_axis_read_desc_ready_int_reg <= 1'b0;
        temp_m_axis_read_desc_valid_reg <= 1'b0;
    end else begin
        m_axis_read_desc_valid_reg <= m_axis_read_desc_valid_next;
        m_axis_read_desc_ready_int_reg <= m_axis_read_desc_ready_int_early;
        temp_m_axis_read_desc_valid_reg <= temp_m_axis_read_desc_valid_next;
    end

    // datapath
    if (store_axis_int_to_output) begin
        m_axis_read_desc_dma_addr_reg <= m_axis_read_desc_dma_addr_int;
        m_axis_read_desc_ram_sel_reg <= m_axis_read_desc_ram_sel_int;
        m_axis_read_desc_ram_addr_reg <= m_axis_read_desc_ram_addr_int;
        m_axis_read_desc_len_reg <= m_axis_read_desc_len_int;
        m_axis_read_desc_tag_reg <= m_axis_read_desc_tag_int;
    end else if (store_axis_temp_to_output) begin
        m_axis_read_desc_dma_addr_reg <= temp_m_axis_read_desc_dma_addr_reg;
        m_axis_read_desc_ram_sel_reg <= temp_m_axis_read_desc_ram_sel_reg;
        m_axis_read_desc_ram_addr_reg <= temp_m_axis_read_desc_ram_addr_reg;
        m_axis_read_desc_len_reg <= temp_m_axis_read_desc_len_reg;
        m_axis_read_desc_tag_reg <= temp_m_axis_read_desc_tag_reg;
    end

    if (store_axis_int_to_temp) begin
        temp_m_axis_read_desc_dma_addr_reg <= m_axis_read_desc_dma_addr_int;
        temp_m_axis_read_desc_ram_sel_reg <= m_axis_read_desc_ram_sel_int;
        temp_m_axis_read_desc_ram_addr_reg <= m_axis_read_desc_ram_addr_int;
        temp_m_axis_read_desc_len_reg <= m_axis_read_desc_len_int;
        temp_m_axis_read_desc_tag_reg <= m_axis_read_desc_tag_int;
    end
end

// descriptor status demux
reg [S_TAG_WIDTH-1:0] m_axis_read_desc_status_tag_reg = {S_TAG_WIDTH{1'b0}}, m_axis_read_desc_status_tag_next;
reg [5:0] m_axis_read_desc_status_error_reg = 6'd0, m_axis_read_desc_status_error_next;
reg [PORTS-1:0] m_axis_read_desc_status_valid_reg = {PORTS{1'b0}}, m_axis_read_desc_status_valid_next;

assign m_axis_read_desc_status_tag = {PORTS{m_axis_read_desc_status_tag_reg}};
assign m_axis_read_desc_status_error = {PORTS{m_axis_read_desc_status_error_reg}};
assign m_axis_read_desc_status_valid = m_axis_read_desc_status_valid_reg;

always @* begin
    m_axis_read_desc_status_tag_next = s_axis_read_desc_status_tag;
    m_axis_read_desc_status_error_next = s_axis_read_desc_status_error;
    m_axis_read_desc_status_valid_next = s_axis_read_desc_status_valid << (PORTS > 1 ? s_axis_read_desc_status_tag[S_TAG_WIDTH+CL_PORTS-1:S_TAG_WIDTH] : 0);
end

always @(posedge clk) begin
    if (rst) begin
        m_axis_read_desc_status_valid_reg <= {PORTS{1'b0}};
    end else begin
        m_axis_read_desc_status_valid_reg <= m_axis_read_desc_status_valid_next;
    end

    m_axis_read_desc_status_tag_reg <= m_axis_read_desc_status_tag_next;
    m_axis_read_desc_status_error_reg <= m_axis_read_desc_status_error_next;
end

generate

genvar n, p;

for (n = 0; n < SEG_COUNT; n = n + 1) begin

    // FIFO to maintain response ordering
    reg [FIFO_ADDR_WIDTH+1-1:0] fifo_wr_ptr_reg = 0;
    reg [FIFO_ADDR_WIDTH+1-1:0] fifo_rd_ptr_reg = 0;
    reg [CL_PORTS-1:0] fifo_sel[(2**FIFO_ADDR_WIDTH)-1:0];

    wire fifo_empty = fifo_wr_ptr_reg == fifo_rd_ptr_reg;
    wire fifo_full = fifo_wr_ptr_reg == (fifo_rd_ptr_reg ^ (1 << FIFO_ADDR_WIDTH));

    integer i;

    initial begin
        for (i = 0; i < 2**FIFO_ADDR_WIDTH; i = i + 1) begin
            fifo_sel[i] = 0;
        end
    end

    // RAM write command demux

    wire [M_RAM_SEL_WIDTH-1:0] seg_if_ram_wr_cmd_sel   = if_ram_wr_cmd_sel[M_RAM_SEL_WIDTH*n +: M_RAM_SEL_WIDTH];
    wire [SEG_BE_WIDTH-1:0]    seg_if_ram_wr_cmd_be    = if_ram_wr_cmd_be[SEG_BE_WIDTH*n +: SEG_BE_WIDTH];
    wire [SEG_ADDR_WIDTH-1:0]  seg_if_ram_wr_cmd_addr  = if_ram_wr_cmd_addr[SEG_ADDR_WIDTH*n +: SEG_ADDR_WIDTH];
    wire [SEG_DATA_WIDTH-1:0]  seg_if_ram_wr_cmd_data  = if_ram_wr_cmd_data[SEG_DATA_WIDTH*n +: SEG_DATA_WIDTH];
    wire                       seg_if_ram_wr_cmd_valid = if_ram_wr_cmd_valid[n];
    wire                       seg_if_ram_wr_cmd_ready;

    assign if_ram_wr_cmd_ready[n] = seg_if_ram_wr_cmd_ready;

    wire [PORTS*S_RAM_SEL_WIDTH-1:0] seg_ram_wr_cmd_sel;
    wire [PORTS*SEG_BE_WIDTH-1:0]    seg_ram_wr_cmd_be;
    wire [PORTS*SEG_ADDR_WIDTH-1:0]  seg_ram_wr_cmd_addr;
    wire [PORTS*SEG_DATA_WIDTH-1:0]  seg_ram_wr_cmd_data;
    wire [PORTS-1:0]                 seg_ram_wr_cmd_valid;
    wire [PORTS-1:0]                 seg_ram_wr_cmd_ready;

    for (p = 0; p < PORTS; p = p + 1) begin
        assign ram_wr_cmd_sel[(p*SEG_COUNT+n)*S_RAM_SEL_WIDTH +: S_RAM_SEL_WIDTH_INT] = seg_ram_wr_cmd_sel[p*S_RAM_SEL_WIDTH +: S_RAM_SEL_WIDTH_INT];
        assign ram_wr_cmd_be[(p*SEG_COUNT+n)*SEG_BE_WIDTH +: SEG_BE_WIDTH] = seg_ram_wr_cmd_be[p*SEG_BE_WIDTH +: SEG_BE_WIDTH];
        assign ram_wr_cmd_addr[(p*SEG_COUNT+n)*SEG_ADDR_WIDTH +: SEG_ADDR_WIDTH] = seg_ram_wr_cmd_addr[p*SEG_ADDR_WIDTH +: SEG_ADDR_WIDTH];
        assign ram_wr_cmd_data[(p*SEG_COUNT+n)*SEG_DATA_WIDTH +: SEG_DATA_WIDTH] = seg_ram_wr_cmd_data[p*SEG_DATA_WIDTH +: SEG_DATA_WIDTH];
        assign ram_wr_cmd_valid[p*SEG_COUNT+n] = seg_ram_wr_cmd_valid[p];
        assign seg_ram_wr_cmd_ready[p] = ram_wr_cmd_ready[p*SEG_COUNT+n];
    end

    // internal datapath
    reg  [S_RAM_SEL_WIDTH-1:0] seg_ram_wr_cmd_sel_int;
    reg  [SEG_BE_WIDTH-1:0]    seg_ram_wr_cmd_be_int;
    reg  [SEG_ADDR_WIDTH-1:0]  seg_ram_wr_cmd_addr_int;
    reg  [SEG_DATA_WIDTH-1:0]  seg_ram_wr_cmd_data_int;
    reg  [PORTS-1:0]           seg_ram_wr_cmd_valid_int;
    reg                        seg_ram_wr_cmd_ready_int_reg = 1'b0;
    wire                       seg_ram_wr_cmd_ready_int_early;

    assign seg_if_ram_wr_cmd_ready = seg_ram_wr_cmd_ready_int_reg && !fifo_full;

    wire [CL_PORTS-1:0] select_cmd = PORTS > 1 ? (seg_if_ram_wr_cmd_sel >> (M_RAM_SEL_WIDTH - CL_PORTS)) : 0;

    always @* begin
        seg_ram_wr_cmd_sel_int   = seg_if_ram_wr_cmd_sel;
        seg_ram_wr_cmd_be_int    = seg_if_ram_wr_cmd_be;
        seg_ram_wr_cmd_addr_int  = seg_if_ram_wr_cmd_addr;
        seg_ram_wr_cmd_data_int  = seg_if_ram_wr_cmd_data;
        seg_ram_wr_cmd_valid_int = (seg_if_ram_wr_cmd_valid && seg_if_ram_wr_cmd_ready) << select_cmd;
    end

    always @(posedge clk) begin
        if (seg_if_ram_wr_cmd_valid && seg_if_ram_wr_cmd_ready) begin
            fifo_sel[fifo_wr_ptr_reg[FIFO_ADDR_WIDTH-1:0]] <= select_cmd;
            fifo_wr_ptr_reg <= fifo_wr_ptr_reg + 1;
        end

        if (rst) begin
            fifo_wr_ptr_reg <= 0;
        end
    end

    // output datapath logic
    reg [S_RAM_SEL_WIDTH-1:0] seg_ram_wr_cmd_sel_reg   = {S_RAM_SEL_WIDTH_INT{1'b0}};
    reg [SEG_BE_WIDTH-1:0]    seg_ram_wr_cmd_be_reg    = {SEG_BE_WIDTH{1'b0}};
    reg [SEG_ADDR_WIDTH-1:0]  seg_ram_wr_cmd_addr_reg  = {SEG_ADDR_WIDTH{1'b0}};
    reg [SEG_DATA_WIDTH-1:0]  seg_ram_wr_cmd_data_reg  = {SEG_DATA_WIDTH{1'b0}};
    reg [PORTS-1:0]           seg_ram_wr_cmd_valid_reg = {PORTS{1'b0}}, seg_ram_wr_cmd_valid_next;

    reg [S_RAM_SEL_WIDTH-1:0] temp_seg_ram_wr_cmd_sel_reg   = {S_RAM_SEL_WIDTH_INT{1'b0}};
    reg [SEG_BE_WIDTH-1:0]    temp_seg_ram_wr_cmd_be_reg    = {SEG_BE_WIDTH{1'b0}};
    reg [SEG_ADDR_WIDTH-1:0]  temp_seg_ram_wr_cmd_addr_reg  = {SEG_ADDR_WIDTH{1'b0}};
    reg [SEG_DATA_WIDTH-1:0]  temp_seg_ram_wr_cmd_data_reg  = {SEG_DATA_WIDTH{1'b0}};
    reg [PORTS-1:0]           temp_seg_ram_wr_cmd_valid_reg = {PORTS{1'b0}}, temp_seg_ram_wr_cmd_valid_next;

    // datapath control
    reg store_axis_resp_int_to_output;
    reg store_axis_resp_int_to_temp;
    reg store_axis_resp_temp_to_output;

    assign seg_ram_wr_cmd_sel = {PORTS{seg_ram_wr_cmd_sel_reg}};
    assign seg_ram_wr_cmd_be = {PORTS{seg_ram_wr_cmd_be_reg}};
    assign seg_ram_wr_cmd_addr = {PORTS{seg_ram_wr_cmd_addr_reg}};
    assign seg_ram_wr_cmd_data = {PORTS{seg_ram_wr_cmd_data_reg}};
    assign seg_ram_wr_cmd_valid = seg_ram_wr_cmd_valid_reg;

    // enable ready input next cycle if output is ready or the temp reg will not be filled on the next cycle (output reg empty or no input)
    assign seg_ram_wr_cmd_ready_int_early = (seg_ram_wr_cmd_ready & seg_ram_wr_cmd_valid_reg) || (!temp_seg_ram_wr_cmd_valid_reg && (!seg_ram_wr_cmd_valid_reg || !seg_ram_wr_cmd_valid_int));

    always @* begin
        // transfer sink ready state to source
        seg_ram_wr_cmd_valid_next = seg_ram_wr_cmd_valid_reg;
        temp_seg_ram_wr_cmd_valid_next = temp_seg_ram_wr_cmd_valid_reg;

        store_axis_resp_int_to_output = 1'b0;
        store_axis_resp_int_to_temp = 1'b0;
        store_axis_resp_temp_to_output = 1'b0;

        if (seg_ram_wr_cmd_ready_int_reg) begin
            // input is ready
            if ((seg_ram_wr_cmd_ready & seg_ram_wr_cmd_valid_reg) || !seg_ram_wr_cmd_valid_reg) begin
                // output is ready or currently not valid, transfer data to output
                seg_ram_wr_cmd_valid_next = seg_ram_wr_cmd_valid_int;
                store_axis_resp_int_to_output = 1'b1;
            end else begin
                // output is not ready, store input in temp
                temp_seg_ram_wr_cmd_valid_next = seg_ram_wr_cmd_valid_int;
                store_axis_resp_int_to_temp = 1'b1;
            end
        end else if (seg_ram_wr_cmd_ready & seg_ram_wr_cmd_valid_reg) begin
            // input is not ready, but output is ready
            seg_ram_wr_cmd_valid_next = temp_seg_ram_wr_cmd_valid_reg;
            temp_seg_ram_wr_cmd_valid_next = {PORTS{1'b0}};
            store_axis_resp_temp_to_output = 1'b1;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            seg_ram_wr_cmd_valid_reg <= {PORTS{1'b0}};
            seg_ram_wr_cmd_ready_int_reg <= 1'b0;
            temp_seg_ram_wr_cmd_valid_reg <= {PORTS{1'b0}};
        end else begin
            seg_ram_wr_cmd_valid_reg <= seg_ram_wr_cmd_valid_next;
            seg_ram_wr_cmd_ready_int_reg <= seg_ram_wr_cmd_ready_int_early;
            temp_seg_ram_wr_cmd_valid_reg <= temp_seg_ram_wr_cmd_valid_next;
        end

        // datapath
        if (store_axis_resp_int_to_output) begin
            seg_ram_wr_cmd_sel_reg <= seg_ram_wr_cmd_sel_int;
            seg_ram_wr_cmd_be_reg <= seg_ram_wr_cmd_be_int;
            seg_ram_wr_cmd_addr_reg <= seg_ram_wr_cmd_addr_int;
            seg_ram_wr_cmd_data_reg <= seg_ram_wr_cmd_data_int;
        end else if (store_axis_resp_temp_to_output) begin
            seg_ram_wr_cmd_sel_reg <= temp_seg_ram_wr_cmd_sel_reg;
            seg_ram_wr_cmd_be_reg <= temp_seg_ram_wr_cmd_be_reg;
            seg_ram_wr_cmd_addr_reg <= temp_seg_ram_wr_cmd_addr_reg;
            seg_ram_wr_cmd_data_reg <= temp_seg_ram_wr_cmd_data_reg;
        end

        if (store_axis_resp_int_to_temp) begin
            temp_seg_ram_wr_cmd_sel_reg <= seg_ram_wr_cmd_sel_int;
            temp_seg_ram_wr_cmd_be_reg <= seg_ram_wr_cmd_be_int;
            temp_seg_ram_wr_cmd_addr_reg <= seg_ram_wr_cmd_addr_int;
            temp_seg_ram_wr_cmd_data_reg <= seg_ram_wr_cmd_data_int;
        end
    end

    // RAM write done mux

    wire [PORTS-1:0] seg_ram_wr_done;
    wire [PORTS-1:0] seg_ram_wr_done_sel;
    wire seg_if_ram_wr_done;

    for (p = 0; p < PORTS; p = p + 1) begin
        assign seg_ram_wr_done[p] = ram_wr_done[p*SEG_COUNT+n];
    end

    assign if_ram_wr_done[n] = seg_if_ram_wr_done;

    wire [CL_PORTS-1:0] select_resp = fifo_sel[fifo_rd_ptr_reg[FIFO_ADDR_WIDTH-1:0]];

    for (p = 0; p < PORTS; p = p + 1) begin
        reg [FIFO_ADDR_WIDTH+1-1:0] done_count_reg = 0;
        reg done_reg = 1'b0;

        assign seg_ram_wr_done_sel[p] = done_reg;

        always @(posedge clk) begin
            if (select_resp == p && (done_count_reg != 0 || seg_ram_wr_done[p])) begin
                done_reg <= 1'b1;
                if (!seg_ram_wr_done[p]) begin
                    done_count_reg <= done_count_reg - 1;
                end
            end else begin
                done_reg <= 1'b0;
                if (seg_ram_wr_done[p]) begin
                    done_count_reg <= done_count_reg + 1;
                end
            end

            if (rst) begin
                done_count_reg <= 0;
                done_reg <= 1'b0;
            end
        end
    end

    assign seg_if_ram_wr_done = seg_ram_wr_done_sel != 0;

    always @(posedge clk) begin
        if (seg_if_ram_wr_done && !fifo_empty) begin
            fifo_rd_ptr_reg <= fifo_rd_ptr_reg + 1;
        end

        if (rst) begin
            fifo_rd_ptr_reg <= 0;
        end
    end

end

endgenerate

endmodule

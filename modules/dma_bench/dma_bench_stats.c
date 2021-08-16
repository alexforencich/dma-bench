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

const char *dma_bench_stats_names[] =
{
    "pcie_rx_tlp_mem_rd",      // index 0
    "pcie_rx_tlp_mem_wr",      // index 1
    "pcie_rx_tlp_io",          // index 2
    "pcie_rx_tlp_cfg",         // index 3
    "pcie_rx_tlp_msg",         // index 4
    "pcie_rx_tlp_cpl",         // index 5
    "pcie_rx_tlp_cpl_ur",      // index 6
    "pcie_rx_tlp_cpl_ca",      // index 7
    "pcie_rx_tlp_atomic",      // index 8
    "pcie_rx_tlp_ep",          // index 9
    "pcie_rx_tlp_hdr_dw",      // index 10
    "pcie_rx_tlp_req_dw",      // index 11
    "pcie_rx_tlp_payload_dw",  // index 12
    "pcie_rx_tlp_cpl_dw",      // index 13
    "",                        // index 14
    "",                        // index 15
    "pcie_tx_tlp_mem_rd",      // index 16
    "pcie_tx_tlp_mem_wr",      // index 17
    "pcie_tx_tlp_io",          // index 18
    "pcie_tx_tlp_cfg",         // index 19
    "pcie_tx_tlp_msg",         // index 20
    "pcie_tx_tlp_cpl",         // index 21
    "pcie_tx_tlp_cpl_ur",      // index 22
    "pcie_tx_tlp_cpl_ca",      // index 23
    "pcie_tx_tlp_atomic",      // index 24
    "pcie_tx_tlp_ep",          // index 25
    "pcie_tx_tlp_hdr_dw",      // index 26
    "pcie_tx_tlp_req_dw",      // index 27
    "pcie_tx_tlp_payload_dw",  // index 28
    "pcie_tx_tlp_cpl_dw",      // index 29
    "",                        // index 30
    "",                        // index 31
    0
};

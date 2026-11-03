// n-way set associative cache
// compatible with custom PHY interface
// TODO: license

module hyperram_cache #(
    // system bus and memory parameters
    parameter int unsigned ADDR_WIDTH = 26,  // 64MB address space by default
    parameter int unsigned DATA_WIDTH = 32,  // 32-bit system bus
    parameter int unsigned BYTE_WIDTH = DATA_WIDTH-1,
    // cache parameters
    parameter int unsigned CACHE_SIZE = 1024*4,  // cache size in bytes
    parameter int unsigned ASSOCIATIVITY = 1,    // options are 1/2/4
    parameter int unsigned LINE_SIZE = 128       // line size in bytes
)(
    // system signals
    input  logic clk,
    input  logic rst,
    // system bus interface
    input  logic                  bus_req_valid,
    input  logic                  bus_req_write,
    input  logic [ADDR_WIDTH-1:0] bus_req_addr ,
    input  logic [BYTE_WIDTH-1:0] bus_req_byte ,
    input  logic [DATA_WIDTH-1:0] bus_req_wdata,
    output logic                  bus_req_ready,
    output logic [DATA_WIDTH-1:0] bus_rsp_rdata,
    // PHY interface
    input  logic                  phy_clk,
    input  logic                  phy_rst,
    output logic                  phy_req_valid,
    output logic                  phy_req_read ,
    output logic [ADDR_WIDTH-1:0] phy_req_addr ,
    output logic [BYTE_WIDTH-1:0] phy_req_byte ,
    input  logic                  phy_req_ready,
    output logic [DATA_WIDTH-1:0] phy_wdt_data ,
    input  logic                  phy_wdt_ready,
    input  logic [DATA_WIDTH-1:0] phy_rdt_data ,
    input  logic                  phy_rdt_valid
);

    // NOTE: lengths are measured in system bus words
    localparam int unsigned CACHE_ENTRY_LENGTH = CACHE_SIZE/ASSOCIATIVITY/BYTE_WIDTH;
    localparam int unsigned CACHE_ADR_WIDTH = $clog2(CACHE_ENTRY_LENGTH);
    localparam int unsigned CACHE_TAG_WIDTH = ADDR_WIDTH-CACHE_ADR_WIDTH-$clog2(BYTE_WIDTH);

    generate
    for (genvar i=0; i<ASSOCIATIVITY; i++) begin: entry
        // data memory
        logic [DATA_WIDTH-1:0] mem_dat [0:CACHE_ENTRY_LENGTH-1];
        // tag memory
        logic []
    end: entry
    endgenerate
    

endmodule: hyperram_cache
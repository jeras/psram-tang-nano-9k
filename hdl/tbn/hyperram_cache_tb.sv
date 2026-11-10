///////////////////////////////////////////////////////////////////////////////
// HyperRAM I/D cache testbench
//
// Copyright 2026 Iztok Jeras <iztok.jeras@gmail.com>
//
// Licensed under CERN-OHL-P v2 or later
///////////////////////////////////////////////////////////////////////////////

module hyperram_cache_tb #(
    // system bus and memory parameters
    parameter int unsigned BUS_ADDR_WIDTH = 26,            // 64MB address space by default
    parameter int unsigned BUS_DATA_WIDTH = 32,            // 16/32/64-bit system bus
    parameter int unsigned BUS_BYTE_WIDTH = BUS_DATA_WIDTH/8,  // word size in bytes
    // cache parameters
    parameter int unsigned ASSOCIATIVITY = 1,        // options are 1/2/4
    parameter int unsigned CACHE_SIZE = 1024*4,      // cache size in bytes
    parameter int unsigned LINE_SIZE = 128,          // line size in bytes

    // HyperRAM parameters (only ones relevant to the simplified model)
    parameter  bit    HYBRID_BURST_ENABLE  = 1'b1,
    parameter  int    BURST_LENGTH         = 32,
    // PYH interface parameters (address width also defines the memory size)
    parameter  int    PHY_SIZE_WIDTH           = $clog2(BURST_LENGTH),  // can be larger
    parameter  int    PHY_ADDR_WIDTH           = 32,
    parameter  int    PHY_DATA_WIDTH           = 16,
    localparam int    PHY_BYTE_WIDTH           = PHY_DATA_WIDTH/8,
    // PHY timing parameters (in clock cycles)
    parameter  int    WRITE_READY_DELAY    = 4,  // from request to being ready to accept write data
    parameter  int    READ_VALID_DELAY     = 8,  // from request to a valid read data response
    parameter  int    EXTENDED_DELAY       = 4,  // added randomly to read/write data delay
    parameter  int    IDLE_DELAY           = 4   // extra delay between request handshakes
);

    // system clock/reset
    logic                  clk;
    logic                  rst;

    // system bus interface
    logic                      bus_req_valid;
    logic                      bus_req_write;
    logic [BUS_ADDR_WIDTH-1:0] bus_req_addr ;
    logic [BUS_BYTE_WIDTH-1:0] bus_req_byte ;
    logic [BUS_DATA_WIDTH-1:0] bus_req_wdata;
    logic                      bus_req_ready;
    logic [BUS_DATA_WIDTH-1:0] bus_rsp_rdata;
    logic [BUS_DATA_WIDTH-1:0] bus_rsp_error;

    // PHY interface: request
    logic                      phy_req_valid;
    logic                      phy_req_type ;
    logic                      phy_req_read ;
    logic [PHY_SIZE_WIDTH-1:0] phy_req_size ;
    logic [PHY_ADDR_WIDTH-1:0] phy_req_addr ;
    logic                      phy_req_ready;
    // memory PHY interface: write data
    logic [PHY_BYTE_WIDTH-1:0] phy_wdt_byte ;
    logic [PHY_DATA_WIDTH-1:0] phy_wdt_data ;
    logic                      phy_wdt_valid;
    logic                      phy_wdt_ready;
    // memory PHY interface: read data
    logic [PHY_DATA_WIDTH-1:0] phy_rdt_data ;
    logic                      phy_rdt_strb ;
    logic                      phy_rdt_pause;

///////////////////////////////////////////////////////////////////////////////
// test sequence
///////////////////////////////////////////////////////////////////////////////

    localparam realtime PERIOD = 10ns;  // 100MHz

    // control interface clock
    initial            clk = 0;
    always #(PERIOD/2) clk = ~clk;

    // control interface reset
    initial
    begin
        // power up state
        rst = 1;
        // reset sequence (release)
        repeat (16) @(posedge clk);
        rst = 0;
        repeat (16) @(posedge clk);
    end

///////////////////////////////////////////////////////////////////////////////
// HyperRAM cache DUT instance
///////////////////////////////////////////////////////////////////////////////

    hyperram_cache #(
        // system bus and memory parameters
        .ADDR_WIDTH (PHY_ADDR_WIDTH),
        .DATA_WIDTH (PHY_DATA_WIDTH),
        // cache parameters
        .ASSOCIATIVITY (),
        .CACHE_SIZE    (),
        .LINE_SIZE     ()
    ) cache (
        // system signals
        .clk           (clk),
        .rst           (rst),
        // system bus interface
        .bus_req_valid (bus_req_valid),
        .bus_req_write (bus_req_write),
        .bus_req_addr  (bus_req_addr ),
        .bus_req_byte  (bus_req_byte ),
        .bus_req_wdata (bus_req_wdata),
        .bus_req_ready (bus_req_ready),
        .bus_rsp_rdata (bus_rsp_rdata),
        .bus_rsp_error (bus_rsp_error),
        // cache control signals
        .ctl_invalidate(ctl_invalidate),
        // memory PHY interface
        .phy_clk       (phy_clk),
        .phy_rst       (phy_rst),
        // memory PHY interface: request
        .phy_req_valid (phy_req_valid),
        .phy_req_read  (phy_req_read ),
        .phy_req_addr  (phy_req_addr ),
        .phy_req_ready (phy_req_ready),
        // memory PHY interface: write data
        .phy_req_byte  (phy_req_byte ),
        .phy_wdt_data  (phy_wdt_data ),
        .phy_wdt_ready (phy_wdt_ready),
        // memory PHY interface: read data
        .phy_rdt_data  (phy_rdt_data ),
        .phy_rdt_valid (phy_rdt_valid)
    );

///////////////////////////////////////////////////////////////////////////////
// HyperRAM HPY model instance
///////////////////////////////////////////////////////////////////////////////

    hyperram_phy_model #(
        // HyperRAM parameters (only ones relevant to the simplified model)
        .HYBRID_BURST_ENABLE  (),
        .BURST_LENGTH         (),
        // PYH interface parameters (address width also defines the memory size)
        .SIZE_WIDTH           (),
        .ADDR_WIDTH           (),
        .DATA_WIDTH           (),
        // PHY timing parameters (in clock cycles)
        .WRITE_READY_DELAY    (),
        .READ_VALID_DELAY     (),
        .EXTENDED_DELAY       (),
        .IDLE_DELAY           ()
    ) phy (
        // system clock
        .clk,
        // PHY interface: request
        .phy_req_valid (phy_req_valid),
        .phy_req_type  (phy_req_type ),
        .phy_req_read  (phy_req_read ),
        .phy_req_size  (phy_req_size ),
        .phy_req_addr  (phy_req_addr ),
        .phy_req_ready (phy_req_ready),
        // memory PHY interface: write data
        .phy_wdt_byte  (phy_wdt_byte ),
        .phy_wdt_data  (phy_wdt_data ),
        .phy_wdt_valid (phy_wdt_valid),
        .phy_wdt_ready (phy_wdt_ready),
        // memory PHY interface: read data
        .phy_rdt_data  (phy_rdt_data ),
        .phy_rdt_strb  (phy_rdt_strb ),
        .phy_rdt_pause (phy_rdt_pause)
    );

endmodule: hyperram_cache_tb

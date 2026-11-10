`timescale 1ns/1ps

module hyperram_phy_tb #(
    // controller configuration
//  parameter  int    FREQUENCY            = 83_000_000,
    parameter  int    FREQUENCY            = 81_000_000,  // system clock frequency (integer Hz units)
    // HyperRAM configuration (parameter defaults are also HyperRAM device defaults)
    parameter  string DRIVE_STRENGTH       = "34ohm",
    parameter  int    INITIAL_LATENCY      = 7,
    parameter  bit    FIXED_LATENCY_ENABLE = 1'b1,
    parameter  bit    HYBRID_BURST_ENABLE  = 1'b1,
    parameter  int    BURST_LENGTH         = 32,
    parameter  bit    MASTER_CLOCK_TYPE    = 1'b1,
    // PYH interface parameters
    parameter  int    SIZE_WIDTH           = $clog2(BURST_LENGTH),  // can be larger
    parameter  int    ADDR_WIDTH           = 32,
    parameter  int    DATA_WIDTH           = 16,
    localparam int    BYTE_WIDTH           = DATA_WIDTH/8
);

///////////////////////////////////////////////////////////////////////////////
// system signals
///////////////////////////////////////////////////////////////////////////////

    localparam realtime SYS_PERIOD = 1s / FREQUENCY;

    logic        sys_clk;
    logic        sys_clk_ck;
    logic        sys_rst;

    // system clock
    initial                sys_clk = 0;
    always #(SYS_PERIOD/2) sys_clk = ~sys_clk;

    // 90DEG phase delayed clock
    assign #(SYS_PERIOD/4) sys_clk_ck = sys_clk;

    // system reset
    initial
    begin
        // power up state
        sys_rst = 1;
        // reset sequence (release)
        repeat (16) @(posedge sys_clk);
        sys_rst = 0;
        repeat (16) @(posedge sys_clk);
    end

//    initial
//    begin
//        // Waveforms
//        $dumpfile("wave.vcd");
//        $dumpvars(0);
//    end

///////////////////////////////////////////////////////////////////////////////
// control interface
///////////////////////////////////////////////////////////////////////////////

    logic          ctl_clk  ;  // clock (independent from system bus clock)
    logic          ctl_rst  ;  // reset (independent from system bus reset)
    logic          ctl_valid;  // handshake valid (the interface is always ready)
    logic  [4-1:0] ctl_addr ;  // write address
    logic  [8-1:0] ctl_data ;  // write data

    localparam realtime CTL_PERIOD = 100ns;  // 10MHz

    // control interface clock
    initial                ctl_clk = 0;
    always #(CTL_PERIOD/2) ctl_clk = ~ctl_clk;

    // control interface reset
    initial
    begin
        // power up state
        ctl_rst = 0;
        // reset sequence (release)
        repeat (16) @(posedge ctl_clk);
        ctl_rst = 1;
        repeat (16) @(posedge ctl_clk);
    end

    // initialization to idle
    initial begin
        ctl_valid = 1'b0;
    end

    // control interface task (write only)
    task ctl_cycle (
        input logic [4-1:0] addr,
        input logic [8-1:0] data
    );
        ctl_valid <= 1'b1;
        ctl_addr  <= addr;
        ctl_data  <= data;
        @(posedge ctl_clk);
        ctl_valid <= 1'b0;
    endtask: ctl_cycle

///////////////////////////////////////////////////////////////////////////////
// PHY bus
///////////////////////////////////////////////////////////////////////////////

    // PHY interface: request
    logic                  phy_req_valid;
    logic                  phy_req_type ;
    logic                  phy_req_read ;
    logic [SIZE_WIDTH-1:0] phy_req_size ;
    logic [ADDR_WIDTH-1:0] phy_req_addr ;
    logic                  phy_req_ready;
    // memory PHY interface: write data
    logic [BYTE_WIDTH-1:0] phy_wdt_byte ;
    logic [DATA_WIDTH-1:0] phy_wdt_data ;
    logic                  phy_wdt_valid;
    logic                  phy_wdt_ready;
    // memory PHY interface: read data
    logic [DATA_WIDTH-1:0] phy_rdt_data ;
    logic                  phy_rdt_strb ;
    logic                  phy_rdt_pause;

//    logic          phy_valid;
//    logic          phy_read ;
//    logic  [7-1:0] phy_size ;
//    logic [22-1:0] phy_addr ;
//    logic  [2-1:0] phy_bytee;
//    logic [16-1:0] phy_dataw;
//    logic [16-1:0] phy_datar;
//    logic          phy_ready;

    // initialization to idle
    initial begin
        phy_req_valid = 1'b0;
        phy_wdt_valid = 1'b0;
        phy_rdt_pause = 1'b0;
    end

    // control interface task (read/write)
    task phy_cycle (
        input  logic          read ,
        input  logic  [7-1:0] size ,
        input  logic [22-1:0] addr ,
        input  logic  [2-1:0] bytew,
        input  logic [16-1:0] dataw,
        output logic [16-1:0] datar
    );
        // start cycle
        phy_req_valid <= 1'b1;
        phy_req_read  <= read;
        phy_req_size  <= size;
        phy_req_addr  <= addr;
        // write data and enable
        phy_wdt_byte  <= bytew;
        phy_wdt_data  <= dataw;
        // wait for handshake
        do
            @(posedge sys_clk);
        while (~(phy_req_valid & phy_req_ready));
        phy_req_valid <= 1'b0;
        // read data
        datar <= phy_rdt_data;
    endtask: phy_cycle

///////////////////////////////////////////////////////////////////////////////
// test sequence
///////////////////////////////////////////////////////////////////////////////

    initial begin
        logic [16-1:0] data;
        wait (~sys_rst);
        @(posedge sys_clk);
        //        read, size,     address, bytew,    dataw, datar
        phy_cycle(1'b0, 7'd0, 22'h00_0000, 2'b11, 16'ha5f0, data);
        phy_cycle(1'b1, 7'd0, 22'h00_0000, 2'bxx, 16'hxxxx, data);
    end

///////////////////////////////////////////////////////////////////////////////
// DUT instance
///////////////////////////////////////////////////////////////////////////////

    // HyperRAM signals
    wire         psram_cs_n;
    wire         psram_ck;
    wire         psram_ck_n;
    wire         psram_rwds;
    wire [8-1:0] psram_dq;
    wire         psram_reset_n;

    // Gowin global reset (active low)
    GSR GSR (1'b1);

    hyperram_phy #(
        // controller configuration
        .FREQUENCY            (FREQUENCY),
        // HyperRAM configuration
        .DRIVE_STRENGTH       (DRIVE_STRENGTH      ),
        .INITIAL_LATENCY      (INITIAL_LATENCY     ),
        .FIXED_LATENCY_ENABLE (FIXED_LATENCY_ENABLE),
        .HYBRID_BURST_ENABLE  (HYBRID_BURST_ENABLE ),
        .BURST_LENGTH         (BURST_LENGTH        ),
        .MASTER_CLOCK_TYPE    (MASTER_CLOCK_TYPE   ),
        // PYH interface parameters
        .SIZE_WIDTH           (SIZE_WIDTH),
        .ADDR_WIDTH           (ADDR_WIDTH),
        .DATA_WIDTH           (DATA_WIDTH)
    ) phy (
        // control interface (independent from system bus clock/reset)
        .ctl_clk         (1'b0),
        .ctl_rst         (1'b0),
        .ctl_valid       (1'b0),
        .ctl_addr        (4'hx),
        .ctl_data        (8'hxx),
        // system clock/reset
        .clk             (sys_clk),
        .clk_ck          (sys_clk_ck),
        .rst             (sys_rst),
        .init_done       (),
        // PHY interface: request
        .phy_req_valid   (phy_req_valid),
        .phy_req_type    (phy_req_type ),
        .phy_req_read    (phy_req_read ),
        .phy_req_size    (phy_req_size ),
        .phy_req_addr    (phy_req_addr ),
        .phy_req_ready   (phy_req_ready),
        // memory PHY interface: write data
        .phy_wdt_byte    (phy_wdt_byte ),
        .phy_wdt_data    (phy_wdt_data ),
        .phy_wdt_valid   (phy_wdt_valid),
        .phy_wdt_ready   (phy_wdt_ready),
        // memory PHY interface: read data
        .phy_rdt_data    (phy_rdt_data ),
        .phy_rdt_strb    (phy_rdt_strb ),
        .phy_rdt_pause   (phy_rdt_pause),
        // HyperRAM
        .O_psram_reset_n (psram_reset_n),
        .O_psram_ck      (psram_ck     ),
        .O_psram_ck_n    (psram_ck_n   ),
        .O_psram_cs_n    (psram_cs_n   ),
        .IO_psram_rwds   (psram_rwds   ),
        .IO_psram_dq     (psram_dq     )
    );

///////////////////////////////////////////////////////////////////////////////
// HyperRAM (psram) model instance
///////////////////////////////////////////////////////////////////////////////

/*
    W955D8MKY psram (
        .resetb (psram_reset_n[0]),
        .clk    (psram_ck     [0]),
        .clk_n  (psram_ck_n   [0]),
        .ceb    (psram_cs_n   [0]),
        .adq    (psram_dq   [7:0]),
        .rwds   (psram_rwds   [0]),
        .VCC    (1'b1),
        .VSS    (1'b0)
    );
*/

    s27kl0642 psram (
	    .DQ7      (psram_dq[7]),
	    .DQ6      (psram_dq[6]),
	    .DQ5      (psram_dq[5]),
	    .DQ4      (psram_dq[4]),
	    .DQ3      (psram_dq[3]),
	    .DQ2      (psram_dq[2]),
	    .DQ1      (psram_dq[1]),
	    .DQ0      (psram_dq[0]),
	    .RWDS     (psram_rwds   ),
	    .CSNeg    (psram_cs_n   ),
	    .CK       (psram_ck     ),
	    .CKn      (psram_ck_n   ),
	    .RESETNeg (psram_reset_n)
    );

endmodule: hyperram_phy_tb

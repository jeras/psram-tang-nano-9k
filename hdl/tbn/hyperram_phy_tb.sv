`timescale 1ns/1ps

module hyperram_phy_tb #(
    parameter int FREQUENCY = 83_000_000,
    parameter int LATENCY = 3
);

///////////////////////////////////////////////////////////////////////////////
// system signals
///////////////////////////////////////////////////////////////////////////////

    localparam realtime SYS_PERIOD = 1s / FREQUENCY;

    logic        sys_clk;
    logic        sys_clk_ck;
    logic        sys_rstn;

    // system clock
    initial                sys_clk = 0;
    always #(SYS_PERIOD/2) sys_clk = ~sys_clk;

    // 90DEG phase delayed clock
    assign #(SYS_PERIOD/4) sys_clk_ck = sys_clk;

    // system reset
    initial
    begin
        // power up state
        sys_rstn = 0;
        // reset sequence (release)
        repeat (16) @(posedge sys_clk);
        sys_rstn = 1;
        repeat (16) @(posedge sys_clk);
    end

    initial
    begin
        // Waveforms
        $dumpfile("wave.vcd");
        $dumpvars(0);
//      $finish;
    end

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

    logic          bus_valid;
    logic          bus_write;
    logic [22-1:0] bus_addr ;
    logic  [2-1:0] bus_bytee;
    logic [16-1:0] bus_dataw;
    logic [16-1:0] bus_datar;
    logic          bus_ready;

    // initialization to idle
    initial begin
        bus_valid = 1'b0;
    end

    // control interface task (read/write)
    task bus_cycle (
        input  logic [22-1:0] write,
        input  logic [22-1:0] addr ,
        input  logic  [2-1:0] bytee,
        input  logic [16-1:0] dataw,
        output logic [16-1:0] datar
    );
        // start cycle
        bus_valid <= 1'b1;
        bus_write <= write;
        bus_addr  <= addr;
        // write data and enable
        bus_bytee <= bytee;
        bus_dataw <= dataw;
        // wait for handshake
        do
            @(posedge sys_clk);
        while (~(bus_valid & bus_ready));
        bus_valid <= 1'b0;
        // read data
        datar <= bus_datar;
    endtask: bus_cycle

///////////////////////////////////////////////////////////////////////////////
// test sequence
///////////////////////////////////////////////////////////////////////////////

    initial begin
        logic [16-1:0] data;
        wait (sys_rstn);
        @(posedge sys_clk);
        //       write,     address, bytee,    dataw, datar
        bus_cycle(1'b1, 22'h00_0000, 2'b11, 16'ha5f0, data);
        bus_cycle(1'b0, 22'h00_0000, 2'bxx, 16'hxxxx, data);
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

    // Gowin global signal
    GSR GSR(1'b1);

    hyperram_phy #(
        // controller configuration
        .FREQUENCY       (FREQUENCY),
        // HyperRAM device configuration
        .INITIAL_LATENCY (LATENCY)
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
        .rstn            (sys_rstn),
        .init_done       (),
        // system bus
        .bus_valid       (bus_valid),
        .bus_write       (bus_write),
        .bus_addr        (bus_addr ),
        .bus_bytee       (bus_bytee),
        .bus_dataw       (bus_dataw),
        .bus_datar       (bus_datar),
        .bus_ready       (bus_ready),
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

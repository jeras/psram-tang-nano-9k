`timescale 1ns/1ps

module tb ();

    logic sys_clk;  // 27 Mhz, crystal clock from board
    logic sys_resetn;
    logic button;   // 0 when pressed

    wire [5:0] led;
    wire uart_txp;

    wire  [1:0] psram_ck;
    wire  [1:0] psram_ck_n;
    wire  [1:0] psram_rwds;
    wire [15:0] psram_dq;
    wire  [1:0] psram_reset_n;
    wire  [1:0] psram_cs_n;

    // system clock (27Mhz external clock oscillator on Tang Nano 9k)
    initial    sys_clk = 0;
    always #37 sys_clk = ~sys_clk;

    // system reset 
    initial
    begin
        // power up state
        sys_resetn = 0;
        button = 1;
        // reset sequence (release)
        repeat (3000) @(posedge sys_clk);
        sys_resetn = 1;
        // delay before button press
        repeat (16) @(posedge sys_clk);
        // press and release button
        button = 0;
        repeat (16) @(posedge sys_clk);
        button = 1;
    end

    // Gowin global signal
    GSR GSR(1'b1);

    // design under test instance
    memory_test dut (
        .sys_clk         (sys_clk),
        .sys_resetn      (sys_resetn),
    
        .button          (button),
        .led             (led),
        .uart_txp        (uart_txp),
        // Magic ports for PSRAM to be inferred
        .O_psram_ck      (psram_ck     ),
        .O_psram_ck_n    (psram_ck_n   ),
        .IO_psram_rwds   (psram_rwds   ),
        .IO_psram_dq     (psram_dq     ),
        .O_psram_reset_n (psram_reset_n),
        .O_psram_cs_n    (psram_cs_n   )
    );

/*
    W955D8MKY psram_0 (
        .resetb (psram_reset_n[0]),
        .clk    (psram_ck     [0]),
        .clk_n  (psram_ck_n   [0]),
        .ceb    (psram_cs_n   [0]),
        .adq    (psram_dq   [7:0]),
        .rwds   (psram_rwds   [0]),
        .VCC    (1'b1),
        .VSS    (1'b0) 
    );
      
    W955D8MKY psram_1 (
        .resetb (psram_reset_n[1]),
        .clk    (psram_ck     [1]),
        .clk_n  (psram_ck_n   [1]),
        .ceb    (psram_cs_n   [1]),
        .adq    (psram_dq  [15:8]),
        .rwds   (psram_rwds   [1]),
        .VCC    (1'b1),
        .VSS    (1'b0) 
    );
*/

    s27kl0642 psram_0(
	    .DQ7      (psram_dq[7]),
	    .DQ6      (psram_dq[6]),
	    .DQ5      (psram_dq[5]),
	    .DQ4      (psram_dq[4]),
	    .DQ3      (psram_dq[3]),
	    .DQ2      (psram_dq[2]),
	    .DQ1      (psram_dq[1]),
	    .DQ0      (psram_dq[0]),
	    .RWDS     (psram_rwds   [0]),
	    .CSNeg    (psram_cs_n   [0]),
	    .CK       (psram_ck     [0]),
	    .CKn      (psram_ck_n   [0]),
	    .RESETNeg (psram_reset_n[0])
    );
      
    s27kl0642 psram_1(
	    .DQ7      (psram_dq[15]),
	    .DQ6      (psram_dq[14]),
	    .DQ5      (psram_dq[13]),
	    .DQ4      (psram_dq[12]),
	    .DQ3      (psram_dq[11]),
	    .DQ2      (psram_dq[10]),
	    .DQ1      (psram_dq[9]),
	    .DQ0      (psram_dq[8]),
	    .RWDS     (psram_rwds   [1]),
	    .CSNeg    (psram_cs_n   [1]),
	    .CK       (psram_ck     [1]),
	    .CKn      (psram_ck_n   [1]),
	    .RESETNeg (psram_reset_n[1])
    );

    initial
    begin
        // Waveforms
        $dumpfile("wave.vcd");
        $dumpvars(0);
//      $finish;
    end

endmodule

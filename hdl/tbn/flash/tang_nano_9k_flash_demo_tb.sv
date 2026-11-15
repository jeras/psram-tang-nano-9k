///////////////////////////////////////////////////////////////////////////////
// Tang Nano 9k demo for the embedded flash controller testbench
//
// Copyright 2026 Iztok Jeras <iztok.jeras@gmail.com>
//
// Licensed under CERN-OHL-P v2 or later
///////////////////////////////////////////////////////////////////////////////

module tang_nano_9k_flash_demo_tb #(
    // 4kB or 2*DPB (each DPB is 16kb organized as 16-bit 2k locations)
    parameter  int unsigned TEST_SIZE = 4*1024,
    // UART baudrate
    parameter longint       BAUDRATE = 115_200
);

    logic       XTAL_IN;
    logic [2:1] S;
    wire  [6:1] LED;
    wire        FPGA_TX;

    localparam time XTAL_PERIOD = (1/27)*1ns;

    // clock source
    initial                  XTAL_IN = 1'b1;
    always #(XTAL_PERIOD/2)  XTAL_IN = ~XTAL_IN;

    // button press
    initial begin
        // short button press
        S[1] <= 1'b0;
        repeat(4)  @(posedge XTAL_IN);
        S[1] <= 1'b1;
        repeat(4)  @(posedge XTAL_IN);
        S[1] <= 1'b0;
        // wait for LED to indicate the end of the test
        @(negedge LED[1])
        repeat(4)  @(posedge XTAL_IN);
        // end simulation
        $finish();
    end

    // test RTL instance
    tang_nano_9k_flash_demo #(
        .TEST_SIZE (TEST_SIZE)
    ) demo (
        .XTAL_IN (XTAL_IN),
        .S       (S      ),
        .LED     (LED    ),
        .FPGA_TX (FPGA_TX)
    );

    // UART model (receiver)
    uart_model #(
        .BAUD   (BAUDRATE),
        // data streams
        .FILE_O ("test_report.txt")
    ) uart (
        .TXD (),
        .RXD (FPGA_TX)
    );

endmodule: tang_nano_9k_flash_demo_tb

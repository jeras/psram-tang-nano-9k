///////////////////////////////////////////////////////////////////////////////
// Tang Nano 9k demo for the embedded flash controller testbench
//
// Copyright 2026 Iztok Jeras <iztok.jeras@gmail.com>
//
// Licensed under CERN-OHL-P v2 or later
///////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps

module tang_nano_9k_flash_demo_tb #(
`ifdef DEBUG
    parameter  int unsigned TEST_SIZE = 16,
    parameter longint       BAUDRATE = 27_000_000/13
`else
    // 4kB or 2*DPB (each DPB is 16kb organized as 16-bit 2k locations)
    parameter  int unsigned TEST_SIZE = 4*1024,
    // UART baudrate
    parameter longint       BAUDRATE = 115_200
`endif
);

    logic       XTAL_IN;
    logic [2:1] S = 1'b1;
    wire  [6:1] LED;
    wire        FPGA_TX;

    localparam realtime XTAL_PERIOD = 1s / 27_000_000;

    // clock source
    initial                  XTAL_IN = 1'b1;
    always #(XTAL_PERIOD/2)  XTAL_IN = ~XTAL_IN;

    // button press
    initial begin
        S <= 2'b11;
  
//        // short "reset" button press
//        repeat(8)  @(posedge XTAL_IN);
//        S[1] <= 1'b0;
//        repeat(4)  @(posedge XTAL_IN);
//        S[1] <= 1'b1;

        // short "reset" button press
        #20ms;
        S[1] <= 1'b0;
        #20ms;
        S[1] <= 1'b1;
        
        // UART dump enable
        uart.start("", "uart_rx.txt");
  
        // short "run" button press
        repeat(8)  @(posedge XTAL_IN);
        S[2] <= 1'b0;
        repeat(4)  @(posedge XTAL_IN);
        S[2] <= 1'b1;

        // short "run" button press
        #20ms;
        S[2] <= 1'b0;
        #20ms;
        S[2] <= 1'b1;
        
        // wait for LED to indicate the end of the test
        @(negedge LED[3])
        repeat(4)  @(posedge XTAL_IN);
        // end simulation
        $finish();
    end

    // simulation timeout for debugging purposes
    initial begin
`ifdef DEBUG
        repeat(2000)  @(posedge XTAL_IN);
`else
        #1000ms;
`endif
        $finish();
    end

    // waveform dump
    initial begin
`ifdef QUESTA
        $dumpfile("tang_nano_9k_flash_demo_tb.vcd");
        $dumpvars(0, tang_nano_9k_flash_demo_tb);
`else
        $dumpfile("tang_nano_9k_flash_demo_tb.fst");
        $dumpvars(0, tang_nano_9k_flash_demo_tb);
        for (int i=0; i<4; i++) $dumpvars(0, demo.sram_mem[i]);
`endif
    end

    // Flash array initialization
    initial begin
        for (int unsigned x=0; x<304; x++) begin
            for (int unsigned y=0; y<64; y++) begin
                demo.flash_ctrl.flash.MEM_DATA[x[9:0]][y[5:0]] = {x[15:0], y[15:0]};
            end
        end
    end

    // test RTL instance
    tang_nano_9k_flash_demo #(
        .TEST_SIZE (TEST_SIZE),
        .BAUDRATE  (BAUDRATE)
    ) demo (
        .XTAL_IN (XTAL_IN),
        .S       (S      ),
        .LED     (LED    ),
        .FPGA_TX (FPGA_TX)
    );

    // UART model (receiver)
    uart_model #(
        .BAUDRATE (BAUDRATE)
    ) uart (
        .TXD (),
        .RXD (FPGA_TX)
    );

endmodule: tang_nano_9k_flash_demo_tb

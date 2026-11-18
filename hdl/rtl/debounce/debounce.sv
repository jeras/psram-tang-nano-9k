///////////////////////////////////////////////////////////////////////////////
// button debounce
//
// Copyright 2026 Iztok Jeras <iztok.jeras@gmail.com>
//
// Licensed under CERN-OHL-P v2 or later
///////////////////////////////////////////////////////////////////////////////

module debounce #(
    // initial value, can be same or opposite (causing a power-up pulse) to button idle state
    parameter bit      INIT = 1'b0,
    // timing parameters
    parameter  int unsigned CNT_LENGTH = 7,                  // counter length
    localparam int unsigned CNT_WIDTH = $clog2(CNT_LENGTH)   // counter width
)(
  input  logic clk,  // clock
  input  logic d_i,  // debounce input
  output logic d_o   // debounce output
);

    // debug code
    initial $display("CNT_LENGTH = %d", CNT_LENGTH);

    // counter signals
    logic [CNT_WIDTH-1:0] cnt = 'd0;  // counter (power-up initial value for FPGA)
    logic [CNT_WIDTH-0:0] cnt_nxt;    // counter next
    logic                 cnt_end;    // counter end

    // data signals
    logic d_0 = INIT;  // input CDC register 0
    logic d_1 = INIT;  // input CDC register 1
    logic d_r = INIT;  // output register
    logic tgl;         // input toggle in relation to output

    // CDC to prevent metastability problems
    always_ff @(posedge clk)
    begin
        d_0 <= d_i;
        d_1 <= d_0;
    end

    // counter decrement
    assign cnt_nxt = {1'b0, cnt} - 'd1;

    // counter reached zero (decrement underflow)
    assign cnt_end = cnt_nxt[CNT_WIDTH];

    // the counter should start running on a toggle
    always_ff @(posedge clk)
    if (~cnt_end)  cnt <= cnt_nxt;
    else if (tgl)  cnt <= CNT_LENGTH[CNT_WIDTH-1:0];

    // when the counter is zero the output should follow the input
    always @ (posedge clk)
    if (cnt_end)  d_r <= d_1;

    // input toggle in relation to output
    assign tgl = d_1 ^ d_r;

    assign d_o = d_r;

endmodule: debounce

//
// PSRAM/HyperRAM controller for Tang Nano 9K / Gowin GW1NR-LV9QN88PC6/15.
// Feng Zhou, 2022.8
//
// This is a word or byte based, non-bursting controller for accessing the on-chip HyperRAM.
// - 1:1 clock design. Memory and main logic work under the same clock.
// - Low latency. Under default settings, write latency is 7 cycles (1x) or 10 cycles (2x).
//   Read latency is 12 cycles (1x) or 15 cycles(2x). In my test, 2x latency happens about
//   0.05% of time.

module psram_controller #(
    parameter FREQ=81_000_000,       // Actual clk frequency, to time 150us initialization delay
    parameter LATENCY=3              // tACC (Initial Latency) in W955D8MBYA datasheet:
                                     // 3 (max 83Mhz), 4 (max 104Mhz), 5 (max 133Mhz) or 6 (max 166Mhz)
)(
    // system signals
    input  logic          clk,
    input  logic          clk_p,      // phase-shifted clock for driving O_psram_ck
    input  logic          rstn,
    // system bus
    input  logic          bus_valid,  // handshake valid
    input  logic          bus_write,  // 0: read, 1: write
    input  logic [22-1:0] bus_addr ,  // address (bit [0] is ignored)
    input  logic  [2-1:0] bus_bytee,  // byte enable
    input  logic [16-1:0] bus_dataw,  // write data
    output logic [16-1:0] bus_datar,  // read data (byte enable is ignored)
    output logic          bus_busy ,  // 1 while an operation is in progress
//  output logic          bus_ready,  // handshake ready
    // HyperRAM physical interface
    output logic        O_psram_reset_n,
    output logic        O_psram_ck,
    output logic        O_psram_ck_n,
    output logic        O_psram_cs_n,
    inout  logic       IO_psram_rwds,
    inout  logic [7:0] IO_psram_dq
);

    reg [2:0] state;
    localparam [2:0] INIT_ST   = 3'd0;
    localparam [2:0] CONFIG_ST = 3'd1;
    localparam [2:0] IDLE_ST   = 3'd2;
    localparam [2:0] READ_ST   = 3'd3;
    localparam [2:0] WRITE_ST  = 3'd4;

    reg cfg_now, dq_oen, ram_cs_n, ck_e, ck_e_p;
    reg wait_for_rd_data;
    reg [15:0] w_data_w;
    reg [23:0] cycles_sr;       // shift register counting cycles
    reg [63:0] dq_sr;           // shifts left 8-bit every cycle

    // DDR input output signals
    wire [7:0] dq_out_pos = dq_sr[63:56];
    wire [7:0] dq_out_neg = dq_sr[55:48];
    wire [7:0] dq_in_pos;
    wire [7:0] dq_in_neg;
    reg rwds_out_pos, rwds_out_neg, rwds_oen;
    wire rwds_in_pos, rwds_in_neg;
    reg additional_latency;

    assign bus_busy = (state != IDLE_ST);

    localparam [3:0] CR_LATENCY = LATENCY == 3 ? 4'b1110 :
                                  LATENCY == 4 ? 4'b1111 :
                                  LATENCY == 5 ? 4'b0 :
                                  LATENCY == 6 ? 4'b0001 : 4'b1110;

    // Main FSM for HyperRAM read/write
    always @(posedge clk)
    if (~rstn) begin
        state    <= INIT_ST;
        ram_cs_n <= 1;
        ck_e     <= 0;
        ck_e_p   <= 1'b0;
        dq_oen   <= 1'b1;
        wait_for_rd_data <= 1'b0;
        cycles_sr <= 24'b1;
        w_data_w <= 0;
        rwds_out_pos <= 1'b0;
        rwds_out_neg <= 1'b0;
        rwds_oen <= 1'b1;
        additional_latency <= 1'b0;
    end else begin
        cycles_sr <= {cycles_sr[22:0], 1'b0};
        dq_sr <= {dq_sr[47:0], 16'b0};          // shift 16-bits each cycle
        ck_e_p <= ck_e;

        if (state == INIT_ST && cfg_now) begin
            cycles_sr <= 24'b1;
            ram_cs_n <= 0;
            state <= CONFIG_ST;
        end
        if (state == CONFIG_ST) begin
            if (cycles_sr[0]) begin
                dq_sr <= {8'h60, 8'h00, 8'h01, 8'h00, 8'h00, 8'h00, 8'h8f, CR_LATENCY, 4'h7};      // last byte, 'e' (3 cycle latency max 83Mhz), '7' (variable 1x/2x latency)
                dq_oen <= 0;
                ck_e <= 1;      // this needs to be earlier 1 cycle to allow for phase shifted clk_p
            end
            if (cycles_sr[4]) begin
                state <= IDLE_ST;
                ck_e <= 0;
                cycles_sr <= 24'b1;
                dq_oen <= 1;
                ram_cs_n <= 1;
            end
        end
        if (state == IDLE_ST) begin
            rwds_oen <= 1;
            ck_e <= 0;
            ram_cs_n <= 1;
            if (bus_valid) begin
                // start read/write operation
                dq_sr <= {~bus_write, 13'b010_0000_0000_00, bus_addr[21:4], 13'b0, bus_addr[3:1], 16'b0000_0100_1101_0100};
                        //      14-bit                     18-bit   13-bit   3-bit             total 48-bit CA
                ram_cs_n <= 0;
                ck_e <= 1;
                dq_oen <= 0;
                wait_for_rd_data <= 0;
                w_data_w <= bus_dataw;
                cycles_sr <= 32'b10;    // start from cycle 1
                state <= bus_write ? WRITE_ST : READ_ST;
            end
        end

        if (state == READ_ST)  begin
            if (cycles_sr[3]) begin
                // command sent, now wait for result
                dq_oen <= 1;
            end
            if (cycles_sr[9])
                wait_for_rd_data <= 1;
            if (wait_for_rd_data && (rwds_in_pos ^ rwds_in_neg)) begin     // sample rwds falling edge to get a word / \_
                bus_datar <= {dq_in_pos, dq_in_neg};
                ram_cs_n <= 1;
                ck_e <= 0;
                state <= IDLE_ST;
            end
        end

        if (state == WRITE_ST) begin
            if (cycles_sr[5])
                additional_latency <= rwds_in_neg;  // sample RWDS to see if we need additional latency
            // Write timing is trickier - we sample RWDS at cycle 5 to determine whether we need to wait another tACC.
            // If it is low, data starts at 2+LATENCY. If high, then data starts at 2+LATENCY*2.
            if (cycles_sr[2+LATENCY] && (LATENCY == 3 ? ~rwds_in_neg : ~additional_latency)
                || cycles_sr[2+LATENCY*2])
            begin
                rwds_oen <= 0;
                rwds_out_pos <= ~bus_bytee[0];
                rwds_out_neg <= ~bus_bytee[1];
                dq_sr[63:48] <= w_data_w;
                state <= IDLE_ST;
            end
        end
    end

///////////////////////////////////////////////////////////////////////////////
// Generate cfg_now pulse after 150us initialization delay
///////////////////////////////////////////////////////////////////////////////

    localparam INIT_TIME = FREQ / 1000 * 160 / 1000;
    reg  [$clog2(INIT_TIME+1):0]   rst_cnt;
    reg rst_done, rst_done_p1;

    always @(posedge clk) begin
    if (~rstn) begin
        rst_cnt  <= 15'd0;
        rst_done <= 0;
        rst_done_p1 <= 0;
    end
        rst_done_p1 <= rst_done;
        cfg_now     <= rst_done & ~rst_done_p1;// Rising Edge Detect
        if (rst_cnt != INIT_TIME) begin      // count to 160 us
            rst_cnt  <= rst_cnt[14:0] + 1;
        end else begin
            rst_done <= 1;
        end
    end

///////////////////////////////////////////////////////////////////////////////
// HyperRAM `ck`/`ck_n` output
///////////////////////////////////////////////////////////////////////////////

    OBUF obuf_reset_n (
        .O   (O_psram_reset_n),
        .I   (rstn)
    );

///////////////////////////////////////////////////////////////////////////////
// HyperRAM `ck`/`ck_n` output
///////////////////////////////////////////////////////////////////////////////

    wire ck_tbuf;
    wire ck_n_tbuf;

    // Note: ck uses phase-shifted clock clk_p
    ODDR oddr_ck (
        .Q0  (ck_tbuf),
        .Q1  (),
        .D0  (ck_e_p),
        .D1  (1'b0),
        .TX  (1'b1),
        .CLK (clk_p)
    );

    ODDR oddr_ck_n (
        .Q0  (ck_n_tbuf),
        .Q1  (),
        .D0  (~ck_e_p),
        .D1  (1'b1),
        .TX  (1'b1),
        .CLK (clk_p)
    );

    OBUF obuf_ck (
        .O   (O_psram_ck),
        .I   (ck_tbuf)
    );

    OBUF obuf_ck_p (
        .O   (O_psram_ck_n),
        .I   (ck_n_tbuf)
    );

///////////////////////////////////////////////////////////////////////////////
// HyperRAM `cs_n` output
///////////////////////////////////////////////////////////////////////////////

    ODDR oddr_cs_n (
        .Q0  (cs_n_tbuf),
        .Q1  (),
        .D0  (ram_cs_n),
        .D1  (ram_cs_n),
        .TX  (1'b1),
        .CLK (clk)
    );

    OBUF obuf_cs_n (
        .O   (O_psram_cs_n),
        .I   (cs_n_tbuf)
    );

///////////////////////////////////////////////////////////////////////////////
// HyperRAM `rwds` output/input
///////////////////////////////////////////////////////////////////////////////

    wire rwds_o;  // IO output
    wire rwds_t;  // IO tristate
    wire rwds_i;  // IO input
    wire rwds_d;  // IO input delay

    ODDR oddr_rwds (
        .Q0  (rwds_o),
        .Q1  (rwds_t),
        .D0  (rwds_out_pos),
        .D1  (rwds_out_neg),
        .TX  (rwds_oen),
        .CLK (clk)
    );

    IOBUF iobuf_rwds (
        .O   (rwds_i),
        .IO  (IO_psram_rwds),
        .I   (rwds_o),
        .OEN (rwds_t)
    );

    IODELAY #(
        .C_STATIC_DLY (0)
    ) idelay_rwds (
        .DO    (rwds_d),
        .DF    (),
        .DI    (rwds_i),
        .SDTAP (1'b0),
        .VALUE (1'b0),
        .SETN  (1'b0)
    );

    // Tristate DDR input
    IDDR iddr_rwds (
        .Q0  (rwds_in_pos),
        .Q1  (rwds_in_neg),
        .D   (rwds_d),
        .CLK (clk)
    );

///////////////////////////////////////////////////////////////////////////////
// HyperRAM `dq` output/input
///////////////////////////////////////////////////////////////////////////////

    wire [7:0] dq_o;  // IO output
    wire [7:0] dq_t;  // IO tristate
    wire [7:0] dq_i;  // IO input
    wire [7:0] dq_d;  // IO input delay

    genvar i;
    generate for (i=0; i<=7; i++) begin: dq

        ODDR oddr_dq (
            .Q0  (dq_o       [i]),
            .Q1  (dq_t       [i]),
            .D0  (dq_out_pos [i]),
            .D1  (dq_out_neg [i]),
            .TX  (dq_oen),
            .CLK (clk)
        );

        IOBUF iobuf_dq (
            .O   (dq_i       [i]),
            .IO  (IO_psram_dq[i]),
            .I   (dq_o       [i]),
            .OEN (dq_t       [i])
        );

        IODELAY #(
            .C_STATIC_DLY (0)
        ) idelay_dq (
            .DO    (dq_d     [i]),
            .DF    (),
            .DI    (dq_i     [i]),
            .SDTAP (1'b0),
            .VALUE (1'b0),
            .SETN  (1'b0)
        );

        IDDR iddr_dq (
            .Q0  (dq_in_pos  [i]),
            .Q1  (dq_in_neg  [i]),
            .D   (dq_d       [i]),
            .CLK (clk)
        );

    end endgenerate

endmodule

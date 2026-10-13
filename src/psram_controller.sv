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
    parameter FREQUENCY=81_000_000,  // system clock frequency (integer Hz units)
    parameter LATENCY=3              // tACC (Initial Latency) in W955D8MBYA datasheet:
                                     // 3 (max 83Mhz), 4 (max 104Mhz), 5 (max 133Mhz) or 6 (max 166Mhz)
)(
    // system signals
    input  logic          clk,
    input  logic          clk_p,      // phase-shifted clock for driving O_psram_ck
    input  logic          rstn,
    // configuration/status interface
    output logic          init_done,  // indicates the end of initialization delay
    input  logic          cfg_valid,  // handshake valid (the interface is always ready)
    input  logic  [4-1:0] cfg_addr ,  // write address
    input  logic  [8-1:0] cfg_data ,  // write data
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

///////////////////////////////////////////////////////////////////////////////
// generate init_pulse after 150us initialization delay
///////////////////////////////////////////////////////////////////////////////

    // T_VCS power voltage (or reset release) to chip select time
//  localparam T_VCS_VAL = FREQUENCY * 150 / 1000 / 1000;
    localparam T_VCS_VAL = FREQUENCY / 1000 * 150 / 1000;
    localparam T_VCS_WIDTH = $clog2(T_VCS_VAL-1);

    logic  [T_VCS_WIDTH-1:0] init_counter;    // counter value
    logic  [T_VCS_WIDTH  :0] init_decrement;  // counter decremented value
    logic                    init_underflow;  // counter underflow
    logic                    init_pulse;      // initialization pulse

    always @(posedge clk, negedge rstn)
    if (~rstn) begin
        init_counter <= T_VCS_VAL-1;
        init_done    <= 1'b0;
        init_pulse   <= 1'b0;
    end else begin
        // counter decrement underflow is used as indication the counter reached zero
        if (~init_underflow) begin
           init_counter <= init_decrement[T_VCS_WIDTH-1:0];
        end
        init_done  <= init_underflow;
        init_pulse <= init_underflow & ~init_done;// Rising Edge Detect
    end

    assign init_decrement = {1'b0, init_counter} - 1'd1;
    assign init_underflow = init_decrement[T_VCS_WIDTH];

///////////////////////////////////////////////////////////////////////////////
// HyperRAM FSM
///////////////////////////////////////////////////////////////////////////////

    localparam [3-1:0] ST_INIT   = 3'd0;
    localparam [3-1:0] ST_CONFIG = 3'd1;
    localparam [3-1:0] ST_IDLE   = 3'd2;
    localparam [3-1:0] ST_READ   = 3'd3;
    localparam [3-1:0] ST_WRITE  = 3'd4;

    localparam [3:0] CR_LATENCY = LATENCY == 3 ? 4'b1110 :
                                  LATENCY == 4 ? 4'b1111 :
                                  LATENCY == 5 ? 4'b0000 :
                                  LATENCY == 6 ? 4'b0001 :
                                                 4'b1110;

    logic  [3-1:0] state;
    logic [24-1:0] cycles_sr;       // shift register counting cycles
    logic [64-1:0] dq_sr;           // shifts left 8-bit every cycle
    logic [16-1:0] w_data_w;
    logic          wait_for_rd_data;
    logic          additional_latency;

    // DDR input/output signals
    logic         ddr_ck_e;
    logic         ddr_ck_e_p;
    logic         ddr_cs_n;
    logic         ddr_rwds_oen;
    logic         ddr_rwds_out_pos;
    logic         ddr_rwds_out_neg;
    wire          ddr_rwds_in_pos;
    wire          ddr_rwds_in_neg;
    logic         ddr_dq_oen;
    wire  [8-1:0] ddr_dq_out_pos = dq_sr[63:56];
    wire  [8-1:0] ddr_dq_out_neg = dq_sr[55:48];
    wire  [8-1:0] ddr_dq_in_pos;
    wire  [8-1:0] ddr_dq_in_neg;

    // Main FSM for HyperRAM read/write
    always @(posedge clk)
    if (~rstn) begin
        // FSM
        state              <= ST_INIT;
        cycles_sr          <= 24'b1;
        dq_sr              <= '0;
        w_data_w           <= 0;
        wait_for_rd_data   <= 1'b0;
        additional_latency <= 1'b0;
        // DDR input output
        ddr_ck_e         <= 0;
        ddr_ck_e_p       <= 1'b0;
        ddr_cs_n         <= 1;
        ddr_rwds_out_pos <= 1'b0;
        ddr_rwds_out_neg <= 1'b0;
        ddr_rwds_oen     <= 1'b1;
        ddr_dq_oen       <= 1'b1;
    end else begin
        dq_sr <= {dq_sr[47:0], 16'b0};          // shift 16-bits each cycle

        // TODO: maybe driving this on the clock negative edge would make sense
        ddr_ck_e_p <= ddr_ck_e;

        unique0 case (state)
        ST_INIT: begin
            if (init_pulse) begin
                state <= ST_CONFIG;
                cycles_sr <= 24'b10;
                ddr_ck_e <= 1;      // this needs to be earlier 1 cycle to allow for phase shifted clk_p
                ddr_cs_n <= 0;
                ddr_dq_oen <= 0;
                dq_sr <= {8'h60, 8'h00, 8'h01, 8'h00, 8'h00, 8'h00, 8'h8f, CR_LATENCY, 4'h7};      // last byte, 'e' (3 cycle latency max 83Mhz), '7' (variable 1x/2x latency)
            end
        end
        ST_CONFIG: begin
            if (cycles_sr[4]) begin
                state <= ST_IDLE;
                cycles_sr <= 24'b1;
                ddr_ck_e <= 0;
                ddr_cs_n <= 1;
                ddr_dq_oen <= 1;
            end else begin
                cycles_sr <= {cycles_sr[22:0], 1'b0};
            end
        end
        ST_IDLE: begin
            if (bus_valid) begin
                // start read/write operation
                state <= bus_write ? ST_WRITE : ST_READ;
                cycles_sr <= 32'b10;
                        //      14-bit                     18-bit   13-bit   3-bit             total 48-bit CA
                dq_sr <= {~bus_write, 13'b010_0000_0000_00, bus_addr[21:4], 13'b0, bus_addr[3:1], 16'b0000_0100_1101_0100};
                ddr_ck_e <= 1;
                ddr_cs_n <= 0;
                wait_for_rd_data <= 0;
                w_data_w <= bus_dataw;
            end
        end
        ST_READ: begin
            if (cycles_sr[3]) begin
                // command sent, now wait for result
                ddr_dq_oen <= 1;
            end
            if (cycles_sr[9])
                wait_for_rd_data <= 1;
            if (wait_for_rd_data && (ddr_rwds_in_pos ^ ddr_rwds_in_neg)) begin     // sample rwds falling edge to get a word / \_
                ddr_cs_n <= 1;
                ddr_ck_e <= 0;
                state <= ST_IDLE;
            end
        end
        ST_WRITE: begin
            if (cycles_sr[5])
                additional_latency <= ddr_rwds_in_neg;  // sample RWDS to see if we need additional latency
            // Write timing is trickier - we sample RWDS at cycle 5 to determine whether we need to wait another tACC.
            // If it is low, data starts at 2+LATENCY. If high, then data starts at 2+LATENCY*2.
            if (cycles_sr[2+LATENCY] && (LATENCY == 3 ? ~ddr_rwds_in_neg : ~additional_latency)
                || cycles_sr[2+LATENCY*2])
            begin
                ddr_rwds_oen <= 0;
                ddr_rwds_out_pos <= ~bus_bytee[0];
                ddr_rwds_out_neg <= ~bus_bytee[1];
                dq_sr[63:48] <= w_data_w;
                state <= ST_IDLE;
            end else begin
                cycles_sr <= {cycles_sr[22:0], 1'b0};
            end
        end
        endcase
    end

///////////////////////////////////////////////////////////////////////////////
// system bus
///////////////////////////////////////////////////////////////////////////////

    assign bus_datar = {ddr_dq_in_pos, ddr_dq_in_neg};

    assign bus_busy = (state != ST_IDLE);

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

    wire ck_o;
    wire ck_n_o;

    // Note: ck uses phase-shifted clock clk_p
    ODDR oddr_ck (
        .Q0  (ck_o),
        .Q1  (),
        .D0  (ddr_ck_e_p),
        .D1  (1'b0),
        .TX  (1'b1),
        .CLK (clk_p)
    );

    ODDR oddr_ck_n (
        .Q0  (ck_n_o),
        .Q1  (),
        .D0  (~ddr_ck_e_p),
        .D1  (1'b1),
        .TX  (1'b1),
        .CLK (clk_p)
    );

    OBUF obuf_ck (
        .O   (O_psram_ck),
        .I   (ck_o)
    );

    OBUF obuf_ck_p (
        .O   (O_psram_ck_n),
        .I   (ck_n_o)
    );

///////////////////////////////////////////////////////////////////////////////
// HyperRAM `cs_n` output
///////////////////////////////////////////////////////////////////////////////

    wire cs_n_o;

    ODDR oddr_cs_n (
        .Q0  (cs_n_o),
        .Q1  (),
        .D0  (ddr_cs_n),
        .D1  (ddr_cs_n),
        .TX  (1'b1),
        .CLK (clk)
    );

    OBUF obuf_cs_n (
        .O   (O_psram_cs_n),
        .I   (cs_n_o)
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
        .D0  (ddr_rwds_out_pos),
        .D1  (ddr_rwds_out_neg),
        .TX  (ddr_rwds_oen),
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
        .Q0  (ddr_rwds_in_pos),
        .Q1  (ddr_rwds_in_neg),
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
            .Q0  (dq_o          [i]),
            .Q1  (dq_t          [i]),
            .D0  (ddr_dq_out_pos[i]),
            .D1  (ddr_dq_out_neg[i]),
            .TX  (ddr_dq_oen),
            .CLK (clk)
        );

        IOBUF iobuf_dq (
            .O   (dq_i          [i]),
            .IO  (IO_psram_dq   [i]),
            .I   (dq_o          [i]),
            .OEN (dq_t          [i])
        );

        IODELAY #(
            .C_STATIC_DLY (0)
        ) idelay_dq (
            .DO    (dq_d        [i]),
            .DF    (),
            .DI    (dq_i        [i]),
            .SDTAP (1'b0),
            .VALUE (1'b0),
            .SETN  (1'b0)
        );

        IDDR iddr_dq (
            .Q0  (ddr_dq_in_pos [i]),
            .Q1  (ddr_dq_in_neg [i]),
            .D   (dq_d          [i]),
            .CLK (clk)
        );

    end endgenerate

endmodule

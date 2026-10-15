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
    // controller configuration
    parameter FREQUENCY=81_000_000,  // system clock frequency (integer Hz units)
    // HyperRAM configuration (parameter defaults are also HyperRAM device defaults)
    parameter string DRIVE_STRENGTH       = "34ohm",
    parameter int    INITIAL_LATENCY      = 7,
    parameter bit    FIXED_LATENCY_ENABLE = 1'b1,
    parameter bit    HYBRID_BURST_ENABLE  = 1'b1,
    parameter int    BURST_LENGTH         = 32,
    parameter bit    MASTER_CLOCK_TYPE    = 1'b1
    // NOTE: there are more detailed comments in the code below
)(
    // control interface
    input  logic          ctl_clk,    // clock (independent from system bus clock)
    input  logic          ctl_rst,    // reset (independent from system bus reset)
    input  logic          ctl_valid,  // handshake valid (the interface is always ready)
    input  logic  [4-1:0] ctl_addr ,  // write address
    input  logic  [8-1:0] ctl_data ,  // write data
    // system clock/reset
    input  logic          clk,
    input  logic          clk_p,      // phase-shifted clock for driving O_psram_ck
    input  logic          rstn,
    output logic          init_done,  // indicates the end of initialization delay
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
// HyperRAM configuration/status interface
///////////////////////////////////////////////////////////////////////////////

    // deep power down enable
    localparam [15:15] CR0_DEEP_PD = 1'b1;  // normal operation (default)

    // drive strength
    localparam [07:04] CR0_DRIVE = DRIVE_STRENGTH ==  "34ohm" ? 3'b000 :  // (default)
                                   DRIVE_STRENGTH == "115ohm" ? 3'b001 :
                                   DRIVE_STRENGTH ==  "67ohm" ? 3'b010 :
                                   DRIVE_STRENGTH ==  "46ohm" ? 3'b011 :
                                   DRIVE_STRENGTH ==  "34ohm" ? 3'b100 :
                                   DRIVE_STRENGTH ==  "27ohm" ? 3'b101 :
                                   DRIVE_STRENGTH ==  "22ohm" ? 3'b110 :
                                   DRIVE_STRENGTH ==  "19ohm" ? 3'b111 :
                                                                3'bxxx;

    // reserved
    localparam [11:08] CR0_RESERVED = 4'b1111;  // (default)

    // initial latency
    localparam [07:04] CR0_LATENCY = INITIAL_LATENCY == 3 ? 4'b1110 :  // CLK <=  83MHz
                                     INITIAL_LATENCY == 4 ? 4'b1111 :  // CLK <= 100MHz
                                     INITIAL_LATENCY == 5 ? 4'b0000 :  // CLK <= 133MHz
                                     INITIAL_LATENCY == 6 ? 4'b0001 :  // CLK <= 166MHz
                                     INITIAL_LATENCY == 7 ? 4'b1110 :  // CLK <= 200MHz (default)
                                                            4'bxxxx;

    // fixed latency enable
    localparam [03:03] CR0_FIXED = FIXED_LATENCY_ENABLE ? 1'b1    // fixed 2 times initial latency (default)
                                                        : 1'b0;   // variable latency

    // hybrid burst enable
    localparam [03:03] CR0_HYBRID = HYBRID_BURST_ENABLE ? 1'b1    // wrapped burst sequences in legacy wrapped burst manner (default)
                                                        : 1'b0;   // wrapped burst sequences to follow hybrid burst sequencing

    // burst length
    localparam [01:00] CR0_BURST = BURST_LENGTH == 128 ? 2'b00 :
                                   BURST_LENGTH ==  64 ? 2'b01 :
                                   BURST_LENGTH ==  16 ? 2'b10 :
                                   BURST_LENGTH ==  32 ? 2'b11 :  // (default)
                                                         2'bxx;

    // reserved
    localparam [15:07] CR1_RESERVED = {8'hFF, 1'b1};  // (default)

    // master clock type
    localparam [06:06] CR1_CLOCK = MASTER_CLOCK_TYPE ? 1'b1   // single ended (default)
                                                     : 1'b0;  // differential

    // hybrid sleep
    localparam [05:05] CR1_SLEEP = 1'b0;  // normal operation (default)

    // partial array refresh
    localparam [04:02] CR1_PARTIAL = 3'b000;  // full array 2 times (default)

    // distributed refresh interval
    localparam [04:02] CR1_DISTRIBUTED = 2'b01;  // 4us (default)

    // configuration sequence memory
    logic [16-1:0] cfg_mem [0:16-1] = '{
        // Configuration Register 0 Write
        {2'd0, 2'd0}: {8'h60, 8'h00},  // CA[47:32]
        {2'd0, 2'd1}: {8'h01, 8'h00},  // CA[31:16]
        {2'd0, 2'd2}: {8'h00, 8'h00},  // CA[15:00]
        {2'd0, 2'd3}: {CR0_DEEP_PD, CR0_DRIVE, CR0_RESERVED, CR0_LATENCY, CR0_FIXED, CR0_HYBRID, CR0_BURST},
        // Configuration Register 1 Write
        {2'd1, 2'd0}: {8'h60, 8'h00},  // CA[47:32]
        {2'd1, 2'd1}: {8'h01, 8'h00},  // CA[31:16]
        {2'd1, 2'd2}: {8'h00, 8'h01},  // CA[15:00]
        {2'd1, 2'd3}: {CR1_RESERVED, CR1_CLOCK, CR1_SLEEP, CR1_PARTIAL, CR1_DISTRIBUTED},
        default: '0
    };

    // configuration memory readout signals
    logic  [2-1:0] cfg_cnt;
    logic  [2-1:0] cfg_idx;
    logic [16-1:0] cfg_dq;

    // write to configuration memory (big endian)
    always_ff @(ctl_clk)
    if (ctl_valid) begin
        if (ctl_addr[0]) cfg_mem[ctl_addr][07:00] <= ctl_data;
        else             cfg_mem[ctl_addr][15:08] <= ctl_data;
    end

    // configuration memory readout
    assign cfg_dq = cfg_mem[{cfg_idx, cfg_cnt}];

///////////////////////////////////////////////////////////////////////////////
// HyperRAM FSM
///////////////////////////////////////////////////////////////////////////////

    localparam [2-1:0] FSM_INIT   = 3'd0;
    localparam [2-1:0] FSM_IDLE   = 3'd1;
    localparam [2-1:0] FSM_READ   = 3'd2;
    localparam [2-1:0] FSM_WRITE  = 3'd3;

    logic  [2-1:0] fsm_state;
    logic  [8-1:0] fsm_cycle;       // shift register counting cycles
    logic          fsm_write;
    logic          fsm_extended;
    logic [64-1:0] dq_sr;           // shifts left 8-bit every cycle
    logic [16-1:0] w_data_w;
    logic          wait_for_rd_data;

    // DDR input/output signals
    logic         sdr_ck_e;
    logic         sdr_ck_e_p;
    logic         sdr_cs_n;
    logic         sdr_rwds_t;
    logic         sdr_rwds_o_p;
    logic         sdr_rwds_o_n;
    wire          sdr_rwds_i_p;
    wire          sdr_rwds_i_n;
    logic         sdr_dq_t;
    wire  [8-1:0] sdr_dq_o_p;
    wire  [8-1:0] sdr_dq_o_n;
    wire  [8-1:0] sdr_dq_i_p;
    wire  [8-1:0] sdr_dq_i_n;

    // configuration memory addressing
    assign cfg_cnt = fsm_cycle[1:0];
    assign cfg_idx = 2'b0;

    // multiplexing data paths
    assign sdr_dq_o_p = (fsm_state == FSM_INIT) ? cfg_dq[07:00] : dq_sr[63:56];
    assign sdr_dq_o_n = (fsm_state == FSM_INIT) ? cfg_dq[15:08] : dq_sr[55:48];

    // Main FSM for HyperRAM read/write
    always @(posedge clk)
    if (~rstn) begin
        // FSM
        fsm_state        <= FSM_INIT;
        fsm_cycle        <= 0;
        fsm_write        <= 1'b0;
        fsm_extended     <= 1'b0;
        dq_sr            <= '0;
        w_data_w         <= 0;
        wait_for_rd_data <= 1'b0;
        // DDR input output
        sdr_ck_e     <= 0;
        sdr_ck_e_p   <= 1'b0;
        sdr_cs_n     <= 1;
        sdr_rwds_o_p <= 1'b0;
        sdr_rwds_o_n <= 1'b0;
        sdr_rwds_t   <= 1'b1;
        sdr_dq_t     <= 1'b1;
    end else begin
        dq_sr <= {dq_sr[47:0], 16'b0};          // shift 16-bits each cycle

        // TODO: maybe driving this on the clock negative edge would make sense
        sdr_ck_e_p <= sdr_ck_e;

        // sample RWDS to see if additional latency is requested
        if (fsm_cycle == 5) begin
            fsm_extended <= sdr_rwds_i_n;
        end

        unique0 case (fsm_state)
        FSM_INIT: begin
            if (init_pulse) begin
                fsm_write     <= 1'b1;
                sdr_ck_e <= 1;      // this needs to be earlier 1 cycle to allow for phase shifted clk_p
                sdr_cs_n <= 0;
                sdr_dq_t <= 0;
            end else if (init_done) begin
                fsm_cycle <= fsm_cycle + 1;
                if (fsm_cycle == 3) begin
                    fsm_state <= FSM_IDLE;
                    fsm_cycle <= 24'b0;
                    sdr_ck_e <= 0;
                    sdr_cs_n <= 1;
                end
            end
        end
        FSM_IDLE: begin
            sdr_rwds_t <= 1;
            if (bus_valid) begin
                // start read/write operation
                fsm_state <= bus_write ? FSM_WRITE : FSM_READ;
                fsm_write <= bus_write;
                        //      14-bit                     18-bit   13-bit   3-bit             total 48-bit CA
                dq_sr <= {~bus_write, 13'b010_0000_0000_00, bus_addr[21:4], 13'b0, bus_addr[3:1], 16'b0000_0100_1101_0100};
                sdr_ck_e <= 1;
                sdr_cs_n <= 0;
                wait_for_rd_data <= 0;
                w_data_w <= bus_dataw;
            end
        end
        FSM_READ: begin
            fsm_cycle <= fsm_cycle + 1;
            if (fsm_cycle == INITIAL_LATENCY) begin
                sdr_dq_t <= ~fsm_write;
            end
            if (fsm_cycle == 8)
                wait_for_rd_data <= 1;
            if (wait_for_rd_data && (sdr_rwds_i_p ^ sdr_rwds_i_n)) begin     // sample rwds falling edge to get a word / \_
                sdr_cs_n <= 1;
                sdr_ck_e <= 0;
                fsm_state <= FSM_IDLE;
                fsm_cycle <= 0;
            end
        end
        FSM_WRITE: begin
            fsm_cycle <= fsm_cycle + 1;
            if (fsm_cycle == INITIAL_LATENCY) begin
                sdr_dq_t <= ~fsm_write;
                sdr_rwds_t <= 0;
            end
            // If it is low, data starts at 2+LATENCY. If high, then data starts at 2+LATENCY*2.
            if (fsm_extended ? (fsm_cycle == 1+INITIAL_LATENCY*2) : (fsm_cycle == 1+INITIAL_LATENCY))
            begin
                sdr_rwds_o_p <= ~bus_bytee[0];
                sdr_rwds_o_n <= ~bus_bytee[1];
                dq_sr[63:48] <= w_data_w;
            end
            if (fsm_extended ? (fsm_cycle == 2+INITIAL_LATENCY*2) : (fsm_cycle == 2+INITIAL_LATENCY))
            begin
                fsm_state <= FSM_IDLE;
                fsm_cycle <= 0;
                sdr_ck_e <= 0;
                sdr_cs_n <= 1;
            end
        end
        endcase
    end

///////////////////////////////////////////////////////////////////////////////
// system bus
///////////////////////////////////////////////////////////////////////////////

    assign bus_datar = {sdr_dq_i_p, sdr_dq_i_n};

    assign bus_busy = (fsm_state != FSM_IDLE);

///////////////////////////////////////////////////////////////////////////////
// HyperRAM RESET# output
///////////////////////////////////////////////////////////////////////////////

    OBUF obuf_reset_n (
        .O   (O_psram_reset_n),
        .I   (rstn)
    );

///////////////////////////////////////////////////////////////////////////////
// HyperRAM CK/CK# output
///////////////////////////////////////////////////////////////////////////////

    wire ddr_ck_o;    // IO output
    wire ddr_ck_n_o;  // IO output

    // Note: ck uses phase-shifted clock clk_p
    ODDR oddr_ck (
        .Q0  (ddr_ck_o),
        .Q1  (),
        .D0  (sdr_ck_e_p),
        .D1  (1'b0),
        .TX  (1'b1),
        .CLK (clk_p)
    );

    ODDR oddr_ck_n (
        .Q0  (ddr_ck_n_o),
        .Q1  (),
        .D0  (~sdr_ck_e_p),
        .D1  (1'b1),
        .TX  (1'b1),
        .CLK (clk_p)
    );

    OBUF obuf_ck (
        .O   (O_psram_ck),
        .I   (ddr_ck_o)
    );

    OBUF obuf_ck_p (
        .O   (O_psram_ck_n),
        .I   (ddr_ck_n_o)
    );

///////////////////////////////////////////////////////////////////////////////
// HyperRAM CS# output
///////////////////////////////////////////////////////////////////////////////

    wire ddr_cs_n_o;  // IO output

    ODDR oddr_cs_n (
        .Q0  (ddr_cs_n_o),
        .Q1  (),
        .D0  (sdr_cs_n),
        .D1  (sdr_cs_n),
        .TX  (1'b1),
        .CLK (clk)
    );

    OBUF obuf_cs_n (
        .O   (O_psram_cs_n),
        .I   (ddr_cs_n_o)
    );

///////////////////////////////////////////////////////////////////////////////
// HyperRAM RWDS output/input
///////////////////////////////////////////////////////////////////////////////

    wire ddr_rwds_o;  // IO output
    wire ddr_rwds_t;  // IO tristate
    wire ddr_rwds_i;  // IO input
    wire ddr_rwds_d;  // IO input delay

    ODDR oddr_rwds (
        .Q0  (ddr_rwds_o),
        .Q1  (ddr_rwds_t),
        .D0  (sdr_rwds_o_p),
        .D1  (sdr_rwds_o_n),
        .TX  (sdr_rwds_t),
        .CLK (clk)
    );

    IOBUF iobuf_rwds (
        .O   (ddr_rwds_i),
        .IO  (IO_psram_rwds),
        .I   (ddr_rwds_o),
        .OEN (ddr_rwds_t)
    );

    IODELAY #(
        .C_STATIC_DLY (0)
    ) idelay_rwds (
        .DO    (ddr_rwds_d),
        .DF    (),
        .DI    (ddr_rwds_i),
        .SDTAP (1'b0),
        .VALUE (1'b0),
        .SETN  (1'b0)
    );

    // Tristate DDR input
    IDDR iddr_rwds (
        .Q0  (sdr_rwds_i_p),
        .Q1  (sdr_rwds_i_n),
        .D   (ddr_rwds_d),
        .CLK (clk)
    );

///////////////////////////////////////////////////////////////////////////////
// HyperRAM DQ output/input
///////////////////////////////////////////////////////////////////////////////

    wire [7:0] ddr_dq_o;  // IO output
    wire [7:0] ddr_dq_t;  // IO tristate
    wire [7:0] ddr_dq_i;  // IO input
    wire [7:0] ddr_dq_d;  // IO input delay

    genvar i;
    generate for (i=0; i<=7; i++) begin: dq

        ODDR #(.TXCLK_POL (1'b1)) oddr_dq (
            .Q0  (ddr_dq_o      [i]),
            .Q1  (ddr_dq_t      [i]),
            .D0  (sdr_dq_o_p[i]),
            .D1  (sdr_dq_o_n[i]),
            .TX  (sdr_dq_t),
            .CLK (clk)
        );

        IOBUF iobuf_dq (
            .O   (ddr_dq_i      [i]),
            .IO  (IO_psram_dq   [i]),
            .I   (ddr_dq_o      [i]),
            .OEN (ddr_dq_t      [i])
        );

        IODELAY #(
            .C_STATIC_DLY (0)
        ) idelay_dq (
            .DO    (ddr_dq_d    [i]),
            .DF    (),
            .DI    (ddr_dq_i    [i]),
            .SDTAP (1'b0),
            .VALUE (1'b0),
            .SETN  (1'b0)
        );

        IDDR iddr_dq (
            .Q0  (sdr_dq_i_p [i]),
            .Q1  (sdr_dq_i_n [i]),
            .D   (ddr_dq_d      [i]),
            .CLK (clk)
        );

    end endgenerate

endmodule

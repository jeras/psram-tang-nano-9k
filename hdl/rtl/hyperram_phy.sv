//
// PSRAM/HyperRAM controller for Tang Nano 9K / Gowin GW1NR-LV9QN88PC6/15.
// Feng Zhou, 2022.8
//
// This is a word or byte based, non-bursting controller for accessing the on-chip HyperRAM.
// - 1:1 clock design. Memory and main logic work under the same clock.
// - Low latency. Under default settings, write latency is 7 cycles (1x) or 10 cycles (2x).
//   Read latency is 12 cycles (1x) or 15 cycles(2x). In my test, 2x latency happens about
//   0.05% of time.

module hyperram_phy #(
    // controller configuration
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
    // NOTE: there are more detailed comments about parameters in the code below
)(
    // control interface
    input  logic          ctl_clk,    // clock (independent from system bus clock)
    input  logic          ctl_rst,    // reset (independent from system bus reset)
    input  logic          ctl_valid,  // handshake valid (the interface is always ready)
    input  logic  [4-1:0] ctl_addr ,  // write address
    input  logic  [8-1:0] ctl_data ,  // write data
    // system clock/reset
    input  logic          clk,        // SDR clock
    input  logic          clk_ck,     // phase-shifted clock for driving CK/CK#
    input  logic          rst,        // SDR reset
    output logic          init_done,  // indicates the end of initialization delay
    // PHY interface: request
    input  logic                  phy_req_valid,  // request handshake valid
    input  logic                  phy_req_type ,  // burst type 0: wrapped, 1: linear
    input  logic                  phy_req_read ,  // 0: write, 1: read
    input  logic [SIZE_WIDTH-1:0] phy_req_size ,  // read sequence size (phy_req_size+1) in 16 bit words
    input  logic [ADDR_WIDTH-1:0] phy_req_addr ,  // word (16-bit) address
    output logic                  phy_req_ready,  // request handshake ready
    // memory PHY interface: write data
    input  logic [BYTE_WIDTH-1:0] phy_wdt_byte ,  // byte enable
    input  logic [DATA_WIDTH-1:0] phy_wdt_data ,  // write data
    input  logic                  phy_wdt_last ,  // last data word in write sequence
    input  logic                  phy_wdt_valid,  // valid write data is available (active clock stop)
    output logic                  phy_wdt_ready,  // ready to accept write data
    // memory PHY interface: read data
    output logic [DATA_WIDTH-1:0] phy_rdt_data ,  // read data (byte enable is ignored)
    output logic                  phy_rdt_strb ,  // strobe read data word
    input  logic                  phy_rdt_pause,  // pause data strobes after ODDR delay (active clock stop)
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

    // T_VCS power voltage (or reset release) to chip select time (150us)
    // WARNING: be careful about integer division rounding errors
    localparam T_VCS_VAL = FREQUENCY / 1000 * 150 / 1000;
    localparam T_VCS_WIDTH = $clog2(T_VCS_VAL-1);

    logic  [T_VCS_WIDTH-1:0] init_counter;    // counter value
    logic  [T_VCS_WIDTH  :0] init_decrement;  // counter decremented value
    logic                    init_underflow;  // counter underflow
    logic                    init_pulse;      // initialization pulse

    always_ff @(posedge clk, negedge rst)
    if (rst) begin
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
    // TODO: check the burst type bit, Infinieon seems to have preferences
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

    // system bus signals
    wire           phy_transfer;

    // FSM signals
    logic          fsm_cycle;
    logic          fsm_config;
    logic          fsm_write;
    logic          fsm_read;
    logic  [8-1:0] fsm_cnt;       // cycle counter
    logic          fsm_last;
    logic          fsm_extended;
    logic [48-1:0] fsm_ac_cmb;   // address-control [47:0] combinational
    logic [32-1:0] fsm_ac_reg;   // address-control [31:0] shift register

    localparam FIFO_SIZE = 16;
    localparam FIFO_LOG2 = $clog2(FIFO_SIZE);

    // write data FIFO
    logic [BYTE_WIDTH+DATA_WIDTH-1:0] fifo_mem [0:FIFO_SIZE-1];
    logic [BYTE_WIDTH+DATA_WIDTH-1:0] fifo_data;
    logic [FIFO_LOG2-1:0] fifo_idx_i;
    logic [FIFO_LOG2-1:0] fifo_idx_o;

    // DQ path multiplexer
    logic [2-1:0] fsm_dq_s;  // select
    logic [8-1:0] fsm_dq_p [0:4-1];
    logic [8-1:0] fsm_dq_n [0:4-1];

    // DDR input/output signals
    logic         sdr_ck_e;
    logic         sdr_ck_e_dly;
    logic         sdr_cs_n;
    logic         sdr_rwds_t;
    logic         sdr_rwds_o_p;
    logic         sdr_rwds_o_n;
    wire          sdr_rwds_i_p;
    wire          sdr_rwds_i_n;
    logic         sdr_dq_t;
    logic [8-1:0] sdr_dq_o_p;
    logic [8-1:0] sdr_dq_o_n;
    wire  [8-1:0] sdr_dq_i_p;
    wire  [8-1:0] sdr_dq_i_n;

    // configuration memory addressing
    assign cfg_cnt = fsm_cnt[1:0];
    assign cfg_idx = 2'b0;

    // RWDS
    assign sdr_rwds_o_p = fifo_data[16];
    assign sdr_rwds_o_n = fifo_data[17];

    // AC field range:   [47]        , [46], [45]        , [44:16]           , [15:3]  , [2:0]
    // AC field name:    R/W#        , AS  , burst type  , address           , reserved, address
    assign fsm_ac_cmb = {phy_req_read, 1'b0, phy_req_type, phy_req_addr[31:3], 13'b0   , phy_req_addr[2:0]};

    // DQ multiplexer array
    //                  configuration   , AC (combinational)  , AC (shift register) , write data
    assign fsm_dq_p = '{0: cfg_dq[15:08], 1: fsm_ac_cmb[47:40], 2: fsm_ac_reg[31:24], 3: fifo_data[07:00]};
    assign fsm_dq_n = '{0: cfg_dq[07:00], 1: fsm_ac_cmb[39:32], 2: fsm_ac_reg[23:16], 3: fifo_data[15:08]};

    // DQ multiplexer
    assign sdr_dq_o_p = fsm_dq_p[fsm_dq_s];
    assign sdr_dq_o_n = fsm_dq_n[fsm_dq_s];

    // DQ multiplexer select
    always_comb begin
        if      (fsm_config)    fsm_dq_s = 2'd0;  // configuration
        else if (phy_transfer)  fsm_dq_s = 2'd1;  // AC (combinational)
        else if (fsm_cnt < 4)   fsm_dq_s = 2'd2;  // AC (registered)
        else                    fsm_dq_s = 2'd3;  // write data
    end

//    // DQ multiplexer select
//    always_ff @(posedge clk)
//    if (rst) begin
//        fsm_dq_s <= 2'd0;  // configuration
//    end else begin
//        if (fsm_cycle == FSM_INIT)  fsm_dq_s <= 2'd0;  // configuration
//        else if (phy_transfer)      fsm_dq_s <= 2'd1;  // AC (combinational)
//        else if (fsm_cnt < 4)     fsm_dq_s <= 2'd2;  // AC (registered)
//        else                        fsm_dq_s <= 2'd3;  // write data
//    end

    // SDR signals
//    always_comb begin
//        if (((fsm_cycle == FSM_INIT) & init_done) | ((fsm_cycle == FSM_IDLE) & phy_transfer)) begin
//            sdr_ck_e <= 1;      // this needs to be earlier 1 cycle to allow for phase shifted clk_ck
//            sdr_cs_n <= 0;
//            sdr_dq_t <= 0;
//    end

    // FSM last
    always_comb
    if (fsm_config) begin
        fsm_last = fsm_cnt[1:0] == 2'd3;
    end else begin
        fsm_last = fsm_extended ? (fsm_cnt == 2+INITIAL_LATENCY*2) : (fsm_cnt == 2+INITIAL_LATENCY);
    end

    // SDR CK CS#
    always_comb begin
        sdr_ck_e   =   init_pulse | phy_transfer | fsm_cycle & ~fsm_last;
        sdr_cs_n   = ~(init_pulse | phy_transfer | fsm_cycle & ~fsm_last);
        sdr_dq_t   = ~(init_pulse | phy_transfer | fsm_cycle & ~fsm_last);
    end

//                if (fsm_extended ? (fsm_cnt == 1+INITIAL_LATENCY*2) : (fsm_cnt == 1+INITIAL_LATENCY)) begin
//                sdr_dq_t <= 1'b0;
//                sdr_rwds_t <= 1'b0;

    // Main FSM for HyperRAM read/write
    always_ff @(posedge clk)
    if (rst) begin
        // FSM
        fsm_cycle        <= 1'b0;
        fsm_config       <= 1'b0;
        fsm_write        <= 1'b0;
        fsm_read         <= 1'b0;
        fsm_cnt          <= 0;
        fsm_extended     <= 1'b0;
        fsm_ac_reg       <= '0;
    end else begin
        // FSM counter
        if (fsm_last)  fsm_cnt <= 'd0;
        else           fsm_cnt <= fsm_cnt + fsm_cycle;
        // sample RWDS to see if additional latency is requested
        if (fsm_cnt == 5) begin
            fsm_extended <= sdr_rwds_i_n;
        end
        // before read data becomes valid, copy ...
        if (fsm_cnt == 8)  fsm_read <= ~fsm_write;

        // IDLE
        if (~fsm_cycle) begin
            if (init_pulse | phy_transfer) begin
                fsm_cycle  <= 1'b1;
                fsm_config <= init_pulse;
            end
            if (phy_transfer) begin
                fsm_write <= phy_req_read;
                fsm_read  <= 1'b0;
                fsm_ac_reg <= fsm_ac_cmb[31:0];
            end
        end
        // CYCLE
        else begin
            if (fsm_last) begin
                fsm_cycle  <= 1'b0;
                fsm_config <= 1'b0;
                fsm_write  <= 1'b0;
                fsm_read   <= 1'b0;
            end
            fsm_ac_reg[31:16] <= fsm_ac_reg[15:0];
//            if (fsm_cnt == INITIAL_LATENCY) begin
//                sdr_dq_t <= 1'b1;
//            end
        end
    end

    // delayed SDR clock
    // TODO: maybe driving this on the clock negative edge would make sense
    always_ff @(posedge ~clk)
    if (rst)  sdr_ck_e_dly <= 1'b0;
    else        sdr_ck_e_dly <= sdr_ck_e;

///////////////////////////////////////////////////////////////////////////////
// system bus
///////////////////////////////////////////////////////////////////////////////

    logic [7-1:0] phy_cntw_reg;
    logic [7-0:0] phy_cntw_nxt;
    logic         phy_cntw_end;

    // request handshake transfer
    assign phy_transfer = phy_req_valid & phy_req_ready;

    // write data counter
    always_ff @(posedge clk, negedge rst)
    if (rst) begin
        phy_cntw_reg <= 7'd0;
    end else begin
        if (phy_transfer) begin
            phy_cntw_reg <= phy_req_size;
        end else if (~phy_cntw_end) begin
            phy_cntw_reg <= phy_cntw_nxt[6:0];
        end
    end

    assign phy_cntw_nxt = {1'b0, phy_cntw_reg} - 'd1;
    assign phy_cntw_end = phy_cntw_nxt[7];

    // write data FIFO write index
    always_ff @(posedge clk, negedge rst)
    if (rst) begin
        fifo_idx_i <= 'd0;
    end else begin
        if (phy_cntw_end) begin
            fifo_idx_i <= 'd0;
        end else if (phy_transfer | ~phy_cntw_end) begin
            fifo_idx_i <= fifo_idx_i + 'd1;
        end
    end

    // FIFO input data write
    always_ff @(posedge clk)
    if ((phy_transfer & ~phy_req_read) | ~phy_cntw_end) begin
        fifo_mem[fifo_idx_i] <= {phy_wdt_byte, phy_wdt_data};
    end

    // FIFO output data index
    // TODO
    assign fifo_idx_o = 'd0;

    // FIFO output data read
    // TODO: registered?
    assign fifo_data = fifo_mem[fifo_idx_o];

    // system bus read data
    assign phy_rdt_data = {sdr_dq_i_p, sdr_dq_i_n};

    // system bus read data pulse
    assign phy_pulse = fsm_read & (sdr_rwds_i_p ^ sdr_rwds_i_n);

    assign phy_req_ready = ~fsm_cycle & init_done;

///////////////////////////////////////////////////////////////////////////////
// HyperRAM RESET# output
///////////////////////////////////////////////////////////////////////////////

    logic sdr_reset_n;
    logic ddr_reset_n_o;

    always_ff @(posedge clk, posedge rst)
    if (rst)  sdr_reset_n <= 1'b0;
    else      sdr_reset_n <= 1'b1;

    ODDR oddr_rst (
        .Q0  (ddr_reset_n_o),
        .Q1  (),
        .D0  (sdr_reset_n),
        .D1  (sdr_reset_n),
        .TX  (1'b1),
        .CLK (clk)
    );

    OBUF obuf_reset_n (
        .O   (O_psram_reset_n),
        .I   (ddr_reset_n_o)
    );

///////////////////////////////////////////////////////////////////////////////
// HyperRAM CK/CK# output
///////////////////////////////////////////////////////////////////////////////

    wire ddr_ck_o;    // IO output
    wire ddr_ck_n_o;  // IO output

    // Note: ck uses phase-shifted clock clk_ck
    ODDR oddr_ck (
        .Q0  (ddr_ck_o),
        .Q1  (),
        .D0  (sdr_ck_e_dly),
        .D1  (1'b0),
        .TX  (1'b1),
        .CLK (clk_ck)
    );

    ODDR oddr_ck_n (
        .Q0  (ddr_ck_n_o),
        .Q1  (),
        .D0  (~sdr_ck_e_dly),
        .D1  (1'b1),
        .TX  (1'b1),
        .CLK (clk_ck)
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

    ODDR #(.TXCLK_POL (1'b1)) oddr_rwds (
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
    generate
    for (i=0; i<=7; i++) begin: dq

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

    end: dq
    endgenerate

endmodule: hyperram_phy

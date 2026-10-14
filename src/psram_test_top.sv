

module memory_test (
    input  wire        sys_clk,  // 27 Mhz, crystal clock from board
    input  wire        sys_resetn,
    input  wire        button,   // 0 when pressed

    output wire  [5:0] led,
    output wire        uart_txp,

    // Magic ports for PSRAM to be inferred
    output wire  [1:0]  O_psram_reset_n,
    output wire  [1:0]  O_psram_ck,
    output wire  [1:0]  O_psram_ck_n,
    output wire  [1:0]  O_psram_cs_n,
    inout  wire  [1:0] IO_psram_rwds,
    inout  wire [15:0] IO_psram_dq
);

    // Customization of the test
    localparam [21:0] BYTES = 1024*1024;    // Test write/read this many bytes

    // Change PLL and here to choose another speed.
    localparam FREQUENCY = 81_000_000;
    localparam LATENCY = 3;
    //localparam FREQUENCY = 102_600_000;
    //localparam LATENCY = 4;

    // Remove UART print module for timing closure (check LED5 for error)
    `define NO_UART_PRINT

    // For GAO debug
    //localparam [21:0] BYTES = 2;
    localparam NO_PAUSE = 1;
    //localparam NO_PAUSE = 0;                // Pause between states to allow UART printing

///////////////////////////////////////////////////////////////////////////////
// clock and reset
///////////////////////////////////////////////////////////////////////////////

    wire clk, clk_p;
    reg rstn_r1, rstn_r2, rstn;

    // reset resynchronization
    always @(posedge clk, negedge sys_resetn)
    if (~sys_resetn) begin
        rstn_r1 <= 1'b0;
        rstn_r2 <= 1'b0;
        rstn    <= 1'b0;
    end else begin
        rstn_r1 <= sys_resetn;
        rstn_r2 <= rstn_r1;
        rstn    <= rstn_r2;
    end

    Gowin_rPLL pll(
        .clkout  (clk),        // MHZ main clock
        .clkoutp (clk_p),      // MHZ phase shifted (90 degrees)
        .clkin   (sys_clk)     // 27Mhz oscillator clock
    );

///////////////////////////////////////////////////////////////////////////////
// Memory Controller under test
///////////////////////////////////////////////////////////////////////////////

    // system bus
    logic          bus_valid;
    logic          bus_write;
    logic  [2-1:0] bus_bytee;
    logic [22-1:0] bus_addr;
    logic [16-1:0] bus_dataw;
    logic [16-1:0] bus_datar;
    logic          bus_busy;

    psram_controller #(
        // controller configuration
        .FREQUENCY       (FREQUENCY),
        // HyperRAM device configuration
        .INITIAL_LATENCY (LATENCY)
    ) mem_ctrl (
        // configuration/status interface
        .cfg_valid       (1'b0),
        .cfg_addr        (4'hx),
        .cfg_data        (8'hxx),
        // system clock/reset
        .clk             (clk),
        .clk_p           (clk_p),
        .rstn            (rstn),
        .init_done       (),
        // system bus
        .bus_valid       (bus_valid),
        .bus_write       (bus_write),
        .bus_addr        (bus_addr ),
        .bus_bytee       (bus_bytee),
        .bus_dataw       (bus_dataw),
        .bus_datar       (bus_datar),
        .bus_busy        (bus_busy ),
        // HyperRAM
        .O_psram_reset_n (O_psram_reset_n[0]),
        .O_psram_ck      (O_psram_ck     [0]),
        .O_psram_ck_n    (O_psram_ck_n   [0]),
        .O_psram_cs_n    (O_psram_cs_n   [0]),
        .IO_psram_rwds   (IO_psram_rwds  [0]),
        .IO_psram_dq     (IO_psram_dq  [7:0])
    );

    // unused second PSRAM device
    assign  O_psram_reset_n [1] = 1'b0;
    assign  O_psram_ck      [1] = 1'bz;
    assign  O_psram_ck_n    [1] = 1'bz;
    assign  O_psram_cs_n    [1] = 1'bz;
    assign IO_psram_rwds    [1] = 1'bz;
    assign IO_psram_dq   [15:8] = 1'bz;

///////////////////////////////////////////////////////////////////////////////
// test FSM
///////////////////////////////////////////////////////////////////////////////

    localparam [3:0] TEST_ZERO               = 4'd0;
    localparam [3:0] TEST_INIT               = 4'd1;
    localparam [3:0] TEST_WRITE              = 4'd2;
    localparam [3:0] TEST_READ               = 4'd3;
    localparam [3:0] TEST_DONE               = 4'd4;
    localparam [3:0] TEST_FAIL_INIT_TIMEOUT  = 4'd5;
    localparam [3:0] TEST_FAIL_WRITE_TIMEOUT = 4'd6;
    localparam [3:0] TEST_FAIL_READ_TIMEOUT  = 4'd7;
    localparam [3:0] TEST_FAIL_READ_WRONG    = 4'd8;
    localparam [3:0] PAUSE                   = 4'd9;

    // pass in address to get hash value
    `define hash(a) (a[7:0] ^ a[15:8] ^ a[21:16] ^ 8'hc3)

    // local signals
    logic  [8-1:0] datar_byte;
    logic          datar_parity;

    logic    [3:0] state, new_state;
    logic    [4:0] cycle = 0;        // max 16
    logic [24-1:0] write_1x, write_2x, read_1x, read_2x;        // counter for 1x or 2x latencies
    logic          tick;             // pulse once per 0.1 second
    logic    [3:0] ticks = 0;        // counter for 0.1 second delays
    logic          error;

    // pipeline addr+1 to meet timing constraint
    logic  [9-1:0] new_addr_0;
    logic  [9-1:0] new_addr_1;
    logic [22-1:0] new_addr;        // available after 3 cycles

    assign datar_byte = bus_addr[0] ? bus_datar[15:8] : bus_datar[7:0];
    assign datar_parity = ^datar_byte;

    assign led = ~{error, datar_parity, state};

    always @(posedge clk)
    if (~rstn) begin
        new_addr_0 <= 9'h000;
        new_addr_1 <= 9'h000;
        new_addr   <= 22'h000000;
    end else begin
        // stage 0
        new_addr_0 <= bus_addr[7:0] + 1;
        // stage 1
        new_addr_1 <= bus_addr[15:8] + new_addr_0[8];
        // stage 2, add higher 6 bits
        new_addr <= {bus_addr[21:16] + new_addr_1[8], new_addr_1[7:0], new_addr_0[7:0]};
    end

    always @(posedge clk)
    if (~rstn) begin
        // system bus
        bus_valid  <= 1'b0;
        bus_write  <= 1'b0;
        bus_addr   <= 22'd0;
        bus_bytee  <= 2'b00;
        bus_dataw  <= 16'h000;
        // local signals
        ticks      <= 0;
        cycle      <= 0;
        new_state  <= TEST_INIT;
        state      <= PAUSE;
        error      <= 0;
        write_1x   <= 0;
        write_2x   <= 0;
        read_1x    <= 0;
        read_2x    <= 0;
    end else begin
        // default values
        bus_valid <= 0;
        bus_write <= 0;
        bus_bytee <= 2'b00;
        ticks <= tick && (state == TEST_INIT || state == PAUSE) ? ticks + 1 : ticks;

        if (state == TEST_ZERO) begin
            cycle <= 0;
            ticks <= 0;
            new_state <= TEST_INIT;
            state <= PAUSE;
            error <= 0;

        end else if (state == TEST_INIT) begin
            // wait for memory to become ready
            if (!bus_busy) begin
                new_state <= TEST_WRITE;
                state <= PAUSE;
            end else if (ticks == 5) begin   // 0.5 second timeout
                new_state <= TEST_FAIL_INIT_TIMEOUT;
                error <= 1'b1;
                state <= PAUSE;
            end

        end if (state == TEST_WRITE) begin
            // write some bytes
            cycle <= cycle + 1;
            if (cycle == 0) begin
                // issue write command
                bus_valid <= 1'b1;
                bus_write <= 1'b1;
                bus_dataw <= {`hash(bus_addr), `hash(bus_addr)};
            end else if (!bus_valid && !bus_busy) begin
                // write finished
                cycle <= 0;
                if (cycle > 4+LATENCY)
                    write_2x <= write_2x + 1;
                else
                    write_1x <= write_1x + 1;
                if (bus_addr == BYTES - 1) begin
                    new_state <= TEST_READ;
                    state <= PAUSE;
                end else
                    bus_addr <= new_addr;
                    bus_bytee <= new_addr[0] ? 2'b10 : 2'b01;
            end else if (cycle == 5+LATENCY*2) begin
                new_state <= TEST_FAIL_WRITE_TIMEOUT;
                error <= 1'b1;
                state <= PAUSE;
            end

        end if (state == TEST_READ) begin
            // read and verify some bytes
            cycle <= cycle + 1;
            if (cycle == 0) begin
                // issue read command
                bus_valid <= 1'b1;
                bus_write <= 1'b0;
            end else if (!bus_valid && !bus_busy) begin
                // read finished
                cycle <= 0;
                if (cycle > 10+LATENCY)     // read_is on cycle 1, so cycle==13 means latency is 12
                    read_2x <= read_2x + 1;
                else
                    read_1x <= read_1x + 1;
                if (datar_byte != `hash(bus_addr)) begin
                    new_state <= TEST_FAIL_READ_WRONG;
                    error <= 1'b1;
                    state <= PAUSE;
                end else if (bus_addr == BYTES - 1) begin
                    new_state <= TEST_DONE;
                    state <= PAUSE;
                end else
                    bus_addr <= new_addr;
            end else if (cycle == 10+LATENCY*2) begin
                new_state <= TEST_FAIL_READ_TIMEOUT;
                error <= 1'b1;
                state <= PAUSE;
            end

        end else if (state == PAUSE) begin
            // pause for 0.1 seconds for print to finish, then enter new_state
            if (ticks == 2 || NO_PAUSE) begin     // pause for 0.1 second
                ticks <= 0;
                state <= new_state;
            end
        end
    end

    reg [23:0] tick_counter;        // max 16M

    always @(posedge clk)
    if (~rstn) begin
        tick_counter <= FREQUENCY/10;
        tick <= 1'b0;
    end else begin
        tick_counter <= tick_counter == 0 ? FREQUENCY/10 : tick_counter - 1;
        tick <= tick_counter == 0;
    end

///////////////////////////////////////////////////////////////////////////////
// print control
///////////////////////////////////////////////////////////////////////////////

    `ifndef NO_UART_PRINT
    `include "print.v"

    defparam tx.uart_freq=115200;
    defparam tx.clk_freq=FREQUENCY;

    assign print_clk = clk;
    assign txp = uart_txp;

    reg [3:0] state_p;
    reg [3:0] print_counters = 0;       // 1. "write_1x=", 2. write_1x, 3. ", write_2x=", 4. write_2x, 5. ", read_1x=", 6. "read_1x", 7, ", read_2x=", 8. read_2x., 9. "\n"
    reg [3:0] print_counters_p;

    always @(posedge clk) begin
        state_p <= state;
        print_counters_p <= print_counters;
        if (state != state_p) begin
            if (state == TEST_INIT) `print("Initializing HyperRAM test...\n", STR);
            if (state == TEST_WRITE) `print("Writing...\n", STR);
            if (state == TEST_READ) `print("Readata_wg...\n", STR);
            if (state == TEST_DONE) `print("All done successfully.\n", STR);
            if (state == TEST_FAIL_INIT_TIMEOUT) `print("FAIL. Initialization timeout.\n", STR);
            if (state == TEST_FAIL_WRITE_TIMEOUT) `print("FAIL. Write time out.\n", STR);
            if (state == TEST_FAIL_READ_TIMEOUT) `print("FAIL. Read time out.\n", STR);
            if (state == TEST_FAIL_READ_WRONG) `print("FAIL. Read wrong data.\n", STR);

            if (state == TEST_DONE || state == TEST_FAIL_INIT_TIMEOUT || state == TEST_FAIL_READ_TIMEOUT || state == TEST_FAIL_READ_WRONG || state == TEST_FAIL_WRITE_TIMEOUT)
                print_counters <= 1;
        end

        if (print_counters > 0 && print_counters == print_counters_p && print_state == PRINT_IDLE_STATE) begin
            case (print_counters)
            1: `print("Latency counters: write_1x=", STR);
            2: `print(write_1x, 3);
            3: `print(", write_2x=", STR);
            4: `print(write_2x, 3);
            5: `print(", read_1x=", STR);
            6: `print(read_1x, 3);
            7: `print(", read_2x=", STR);
            8: `print(read_2x, 3);
            9: `print("\n", STR);
            endcase
            print_counters <= print_counters == 9 ? 0 : print_counters + 1;
        end

    end
    `endif

endmodule

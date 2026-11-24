///////////////////////////////////////////////////////////////////////////////
// Tang Nano 9k demo for the embedded flash controller
//
// Copyright 2026 Iztok Jeras <iztok.jeras@gmail.com>
//
// Licensed under CERN-OHL-P v2 or later
///////////////////////////////////////////////////////////////////////////////

module tangnano9k_flash_demo #(
    // 4kB or 2*DPB (each DPB is 16kb organized as 2k 16-bit locations)
    parameter  int unsigned TEST_SIZE = 304*64*4,
    parameter  int unsigned SRAM_SIZE = 4*1024,
    // UART baudrate
    parameter longint       BAUDRATE = 115_200,
    // oscillator frequency
    localparam real         FREQUENCY = 27_000_000,  // 27MHz
    // debounce counter length (frequency * time)
    parameter  int unsigned DEBOUNCE_LENGTH = 270000  // 27MHz * 10ms
)(
    input  logic       XTAL_IN,
    input  logic [2:1] S,
    output logic [6:1] LED,
    input  wire        FPGA_RX,
    output wire        FPGA_TX
);

    // byte address width
    localparam int unsigned ADDR_WIDTH = $clog2(TEST_SIZE);
    localparam int unsigned SRAM_WIDTH = $clog2(SRAM_SIZE);
    // data width (based on flash data bus width)
    localparam int unsigned DATA_WIDTH = 32;
    localparam int unsigned BYTE_WIDTH = DATA_WIDTH/8;

    // UART baudrate calculations
    localparam int unsigned BAUD_RATE = int'(FREQUENCY/real'(BAUDRATE));
    localparam int unsigned BAUD_WIDTH = $clog2(BAUD_RATE);

    // test FSM
    localparam bit [2-1:0] FSM_IDLE = 2'b00;  // idle
    localparam bit [2-1:0] FSM_READ = 2'b10;  // read flash into SRAM
    localparam bit [2-1:0] FSM_SEND = 2'b11;  // send data from SRAM to UART

    // local system signals
    logic clk;
    logic rst;

    // start button
    logic start;
    logic start_btn;
    logic start_reg;

    // button debounce
    logic [2:1] btn;

    // test FSM
    logic          [2-1:0] fsm_state;

    logic [ADDR_WIDTH-1:0] fsm_cnt;
    logic [ADDR_WIDTH-0:0] fsm_cnt_nxt_read;
    logic [ADDR_WIDTH-0:0] fsm_cnt_nxt_send;

    // Flash interface
    logic                  flash_req_transfer;

    logic                  flash_req_valid;
    logic [ADDR_WIDTH-1:0] flash_req_addr ;
    logic                  flash_req_ready;
    logic [DATA_WIDTH-1:0] flash_rdt_data ;

    // dual port SRAM A port (write only)
    logic [SRAM_WIDTH  -1:0]        sram_a_addr;
    logic                           sram_a_enable;
    logic [DATA_WIDTH/8-1:0][8-1:0] sram_a_wdata;
    // dual port SRAM B port (read only)
    logic [SRAM_WIDTH  -1:0]        sram_b_addr;
    logic                           sram_b_enable;
    logic [DATA_WIDTH/8-1:0][8-1:0] sram_b_rdata;

    // UART RX signals
    logic                uart_rx_valid;
    logic        [8-1:0] uart_rx_data ;
    logic                uart_rx_ready;
    logic                uart_rx_transfer;

    // UART TX signals
    logic                uart_tx_valid;
    logic        [8-1:0] uart_tx_data ;
    logic                uart_tx_ready;
    logic                uart_tx_transfer;

    logic [$clog2(BYTE_WIDTH)-1:0] uart_tx_off;  // nibble offset

///////////////////////////////////////////////////////////////////////////////
// system signals
///////////////////////////////////////////////////////////////////////////////

    // system clock
    assign clk = XTAL_IN;

    // button RESET debounce (INIT: detect a button press at power up)
    debounce #(
        .INIT_CDC   (1'b1),
        .INIT_OUT   (1'b0),
        .CNT_LENGTH (DEBOUNCE_LENGTH)
    ) button1 (
        .clk  (clk),
        .d_i  (~S [1]),
        .d_o  (btn[1])
    );

    // button START debounce
    debounce #(
        .INIT_CDC   (1'b1),
        .INIT_OUT   (1'b0),
        .CNT_LENGTH (DEBOUNCE_LENGTH)
    ) button2 (
        .clk  (clk),
        .d_i  (~S [2]),
        .d_o  (btn[2])
    );

    // system reset
    assign rst = btn[1];  // buttons are active low

    // start button
    assign start_btn = btn[2];  // buttons are active low

    // start button register (delay)
    always_ff @(posedge clk, posedge rst)
    if (rst) start_reg <= 1'b0;
    else     start_reg <= start_btn;

    // start pulse
    assign start = start_btn | uart_rx_transfer;

    // LED-s
    assign LED[1] = ~rst;            // reset signal
    assign LED[2] = ~start;          // start button
    assign LED[5] = ~fsm_state[0];   // UART TX active
    assign LED[6] =  fsm_state[1];   // FSM IDLE

///////////////////////////////////////////////////////////////////////////////
// test FSM
///////////////////////////////////////////////////////////////////////////////

    always_ff @(posedge clk, posedge rst)
    if (rst) begin
        fsm_state <= FSM_IDLE;
        fsm_cnt   <= 'd0;
    end else begin
        case (fsm_state)
            FSM_READ:
            if (flash_req_transfer) begin
                if (fsm_cnt_nxt_read[SRAM_WIDTH-1:0] == 0) begin
                    fsm_state <= FSM_SEND;
                end
                fsm_cnt <= fsm_cnt_nxt_read;
            end
            FSM_SEND:
            if (uart_tx_transfer) begin
                if (fsm_cnt_nxt_send[SRAM_WIDTH-1:0] == 0) begin
                    if (fsm_cnt_nxt_send == TEST_SIZE) begin
                        fsm_state <= FSM_IDLE;
                    end else begin
                        fsm_state <= FSM_READ;
                    end
                end
                fsm_cnt <= fsm_cnt_nxt_send;
            end
            // the default includes FSM_IDLE
            default: begin
                if (start) begin
                    fsm_state <= FSM_READ;
                    fsm_cnt   <= 'd0;
                end
            end
        endcase
    end

    assign fsm_cnt_nxt_read = {1'b0, fsm_cnt[ADDR_WIDTH-1:SRAM_WIDTH], SRAM_WIDTH'(fsm_cnt[SRAM_WIDTH-1:0] + (SRAM_WIDTH)'(DATA_WIDTH/8))};
    assign fsm_cnt_nxt_send = {1'b0, fsm_cnt} + (ADDR_WIDTH+1)'(1);

///////////////////////////////////////////////////////////////////////////////
// embedded flash controller instance
///////////////////////////////////////////////////////////////////////////////

    assign flash_req_valid = (fsm_state == FSM_READ);

    assign flash_req_addr = fsm_cnt[ADDR_WIDTH-1:0];

    embedded_flash_controller #(
        .PROTOCOL_CYCLES   (1),
        .PROTOCOL_REGISTER (1'b0)
    ) flash_ctrl (
        // system signals
        .clk  (clk),
        .rst  (rst),
        // system bus
        .bus_req_valid  (flash_req_valid),
        .bus_req_addr   (flash_req_addr ),
        .bus_req_ready  (flash_req_ready),
        .bus_rdt_data   (flash_rdt_data )
    );

    assign flash_req_transfer = flash_req_valid & flash_req_ready;

///////////////////////////////////////////////////////////////////////////////
// SRAM inference
///////////////////////////////////////////////////////////////////////////////

    logic [DATA_WIDTH-1:0] sram_mem [0:SRAM_SIZE/(DATA_WIDTH/8)-1];

    // write port
    always_ff @(posedge clk, posedge rst)
    if (rst)  sram_a_enable <= 1'b0;
    else      sram_a_enable <= flash_req_transfer;

    always_ff @(posedge clk)
    sram_a_addr <= flash_req_addr[SRAM_WIDTH-1:$clog2(BYTE_WIDTH)];

    assign sram_a_wdata = flash_rdt_data;

    // read port
    assign sram_b_addr = fsm_cnt[SRAM_WIDTH-1:$clog2(BYTE_WIDTH)];
    assign sram_b_enable  = 1'b1;

    always_ff @(posedge clk)
    begin
        // write port
        if (sram_a_enable) begin
            sram_mem[sram_a_addr] <= sram_a_wdata;
        end
        // read port
        sram_b_rdata <= sram_mem[sram_b_addr];
    end

///////////////////////////////////////////////////////////////////////////////
// UART RX instance
///////////////////////////////////////////////////////////////////////////////

    logic fpga_rx0;
    logic fpga_rx1;

    // UART RXD CDC (avoiding metastability issues)
    always_ff @(posedge clk)
    {fpga_rx1, fpga_rx0} <= {fpga_rx0, FPGA_RX};

    // UART RX characters must always be accepted
    assign uart_rx_ready = 1'b1;
    assign uart_rx_transfer = uart_rx_valid & uart_rx_ready;

    // deserializer
    tcb_dev_uart_des #(
        .BAUD_WIDTH (BAUD_WIDTH)
    ) uart_rx (
        // system signals
        .clk     (clk),
        .rst     (rst),
        // configuration
        .cfg_bdr (BAUD_RATE[BAUD_WIDTH-1:0]  -BAUD_WIDTH'(1)),
        .cfg_smp (BAUD_RATE[BAUD_WIDTH-1:0]/2-BAUD_WIDTH'(1)),
        // parallel stream
        .str_vld (uart_rx_valid),
        .str_dat (uart_rx_data ),
        // serial RX input
        .rxd     (fpga_rx1)
    );

///////////////////////////////////////////////////////////////////////////////
// UART TX instance
///////////////////////////////////////////////////////////////////////////////

    assign uart_tx_transfer = uart_tx_valid & uart_tx_ready;

    always_ff @(posedge clk, posedge rst)
    if (rst) begin
        uart_tx_valid <= 1'b0;
    end else begin
        uart_tx_valid <= (fsm_state == FSM_SEND);
    end

    // extract a single byte from the data word
    assign uart_tx_off  = fsm_cnt[$clog2(BYTE_WIDTH)-1:0];
    assign uart_tx_data = sram_b_rdata[uart_tx_off[$clog2(BYTE_WIDTH)-1:0]];

    // serializer
    tcb_dev_uart_ser #(
        .BAUD_WIDTH (BAUD_WIDTH)
    ) uart_tx (
        // system signals
        .clk     (clk),
        .rst     (rst),
        // configuration
        .cfg_bdr (BAUD_RATE[BAUD_WIDTH-1:0]-BAUD_WIDTH'(1)),
        // parallel stream
        .str_vld (uart_tx_valid),
        .str_dat (uart_tx_data ),
        .str_rdy (uart_tx_ready),
        // serial TX output
        .txd     (FPGA_TX)
    );

endmodule: tangnano9k_flash_demo

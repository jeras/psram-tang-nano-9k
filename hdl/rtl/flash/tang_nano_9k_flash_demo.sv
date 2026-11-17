///////////////////////////////////////////////////////////////////////////////
// Tang Nano 9k demo for the embedded flash controller
//
// Copyright 2026 Iztok Jeras <iztok.jeras@gmail.com>
//
// Licensed under CERN-OHL-P v2 or later
///////////////////////////////////////////////////////////////////////////////

module tang_nano_9k_flash_demo #(
    // 4kB or 2*DPB (each DPB is 16kb organized as 16-bit 2k locations)
    parameter  int unsigned TEST_SIZE = 4*1024,
    // UART baudrate
    parameter longint       BAUDRATE = 115_200
)(
    input  logic       XTAL_IN,
    input  logic [2:1] S,
    output logic [6:1] LED,
    output wire        FPGA_TX
);

    // system local parameters
    localparam real FREQUENCY = 27_000_000;  // 27MHz
    localparam real DEBOUNCE_TIME = 0.010;  // 10ms

    // byte address width
    localparam int unsigned ADDR_WIDTH = $clog2(TEST_SIZE);
    // data width (based on flash data bus width)
    localparam int unsigned DATA_WIDTH = 32;
    localparam int unsigned BYTE_WIDTH = DATA_WIDTH/8;

    // test FSM
    localparam bit [2-1:0] FSM_READ = 2'b00;  // read flash into SRAM
    localparam bit [2-1:0] FSM_SEND = 2'b01;  // send data from SRAM to UART
    localparam bit [2-1:0] FSM_IDLE = 2'b10;  // idle

    // local system signals
    logic clk;
    logic rst;

    // run button
    logic run;
    logic run_btn;
    logic run_reg;

    // button debounce
    logic [2:1] btn;

    // test FSM
    logic          [2-1:0] fsm_state;

    logic [ADDR_WIDTH-1:-1] fsm_cnt;
    logic [ADDR_WIDTH-0:-1] fsm_cnt_nxt;
    logic [ADDR_WIDTH-0:-1] fsm_cnt_inc;

    // Flash interface
    logic                  flash_req_transfer;

    logic                  flash_req_valid;
    logic [ADDR_WIDTH-1:0] flash_req_addr ;
    logic                  flash_req_ready;
    logic [DATA_WIDTH-1:0] flash_rdt_data ;

    // dual port SRAM A port (write only)
    logic [ADDR_WIDTH  -1:0]        sram_a_addr;
    logic                           sram_a_enable;
    logic [DATA_WIDTH/8-1:0][8-1:0] sram_a_wdata;
    // dual port SRAM B port (read only)
    logic [ADDR_WIDTH  -1:0]        sram_b_addr;
    logic                           sram_b_enable;
    logic [DATA_WIDTH/8-1:0][8-1:0] sram_b_rdata;

    // UART TX signals
    logic                uart_tx_valid;
    logic                uart_tx_ready;

    logic                uart_tx_transfer;

    logic [$clog2(BYTE_WIDTH)-1:-1] uart_tx_off;  // nibble offset

    logic [2-1:0][4-1:0] uart_tx_byte;   // raw byte data
    logic        [8-1:0] uart_tx_char;   // ASCII character for a hexadecimal value of a nibble

///////////////////////////////////////////////////////////////////////////////
// system signals
///////////////////////////////////////////////////////////////////////////////

    // system clock
    assign clk = XTAL_IN;

    // button debounce
    generate
    for (genvar i=1; i<=2; i++) begin: buttons

        debounce #(
            .FREQ (FREQUENCY),
            .TIME (DEBOUNCE_TIME),
`ifdef DEBUG
            // the DEBUG option avoids long simulation times
            .CNT_LENGTH (6)
`endif
            .INIT (1'b1)
        ) button (
            .clk  (clk),
            .d_i  (S[i]),
            .d_o  (btn[i])
        );

    end: buttons
    endgenerate

    // system reset
    assign rst = ~btn[1];  // buttons are active low

    // run button
    assign run_btn = ~btn[2];  // buttons are active low

    // start button register (delay)
    always_ff @(posedge clk, posedge rst)
    if (rst) run_reg <= 1'b0;
    else     run_reg <= run_btn;

    // run pulse
    assign run = run_btn & ~run_reg;

    // LED-s
    assign LED[1] = ~rst;            // reset signal
    assign LED[2] = ~run;            // run button
    assign LED[3] = ~uart_tx_valid;  // UART TX active

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
                if (fsm_cnt_nxt == TEST_SIZE*2) begin
                    fsm_state <= FSM_SEND;
                    fsm_cnt <= 'd0;
                end else begin
                    fsm_cnt <= fsm_cnt_nxt;
                end
            end
            FSM_SEND:
            if (uart_tx_transfer) begin
                if (fsm_cnt_nxt == TEST_SIZE*2) begin
                    fsm_state <= FSM_IDLE;
                    fsm_cnt <= 'd0;
                end else begin
                    fsm_cnt <= fsm_cnt_nxt;
                end
            end
            // the default includes FSM_IDLE
            default: begin
                if (run) begin
                    fsm_state <= FSM_READ;
                end
            end
        endcase
    end

    assign fsm_cnt_nxt = fsm_cnt + fsm_cnt_inc;

    always_comb
    begin
        case (fsm_state)
            FSM_READ: begin
                fsm_cnt_inc = (ADDR_WIDTH+1)'(2*(DATA_WIDTH/8));
            end
            FSM_SEND: begin
                fsm_cnt_inc = (ADDR_WIDTH+1)'(1);
            end
            default: begin
                fsm_cnt_inc = 'x;
            end
        endcase
    end

///////////////////////////////////////////////////////////////////////////////
// embedded flash controller instance
///////////////////////////////////////////////////////////////////////////////

    assign flash_req_valid = (fsm_state == FSM_READ);

    assign flash_req_addr = fsm_cnt[ADDR_WIDTH-1:0];
//    assign flash_req_addr = fsm_cnt[5:3];

    embedded_flash_controller flash_ctrl (
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

    logic [DATA_WIDTH/8-1:0][8-1:0] sram_mem [0:TEST_SIZE/(DATA_WIDTH/8)-1];

    // write port
    always_ff @(posedge clk, posedge rst)
    if (rst)  sram_a_enable <= 1'b0;
    else      sram_a_enable <= flash_req_transfer;

    always_ff @(posedge clk)
    sram_a_addr <= flash_req_addr[ADDR_WIDTH-1:$clog2(BYTE_WIDTH)];

    assign sram_a_wdata = flash_rdt_data;

    // read port
    assign sram_b_addr = fsm_cnt[ADDR_WIDTH-1:$clog2(BYTE_WIDTH)];
    assign sram_b_enable  = 1'b1;

    always_ff @(posedge clk)
    begin
        // write port
        if (sram_a_enable) begin
            sram_mem[sram_a_addr] <= sram_a_wdata;
        end
        // read port
        if (sram_b_enable) begin
            sram_b_rdata <= sram_mem[sram_b_addr];
        end
    end

///////////////////////////////////////////////////////////////////////////////
// UART instance
///////////////////////////////////////////////////////////////////////////////

    // table containing ASCII values for each hexadecimal (nibble) value
    byte ascii_table [0:16-1] = '{"0", "1","2","3","4","5","6","7","8","9","A","B","C","D","E","F"};

    localparam int unsigned CFG_BDR = int'(FREQUENCY/real'(BAUDRATE));
    localparam int unsigned CFG_BDR_WIDTH = $clog2(CFG_BDR);

    assign uart_tx_transfer = uart_tx_valid & uart_tx_ready;

    always_ff @(posedge clk, posedge rst)
    if (rst) begin
        uart_tx_valid <= 1'b0;
    end else begin
        uart_tx_valid <= (fsm_state == FSM_SEND);
    end

    // extract a single byte from the data word
    assign uart_tx_off  = fsm_cnt[$clog2(BYTE_WIDTH)-1:-1];
    assign uart_tx_byte = sram_b_rdata[uart_tx_off[$clog2(BYTE_WIDTH)-1:0]];

    // convert a nibble into an ASCII character
    assign uart_tx_char = ascii_table[uart_tx_byte[~uart_tx_off[-1]]];

    uart_tx #(
        .BDR (CFG_BDR_WIDTH)
    ) uart (
        // system signals
        .clk     (clk),
        .rst     (rst),
        // configuration
        .cfg_bdr (CFG_BDR),
        // parallel stream
        .str_vld (uart_tx_valid),
        .str_dat (uart_tx_char ),
        .str_rdy (uart_tx_ready),
        // serial TX output
        .txd     (FPGA_TX)
    );

endmodule: tang_nano_9k_flash_demo

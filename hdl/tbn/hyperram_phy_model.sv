///////////////////////////////////////////////////////////////////////////////
// HyperRAM PHY simplified model
//
// Copyright 2026 Iztok Jeras <iztok.jeras@gmail.com>
//
// Licensed under CERN-OHL-P v2 or later
///////////////////////////////////////////////////////////////////////////////

module hyperram_phy_model #(
    // HyperRAM parameters (only ones relevant to the simplified model)
    parameter  bit    HYBRID_BURST_ENABLE  = 1'b1,
    parameter  int    BURST_LENGTH         = 32,
    // PYH interface parameters (address width also defines the memory size)
    parameter  int    SIZE_WIDTH           = $clog2(BURST_LENGTH),  // can be larger
    parameter  int    ADDR_WIDTH           = 32,
    parameter  int    DATA_WIDTH           = 16,
    localparam int    BYTE_WIDTH           = DATA_WIDTH/8,
    // PHY timing parameters (in clock cycles)
    parameter  int    WRITE_READY_DELAY    = 4,  // from request to being ready to accept write data
    parameter  int    READ_VALID_DELAY     = 8,  // from request to a valid read data response
    parameter  int    EXTENDED_DELAY       = 4,  // added randomly to read/write data delay
    parameter  int    IDLE_DELAY           = 4   // extra delay between request handshakes
)(
    // system clock/reset
    input  logic                  phy_clk,
    input  logic                  phy_rst,
    // memory PHY interface: request
    input  logic                  phy_req_valid,  // request handshake valid
    input  logic                  phy_req_type ,  // burst type 0: wrapped, 1: linear
    input  logic                  phy_req_read ,  // 0: write, 1: read
    input  logic [SIZE_WIDTH-1:0] phy_req_size ,  // transfer size (phy_req_size+1) in 16 bit words
    input  logic [ADDR_WIDTH-1:0] phy_req_addr ,  // word (16-bit) address
    output logic                  phy_req_ready,  // request handshake ready
    // memory PHY interface: write data
    input  logic [BYTE_WIDTH-1:0] phy_wdt_byte ,  // byte enable
    input  logic [DATA_WIDTH-1:0] phy_wdt_data ,  // write data
    input  logic                  phy_wdt_valid,  // valid write data is available (active clock stop)
    output logic                  phy_wdt_ready,  // ready to accept write data
    // memory PHY interface: read data
    output logic [DATA_WIDTH-1:0] phy_rdt_data ,  // read data (byte enable is ignored)
    output logic                  phy_rdt_strb ,  // strobe read data word
    input  logic                  phy_rdt_pause   // pause data strobes after ODDR delay (active clock stop)
);

    // FSM parameters
    localparam bit [2-1:0] FSM_IDLE  = 2'b00;
    localparam bit [2-1:0] FSM_READ  = 2'b10;
    localparam bit [2-1:0] FSM_WRITE = 2'b11;

    // FSM signals
    bit            [2-1:0] fsm_state;
    int unsigned           fsm_delay;
    int unsigned           fsm_cnt;
    logic                  fsm_read;
    logic [SIZE_WIDTH-1:0] fsm_size;
    logic [ADDR_WIDTH-1:0] fsm_addr;

    // interface signals
    logic phy_req_transfer;

    // model memory
    logic [8-1:0] mem [0:2**ADDR_WIDTH-1];

    // interface handshake transfer
    assign phy_req_transfer = phy_req_valid & phy_req_ready;

    // initialization to an idle state
    // TODO: memory initialization
    initial begin
    end

    always_ff @(posedge phy_clk, posedge phy_rst)
    if (phy_rst) begin
        // FSM
        fsm_state <= FSM_IDLE;
        fsm_delay <= 0;
        fsm_cnt   <= 0;
        // request signal copies
        fsm_read  <= 'x;
        fsm_size  <= 'x;
        fsm_addr  <= 'x;
        // interface
        phy_req_ready <= 1'b0;
        phy_wdt_ready <= 1'b0;
        phy_rdt_strb  <= 1'b0;        
    end else begin
        case (fsm_state)
            FSM_IDLE: begin
                if (fsm_delay == IDLE_DELAY) begin
                    phy_req_ready <= 1'b1;
                end
                if (phy_req_transfer) begin
                    // state
                    fsm_state <= phy_req_read ? FSM_READ : FSM_WRITE;
                    fsm_delay <= 0;
                    fsm_cnt   <= 0;
                    // request signal copies
                    fsm_read  <= phy_req_read;
                    fsm_size  <= phy_req_size;
                    fsm_addr  <= phy_req_addr;
                end else begin
                    fsm_delay <= fsm_delay + 1;
                end
            end
            FSM_READ: begin
                if (fsm_delay > READ_VALID_DELAY) begin
                    if (fsm_cnt < fsm_size) begin
                        // read data interface
                        phy_rdt_strb  <= 1'b1;
                        phy_rdt_data  <= {mem[fsm_addr+1], mem[fsm_addr]};
                        // FSM
                        fsm_cnt       <= fsm_cnt + 1;
                        fsm_addr      <= fsm_addr + 'd2;
                    end else begin
                        // read data interface
                        phy_rdt_strb  <= 1'b0;
                        phy_rdt_data  <= 'x;
                        // FSM
                        fsm_state     <= FSM_IDLE;
                        fsm_delay     <= 0;
                        fsm_cnt       <= 0;
                    end
                end else begin
                    fsm_delay <= fsm_delay + 1;
                end
            end
            FSM_WRITE: begin
    
            end
            default: begin end
        endcase        
    end
    
    

//    always_comb
//    case (fsm_state)
//        FSM_IDLE: begin
//
//        end
//        FSM_READ: begin
//
//        end
//        FSM_WRITE: begin
//
//        end
//    endcase

endmodule: hyperram_phy_model

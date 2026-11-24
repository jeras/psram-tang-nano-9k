///////////////////////////////////////////////////////////////////////////////
// embedded flash controller
//
// Copyright 2026 Iztok Jeras <iztok.jeras@gmail.com>
//
// Licensed under CERN-OHL-P v2 or later
///////////////////////////////////////////////////////////////////////////////

module embedded_flash_controller #(
    // flash size/width parameters
    parameter  int unsigned SIZE = 608_000 / 32,
    parameter  int unsigned DATA_WIDTH = 32,
    parameter  int unsigned XADR_WIDTH = 9,
    parameter  int unsigned YADR_WIDTH = 6,
    parameter  int unsigned ADDR_WIDTH = XADR_WIDTH + YADR_WIDTH + $clog2(DATA_WIDTH/8),
    // flash protocol parameters
    parameter  int unsigned PROTOCOL_CYCLES = 4,
    parameter  int unsigned READY_READ_DELAY = 1
)(
    // system signals
    input  logic clk,
    input  logic rst,
    // system bus
    input  logic                  bus_req_valid,
    input  logic [ADDR_WIDTH-1:0] bus_req_addr ,  // byte address
    output logic                  bus_req_ready,
    output logic [DATA_WIDTH-1:0] bus_rdt_data    // read data
);

///////////////////////////////////////////////////////////////////////////////
// embedded flash signals and instance
///////////////////////////////////////////////////////////////////////////////

    // embedded flash controller interface signals
    logic [DATA_WIDTH-1:0] flash_dout;
    logic [DATA_WIDTH-1:0] flash_din;
    logic [XADR_WIDTH-1:0] flash_xadr;
    logic [YADR_WIDTH-1:0] flash_yadr;
    logic                  flash_xe;
    logic                  flash_ye;
    logic                  flash_se;
    logic                  flash_prog  = 1'b0;
    logic                  flash_erase = 1'b0;
    logic                  flash_nvstr = 1'b0;

    // embedded flash interface instance
    FLASH608K flash (
        .XADR  (flash_xadr),
        .YADR  (flash_yadr),
        .XE    (flash_xe),
        .YE    (flash_ye),
        .SE    (flash_se),
        .ERASE (flash_erase),
        .PROG  (flash_prog),
        .NVSTR (flash_nvstr),
        .DIN   (flash_din),
        .DOUT  (flash_dout)
    );

///////////////////////////////////////////////////////////////////////////////
// protocol FSM
///////////////////////////////////////////////////////////////////////////////

    // sample the request address
    always_ff @(posedge clk)
    if (bus_req_valid) begin
        flash_xadr <= bus_req_addr[$clog2(DATA_WIDTH/8)+YADR_WIDTH+:XADR_WIDTH];
        flash_yadr <= bus_req_addr[$clog2(DATA_WIDTH/8)           +:YADR_WIDTH];
    end

    generate
    case (PROTOCOL_CYCLES)

        // 4 clock period access protocol
        4: begin: cyc4

            // FSM states encode signals {ready, SE, [X/Y]E}
            localparam bit [3-1:0] FSM_IDLE = 3'b000;  // idle (XE/YE are not active)
            localparam bit [3-1:0] FSM_ADDR = 3'b001;  // drive address
            localparam bit [3-1:0] FSM_SE   = 3'b011;  // SE active
            localparam bit [3-1:0] FSM_SMPL = 3'b101;  // sample

            logic [3-1:0] fsm_state;

            always_ff @(posedge clk, posedge rst)
            if (rst) begin
                fsm_state <= FSM_IDLE;
            end else begin
                case (fsm_state)
                    FSM_IDLE: begin
                        if (bus_req_valid)  fsm_state <= FSM_ADDR;
                    end
                    FSM_ADDR: begin
                        fsm_state <= FSM_SE;
                    end
                    FSM_SE  : begin
                        fsm_state <= FSM_SMPL;
                    end
                    FSM_SMPL: begin
                        fsm_state <= FSM_IDLE;
                        // read data is sampled in this state
                    end
                    default: begin  end
                endcase
            end

            // FSM states encode signals {ready, SE, [X/Y]E}
            assign flash_xe = fsm_state[0];
            assign flash_ye = fsm_state[0];
            assign flash_se = fsm_state[1];

            // READY is returned during the FSM_SMPL state
            assign bus_req_ready = fsm_state[2];

            // sample the response data
            always_ff @(posedge clk)
            if (bus_req_ready) begin
                bus_rdt_data <= flash_dout;
            end

        end: cyc4

        // 3 clock period access protocol
        3: begin: cyc3

            // FSM states encode signals {ready, SE, [X/Y]E}
            localparam bit [3-1:0] FSM_IDLE = 3'b000;  // idle (XE/YE are not active)
            localparam bit [3-1:0] FSM_ADDR = 3'b001;  // drive address
            localparam bit [3-1:0] FSM_SE   = 3'b011;  // SE active
            localparam bit [3-1:0] FSM_SMPL = 3'b101;  // sample

            logic [3-1:0] fsm_state;

            always_ff @(posedge clk, posedge rst)
            if (rst) begin
                fsm_state <= FSM_IDLE;
            end else begin
                case (fsm_state)
                    FSM_IDLE: begin
                        if (bus_req_valid)  fsm_state <= FSM_ADDR;
                    end
                    FSM_ADDR: begin
                        fsm_state <= FSM_SE;
                    end
                    FSM_SE  : begin
                        fsm_state <= FSM_SMPL;
                        // read data is sampled in this state
                    end
                    FSM_SMPL: begin
                        // only enter the idle state if there are no pending requests
                        if (bus_req_valid)  fsm_state <= FSM_ADDR;
                        else                fsm_state <= FSM_IDLE;
                    end
                    default: begin end
                endcase
            end

            // FSM states encode signals {ready, SE, [X/Y]E}
            assign flash_xe = fsm_state[0];
            assign flash_ye = fsm_state[0];
            assign flash_se = fsm_state[1];

            assign bus_req_ready = fsm_state[1];

            // sample the response data
            always_ff @(posedge clk)
            if (bus_req_ready) begin
                bus_rdt_data <= flash_dout;
            end

        end: cyc3

        // 2 clock period access protocol
        2: begin: cyc2

            // FSM states encode signals {ready, SE, [X/Y]E}
            localparam bit [3-1:0] FSM_IDLE = 3'b000;  // idle (XE/YE are not active)
            localparam bit [3-1:0] FSM_SE   = 3'b011;  // SE active
            localparam bit [3-1:0] FSM_SMPL = 3'b101;  // sample

            logic [3-1:0] fsm_state;

            always_ff @(posedge clk, posedge rst)
            if (rst) begin
                fsm_state <= FSM_IDLE;
            end else begin
                case (fsm_state)
                    FSM_IDLE: begin
                        if (bus_req_valid)  fsm_state <= FSM_SE;
                    end
                    FSM_SE  : begin
                        fsm_state <= FSM_SMPL;
                        // read data is sampled in this state
                    end
                    FSM_SMPL: begin
                        // only enter the idle state if there are no pending requests
                        if (bus_req_valid)  fsm_state <= FSM_SE;
                        else                fsm_state <= FSM_IDLE;
                    end
                    default: begin end
                endcase
            end

            // FSM states encode signals {ready, SE, [X/Y]E}
            assign flash_xe = fsm_state[0];
            assign flash_ye = fsm_state[0];

            LUT4 #(
                .INIT (16'b0000_0000_0000_0010)
            ) delay_lut (
                .F  (flash_se),
                .I0 (fsm_state[1]),
                .I1 (1'b0),
                .I2 (1'b0),
                .I3 (1'b0)
            );

            assign bus_req_ready = fsm_state[1];

            // sample the response data
            always_ff @(posedge clk)
            if (bus_req_ready) begin
                bus_rdt_data <= flash_dout;
            end

        end: cyc2

        // 1 clock period access protocol
        1: begin: cyc1

            logic flash_enable;
            logic flash_toggle_posedge;
            logic flash_toggle_negedge;

            always_ff @(posedge clk, posedge rst)
            if (rst) begin
                flash_enable         = 1'b0;
                flash_toggle_posedge = 1'b0;
            end else begin
                flash_enable         <= bus_req_valid;
                flash_toggle_posedge <= bus_req_valid ^ flash_toggle_posedge;
            end

            // FSM states encode signals {ready, SE, [X/Y]E}
            assign flash_xe = flash_enable;
            assign flash_ye = flash_enable;

            always_ff @(negedge clk, posedge rst)
            if (rst) begin
                flash_toggle_negedge <= 1'b0;
            end else begin
                flash_toggle_negedge <= flash_toggle_posedge;
            end

            LUT4 #(
                .INIT (16'b0000_0000_0000_0110)
            ) delay_lut (
                .F  (flash_se),
                .I0 (flash_toggle_posedge),
                .I1 (flash_toggle_negedge),
                .I2 (1'b0),
                .I3 (1'b0)
            );

            assign bus_req_ready = 1'b1;

            // combinational response data
            assign bus_rdt_data = flash_dout;

        end: cyc1

    endcase
    endgenerate

endmodule: embedded_flash_controller

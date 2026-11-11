// n-way set associative cache
// compatible with custom PHY interface
// TODO: license

module hyperram_cache #(
    // system bus and memory parameters
    parameter  int unsigned ADDR_WIDTH = 32,            // address space size
    parameter  int unsigned DATA_WIDTH = 32,            // 16/32/64-bit system bus
    localparam int unsigned BYTE_WIDTH = DATA_WIDTH/8,  // word size in bytes
    // cache parameters
    parameter  int unsigned ASSOCIATIVITY = 1,          // options are 1/2/4
    parameter  int unsigned BLOCK_SIZE = 2*1024,        // cache block size in bytes
    parameter  int unsigned LINE_SIZE = 128,            // cache line size in bytes
    localparam int unsigned CACHE_SIZE = BLOCK_SIZE*ASSOCIATIVITY,
    // calculated PHY parameters (PHY interface data unit is 16-bit)
    localparam int unsigned PHY_SIZE_WIDTH = $clog2(LINE_SIZE)-1,
    parameter  int unsigned PHY_ADDR_WIDTH = ADDR_WIDTH-1,
    parameter  int unsigned PHY_DATA_WIDTH = 16,
    localparam int unsigned PHY_BYTE_WIDTH = PHY_DATA_WIDTH/8
)(
    // system signals
    input  logic                      clk,
    input  logic                      rst,
    // cache control signals
    input  logic                      ctl_invalidate,
    // system bus interface
    input  logic                      bus_req_valid,
    input  logic                      bus_req_write,
    input  logic     [ADDR_WIDTH-1:0] bus_req_addr ,
    input  logic     [BYTE_WIDTH-1:0] bus_req_byte ,
    input  logic     [DATA_WIDTH-1:0] bus_req_wdata,
    output logic                      bus_req_ready,
    output logic     [DATA_WIDTH-1:0] bus_rsp_rdata,
    output logic     [DATA_WIDTH-1:0] bus_rsp_error,  // ???
    // memory PHY interface
    input  logic                      phy_clk,
    input  logic                      phy_rst,
    // memory PHY interface: request
    output logic                      phy_req_valid,
    output logic                      phy_req_type ,
    output logic                      phy_req_read ,
    output logic [PHY_SIZE_WIDTH-1:0] phy_req_size ,
    output logic [PHY_ADDR_WIDTH-1:0] phy_req_addr ,
    input  logic                      phy_req_ready,
    // memory PHY interface: write data
    output logic [PHY_BYTE_WIDTH-1:0] phy_req_byte ,
    output logic [PHY_DATA_WIDTH-1:0] phy_wdt_data ,
    output logic                      phy_wdt_last ,
    output logic                      phy_wdt_valid,
    input  logic                      phy_wdt_ready,
    // memory PHY interface: read data
    input  logic [PHY_DATA_WIDTH-1:0] phy_rdt_data ,
    input  logic                      phy_rdt_strb ,
    input  logic                      phy_rdt_last ,
    output logic                      phy_rdt_pause
);

///////////////////////////////////////////////////////////////////////////////
// local parameters
///////////////////////////////////////////////////////////////////////////////

    // NOTE: sizes are measured in bytes
    // NOTE: lengths are the number of addressable locations

    // memory addressable length
    localparam int unsigned BLOCK_LENGTH = BLOCK_SIZE/BYTE_WIDTH;
    localparam int unsigned TAG_LENGTH   = BLOCK_SIZE/LINE_SIZE;

    // address signal widths
    localparam int unsigned ADDR_BLOCK_WIDTH  = $clog2(BLOCK_SIZE);
    localparam int unsigned ADDR_WORD_WIDTH   = $clog2(BYTE_WIDTH);
    localparam int unsigned ADDR_OFFSET_WIDTH = $clog2(LINE_SIZE);
    localparam int unsigned ADDR_INDEX_WIDTH  = ADDR_BLOCK_WIDTH - ADDR_OFFSET_WIDTH;
    localparam int unsigned ADDR_TAG_WIDTH    = ADDR_WIDTH-ADDR_BLOCK_WIDTH;

///////////////////////////////////////////////////////////////////////////////
// local signals
///////////////////////////////////////////////////////////////////////////////

    // address structure {tag, index, offset}
    logic [                                ADDR_OFFSET_WIDTH-1:0] addr_offset;
    logic [             ADDR_BLOCK_WIDTH-1:ADDR_OFFSET_WIDTH    ] addr_index;
    logic [ADDR_WIDTH-1:ADDR_BLOCK_WIDTH                        ] addr_tag;
    // word address within a block
    logic [             ADDR_BLOCK_WIDTH-1:ADDR_WORD_WIDTH      ] addr_word;

    logic        [DATA_WIDTH-1:0] entry_data [ASSOCIATIVITY-1:0];
    logic    [ADDR_TAG_WIDTH-1:0] entry_tag  [ASSOCIATIVITY-1:0];
    logic     [ASSOCIATIVITY-1:0] entry_valid;
    logic     [ASSOCIATIVITY-1:0] entry_dirty;
    logic     [ASSOCIATIVITY-1:0] entry_hit;
    logic hit;

    // cache controller valid/dirty/tag
    logic                        ctl_valid;
    logic                        ctl_dirty;
    logic   [ADDR_TAG_WIDTH-1:0] ctl_tag  ;
    // cache controller
    logic [ADDR_INDEX_WIDTH-1:0] ctl_index;
    logic                        ctl_write;

    // cache controller FSM
    logic                [2-1:0] fsm_state;
    logic [ADDR_INDEX_WIDTH-1:0] fsm_index;
    logic [ADDR_INDEX_WIDTH-0:0] fsm_cnt;    // extra overflow (carry) bit

    // system bus local signals
    logic bus_req_transfer;

///////////////////////////////////////////////////////////////////////////////
// cache
///////////////////////////////////////////////////////////////////////////////

    // address structure
    assign {addr_tag, addr_index, addr_offset} = bus_req_addr;
    // word address within a block
    assign addr_word = bus_req_addr[ADDR_BLOCK_WIDTH-1:ADDR_WORD_WIDTH];

    generate
    for (genvar i=0; i<ASSOCIATIVITY; i++) begin: block

        // data memory
        logic [BYTE_WIDTH-1:0][8-1:0] mem_dat [0:BLOCK_LENGTH-1];
        // tag memory
        logic                       mem_valid [0:TAG_LENGTH-1];
        logic                       mem_dirty [0:TAG_LENGTH-1];
        logic  [ADDR_TAG_WIDTH-1:0] mem_tag   [0:TAG_LENGTH-1];

        // asynchronous read tag memory
        assign entry_valid[i] = mem_valid[addr_index];
        assign entry_dirty[i] = mem_dirty[addr_index];
        assign entry_tag  [i] = mem_tag  [addr_index];

        // per block hit
        assign entry_hit[i] = (entry_tag[i] == addr_tag) & entry_valid[i];

        // system bus read/write data memory (enabled only on hit)
        always_ff @(posedge clk)
        if (bus_req_valid & entry_hit[i]) begin
            // write access
            if (bus_req_write) begin
                for (int unsigned b=0; b<BYTE_WIDTH; b++) begin
                    if (bus_req_byte[b])  mem_dat[addr_word][b] <= bus_req_wdata[b*8+:8];
                end
            end
            // read access
            if (~bus_req_write)  entry_data[i] <= mem_dat[addr_word];
        end

        // valid/dirty/tag write logic
        always_ff @(posedge clk)
        if (ctl_write) begin
            mem_valid[ctl_index] <= ctl_valid;
            mem_dirty[ctl_index] <= ctl_dirty;
            mem_tag  [ctl_index] <= ctl_tag  ;
        end

    end: block
    endgenerate

    // cache line hit
    assign hit = |entry_hit;

///////////////////////////////////////////////////////////////////////////////
// cache controller FSM
///////////////////////////////////////////////////////////////////////////////

    // NOTE: for ASSOCIATIVITY==4 use 3 bit pseudo-LRU  (binary tree)
    // NOTE: for ASSOCIATIVITY==2 use 1 bit LRU
    // NOTE: for ASSOCIATIVITY==1 there is no replacement policy
    localparam int unsigned CACHE_PLRU_WIDTH = ASSOCIATIVITY == 4 ? 3 : 1;

    // pLRU (binary tree pseudo least recently used)
    logic [CACHE_PLRU_WIDTH-1:0] mem_plru [0:BLOCK_LENGTH-1];

    // FSM
    localparam bit [2-1:0] FSM_INIT  = 2'b00;
    localparam bit [2-1:0] FSM_IDLE  = 2'b01;
    localparam bit [2-1:0] FSM_WRITE = 2'b10;
    localparam bit [2-1:0] FSM_READ  = 2'b11;
    localparam             FSM_FETCH = 2'b10;
    localparam             FSM_WBACK = 2'b11;

    // TODO: a FSM for clearing the VALID bit from tag memory is needed for ASIC implementations
    // tag
    always_ff @(posedge clk, posedge rst)
    if (rst) begin
        // require invalidation sequence after reset
        fsm_state <= 2'b00;
        fsm_index <=  'd0;
    end else begin
        case (fsm_state)
            // invalidation sequence
            FSM_INIT: begin
                // index counter increment
                fsm_index <= fsm_cnt[ADDR_INDEX_WIDTH-1:0];
                // index counter overflow ends invalidation sequence
                if (fsm_cnt[ADDR_INDEX_WIDTH])  fsm_state <= FSM_INIT;
            end
            // idle
            FSM_IDLE: begin
                // request cache invalidation sequence
                if (ctl_invalidate) begin
                    fsm_state <= FSM_INIT;
                end
                if (bus_req_valid & ~hit) begin
                    fsm_state <= bus_req_write ? FSM_WRITE : FSM_READ;
                end
            end
            default: begin end
        endcase
    end

    // index counter increment
    assign fsm_cnt = fsm_index + 'd1;

///////////////////////////////////////////////////////////////////////////////
// memory PHY interface
///////////////////////////////////////////////////////////////////////////////



///////////////////////////////////////////////////////////////////////////////
// system bus
///////////////////////////////////////////////////////////////////////////////

    // system bus ready
    assign bus_req_ready = hit;

    // system bus transfer
    assign bus_req_transfer = bus_req_valid & bus_req_ready;

endmodule: hyperram_cache
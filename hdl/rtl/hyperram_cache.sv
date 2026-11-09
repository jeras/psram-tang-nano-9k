// n-way set associative cache
// compatible with custom PHY interface
// TODO: license

module hyperram_cache #(
    // system bus and memory parameters
    parameter int unsigned ADDR_WIDTH = 26,            // 64MB address space by default
    parameter int unsigned DATA_WIDTH = 32,            // 16/32/64-bit system bus
    parameter int unsigned BYTE_WIDTH = DATA_WIDTH/8,  // word size in bytes
    // cache parameters
    parameter int unsigned ASSOCIATIVITY = 1,        // options are 1/2/4
    parameter int unsigned CACHE_SIZE = 1024*4,      // cache size in bytes
    parameter int unsigned LINE_SIZE = 128,          // line size in bytes
)(
    // system signals
    input  logic clk,
    input  logic rst,
    // system bus interface
    input  logic                  bus_req_valid,
    input  logic                  bus_req_write,
    input  logic [ADDR_WIDTH-1:0] bus_req_addr ,
    input  logic [BYTE_WIDTH-1:0] bus_req_byte ,
    input  logic [DATA_WIDTH-1:0] bus_req_wdata,
    output logic                  bus_req_ready,
    output logic [DATA_WIDTH-1:0] bus_rsp_rdata,
    output logic [DATA_WIDTH-1:0] bus_rsp_error,  // ???
    // cache control signals
    input  logic                  ctl_invalidate,
    // memory PHY interface
    input  logic                  phy_clk,
    input  logic                  phy_rst,
    // memory PHY interface: request
    output logic                  phy_req_valid,
    output logic                  phy_req_read ,
    output logic [ADDR_WIDTH-1:0] phy_req_addr ,
    output logic [BYTE_WIDTH-1:0] phy_req_byte ,
    input  logic                  phy_req_ready,
    // memory PHY interface: write data
    output logic [DATA_WIDTH-1:0] phy_wdt_data ,
    input  logic                  phy_wdt_ready,
    // memory PHY interface: read data
    input  logic [DATA_WIDTH-1:0] phy_rdt_data ,
    input  logic                  phy_rdt_valid
);

///////////////////////////////////////////////////////////////////////////////
// local parameters
///////////////////////////////////////////////////////////////////////////////

    // NOTE: sizes are measured in bytes
    // NOTE: lengths are the number of addressable locations

    // a N-way cache has N entries, the cache size is divided into N entry sizes
    localparam int unsigned CACHE_ENTRY_SIZE   = CACHE_SIZE/ASSOCIATIVITY;
    localparam int unsigned CACHE_ENTRY_LENGTH = CACHE_ENTRY_SIZE/LINE_SIZE;
    localparam int unsigned CACHE_TAG_LENGTH   = CACHE_ENTRY_SIZE/LINE_SIZE;

    // address signal widths
    localparam int unsigned CACHE_ADDR_WIDTH   = $clog2(CACHE_ENTRY_LENGTH);
    localparam int unsigned CACHE_WORD_WIDTH   = $clog2(BYTE_WIDTH);
    localparam int unsigned CACHE_OFFSET_WIDTH = $clog2(LINE_SIZE);
    localparam int unsigned CACHE_INDEX_WIDTH  =            CACHE_ADDR_WIDTH-CACHE_OFFSET_WIDTH;
    localparam int unsigned CACHE_TAG_WIDTH    = ADDR_WIDTH-CACHE_ADDR_WIDTH;

///////////////////////////////////////////////////////////////////////////////
// local signals
///////////////////////////////////////////////////////////////////////////////

    // address structure {tag, index, offset}
    logic [                                CACHE_OFFSET_WIDTH-1:0] addr_offset;
    logic [             CACHE_ADDR_WIDTH-1:CACHE_OFFSET_WIDTH    ] addr_index;
    logic [ADDR_WIDTH-1:CACHE_ADDR_WIDTH                         ] addr_tag;
    // word address within a block
    logic [             CACHE_ADDR_WIDTH-1:CACHE_WORD_WIDTH      ] addr_word;

    logic        [DATA_WIDTH-1:0] entry_data [ASSOCIATIVITY-1:0];
    logic [2+CACHE_TAG_WIDTH-1:0] entry_tag  [ASSOCIATIVITY-1:0];
    logic     [ASSOCIATIVITY-1:0] entry_valid;
    logic     [ASSOCIATIVITY-1:0] entry_dirty;
    logic     [ASSOCIATIVITY-1:0] entry_hit;
    logic hit;

    // cache controller valid/dirty/tag
    logic                         ctl_valid;
    logic                         ctl_dirty;
    logic   [CACHE_TAG_WIDTH-1:0] ctl_tag  ;
    // cache controller
    logic [CACHE_INDEX_WIDTH-1:0] ctl_index;
    logic                         ctl_write;

    // cache controller FSM
    logic                 [2-1:0] fsm_state;
    logic [CACHE_INDEX_WIDTH-1:0] fsm_index;
    logic [CACHE_INDEX_WIDTH-0:0] fsm_cnt;    // extra overflow (carry) bit

    // system bus local signals
    logic bus_req_transfer;

///////////////////////////////////////////////////////////////////////////////
// cache
///////////////////////////////////////////////////////////////////////////////

    // address structure
    assign {addr_tag, addr_index, addr_offset} = bus_req_addr;
    // word address within a block
    assign addr_word = bus_req_addr[CACHE_INDEX_WIDTH-1:CACHE_WORD_WIDTH];

    generate
    for (genvar i=0; i<ASSOCIATIVITY; i++) begin: block

        // data memory
        logic [8-1:0][BYTE_WIDTH-1:0] mem_dat [0:CACHE_ENTRY_LENGTH-1];
        // tag memory
        logic                       mem_valid [0:CACHE_ENTRY_LENGTH-1];
        logic                       mem_dirty [0:CACHE_ENTRY_LENGTH-1];
        logic [CACHE_TAG_WIDTH-1:0] mem_tag   [0:CACHE_ENTRY_LENGTH-1];

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
                    if (bus_req_byte[b])  mem_dat[addr_word][b] = bus_req_wdata[b*8:8];
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
    logic [CACHE_PLRU_WIDTH-1:0] mem_plru [0:CACHE_ENTRY_LENGTH-1];

    // FSM
    localparam bit [2-1:0] FSM_INIT  = 2'b00;
    localparam bit [2-1:0] FSM_IDLE  = 2'b01;
    localparam bit [2-1:0] FSM_WRITE = 2'b10;
    localparam bit [2-1:0] FSM_READ  = 2'b11;
    localparam             FSM_FETCH = 2'b10;
    localparam             FSM_ESPUNGE;

    logic 

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
                fsm_index <= fsm_cnt[CACHE_INDEX_WIDTH-1:0];
                // index counter overflow ends invalidation sequence
                fsm_state <= fsm_cnt[CACHE_INDEX_WIDTH];
            end
            // idle
            FSM_IDLE: begin
                // request cache invalidation sequence
                if (ctl_invalidate) begin
                    fsm_state <= FSM_INIT;
                end
                if (bus_req_valid & ~hit) begin
                    fsm_state <= 
                end
                
            end
            
    end

    // index counter increment
    assign fsm_cnt = fsm_index + 'd1;

///////////////////////////////////////////////////////////////////////////////
// memory PHY interface
///////////////////////////////////////////////////////////////////////////////

    input  logic                  phy_clk,
    input  logic                  phy_rst,
    // memory PHY interface: request
    output logic                  phy_req_valid,
    output logic                  phy_req_read ,
    output logic [ADDR_WIDTH-1:0] phy_req_addr ,
    output logic [BYTE_WIDTH-1:0] phy_req_byte ,
    input  logic                  phy_req_ready,
    // memory PHY interface: write data
    output logic [DATA_WIDTH-1:0] phy_wdt_data ,
    input  logic                  phy_wdt_ready,
    // memory PHY interface: read data
    input  logic [DATA_WIDTH-1:0] phy_rdt_data ,
    input  logic                  phy_rdt_valid

    always_ff @(posedge clk)
    if (bus_req_valid & ~hit)

///////////////////////////////////////////////////////////////////////////////
// system bus
///////////////////////////////////////////////////////////////////////////////

    // system bus ready
    assign bus_req_ready = hit;

    // system bus transfer
    assign bus_req_transfer = bus_req_valid & bus_req_ready;

endmodule: hyperram_cache
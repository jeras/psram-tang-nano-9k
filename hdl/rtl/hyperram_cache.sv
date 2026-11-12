// n-way set associative cache
// compatible with custom PHY interface
// TODO: license

module hyperram_cache #(
    // system bus and memory parameters
    parameter  int unsigned ADDR_WIDTH = 32,            // address space size
    parameter  int unsigned DATA_WIDTH = 32,            // 16/32/64-bit system bus
    localparam int unsigned BYTE_WIDTH = DATA_WIDTH/8,  // word size in bytes
    // cache parameters
    parameter  int unsigned ASSOCIATIVITY  = 1,         // options are 1/2/4
    parameter  int unsigned BLOCK_SIZE     = 2*1024,    // cache block size in bytes
    parameter  int unsigned LINE_SIZE      = 64,        // cache line size in bytes
    localparam int unsigned CACHE_SIZE     = BLOCK_SIZE*ASSOCIATIVITY,
    // calculated PHY parameters (PHY interface data unit is 16-bit)
    localparam int unsigned PHY_SIZE_WIDTH = $clog2(LINE_SIZE)-1,
    parameter  int unsigned PHY_ADDR_WIDTH = ADDR_WIDTH-1,
    parameter  int unsigned PHY_DATA_WIDTH = 16,
    localparam int unsigned PHY_BYTE_WIDTH = PHY_DATA_WIDTH/8
)(
    // system signals
    input  logic                      bus_clk,
    input  logic                      bus_rst,
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
    logic                         ctl_valid;
    logic                         ctl_dirty;
    logic    [ADDR_TAG_WIDTH-1:0] ctl_tag  ;
    // cache controller
    logic  [ADDR_INDEX_WIDTH-1:0] ctl_index;
    logic                         ctl_valid_write;
    logic                         ctl_dirty_write;
    logic                         ctl_tag_write;

    // cache invalidation signals
    logic  [ADDR_INDEX_WIDTH-1:0] inv_index;
    logic  [ADDR_INDEX_WIDTH-0:0] inv_index_cnt;
    logic                         inv_write;

    // cache controller FSM
    logic                 [2-1:0] fsm_state;
    logic [ADDR_OFFSET_WIDTH-1:0] fsm_offset;
    logic [ADDR_OFFSET_WIDTH-0:0] fsm_offset_cnt;
    logic  [ADDR_INDEX_WIDTH-1:0] fsm_index;
    logic  [ADDR_INDEX_WIDTH-0:0] fsm_index_cnt;  // extra overflow (carry) bit
    logic    [ADDR_TAG_WIDTH-1:0] fsm_tag;

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
        always_ff @(posedge bus_clk)
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

        // PHY interface read/write data memory
        always_ff @(posedge phy_clk)
        begin
            // write access
            // TODO: avoid long line
            if (phy_rdt_strb) begin
                if (~fsm_offset[ADDR_WORD_WIDTH-1])  mem_dat[{fsm_index, fsm_offset[ADDR_OFFSET_WIDTH-1:ADDR_WORD_WIDTH]}][1:0] <= phy_rdt_data;
                if ( fsm_offset[ADDR_WORD_WIDTH-1])  mem_dat[{fsm_index, fsm_offset[ADDR_OFFSET_WIDTH-1:ADDR_WORD_WIDTH]}][3:2] <= phy_rdt_data;
            end
            // read access
            if (~bus_req_write)  entry_data[i] <= mem_dat[addr_word];
        end

        // valid/dirty/tag write logic
        always_ff @(posedge bus_clk)
        begin
            if (ctl_valid_write)  mem_valid[ctl_index] <= ctl_valid;
            if (ctl_dirty_write)  mem_dirty[ctl_index] <= ctl_dirty;
            if (ctl_tag_write  )  mem_tag  [ctl_index] <= ctl_tag  ;
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
    localparam bit [2-1:0] FSM_FETCH = 2'b10;
    localparam bit [2-1:0] FSM_WBACK = 2'b11;

    // TODO: a FSM for clearing the VALID bit from tag memory is needed for ASIC implementations
    // tag
    always_ff @(posedge bus_clk, posedge bus_rst)
    if (bus_rst) begin
        // invalidation
        inv_index <=  'b0;
        inv_write <= 1'b0;

        fsm_state <= 2'b00;
        fsm_index <=  'd0;
    end else begin
        case (fsm_state)
            // invalidation sequence
            FSM_INIT: begin
                // index counter increment
                inv_write <= 1'b1;
                inv_index <= inv_index_cnt[ADDR_INDEX_WIDTH-1:0];
                // index counter overflow ends invalidation sequence
                if (inv_index_cnt[ADDR_INDEX_WIDTH]) begin
                    inv_write <= 1'b0;
                    fsm_state <= FSM_IDLE;
                end
            end
            // idle
            FSM_IDLE: begin
                // request cache invalidation sequence
                if (ctl_invalidate) begin
                    fsm_state <= FSM_INIT;
                end
                if (bus_req_valid & ~hit) begin
                    // TODO: handle writing dirty lines
                    fsm_state  <= FSM_FETCH;
                    fsm_tag    <= addr_tag;
                    fsm_index  <= addr_index;
//                  fsm_offset <= addr_offset;
                    fsm_offset <= '0;
                    // request PHY transaction
                    phy_req_valid <= 1'b1;
                    phy_req_read  <= 1'b1;
                    fsm_state <= bus_req_write ? FSM_WBACK : FSM_FETCH;
                end
            end
            FSM_FETCH: begin
                if (phy_rdt_strb) begin
                    fsm_offset <= fsm_offset_cnt[ADDR_OFFSET_WIDTH-1:0];
                    if (fsm_offset_cnt[ADDR_OFFSET_WIDTH]) fsm_state <= FSM_IDLE;
                end
            end
            FSM_WBACK: begin
                
            end
            default: begin end
        endcase
    end

    // invalidation index counter increment
    assign inv_index_cnt = {1'b0, inv_index} + inv_write;

    // fetch/wback {index, offset} address
    assign fsm_offset_cnt = {1'b0, fsm_offset} + (ADDR_OFFSET_WIDTH+1)'({phy_rdt_strb, 1'b0});

//    assign ctl_index = (fsm_state == FSM_INIT) fsm_index : add
    assign ctl_index       = (fsm_state == FSM_INIT) ? inv_index : fsm_index;
    assign ctl_valid       = (fsm_state == FSM_INIT) ? 1'b0      : 1'bx;
    assign ctl_valid_write = (fsm_state == FSM_INIT) ? inv_write : 1'b0;

///////////////////////////////////////////////////////////////////////////////
// memory PHY interface
///////////////////////////////////////////////////////////////////////////////

    assign phy_req_size = PHY_SIZE_WIDTH'(LINE_SIZE/2-1);
    assign phy_req_addr = {fsm_tag, fsm_index, (ADDR_OFFSET_WIDTH-1)'('d0)};

///////////////////////////////////////////////////////////////////////////////
// system bus
///////////////////////////////////////////////////////////////////////////////

    // system bus ready
    assign bus_req_ready = hit;

    // system bus transfer
    assign bus_req_transfer = bus_req_valid & bus_req_ready;

endmodule: hyperram_cache
vcd file hyperram_phy_tb.vcd
vcd add -r /hyperram_phy_tb/*
log /hyperram_phy_tb/phy/fifo_data
vcd add /hyperram_phy_tb/phy/fifo_data
run 200us
quit 

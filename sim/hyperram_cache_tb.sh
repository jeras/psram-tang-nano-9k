#!/usr/bin/env sh

# compile HDL sources
verilator --binary -O3 --x-assign fast --assert \
--trace-fst --trace-structs \
-top hyperram_cache_tb \
../hdl/rtl/hyperram_cache.sv \
../hdl/tbn/hyperram_phy_model.sv \
../hdl/tbn/hyperram_cache_tb.sv

# run simulation
obj_dir/Vhyperram_cache_tb

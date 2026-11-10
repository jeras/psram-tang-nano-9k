#!/usr/bin/env sh

verilator --binary -O3 --x-assign fast --assert \
--trace-fst --trace-structs \
-top hyperram_cache_tb \
../hdl/rtl/hyperram_cache.sv \
../hdl/tbn/hyperram_phy_model.sv \
../hdl/tbn/hyperram_cache_tb.sv
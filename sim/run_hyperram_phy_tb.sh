#!/usr/bin/env sh

qrun -suppress 14408 -suppress 16154 -voptargs=+acc \
-top hyperram_phy_tb -sv \
-defineall S27KS0642DPBHI \
/opt/Gowin/Gowin_V1.9.12.04_linux/IDE/simlib/gw1n/prim_sim.v \
../hdl/rtl/hyperram_phy.sv \
../hdl/tbn/s27kl0642.v \
../hdl/tbn/hyperram_phy_tb.sv \
-do "run 600us"

#-gui \
#-do cmd.do

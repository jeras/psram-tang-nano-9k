#!/usr/bin/env sh

qrun -suppress 14408 -suppress 16154 -voptargs=+acc \
-top tb -sv \
-defineall S27KS0642DPBHI \
/opt/Gowin/Gowin_V1.9.12.04_linux/IDE/simlib/gw1n/prim_sim.v \
../hdl/rtl/gowin_rpll/gowin_rpll.v \
../hdl/rtl/psram_controller.sv \
../hdl/rtl/uart_tx.v \
../hdl/rtl/psram_test_top.sv \
../hdl/tbn/s27kl0642.v \
../hdl/tbn/tb.sv \
-do "run 600us"

#-gui \
#-do cmd.do

#../impl/qwsynthesis/psram_controller.vg

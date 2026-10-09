#!/usr/bin/env sh

qrun -suppress 14408 -suppress 16154 -voptargs=+acc \
-top tb -sv \
-defineall S27KS0642DPBHI \
-gui \
/opt/Gowin/Gowin_V1.9.12.04_linux/IDE/simlib/gw1a/prim_sim_a.v \
../src/gowin_rpll/gowin_rpll.v \
../src/psram_controller.v \
../src/uart_tx.v \
../src/psram_test_top.v \
../tb/s27kl0642.v \
../tb/tb.v \
-do cmd.do

#../impl/qwsynthesis/psram_controller.vg

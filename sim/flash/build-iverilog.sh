#!/usr/bin/env sh

iverilog -g2023 -DDEBUG \
-o tang_nano_9k_flash_demo_tb \
-s tang_nano_9k_flash_demo_tb \
-l /opt/Gowin/Gowin_V1.9.12.04_linux/IDE/simlib/gw1n/prim_sim.v \
../../hdl/tbn/uart/uart_model.sv \
../../hdl/rtl/debounce/debounce.sv \
../../hdl/rtl/uart_tx/uart_tx.sv \
../../hdl/rtl/flash/embedded_flash_controller.sv \
../../hdl/rtl/flash/tang_nano_9k_flash_demo.sv \
../../hdl/tbn/flash/tang_nano_9k_flash_demo_tb.sv

#../impl/qwsynthesis/tang_nano_9k_flash_demo.vg

vvp tang_nano_9k_flash_demo_tb

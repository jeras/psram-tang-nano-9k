#!/usr/bin/env sh

qrun -suppress 14408 -suppress 16154 -voptargs=+acc \
-top tang_nano_9k_flash_demo_tb -sv \
/opt/Gowin/Gowin_V1.9.12.04_linux/IDE/simlib/gw1n/prim_sim.v \
../../TCB/hdl/tbn/dev/uart/uart_model.sv \
../../TCB/hdl/rtl/dev/uart/tcb_dev_uart_ser.sv \
../../TCB/hdl/rtl/dev/uart/tcb_dev_uart_des.sv \
../../hdl/rtl/debounce/debounce.sv \
../../hdl/rtl/flash/embedded_flash_controller.sv \
../../hdl/rtl/flash/tang_nano_9k_flash_demo.sv \
../../hdl/tbn/flash/tang_nano_9k_flash_demo_tb.sv \
-do "run 1000ms"

#-gui \
#-do cmd.do

#../impl/qwsynthesis/tang_nano_9k_flash_demo.vg

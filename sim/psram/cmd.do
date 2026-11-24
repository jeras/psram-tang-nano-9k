# compile

qrun -suppress 14408 -suppress 16154 -voptargs=+acc \
-top tb -sv \
-defineall S27KS0642DPBHI \
-gui \
../src/psram_controller.v \
../src/uart_tx.v \
../src/psram_test_top.v \
../tb/s27kl0642.v \
../tb/tb.v

#../impl/qwsynthesis/psram_controller.vg

# GUI

add wave /tb/psram_ck
add wave /tb/psram_ck_n
add wave /tb/psram_cs_n
add wave /tb/psram_rwds
add wave /tb/psram_dq
add wave /tb/psram_reset_n

view wave
view structure
view signals

# run

#run 20000us

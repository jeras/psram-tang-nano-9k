# import yosys commands
yosys -import

puts "================================================================================"
puts "= parsing SystemVerilog using Yosys-Slang"
puts "================================================================================"

# TODO: can PRJ be inherited from the shell script?
set PRJ "tangnano9k_flash_demo"

set PATH_TCB_RTL "../../../TCB/hdl/rtl"
set PATH_SOC_RTL "../../../hdl/rtl"

read_verilog -sv \
$PATH_TCB_RTL/dev/uart/tcb_dev_uart_des.sv \
$PATH_TCB_RTL/dev/uart/tcb_dev_uart_ser.sv \
$PATH_SOC_RTL/debounce/debounce.sv \
$PATH_SOC_RTL/flash/embedded_flash_controller.sv \
$PATH_SOC_RTL/flash/tangnano9k_flash_demo.sv \

puts "================================================================================"
puts "= synthesis with Yosys/Apicula"
puts "================================================================================"

synth_gowin -json $PRJ.json

write_verilog -norename $PRJ.syn.v

# Embedded Flash controller

## Simulation

Creating a user Flash content file (a binary file, containing text):
```sh
./incrementing_lines.py
```

Using _Icarus Verilog_:
```sh
./simulate-iverilog.sh
```

Using _Questa_:
```sh
./simulate-questa.sh
```

## Live testing

Programming both the FPGA bitstream Flash and user Flash.
```sh
openFPGALoader -b tangnano9k -f impl/pnr/tang_nano_9k_flash_demo.fs --user-flash ../../sim/flash/incrementing_lines.txt
```

Programming the FPGA bitstream into SRAM, keeping the user Flash unchanged:
```sh
openFPGALoader -b tangnano9k -m impl/pnr/tang_nano_9k_flash_demo.fs
```

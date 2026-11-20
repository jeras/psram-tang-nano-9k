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

## FPGA board programming

Programming both the FPGA bitstream Flash and user Flash.
```sh
openFPGALoader -b tangnano9k -f ../../fpga/flash/impl/pnr/tang_nano_9k_flash_demo.fs --user-flash incrementing_lines.txt
```

Programming the FPGA bitstream into Flash, keeping the user Flash unchanged:
```sh
openFPGALoader -b tangnano9k -f ../../fpga/flash/impl/pnr/tang_nano_9k_flash_demo.fs
```

Programming the FPGA bitstream into SRAM, keeping the user Flash unchanged:
```sh
openFPGALoader -b tangnano9k -m ../../fpga/flash/impl/pnr/tang_nano_9k_flash_demo.fs
```

## Live testing

Read flash contents with a shell script (WARNING: it is not working):
```sh
./flash_readout.sh /dev/ttyUSB1 flash_contents.txt
```

Read flash contents with a Python script (with TTY device and output file as arguments):
```sh
./flash_readout.py /dev/ttyUSB1 flash_contents.txt
```

Check the user Flash contents:
```sh
diff flash_contents.txt incrementing_lines.txt
```
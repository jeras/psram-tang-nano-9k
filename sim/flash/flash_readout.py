#!/usr/bin/env python3

import sys
import serial


if __name__ == "__main__":
    # parse CLI arguments
    tty_device = sys.argv[1]
    out_file   = sys.argv[2]
    with serial.Serial(tty_device, 115200, timeout=None, exclusive=True) as ser:
        # reset buffers
        ser.reset_input_buffer()
        ser.reset_output_buffer()
        # send readout command
        ser.write(b'\n')
        # read up to ten bytes (timeout)
        flash = ser.read(304*64*4)
#        print(len(flash))
#       print("Flash (bin): ", flash)
#       print("Flash (hex): ", flash.hex())
        with open(out_file, "wb") as file:
            file.write(flash)

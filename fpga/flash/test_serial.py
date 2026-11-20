#!/usr/bin/env python3

import serial

if __name__ == "__main__":
    with serial.Serial('/dev/ttyUSB1', 115200, timeout=1) as ser:
        # clear read buffer
        flush = ser.read_all()
        print("FLUSH: ", flush)
        # send readout command
        ser.write(b'\n')
        # read up to ten bytes (timeout)
        flash = ser.read(304*64*4)
        print("Flash: ", flash)
#    with open("incrementing_lines.txt", "w") as file:
#        for page in range(304):
#            for word in range(64//2):
#                file.write(f"P{page:03}W{(word*2):02}\n")

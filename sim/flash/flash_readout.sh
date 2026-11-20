#!/bin/bash

echo "configure the host device $1"
stty -F $1 115200 -crtscts

echo "flush $1 receive buffer into /dev/null"
cat $1 > /dev/null

echo "start receiving data from $1 and write it into $2"
head -c 77824 $1 > $2 &
echo "send a `\n` character to the FPGA board UART"
echo > $1

echo "receive data from $1 and write it into $2"
wait

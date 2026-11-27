#! /bin/bash

PRJ=tangnano9k_flash_demo

echo "================================================================================"
echo "= Synthesis"
echo "================================================================================"

yosys --logfile ${PRJ}.syn.log --tcl-scriptfile ${PRJ}.tcl

echo "================================================================================"
echo "= P&R"
echo "================================================================================"

nextpnr-himbaechel --gui \
    --json   ${PRJ}.json \
    --device 'GW1NR-LV9QN88PC6/I5' \
    --vopt   family='GW1N-9C' \
    --vopt   cst=${PRJ}.cst \
    --sdc    ${PRJ}.sdc \
    --write  ${PRJ}.pnr.json \
    --log    ${PRJ}.pnr.log \
    --sdf    ${PRJ}.sdf

echo "================================================================================"
echo "= pack"
echo "================================================================================"

gowin_pack -d GW1N-9C -o ${PRJ}.fs ${PRJ}.pnr.json
# gowin_unpack -d $DEVICE -o ${PRJ}_unpack.v ${PRJ}.fs
# yosys -p "read_verilog -lib +/gowin/cells_sim.v; clean -purge; show" ${PRJ}_unpack.v

echo "================================================================================"
echo "= program"
echo "================================================================================"

# program bitstream into memory
#openFPGALoader -b tangnano9k -m ${PRJ}.fs

# program bitstream into flash
#openFPGALoader -b tangnano9k -f ${PRJ}.fs


## Tang Nano 9K SoC

The project was initially based on [PSRAM/HyperRAM controller for Tang Nano 9K](https://github.com/zf3/psram-tang-nano-9k).

Documentation:
* debouncer and power-on reset,
* [user Flash controller](doc/flash/README.md),
* PSRAM/HyperRAM PHY, controller and cache,

# Scratchpad

LVCMOS18D
ELVDS_IOBUF

# References

[VexRiscv data cache](https://github.com/SpinalHDL/VexRiscv/blob/master/src/main/scala/vexriscv/plugin/DBusCachedPlugin.scala)

[CVA5 data cache](https://github.com/openhwfoundation/cva5/blob/2acf79fa87a94869eb8650c9b5805f14a7d3d9f8/core/execution_units/load_store_unit/dcache_noinv.sv)
* replacement policy is random (to cycle periodically over all ways)
  https://github.com/openhwfoundation/cva5/blob/2acf79fa87a94869eb8650c9b5805f14a7d3d9f8/docs/FCCM_Presentation/CVA5_FCCM_Workshop.pptx

[Ibex instruction cache](https://github.com/lowRISC/ibex/blob/master/rtl/ibex_icache.sv)
* round robin https://github.com/lowRISC/ibex/blob/master/rtl/ibex_icache.sv#L524-L543

Livestream - Digital Design and Computer Architecture (Spring 2026)
[L23: Cache Design, Management, and Tradeoffs](https://www.youtube.com/watch?v=_CzOaPRjt4Q&list=PL5Q2soXY2Zi-yo9kK-BKrq11ykNKkVEpd&index=39&pp=iAQB0gcJCUEMAYcqIYzv)
[L24: Prefetching](https://www.youtube.com/watch?v=5dzzhFV4IlY&list=PL5Q2soXY2Zi-yo9kK-BKrq11ykNKkVEpd&index=41)
[L13: Precise Exceptions & Interrupts](https://www.youtube.com/watch?v=TH386wzOXvA&list=PL5Q2soXY2Zi-yo9kK-BKrq11ykNKkVEpd&index=21)

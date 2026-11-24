# Embedded flash controller

In the current state this are more like instructions on how to build your custom
embedded flash controller than a parameterized general purpose IP block.

## System bus protocol

The system bus protocol is a combination of the VALID/READY handshake
and SRAM access timing, with the exception that write access is not implemented.

The VALID signal indicates a request and the address must be stable
through the entire valid period.

The READY signal would generally be used either by a subordinate
to extend the access to a slow peripheral (in this case),
or the interconnect to indicate when the arbiter
is giving access to the observed manager.

The described Flash controllers all follow a similar principle to SRAM (synchronous RAM),
The setup timing for the address is low and
read data is available after the rising edge of the clock (after a clock to output delay).

The low setup timing is achieved by registering the request address signals withing the controller.

In **combinational** mode, similar to SRAM access timing,
the Flash read data is available after a clock to data valid delay.
This delay is small for FPGA BSRAM (_3.46ns_) but large for the embedded flash (_25ns_).

In **registered** mode, there read data signals are registered,
thus delaying the data for another clock cycle in relation to the handshake.
This is similar to enabling the read data register for BSRAM.

## Flash protocol

For all discussed controller implementations the `XADDR`/`YADDR` registered
and at the same clock edge `XE`/`YE` are driven high.

The read data signal can be either forwarded combinationaly to the rest of the SoC,
In this case the setup delay within the SoC must be added to the Flash access time (_25ns_)
when calculating the maximum clock frequency.

As an alternative, the read data signals can be registered within the controller.
In this case the controller timing can be calculated manually,
while for the rest of the SoC the timing can be just a simple clock period constraint.

### Common approach

The common approach is to handle all protocol timing requirements
using one or more clock periods and to register the read data path.

All timing requirements are fulfilled with one or more clock period states:
* `IDLE`: the address enable signals `XE`/`YE` are low,
  Gowin documentation does not specify a minimum or maximum time.
  _Tnws_` (SE pulse low level time) is just _2ns_,
  so a single clock period is enough for up to a 500MHz clock.
* `ADDR`: at the beginning the `XADDR`/`YADDR` address signals become valid and
  address enable signals `XE`/`YE` become active.
  _Tas_ (time from address and `XE`/`YE` pos-edge to `SE` pose-edge) is just _0.1ns_,
  so a single clock period is always enough.
* `DETECT`: the `SE` pulse must be at least _5ns_ long,
  a single clock period is enough for up to a _200MHz_ clock speed.
* `DATA`: state can be from 0 to many clock cycles depending on the clock frequency.
  The length of `DETECT`+`DATA` states must be at least _Tacc_ (access time).
  In case of a registered read path at least _25ns_,
  in case of a combinational path, the setup delay within the SoC must be added.
* After the `XE`/`YE` transition to low, the data is only valid for _Tdh_ (data hold time),
  at _0.5ns_ it should be enough for FPGA register hold requirements.

![4 cycle protocol](protocol_4cyc.svg)

### Removing the idle state

The timing diagrams in the Gowin device documentation seem to indicate,
`SE` pulses can be issued without lowering the address enable signals `XE`/`YE`.
Unfortunately the address signals `XADDR`/`YADDR` in the diagram remain unchanged,
so the documentation is not clear.

So I guessed address enable gaps are not really necessary,
I removed them from the controller state machine and tested the setup.
Again unfortunately the Flash model does not support this,
so I was only able to test this on the actual running hardware using the demo design.

While the demo apparently works as I would have hoped,
there could still be unexpected side effect affecting Flash reliability.
I would need the full embedded flash documentation from the manufacturer (TSMC 55nm).

![3 cycle protocol](protocol_3cyc.svg)

### Removing the `SE` setup state

Since the _Tas_ (time from address and `XE`/`YE` pos-edge to `SE` pose-edge) is just _0.1ns_,
it can be implemented with some combinatorial logic delay (`LUT4` in this design)
instead of a full clock period. This saves another clock period
not going toward the Flash access time.

If the `SE` high pulse is a full clock period long,
there must be at least another state where `SE` is low.

![2 cycle protocol](protocol_2cyc.svg)

**WARNING:** The propagation delay of a `LUT4` (input I0) is about _250ps_,
while interconnect delays can be larger (_500ps_).
So the proper timing might depend on logic placement and routing.
To reliably (repeatably) solve this issue, controller logic locations should be constrained.

### Half period `SE` pulse

The `SE` pulse length can be reduced to a half clock period.
The solution given here is to have a positive clocked `SEp` signal
togling each system bus access cycle and a negatively clocked `SEn` signal
following the positive one.
The `SE` signal is obtaining by XOR-in the positive/negative signals.
The XOR implementation with `LUT4` provides enough propagation delay
to cover the _Tas_ requirement.

This protocol configuration allows for a single clock cycle access to the Flash
at up to 100MHz (`SE` high pulse must be at lest _5ns_ log).
But since above _40MHz_ the access time is already at 2 clock periods,
the previous configuration makes more sense (it is simpler).

![1 cycle protocol](protocol_1cyc.svg)

NOTE: With combinational logic the possibility of
[glitches](https://en.wikipedia.org/wiki/Race_condition) should be considered.
A glitch can occur when a signal is split,
propagated through separate paths with different delays and later recombined.
Based on my understanding of Gowin `LUT4` logic, glitches should not be a problem.

WARNING: the same warning about interconnect timing repeatability applies here.

### Address prediction/prefetch

In case of a registered read data configuration the read data
is delayed 2 clock periods compared to the handshake,
which is not ideal for a tightly coupled system bus.

Since most access patterns are sequential,
a controller can increment the request address and prefetch the next address.
If the next system bus request address matches the prediction the response
can take a single cycle, if the address does not match the prediction,
the request takes another clock cycle.

## Conclusions

Recommendations ...

## APPENDIX: Test demo

A few notes on the RTL design:
* The Flash control signals `[X/Y]E`, `SE` and `VALID`/`READY` are encoded into the FSM states themselves,
  since only 4 signals control the FSM, all can be implemented using only LUT4.
  So there is the FSM does not consume any additional logic.
* While the controller could be tested using a RISC-V CPU,
  I thought it would be easier writing a custom FSM for the demo,
  than finding a simple RISC-V CPU performing back to back reads each clock period.

The controller and demo code can be found in:
* RTL: `hdl/rtl/flash`,
* testbench: `hdl/tbn/flash`.

### Simulating

Enter the simulation folder:
```sh
cd sim/flash
```

Creating a user Flash content file (a binary file, containing text):
```sh
./incrementing_lines.py
```

Using _Icarus Verilog_ (testing using a Git HEAD build of Icarus Verilog):
```sh
./simulate-iverilog.sh
```

Using _Questa_:
```sh
./simulate-questa.sh
```

### Synthesis

A Gowin IDE project can be found in the `fpga/flash` folder.

### FPGA board programming

Enter the simulation folder and generate the user Flash contents file:
```sh
cd sim/flash
./incrementing_lines.py
```

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

### Live hardware testing

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

## References

Official vendor documentation:

1. [UG285 - Gowin BSRAM & SSRAM (User Guide)](https://gowinsemi.com/upload/database_doc/2470/document/68f6993855a87.pdf)
2. [DS117 - GW1NR series of FPGA Products (Data Sheet)](https://gowinsemi.com/upload/database_doc/1785/document/6b008320624e0.pdf)

3. [UG295 - Gowin User Flash (User Guide)](https://cdn.gowinsemi.com.cn/UG295E.pdf)
4. [Gowin Flash Control (IP documentation)](https://gowinsemi.com/en/support/ip_detail/38/)

5. [SUG940 - Gowin Design Timing Constraints (User Guide)](https://www.gowinsemi.com/upload/database_doc/1875/document/6abd2bec0078c.pdf)
6. [SUG1541 - Gowin Software Physical Constraints (User Guide)](https://www.gowinsemi.com/upload/database_doc/1872/document/6abd2c88904cc.pdf)

Open source Flash controller implementations:

7. [`Flash_Controller` from `](https://github.com/htminuslab/Flash_Controller)

8. [Gowin User Flash on Tang Nano 9K FPGA Development Board](https://www.youtube.com/watch?v=uRGNqobXO5E)
9. [Faster User Flash Controller for the Tang Nano 9K](https://www.youtube.com/watch?v=LX4mTK7icNk)
10. [faster_user_flash](https://github.com/grughuhler/picorv32/tree/faster_user_flash)

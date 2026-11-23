# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# Project

Create a TRNG in VHDL and export via USB-Blaster at least 125 MBytes of the output (total 1 Gbit).

This directory (`trng/`) currently contains no Quartus project yet — only this
spec and `knowledge/` reference PDFs (`counter_jtag_explained (1).pdf`,
`Material complementar 3.pdf`). The project must be built from scratch,
following the patterns in the two sibling example projects below.

## Circuit & Sampling
  **Ring Oscillator**: Each ring must use 13 NOT gates. The circuit must has 114 these rings.
  **Mixing**: For each Ring Oscillator, apply the XOR gate for all of the 114 Rings.
  **Sampling**: Use a D-Flip-Flop to sample the output at 40 MHz
  **Export**: Use USB-Blaster to export the data to the computer. Use the Megafunction alt\_jtag\_atlantic.
## The Board & Computer specification
  **Board Spec**: FPGA Altera Cyclone V 5CEBA4F23C7 DE0-CV.
  **Computer's**: Linux UBUNTU 24.04. Capture the output using juart-terminal command
## Example & Material
  `@/home/mvm/altera_lite/25.1std/quartus/codes/DE0CV/COUNTER_JTAG`: Simple project that implements a counter and exports it via USB-Blaster. This is the model for the export path (alt_jtag_atlantic wrapper + byte-stream handshake) — reuse its pattern, not its content.
  `@/home/mvm/altera_lite/25.1std/quartus/codes/DE0CV/RingOsc`: A minimal 3-inverter ring oscillator captured with SignalTap (`.stp`), i.e. a finite logic-analyzer snapshot buffer, not a continuous PC-side export — this is why its "exportation time is limited". The real TRNG must stream continuously through `alt_jtag_atlantic` like `COUNTER_JTAG` does, not through SignalTap. (Note: the actual folder is `RingOsc`, not `ringOscilator` as the path is sometimes written.)

## Toolchain commands

Quartus Prime (25.1std) is installed under `/home/mvm/altera_lite/25.1std/quartus`.
Both example projects use this environment/flow; use the same for this project
once a `.qpf`/`.qsf` exist here:

```bash
export QUARTUS_ROOTDIR=/home/mvm/altera_lite/25.1std/quartus
export PATH=$QUARTUS_ROOTDIR/bin:$PATH

# Compile (creates output_files/<top_entity>.sof)
quartus_sh --flow compile <top_entity>

# Confirm the USB-Blaster and the 5CEBA4 device are visible
jtagconfig

# Program the FPGA over JTAG (volatile — lost on power-cycle)
quartus_pgm -m jtag -o "p;output_files/<top_entity>.sof"

# Capture the JTAG-Atlantic byte stream on the PC
juart-terminal                        # to stdout
juart-terminal | tee capture.bin      # ...and log it
juart-terminal -c <n>                 # select cable, if more than one
```

`nios2-terminal` also works (same underlying JTAG-Atlantic link) but
`juart-terminal` is the one specified for this project.

For the 1 Gbit / 125 MByte capture requirement: `alt_jtag_atlantic` throughput
over the on-board USB-Blaster is well below the raw 40 MHz sample rate in
practice, so the capture will run far longer than the 25 s that 1 Gbit at
40 Mb/s would imply — plan to leave `juart-terminal` capturing for an extended
run and verify the resulting file size (`wc -c capture.bin` or similar) rather
than timing it.

## Architecture patterns to reuse from the example projects

- **JTAG export wrapper** (`COUNTER_JTAG/jtag_uart_tx.vhd`): don't touch the
  `alt_jtag_atlantic` megafunction directly from the top level — wrap it once,
  exposing a plain byte-stream sink (`s_data`/`s_valid`/`s_ready`, byte
  consumed when both valid and ready are high in the same cycle). RX
  (PC→FPGA) is unused; tie `t_dav <= '1'` and leave `t_dat`/`t_ena`/`t_pause`
  open, as `COUNTER_JTAG` does.
- **Sampling → byte packing**: the TRNG produces one bit per DFF sample at
  40 MHz, but `alt_jtag_atlantic` consumes whole bytes. Something analogous to
  `hex_printer.vhd`'s valid/ready producer is needed between the sampler and
  `jtag_uart_tx`: shift 8 sampled bits into a byte, assert `m_valid` once full,
  and only advance when `m_ready` is high (i.e. back-pressure from the JTAG
  core, via `t_pause`/FIFO fullness, must be able to stall the sampler side or
  drop/buffer samples — sustained 40 MHz production will outrun the JTAG link).
- **Ring oscillator synthesis**: `RingOsc/ring_osc.vhd` shows the trick to keep
  Quartus from optimizing away a combinational feedback loop of NOT gates —
  `attribute KEEP : boolean` on every intermediate signal in the ring
  (including the final output). Each of the 114 rings (13 NOT gates each)
  needs this, and the ring outputs are XORed together before the sampling
  D-flip-flop.
- **Clock-domain / timing constraints** (`COUNTER_JTAG/de0cv_counter_jtag.sdc`):
  `create_clock` on the board clock, `set_clock_groups -asynchronous` between
  it and the auto-generated `altera_reserved_tck` (JTAG clock), plus
  `set_false_path` on async I/O (buttons/LEDs). This project additionally
  needs timing exceptions for the ring-oscillator combinational loops
  themselves (free-running, not meant to close static timing) and for the
  40 MHz sampling domain if it differs from the board's 50 MHz `CLOCK_50`
  (would need a PLL).
- **Pin assignments** (`COUNTER_JTAG/de0cv_counter_jtag.qsf`): DE0-CV pin
  locations for `CLOCK_50` (`PIN_M9`), `KEY[0]` (`PIN_U7`), `LEDR[9:0`) are
  already known-good from `COUNTER_JTAG`'s `.qsf` — copy the ones this project
  needs (clock, and LEDs for a liveness indicator) rather than re-deriving
  them; ring oscillators and the mixing/sampling logic are internal and need
  no pin assignments.
- **Device/family assignments**: `FAMILY "Cyclone V"`, `DEVICE 5CEBA4F23C7`,
  matching both example `.qsf` files.

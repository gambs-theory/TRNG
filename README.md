# DE0-CV — ring-oscillator TRNG over JTAG

114 free-running ring oscillators (13 NOT gates each) are XORed into one
entropy signal, sampled by a single D-flip-flop at 40 MHz, de-biased (von
Neumann extractor), packed into bytes and streamed continuously to the PC
over the on-board USB-Blaster cable via the JTAG UART (`alt_jtag_atlantic`) —
the same link `COUNTER_JTAG` uses, read the same way with `juart-terminal`.
Architecture follows B. Sunar, W.J. Martin, D.R. Stinson, IEEE Trans.
Computers 56(1), 2007, Figure 8 (see `knowledge/Material complementar
3.pdf`, Sec. 2.2 and 2.5).

```
114x [ring_oscillator: 13 NOT] --XOR--> entropy_bit --40MHz DFF--> sampled_bit
                                                                       |
                                                                von_neumann.vhd
                                                             (de-bias, Sec. 2.5)
                                                                       |
                                                                trng_packer.vhd
                                                              (bits -> bytes)
                                                                       |
                                                                jtag_uart_tx.vhd
                                                              (alt_jtag_atlantic)
                                                                       |
                                                             USB-Blaster | JTAG
                                                                       v
                                                          PC: juart-terminal
```

50 MHz `CLOCK_50` also drives `pll40.vhd` (ALTPLL, x4 / div 5) to generate the
40 MHz sampling clock; everything from the sampler onward (de-bias, packer,
JTAG export) runs on that one 40 MHz clock, so there is exactly one clock
domain crossing to handle (`CLOCK_50` -> `clk40`, via the reset
synchronisers in `de0cv_trng.vhd`) rather than one per stage.

## Files

| File | Role |
|------|------|
| `de0cv_trng.vhd`     | top level: PLL, resets, 114 rings, XOR, sampler, wiring |
| `ring_oscillator.vhd`| one 13-NOT-gate ring (generic `NUM_INV`), `enable`-gated startup |
| `pll40.vhd`          | ALTPLL wrapper, 50 MHz -> 40 MHz |
| `von_neumann.vhd`    | bias-removal post-processing ("Pos-processamento" in Fig. 8) |
| `trng_packer.vhd`    | de-biased bits -> bytes, valid/ready handshake (same shape as `COUNTER_JTAG/hex_printer.vhd`) |
| `jtag_uart_tx.vhd`   | `alt_jtag_atlantic` wrapper, reused from `COUNTER_JTAG` |
| `de0cv_trng.sdc`     | 50/40 MHz clocks, JTAG clock-group cut, false paths for the free-running rings and the async sampler input |
| `de0cv_trng.qsf`     | device `5CEBA4F23C7`, DE0-CV pins, fast/area fitting (see note below) |

## Build

```bash
export QUARTUS_ROOTDIR=/home/mvm/altera_lite/25.1std/quartus
export PATH=$QUARTUS_ROOTDIR/bin:$PATH

cd /home/mvm/altera_lite/25.1std/quartus/codes/DE0CV/trng
quartus_sh --flow compile de0cv_trng
```

Output bitstream: `output_files/de0cv_trng.sof`. Fitting is slow (tens of
minutes) because of the 114 free-running, unconstrained ring-oscillator
combinational loops — `FITTER_EFFORT FAST_FIT` / `OPTIMIZATION_TECHNIQUE
AREA` are set in the `.qsf` since timing-driven placement effort on those
loops is wasted; the one real timing requirement (the ~40 MHz packer/JTAG
logic) closes easily either way. Expect a "Found combinational loop" critical
warning for every ring instance during fitting — that is inherent to a ring
oscillator (it is the entropy source, not a bug) and does not block
compilation.

## Program the FPGA (volatile, over USB-Blaster)

```bash
jtagconfig
quartus_pgm -c 1 -m jtag -o "p;output_files/de0cv_trng.sof"
```

## Capture the output

```bash
juart-terminal --no-quit-on-ctrl-d -o 300 -q > capture.bin
```

**`--no-quit-on-ctrl-d` is required.** The output is raw random bytes, not
text; `juart-terminal` was built for interactive text terminals and, by
default, treats any incoming `0x04` (Ctrl-D) byte as the far end signalling
EOF and disconnects — which a truly random byte stream hits by chance about
once every 256 bytes. Without this flag, capture dies almost immediately.

In this environment, single long-lived `juart-terminal` invocations
(foreground, backgrounded, or harness-managed background) were observed to
occasionally get killed a few minutes in for reasons that didn't trace back
to `juart-terminal`, the FPGA, or the USB-Blaster cable (`jtagconfig` kept
seeing the board fine throughout, and the design side never logged an
error). The robust workaround used for the reference 1 Gbit capture was a
short retry loop appending to the same output file:

```bash
END=$(( $(date +%s) + 540 ))
while [ "$(date +%s)" -lt "$END" ]; do
  juart-terminal --no-quit-on-ctrl-d -o 25 -q >> capture.bin
done
```

A restart mid-stream just picks up wherever the FPGA's TX FIFO currently is
(the design keeps running regardless of host-side (dis)connects) — no reset,
no realignment needed, and no harm to the randomness of the resulting file
even if a few bytes are skipped at a reconnect boundary.

## Result (reference capture)

A capture taken this way on 2026-09-01 produced
`capture/trng_1gbit.bin`, **140,677,327 bytes (≈134.2 MiB, ≈1.125 Gbit)** —
above both the 125 MByte and 1 Gbit requirements. Basic statistical checks
on the full file:

- bit balance: 49.9990% ones / 50.0010% zeros (essentially perfect, and
  stable across the whole ~35-minute capture -- no drift)
- per-bit-position-within-byte balance: 0.49982-0.50018 (all within noise)
- bit-level autocorrelation: lag >=2 bits statistically indistinguishable
  from independent; a small but real anti-correlation at lag 1
  (49.90% vs 50.00% match rate) -- the expected residual signature of
  sampling a physical oscillator well above its correlation time. This is
  why real deployments add a cryptographic conditioner (AES/SHA-based, per
  NIST SP 800-90B) after simple bias correction; that is beyond this
  project's specified architecture (ring oscillators -> XOR -> 40 MHz
  sampler -> de-bias -> export) but worth knowing about the data's actual
  quality rather than assuming a raw ring-oscillator TRNG is
  cryptographically flawless.

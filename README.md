# DUCO-FPGA (Tang Nano 20K + Verilator)

Hardware DUCO-S1 (Duino-Coin) SHA-1 miner in Verilog, with a Verilator C++ testbench and Tang Nano 20K (`GW2AR-LV18QN88C8/I7`) build targets.

## Project Structure

- `rtl/sha1_core.v` — Iterative SHA-1 core (1 round/cycle, 80 rounds + finish).
- `rtl/duco_miner.v` — DUCO-S1 miner: maintains an ASCII decimal nonce counter (no dividers), pads `base_hash || ascii(nonce)` into a 512-bit block, runs `sha1_core`, and compares against `target_hash`.
- `sim/tb_duco_miner.cpp` — Verilator C++ testbench with verified SHA-1 test vectors.
- `tangnano20k.cst` — Pin constraints for the Tang Nano 20K.
- `Makefile` — Simulation (`sim`) and FPGA (`synth`, `pnr`, `pack`, `flash`) targets.

## 1. Install Tools

### Verilator (for simulation now)
On Arch Linux:
```bash
sudo pacman -S verilator
```
(Or on Ubuntu/Debian: `sudo apt install verilator`)

### Open-Source Gowin FPGA Toolchain (for Tang Nano 20K)
The easiest way to get `yosys`, `nextpnr-himbaechel`, `gowin_pack`, and `openFPGALoader` together is **OSS CAD Suite** from YosysHQ:
https://github.com/YosysHQ/oss-cad-suite-build/releases

Extract it and add its `bin/` directory to your `PATH`.

## 2. Run Verilator Simulation

```bash
make sim
```

## Branches & Performance (Tang Nano 20K)

| Branch | Architecture | @ 27 MHz | `Fmax` | Max @ `Fmax` |
|---|---|---|---|---|
| `master` | 2 cores × 2 rounds/cycle (`kw` pre-add) | ~1.22 MH/s | ~38.6 MHz | **~1.75 MH/s** |
| `4core-1round` | 4 cores × 1 round/cycle (`kw` pre-add) | ~1.28 MH/s | ~34.5 MHz | **~1.64 MH/s** |

## 3. Build & Flash to Tang Nano 20K (when board arrives)

`duco_top.v` wraps `duco_miner` with a 115200 8N1 UART interface (pins 69/70 in `tangnano20k.cst`).

```bash
make flash
./host/miner_host.py --username YOUR_DUCO_USERNAME --miner-key YOUR_KEY --backend serial --port /dev/ttyUSB1
```

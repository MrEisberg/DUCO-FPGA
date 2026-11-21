# DUCO-FPGA (Tang Nano 20K + Verilator)

Hardware DUCO-S1 (Duino-Coin) SHA-1 miner in Verilog for the Sipeed Tang Nano 20K (`GW2AR-LV18QN88C8/I7`), with a Verilator C++ simulation backend and Python pool host.

## Project Structure

- `rtl/sha1_core.v` — Compact 16-word shift-register SHA-1 core (1 round/cycle, `e + K + W` pre-add, registered round-76 H4 early abort, full 160-bit match).
- `rtl/duco_miner.v` — 10-core lockstep DUCO-S1 miner sharing a single prefix BCD counter (tests `10*prefix + 0..9` in parallel as a single miner to avoid the Kolka multi-miner penalty).
- `rtl/duco_top.v` — Tang Nano 20K top-level wrapper with 115200 8N1 UART, Double-Dabble BCD converter, Power-On Reset + S1 button reset, and onboard status LEDs (`led[0]` mining heartbeat, `led[1]` share pulse).
- `rtl/uart_rx.v`, `rtl/uart_tx.v` — 8N1 UART transceiver.
- `rtl/pll_60m.v` — Gowin `rPLL` (`27 MHz -> 60.0 MHz`).
- `sim/tb_duco_miner.cpp` — Verilator unit testbench with verified SHA-1 test vectors.
- `sim/sim_server.cpp` — Persistent Verilator stdin/stdout job solver for live pool mining in simulation.
- `host/miner_host.py` — Python host miner supporting both `--backend sim` (Verilator) and `--backend serial` (Tang Nano 20K over USB-UART).
- `tangnano20k.cst` — Pin constraints for the Tang Nano 20K.
- `Makefile` — Simulation (`sim`, `sim-server`) and FPGA (`synth`, `pnr`, `pack`, `flash`) targets.

## Performance (Tang Nano 20K)

| Branch | Architecture | Clock | `Fmax` | Hashrate |
|---|---|---|---|---|
| `master` | 10 cores × 1 round/cycle (shift-reg + early abort + `rPLL`) | 60.0 MHz | ~64.3 MHz | **~7.60 MH/s** |

## 1. Install Tools

Install **OSS CAD Suite** (includes Verilator, Yosys, `nextpnr-himbaechel`, `gowin_pack`, and `openFPGALoader`):
https://github.com/YosysHQ/oss-cad-suite-build/releases

Extract it and add its `bin/` directory to your `PATH`.

## 2. Run Verilator Simulation

Unit tests:
```bash
make sim
```

Live pool mining in Verilator simulation:
```bash
make sim-server
./host/miner_host.py --username YOUR_DUCO_USERNAME --miner-key YOUR_KEY --backend sim
```

## 3. Build & Flash to Tang Nano 20K

```bash
make flash
./host/miner_host.py --username YOUR_DUCO_USERNAME --miner-key YOUR_KEY --backend serial --port /dev/ttyUSB1
```

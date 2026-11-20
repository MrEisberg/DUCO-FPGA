#!/usr/bin/env python3
"""
Host miner for DUCO-FPGA.
Connects to a Duino-Coin pool over TCP, dispatches jobs to either the Verilator
simulation server (--backend sim) or a Tang Nano 20K over UART (--backend serial),
and submits found nonces back to the pool.
"""

import argparse
import json
import random
import socket
import subprocess
import sys
import time
import urllib.request


def get_pool(timeout: float = 10.0) -> tuple[str, int]:
    req = urllib.request.Request(
        "https://server.duinocoin.com/getPool",
        headers={"User-Agent": "DUCO-FPGA/0.1"},
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        data = json.loads(resp.read().decode("utf-8"))
        return data["ip"], int(data["port"])


class SimBackend:
    def __init__(self, bin_path: str):
        self.proc = subprocess.Popen(
            [bin_path],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            text=True,
            bufsize=1,
        )

    def solve(self, base_hash: str, target_hash: str, max_nonce: int) -> tuple[bool, int, int]:
        assert self.proc.stdin is not None and self.proc.stdout is not None
        self.proc.stdin.write(f"{base_hash},{target_hash},{max_nonce}\n")
        self.proc.stdin.flush()
        line = self.proc.stdout.readline().strip()
        if not line or line.startswith("ERR"):
            raise RuntimeError(f"Sim error: {line}")
        found_s, nonce_s, cycles_s = line.split(",")
        return found_s == "1", int(nonce_s), int(cycles_s)

    def close(self) -> None:
        self.proc.terminate()
        self.proc.wait(timeout=3)


class SerialBackend:
    def __init__(self, port: str, baud: int):
        try:
            import serial  # type: ignore
        except ImportError as exc:
            raise RuntimeError("pyserial is required for --backend serial (pip install pyserial)") from exc
        self.ser = serial.Serial(port, baudrate=baud, timeout=60)

    def solve(self, base_hash: str, target_hash: str, max_nonce: int) -> tuple[bool, int, int]:
        self.ser.write(f"{base_hash},{target_hash},{max_nonce}\n".encode("ascii"))
        self.ser.flush()
        line = self.ser.readline().decode("ascii", errors="replace").strip()
        if not line or line.startswith("ERR"):
            raise RuntimeError(f"FPGA serial error: {line}")
        found_s, nonce_s, cycles_s = line.split(",")
        return found_s == "1", int(nonce_s), int(cycles_s)

    def close(self) -> None:
        self.ser.close()


def mine_loop(args: argparse.Namespace) -> None:
    if args.backend == "sim":
        backend = SimBackend(args.sim_bin)
    else:
        backend = SerialBackend(args.port, args.baud)

    try:
        while True:
            try:
                host, port = (args.host, args.port_num) if args.host else get_pool()
                print(f"[INFO] Connecting to {host}:{port} ...")
                with socket.create_connection((host, port), timeout=15) as sock:
                    f = sock.makefile("rw", encoding="utf-8", newline="\n")
                    version = f.readline().strip()
                    print(f"[INFO] Connected (server version: {version})")

                    while True:
                        # Pool protocol: JOB,username,difficulty,mining_key,extra
                        f.write(f"JOB,{args.username},{args.diff},{args.miner_key},\n")
                        f.flush()

                        job_line = f.readline().strip()
                        if not job_line:
                            print("[WARN] Empty response from server, reconnecting...")
                            break

                        parts = job_line.split(",")
                        if len(parts) < 3:
                            print(f"[WARN] Unexpected server message: {job_line}")
                            break

                        base_hash, target_hash, difficulty_s = parts[0], parts[1], parts[2]
                        max_nonce = 100 * int(difficulty_s)

                        t0 = time.perf_counter()
                        found, nonce, cycles = backend.solve(base_hash, target_hash, max_nonce)
                        dt = max(time.perf_counter() - t0, 1e-9)

                        if not found:
                            print(f"[WARN] Nonce not found within {max_nonce} (cycles={cycles})")
                            continue

                        hashrate = (nonce + 1) / dt
                        # Share submission: nonce,hashrate,software,rigid,chip_id,wallet_id
                        f.write(
                            f"{nonce},{hashrate:.2f},{args.software},"
                            f"{args.rig_id},{args.chip_id},{args.wallet_id}\n"
                        )
                        f.flush()

                        feedback = f.readline().strip()
                        print(
                            f"[{feedback}] nonce={nonce} diff={difficulty_s} "
                            f"cycles={cycles} time={dt:.3f}s hashrate={hashrate/1000:.2f} kH/s"
                        )
            except (OSError, ValueError, RuntimeError) as exc:
                print(f"[ERROR] {exc} — retrying in 5s...")
                time.sleep(5)
    finally:
        backend.close()


def main() -> None:
    parser = argparse.ArgumentParser(description="DUCO-FPGA Host Miner")
    parser.add_argument("--username", required=True, help="Duino-Coin username")
    parser.add_argument("--miner-key", default="", help="Duino-Coin mining key (required if enabled on account)")
    parser.add_argument("--rig-id", default="DUCO-FPGA", help="Rig identifier")
    parser.add_argument("--diff", default="LOW", help="Job difficulty (LOW, MEDIUM, NET, etc.)")
    parser.add_argument("--software", default="FPGA Miner 0.1", help="Software version string")
    parser.add_argument("--chip-id", default=f"DUCOID{random.randint(10000000, 99999999)}", help="Chip ID (random by default)")
    parser.add_argument("--wallet-id", default=str(random.randint(100000, 9999999)), help="Wallet ID (random by default)")
    parser.add_argument("--backend", choices=["sim", "serial"], default="sim")
    parser.add_argument("--sim-bin", default="./obj_dir/server/Vduco_sim_server")
    parser.add_argument("--port", default="/dev/ttyUSB1", help="Serial port for FPGA")
    parser.add_argument("--baud", type=int, default=115200, help="Serial baud rate")
    parser.add_argument("--host", default=None, help="Optional pool IP/hostname")
    parser.add_argument("--port-num", type=int, default=2813, help="Optional pool port")
    args = parser.parse_args()

    try:
        mine_loop(args)
    except KeyboardInterrupt:
        print("\n[INFO] Stopped by user.")
        sys.exit(0)


if __name__ == "__main__":
    main()

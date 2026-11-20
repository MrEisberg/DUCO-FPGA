#include <verilated.h>
#include "Vduco_miner.h"

#include <cstdint>
#include <cstdio>
#include <cstring>
#include <string>

static void set_base_hash(Vduco_miner* dut, const std::string& ascii40) {
    // base_hash[319:0]: byte 0 at MSB [319:312], byte 39 at LSB [7:0]
    // VlWide<10>: word 0 is [31:0], word 9 is [319:288]
    for (int w = 0; w < 10; ++w) {
        uint32_t val = 0;
        for (int b = 0; b < 4; ++b) {
            int byte_idx = (9 - w) * 4 + b;
            val = (val << 8) | static_cast<uint8_t>(ascii40[byte_idx]);
        }
        dut->base_hash[w] = val;
    }
}

static uint32_t hex_to_u32(const std::string& s, size_t offset) {
    return static_cast<uint32_t>(std::stoul(s.substr(offset, 8), nullptr, 16));
}

static void set_target_hash(Vduco_miner* dut, const std::string& hex40) {
    // target_hash[159:0]: MSB [159:128] is hex[0..7], LSB [31:0] is hex[32..39]
    for (int w = 0; w < 5; ++w) {
        dut->target_hash[w] = hex_to_u32(hex40, (4 - w) * 8);
    }
}

static void tick(Vduco_miner* dut) {
    dut->clk = 0;
    dut->eval();
    dut->clk = 1;
    dut->eval();
}

static bool run_test(
    Vduco_miner* dut,
    const char* name,
    const std::string& base_hash,
    const std::string& target_hash,
    uint32_t max_nonce,
    bool expect_found,
    uint32_t expected_nonce
) {
    set_base_hash(dut, base_hash);
    set_target_hash(dut, target_hash);
    dut->max_nonce = max_nonce;

    dut->start = 1;
    tick(dut);
    dut->start = 0;

    uint64_t cycles = 0;
    const uint64_t timeout = 2000000;
    while (!dut->done && cycles < timeout) {
        tick(dut);
        cycles++;
    }

    if (!dut->done) {
        std::printf("[FAIL] %s: timed out after %llu cycles\n", name, (unsigned long long)cycles);
        return false;
    }

    bool ok = (dut->found == expect_found) && (!expect_found || dut->found_nonce == expected_nonce);
    double hashrate_27mhz = (expect_found && cycles > 0)
        ? (static_cast<double>(expected_nonce + 1) * 27000000.0 / static_cast<double>(cycles))
        : 0.0;

    std::printf(
        "[%s] %s: found=%d nonce=%u cycles=%llu (est. %.2f kH/s @ 27 MHz)\n",
        ok ? "PASS" : "FAIL",
        name,
        dut->found,
        dut->found_nonce,
        (unsigned long long)cycles,
        hashrate_27mhz / 1000.0
    );
    return ok;
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Vduco_miner* dut = new Vduco_miner;

    // Reset
    dut->rst_n = 0;
    dut->start = 0;
    dut->max_nonce = 0;
    for (int i = 0; i < 4; ++i) tick(dut);
    dut->rst_n = 1;
    tick(dut);

    const std::string base = "a94a8fe5ccb19ba61c4c0873d391e987982fbbd3";
    bool all_ok = true;

    all_ok &= run_test(dut, "Nonce 42",   base, "0a3c0241294f89ef0e76b1e8650a6d6d3f527040", 100,  true,  42);
    all_ok &= run_test(dut, "Nonce 1234", base, "fccde712301b262a8e3a29f097aeda62c0570349", 2000, true,  1234);
    all_ok &= run_test(dut, "Not found",  base, "ffffffffffffffffffffffffffffffffffffffff", 50,   false, 0);

    delete dut;
    return all_ok ? 0 : 1;
}

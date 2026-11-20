#include <verilated.h>
#include "Vduco_miner.h"

#include <cstdint>
#include <iostream>
#include <sstream>
#include <string>

static void set_base_hash(Vduco_miner* dut, const std::string& ascii40) {
    for (int w = 0; w < 10; ++w) {
        uint32_t val = 0;
        for (int b = 0; b < 4; ++b) {
            int byte_idx = (9 - w) * 4 + b;
            val = (val << 8) | static_cast<uint8_t>(ascii40[byte_idx]);
        }
        dut->base_hash[w] = val;
    }
}

static void set_target_hash(Vduco_miner* dut, const std::string& hex40) {
    for (int w = 0; w < 5; ++w) {
        dut->target_hash[w] = static_cast<uint32_t>(
            std::stoul(hex40.substr((4 - w) * 8, 8), nullptr, 16)
        );
    }
}

static void tick(Vduco_miner* dut) {
    dut->clk = 0;
    dut->eval();
    dut->clk = 1;
    dut->eval();
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Vduco_miner* dut = new Vduco_miner;

    dut->rst_n = 0;
    dut->start = 0;
    dut->max_nonce = 0;
    for (int i = 0; i < 4; ++i) tick(dut);
    dut->rst_n = 1;
    tick(dut);

    std::string line;
    while (std::getline(std::cin, line)) {
        if (line.empty()) continue;

        std::istringstream ss(line);
        std::string base_hash, target_hash, max_nonce_str;
        if (!std::getline(ss, base_hash, ',') ||
            !std::getline(ss, target_hash, ',') ||
            !std::getline(ss, max_nonce_str, ',')) {
            std::cout << "ERR,invalid_input\n" << std::flush;
            continue;
        }

        if (base_hash.size() != 40 || target_hash.size() != 40) {
            std::cout << "ERR,invalid_length\n" << std::flush;
            continue;
        }

        uint32_t max_nonce = static_cast<uint32_t>(std::stoul(max_nonce_str));
        set_base_hash(dut, base_hash);
        set_target_hash(dut, target_hash);
        dut->max_nonce = max_nonce;

        dut->start = 1;
        tick(dut);
        dut->start = 0;

        uint64_t cycles = 0;
        while (!dut->done) {
            tick(dut);
            cycles++;
        }

        std::cout << (dut->found ? 1 : 0) << ","
                  << dut->found_nonce << ","
                  << cycles << "\n" << std::flush;
    }

    delete dut;
    return 0;
}

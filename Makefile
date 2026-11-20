TOP_SIM   := duco_miner
TOP_FPGA  := duco_top
RTL_SRCS  := rtl/sha1_core.v rtl/duco_miner.v
FPGA_SRCS := $(RTL_SRCS) rtl/uart_rx.v rtl/uart_tx.v rtl/duco_top.v
SIM_TB    := sim/tb_duco_miner.cpp
OBJ_DIR   := obj_dir

# Tang Nano 20K (GW2AR-LV18QN88C8/I7)
DEVICE    := GW2AR-LV18QN88C8/I7
FAMILY    := GW2A-18C
CST       := tangnano20k.cst
BUILD_DIR := build

.PHONY: all sim sim-server clean synth pnr pack flash

all: sim

sim: $(RTL_SRCS) $(SIM_TB)
	verilator --cc --exe --build -j 0 -Wall \
		--top-module $(TOP_SIM) \
		$(RTL_SRCS) $(SIM_TB) \
		--Mdir $(OBJ_DIR)
	./$(OBJ_DIR)/V$(TOP_SIM)

sim-server: $(RTL_SRCS) sim/sim_server.cpp
	verilator --cc --exe --build -j 0 -Wall \
		--top-module $(TOP_SIM) \
		-o Vduco_sim_server \
		$(RTL_SRCS) sim/sim_server.cpp \
		--Mdir $(OBJ_DIR)/server

synth: $(FPGA_SRCS)
	mkdir -p $(BUILD_DIR)
	yosys -p "read_verilog $(FPGA_SRCS); synth_gowin -top $(TOP_FPGA) -json $(BUILD_DIR)/$(TOP_FPGA).json"

pnr: synth $(CST)
	nextpnr-himbaechel --json $(BUILD_DIR)/$(TOP_FPGA).json \
		--write $(BUILD_DIR)/$(TOP_FPGA)_pnr.json \
		--device $(DEVICE) \
		--freq 27 \
		--vopt family=$(FAMILY) \
		--vopt cst=$(CST)

pack: pnr
	gowin_pack -d $(FAMILY) -o $(BUILD_DIR)/$(TOP_FPGA).fs $(BUILD_DIR)/$(TOP_FPGA)_pnr.json

flash: pack
	openFPGALoader -b tangnano20k $(BUILD_DIR)/$(TOP_FPGA).fs

clean:
	rm -rf $(OBJ_DIR) $(BUILD_DIR)

TOP_SIM   := duco_miner
RTL_SRCS  := rtl/sha1_core.v rtl/duco_miner.v
SIM_TB    := sim/tb_duco_miner.cpp
OBJ_DIR   := obj_dir

# Tang Nano 20K (GW2AR-LV18QN88C8/I7)
DEVICE    := GW2AR-LV18QN88C8/I7
FAMILY    := GW2A-18C
CST       := tangnano20k.cst
BUILD_DIR := build

.PHONY: all sim clean synth pnr pack flash

all: sim

sim: $(RTL_SRCS) $(SIM_TB)
	verilator --cc --exe --build -j 0 -Wall \
		--top-module $(TOP_SIM) \
		$(RTL_SRCS) $(SIM_TB) \
		--Mdir $(OBJ_DIR)
	./$(OBJ_DIR)/V$(TOP_SIM)

synth: $(RTL_SRCS)
	mkdir -p $(BUILD_DIR)
	yosys -p "read_verilog $(RTL_SRCS); synth_gowin -top $(TOP_SIM) -json $(BUILD_DIR)/$(TOP_SIM).json"

pnr: synth $(CST)
	nextpnr-himbaechel --json $(BUILD_DIR)/$(TOP_SIM).json \
		--write $(BUILD_DIR)/$(TOP_SIM)_pnr.json \
		--device $(DEVICE) \
		--vopt family=$(FAMILY) \
		--vopt cst=$(CST)

pack: pnr
	gowin_pack -d $(FAMILY) -o $(BUILD_DIR)/$(TOP_SIM).fs $(BUILD_DIR)/$(TOP_SIM)_pnr.json

flash: pack
	openFPGALoader -b tangnano20k $(BUILD_DIR)/$(TOP_SIM).fs

clean:
	rm -rf $(OBJ_DIR) $(BUILD_DIR)

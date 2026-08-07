CXX = g++
CXXFLAGS = -std=c++17 -Wall -O2

SRC = \
scripts/cpp_golden_model/TOP_MODULE.CPP \
scripts/cpp_golden_model/ALU_MODEL.CPP \
scripts/cpp_golden_model/branch_target_buffer.cpp \
scripts/cpp_golden_model/data_and_instruction_memory.cpp \
scripts/cpp_golden_model/instruction_fetch_unit.cpp \
scripts/cpp_golden_model/register_file.cpp \
scripts/cpp_golden_model/RV64_decode_unit.cpp

TARGET = rv64_golden_model.exe

all:
	$(CXX) $(CXXFLAGS) $(SRC) -o $(TARGET)

run_golden_model: all
	./$(TARGET)

clean:
	del /Q $(TARGET)
# Files
ASM     = scripts\test_env\program.asm
IMEM    = memory\golden_instruction_memory.hex
DMEM    = memory\golden_data_memory.hex
SYMS    = symbols.txt

# Python interpreter
PYTHON  = python3

# Assembler script
ASM_TOOL = scripts\python_assembler\rv64im_assembler.py

all_python:
	$(PYTHON) $(ASM_TOOL) $(ASM)

dis:
	$(PYTHON) $(ASM_TOOL) $(ASM) --dis

clean_python:
	rm -f $(IMEM) $(DMEM) $(SYMS)


CCOMPILER = python3 c_compiler.py

INPUT_C = scripts\test_env\program.c
OUTPUT_ASM = scripts\test_env\program.asm

compile_all:
	$(CCOMPILER) $(INPUT_C) -o $(OUTPUT_ASM)

# Makefile for Verilator simulation

# Top testbench module
TOP_MODULE = fetch_top_tb

# RTL files
RTL_FILES = RV64_core\RTL\instruction_fetch\fetch_top.sv\
			RV64_core\RTL\instruction_fetch\instruction_fetch_unit.sv\
			RV64_core\RTL\memory\instruction_memory.sv

# Testbench file
TB_FILE = RV64_core\testbench\fetch_top_tb.sv

all_fetch:
	verilator --binary \
	--trace \
	--top-module $(TOP_MODULE) \
	$(RTL_FILES) \
	$(TB_FILE)

run: all_fetch
	./obj_dir/V$(TOP_MODULE)

clean_fetch:
	rm -rf obj_dir *.vcd

.PHONY: all_fetch run clean_fetch

TOP_MODULE_memory = load_store_tb

PKG_FILES_MEMORY = RV64_core\RTL\instruction_decode_unit\decode_pkg.svh

RTL_FILES_MEMORY = RV64_core\RTL\memory_read_write_unit\memory_top.sv \
                   RV64_core\RTL\memory\data_memory.sv \
                   RV64_core\RTL\memory_read_write_unit\memory_connection.sv

TB_FILE_MEMORY = RV64_core\testbench\load_store_tb.sv

all_memory:
	verilator --binary \
	--trace \
	--top-module $(TOP_MODULE_memory) \
	$(PKG_FILES_MEMORY) \
	$(RTL_FILES_MEMORY) \
	$(TB_FILE_MEMORY)

run_memory: all_memory
	./obj_dir/V$(TOP_MODULE_memory)

clean_memory:
	rm -rf obj_dir *.vcd



TOP_MODULE_EXECUTION_UNIT = tb_for_m_extention

PKG_FILES_EXECUTION = RV64_core\RTL\instruction_decode_unit\decode_pkg.svh\
                      RV64_core\RTL\pkg\alu_pkg.svh

RTL_FILES_EXECUTION = RV64_core\RTL\Execution_unit\alu_module.SV\
                     RV64_core\RTL\Execution_unit\execution_top.sv

TB_FILE_EXECUTION = RV64_core\testbench\tb_for_m_extention.sv
ALL_EXECUTION:
	verilator --binary \
	--trace \
	--threads 8 \
	--top-module $(TOP_MODULE_EXECUTION_UNIT) \
	$(PKG_FILES_EXECUTION) \
	$(RTL_FILES_EXECUTION) \
	$(TB_FILE_EXECUTION)

RUN_EXECUTION: ALL_EXECUTION
	./obj_dir/V$(TOP_MODULE_EXECUTION_UNIT)

CLEAN_EXECUTION:
	rm -rf obj_dir *.vcd

TOP_MODULE_EXECUTION_UNIT = branch_logic_tb

PKG_FILES_EXECUTION = RV64_core\RTL\instruction_decode_unit\decode_pkg.svh\
                      RV64_core\RTL\pkg\alu_pkg.svh

RTL_FILES_EXECUTION = RV64_core\RTL\branch_prediction_logic\branch_target_buffer.sv\
                      RV64_core\RTL\branch_prediction_logic\branch_logic_top.sv
TB_FILE_EXECUTION = RV64_core\testbench\branch_logic_tb.sv
ALL_BRANCH:
	verilator --binary \
	--trace \
	--threads 8 \
	--top-module $(TOP_MODULE_EXECUTION_UNIT) \
	$(PKG_FILES_EXECUTION) \
	$(RTL_FILES_EXECUTION) \
	$(TB_FILE_EXECUTION)

RUN_BRANCH: ALL_BRANCH
	./obj_dir/V$(TOP_MODULE_EXECUTION_UNIT)

CLEAN_BRANCH:
	rm -rf obj_dir *.vcd


TOP_MODULE_PC_GENERATION = pc_generation_tb

PKG_FILES_PC_GENERATION = RV64_core\RTL\instruction_decode_unit\decode_pkg.svh\
                      RV64_core\RTL\pkg\alu_pkg.svh

RTL_FILES_PC_GENERATION = RV64_core\RTL\branch_prediction_logic\branch_target_buffer.sv\
                      RV64_core\RTL\branch_prediction_logic\branch_logic_top.sv \
                      RV64_core\RTL\pc_generation\pc_generation.sv
TB_FILE_PC_GENERATION = RV64_core\testbench\pc_generation_tb.sv
ALL_pc_generation:
	verilator --binary \
	--trace \
	--threads 8 \
	--top-module $(TOP_MODULE_PC_GENERATION) \
	$(PKG_FILES_PC_GENERATION) \
	$(RTL_FILES_PC_GENERATION) \
	$(TB_FILE_PC_GENERATION)

RUN_PC: ALL_pc_generation
	./obj_dir/V$(TOP_MODULE_PC_GENERATION)

CLEAN_PC:
	rm -rf obj_dir *.vcd



TOP_MODULE_CONNECTION = connection_E_F_D

PKG_FILES_CONNECTION = RV64_core\RTL\instruction_decode_unit\decode_pkg.svh\
                      RV64_core\RTL\pkg\alu_pkg.svh

RTL_FILES_CONNECTION = RV64_core\RTL\branch_prediction_logic\branch_target_buffer.sv\
					  RV64_core\RTL\branch_prediction_logic\branch_logic_top.sv \
					  RV64_core\RTL\pc_generation\pc_generation.sv \
					  RV64_core\RTL\instruction_fetch\fetch_top.sv \
					  RV64_core\RTL\instruction_fetch\instruction_fetch_unit.sv \
					  RV64_core\RTL\memory_read_write_unit\memory_top.sv \
					  RV64_core\RTL\memory\data_memory.sv \
					  RV64_core\RTL\memory_read_write_unit\memory_connection.sv
TB_FILE_CONNECTION = RV64_core\testbench\connection_E_F_D.sv
ALL_CONNECTION:
	verilator --binary \
	--trace \
	--threads 8 \
	--top-module $(TOP_MODULE_CONNECTION) \
	$(PKG_FILES_CONNECTION) \
	$(RTL_FILES_CONNECTION) \
	$(TB_FILE_CONNECTION)

RUN_CONNECTION: ALL_CONNECTION
	./obj_dir/V$(TOP_MODULE_CONNECTION)

CLEAN_CONNECTION:
	rm -rf obj_dir *.vcd




# Top-level module
TOP_MODULE = top_tb

# Package files
PKG_FILES_TOP = \
RV64_core/RTL/instruction_decode_unit/decode_pkg.svh \
RV64_core/RTL/pkg/alu_pkg.svh

# RTL files
RTL_FILES_TOP = \
$(wildcard RV64_core/RTL/*.sv) \
$(wildcard RV64_core/RTL/memory/*.sv)\
$(wildcard RV64_core/RTL/instruction_decode_unit/*.sv) \
$(wildcard RV64_core/RTL/branch_prediction_logic/*.sv) \
$(wildcard RV64_core/RTL/pc_generation/*.sv) \
$(wildcard RV64_core/RTL/instruction_fetch/*.sv) \
$(wildcard RV64_core/RTL/memory_read_write_unit/*.sv) \
$(wildcard RV64_core/RTL/execution_unit/*.sv) \
$(wildcard RV64_core/RTL/writeback_unit/*.sv)

# Testbench
TB_FILE_TOP = RV64_core/testbench/top_tb.sv

# Build
ALL_CONNECTION_TOP:
	verilator --binary \
	--trace \
	--threads 8 \
	--top-module $(TOP_MODULE) \
	$(PKG_FILES_TOP) \
	$(RTL_FILES_TOP) \
	$(TB_FILE_TOP)

# Run
run_top: ALL_CONNECTION_TOP
	./obj_dir/V$(TOP_MODULE)


clean_top:
	rm -rf obj_dir *.vcd

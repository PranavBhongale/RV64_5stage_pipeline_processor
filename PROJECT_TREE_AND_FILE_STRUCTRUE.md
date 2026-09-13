## Project Structure


## 5STAGERV64_PROCESSOR /
```
  |------ DOC /
  |         |----architecture_drawings /
  |         |                        |----black_box_.drawio   //  this file content BLACK box diagram of the cpu core
  |         |                        |----CPU_BLOCK_DIAGRAM.drawio // a detailed pipelined diagram of PROCESSOR
  |         |                        |----CPU_DATA_FLOW.drawio // the simple data flow diagram
  |         |                        |----project_verification_flow.drawio //  how to verifi the project by comparing the
  |         |                                                                // memory
  |         |
  |         |                        |
  |         |                        |    the same .drawio files are converted into .png file for better visiblity
  |         |                        |    
  |         |
  |         |----backup/
  |         |         |---pdf.py  // this is just the python assembler file  which is not used 
  |         |         |---
  |         |         |---
  |         |
  |         |
  |         |
  |         |-------------------synopsis report pdf  
  |         |
  |         |--------------------|
  |                              |----instruction_support /
  |                              | 
  |                              |----skipped_instruction /
  |                              |                      |--- RV64_Skipped_Extensions_A_FD_C.pdf // all the instruction
  |                              |                      |                 are not implimented it is difficult to maintain
  |                              |                      |                 the project for single person
  |                              |----used_instruction /
  |                              |                  |---- RV64_instruction_decoding.pdf // this contain all the
  |                              |                  |        instruction which are implimented 
  |                              |                  |---- RV64M_instruction_decoding.pdf // i am also adding the M instruction support
  |                              |                  |        in the project this is also a advancement over previous project
  |                              |
  |                              |---- RISC-V  ISA  quick reference pdf from CS 3210 fall 2025 
  |
  |
  |
  |
  |
  |----memory /
  |       |---golden_data_memory.hex // memory for golden model
  |       |---golden_instruction_memory.hex // instruction memory for golden model
  |       |---rtl_data_memory_result.hex // data memory for RTL for verification
  |       |---rtl_instruction_memory.hex 
  |
  |
  |----myenv / 
  |      | this is just python virtual  environment 
  |      |  to decrease the colusion of python libraries
  |      | 
  |
  |----RV64_core /
  |         |
  |         |---- RTL /
  |         |       |---branch_prediction_logic /
  |         |       |                     |--- branch_logic_top.sv
  |         |       |                     |---branch_target_buffer.sv
  |         |       |---Execution_unit /
  |         |       |             |--- alu_module.sv                 
  |         |       |             |--- execution_pipeline.sv
  |         |       |             |--- execution_top.sv
  |         |       |
  |         |       |---instruction_decode_unit /
  |         |       |             |---decode_pkg.svh
  |         |       |             |---decoding_pipeline.sv
  |         |       |             |---instruction_decode_top.sv
  |         |       |             |---instruction_decode.sv
  |         |       |
  |         |       |---instruction_fetch /
  |         |       |             |--- fetch_top.sv
  |         |       |             |--- instruction_fetch_unit.sv
  |         |       |
  |         |       |---memory /
  |         |       |        |---data_memory.sv
  |         |       |        |---instruction_memory.sv
  |         |       |
  |         |       |---memory_read_write_unit /
  |         |       |              |---memory_connection.sv
  |         |       |              |---memory_top.sv
  |         |       |
  |         |       |---pc_generation / 
  |         |       |            |--- pc_generation.sv
  |         |       |            |
  |         |       |---pkg /
  |         |       |    |---alu_pkg.svh
  |         |       |---writeback_unit /
  |         |       |           |--- writeback_unit.sv
  |         |       |           |
  |         |       | 
  |         |       |--- connection_E_F_D.sv   //  this is the half connection of execute and fetch and decode 
  |         |       |                          // to verify the branch prediction logic is working or not
  |         |       |--- connection_M_W.sv     // to verify the forwarding logic working or not I use hirarchical verification 
  |         |       |---TOP_MODULE.sv   this is the top module which just connect the connection_E_F_D.sv
  |                                     and connection_MW.sv
  |         |---testbench /
  |         |       |
  |         |       |---branch_logic_tb.sv
  |         |       |---connection_E_F_D.sv
  |         |       |---execution_unit_tb.sv
  |         |       |---fetch_top_tb.sv
  |         |       |---load_store_tb.sv
  |         |       |---pc_generation_tb.sv
  |         |       |---tb_for_m_extention.sv
  |         |       |--- top_tb.sv 
  |         |       |
  |
  |----scripts/
  |         |---cpp_golden_model /
  |         |               |--- ALU_MODEL.CPP
  |         |               |--- alu_op.h
  |         |               |--- branch_target_buffer.cpp
  |         |               |---data_and_instruction_memory.cpp
  |         |               |---instruction_fetch_unit.cpp
  |         |               |---register_file.cpp
  |         |               |---RV64_decode_unit.cpp
  |         |               |---TOP_MODULE.CPP
  |         |
  |         |---python_assembler/
  |         |               |---rv64im_assembler.py //  this is the vailable version of assembler
  |         |                                        // specially this is design  by CLAUID  not by me
  |         |
  |         |---python compiler /
  |         |               |---ast_nodes.py
  |         |               |---c_compiler.py
  |         |               |---codegen.py
  |         |               |---lexer.py
  |         |               |---parser.py
  |         |               |---README.md
  |         |               |--- test_compiler.py // tll compiler is designed by clauid.AI  I am just implimenting this  
  |         |               |                           for testing purpose the discreaption is in the MD file of Compiler
  |         |
  |
  |----test_env /
  |       |--- program.asm
  |       |---program.c
  |
  |----waveforms /
  |         |  *
  |         |  this folder contain all waveforms .vcd file and .gtkw  file for waveform debuging
  |
  |----.library_mapping.xml   // I  am using sigasi studio for system verilog this is sigasi project 
  | 
  |---- makefile // this is the important file which is configure for MSYS terminal all make commant to run verilator are there
```

// all other are .exe file 
above this is complete project structure

# 5-Stage RV64 Processor

## Overview

Welcome to the **5-Stage RV64 Processor** project.

This repository contains the complete design and implementation of a **64-bit RISC-V (RV64I) 5-stage pipelined processor**, developed to explore modern processor microarchitecture, RTL design, verification, and computer architecture concepts.

The project is organized into modular components to make the architecture easier to understand, maintain, verify, and extend. In addition to the RTL implementation, this repository also contains supporting software, test environments, assembly programs, verification infrastructure, and design documentation.

This project is intended for students, researchers, and hardware engineers who want to study or contribute to the implementation of a pipelined RISC-V processor.

---

##  Before You Start

This **README** provides only a high-level overview of the project.

For a complete understanding of the processor architecture, implementation details, design decisions, verification methodology, and module descriptions, please refer to the documentation available in the **`DOC/`** directory.

> **Important:** It is highly recommended to read the documentation inside the **`DOC/`** folder before exploring the RTL source code.

---

##  Project Structure

The complete directory organization and file descriptions are documented in:

- **`PROJECT_TREE_AND_FILE_STRUCTURE.md`**

This document explains:
- Complete project directory structure
- Purpose of every folder
- Description of important source files
- RTL organization
- Verification environment
- Utility scripts
- Documentation hierarchy

Reading the project tree first will make it much easier to navigate the repository.

---

## Repository Contents

This repository includes:

- RTL implementation of the RV64 processor
- Five-stage pipeline architecture
- Instruction fetch, decode, execute, memory, and write-back stages
- Register file
- ALU and control logic
- Memory subsystem
- Test environment
- Assembly test programs
- Python utilities
- C++ golden model
- Waveform generation
- Complete project documentation

---

## Documentation Roadmap

For the best experience, it is recommended to explore the repository in the following order:

1. Read this **README.md**
2. Read **PROJECT_TREE_AND_FILE_STRUCTURE.md**
3. Explore the **DOC/** directory
4. Study the processor architecture
5. Review the RTL implementation
6. Run the simulation environment

Following this order will help you understand both the architecture and the codebase efficiently.

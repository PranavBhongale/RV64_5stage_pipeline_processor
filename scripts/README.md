## Test Environment and Automation

This folder contains the complete **test environment** for the project, including scripts for the assembler, compiler, and golden model.

These components are mainly part of the **automation and verification infrastructure** of the project. My primary focus throughout the project has been the **RTL and SystemVerilog implementation and the microarchitecture**.

The automation scripts and supporting infrastructure were developed with the help of **AI tools (Claude)**. I did not spend significant effort optimizing or architecting these components. I treated this part of the project more like getting the required support infrastructure from another team so that I could focus on the core RTL and microarchitecture.

This separation is intentional: the main engineering focus of the project is the processor's **RTL, SystemVerilog design, and microarchitecture**, while the scripts provide the supporting automation required for testing and verification.

### Running the Test Environment

The available scripts can be executed through the project's **Makefile**. The Makefile provides the required commands to build and run the different parts of the test environment.

For details on how to run individual scripts and test cases, please refer to the available targets and commands in the **Make**


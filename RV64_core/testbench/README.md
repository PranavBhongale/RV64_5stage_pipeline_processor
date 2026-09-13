## Testbenches and Verification Methodology

This folder contains a large number of **SystemVerilog testbench files** that I used to verify different parts of the RTL.

I believe **hierarchical verification** is the most effective approach for this type of project. Bugs should first be identified and fixed at the lower level before moving to higher-level verification. This helps isolate problems and prevents dependent bugs at higher levels from making debugging more difficult.

### Testbench Configuration

If you want to run some of the individual test cases, you may need to **reconfigure the corresponding testbench code**. During the debugging process, some testbenches were modified to investigate and fix issues discovered at higher levels of the design.

It is difficult to create exhaustive corner-case coverage for every individual testbench. Therefore, the testbenches provided here are primarily designed to cover **general and representative cases**.

Because of this, some individual testbenches may require additional configuration before they can be executed successfully. If the required configuration is not performed, the testbench may report errors even though the RTL itself is working correctly.

### Top-Level Testbench

The main testbench is **`top_tb`**. It integrates the complete processor and executes instructions through the entire pipeline.

This is the primary and fully functional testbench for the project. It can be run directly to verify the complete processor without requiring additional configuration.

The **Synopsis Report** contains a detailed explanation of the testing and verification methodology used throughout the project. Please refer to that section for more information about the verification strategy, test cases, debugging methodology, and overall verification flow.

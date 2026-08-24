
#include <iostream>
#include <cstdint>
using namespace std;
class instruction_fetch
{
public:
    // ──── INPUTS ────
    uint64_t pc        = 0;      // Program counter input
    bool     pc_valid  = false;  // PC valid signal (from upstream / branch unit)

    // ──── IMEM INTERFACE (request) ────
    uint64_t imem_addr  = 0;     // Address sent to instruction memory
    bool     imem_req   = false; // Request signal to instruction memory

    // ──── IMEM INTERFACE (response) ────
    uint32_t imem_data  = 0;     // Instruction data returned by memory
    bool     imem_ready = false; // Memory response ready signal (driven by memory)
    bool flush_i = false;
    // ──── OUTPUTS (to decode stage) ────
    uint64_t out_pc          = 0;          // PC forwarded to decode
    uint32_t out_instruction = 0;          // Fetched instruction forwarded to decode
    bool     out_valid       = false;      // Output valid to decode
    bool     out_ready       = false;      // Decode stage ready (backpressure input)

private:
    // Internal state machine
    enum class State { IDLE, WAIT_MEM, SEND_DECODE };
    State    state         = State::IDLE;
    uint64_t latched_pc    = 0;   // PC latched when request was sent
    uint32_t latched_instr = 0;   // Instruction latched when memory responds

public:
    void tick() {
        // Default de-assert request every cycle (re-asserted if needed)
        imem_req  = false;
        out_valid = false;

        switch (state) {

            // ── IDLE: waiting for a valid PC from upstream ──────────────────
            case State::IDLE:
                if (pc_valid) {
                    // Latch PC and issue request to instruction memory
                  //  cout << "  [IF] PC=0x" << hex << pc << dec << " valid = requesting instruction\n";
                    latched_pc = pc;
                    imem_addr  = pc;
                    imem_req   = true;
                    state      = State::WAIT_MEM;
                }
                break;

            // ── WAIT_MEM: request issued, waiting for memory response ───────
            case State::WAIT_MEM:
                // Hold the request address steady while waiting
                imem_addr = latched_pc;
                imem_req  = true;
              // cout << "  [IF] Waiting for memory response...\n";
                if (imem_ready) {               // Memory responded with data
                    imem_req      = false;       // De-assert request
                    latched_instr = imem_data;   // Latch instruction before req drops
                    state         = State::SEND_DECODE;
                }
                break;

            // ── SEND_DECODE: drive outputs until decode accepts ─────────────
            case State::SEND_DECODE:
                out_pc          = latched_pc;
                out_instruction = latched_instr; // Use internally latched data
                out_valid       = true;          // Signal decode: data is valid
            //  cout  << "  [IF] Instruction 0x" << hex << latched_instr << dec << " ready for decode\n";
                if (out_ready) {                 // Decode accepted the instruction
                    state = State::IDLE;         // Ready to fetch next instruction
                }
                break;
        }
if (flush_i)
{
    state =  State::  IDLE;
    out_valid = false;
    imem_req = false;
    flush_i = false;
}
        
    }
};


    /*            ┌───────────────────────────────┐
  pc       ──────►│                               ├──────► imem_addr   (to memory)
  pc_valid ──────►│     instruction_fetch         ├──────► imem_req    (to memory)
                  │                               │
  imem_data ─────►│        (black box)            ├──────► out_pc
  imem_ready ────►│                               ├──────► out_instruction
                  │                               ├──────► out_valid   (to decode)
  out_ready ─────►│                               │
                  └───────────────────────────────┘

*/

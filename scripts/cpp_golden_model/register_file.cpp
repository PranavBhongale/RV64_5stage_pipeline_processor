#include<iostream> 
#include <cstdint>
#include <cstdio>
#include <cassert>

// ============================================================
//  RV64 Register File
//  ─────────────────────────────────────────────────────────
//  Black-box model of the physical register file used in a
//  5-stage RV64 pipeline.
//
//  Architecture
//  ┌─────────────────────────────────────────────┐
//  │              REGISTER FILE                  │
//  │   32 × 64-bit registers  (x0 … x31)         │
//  │   x0 is hardwired to 0 (writes ignored)     │
//  │                                             │
//  │  PORT A (read)   PORT B (read)              │
//  │  addr_a[4:0]     addr_b[4:0]                │
//  │  valid_a ──►     valid_b ──►                │
//  │  ◄── ready_a     ◄── ready_b                │
//  │  ◄── data_a      ◄── data_b                 │
//  │                                             │
//  │  PORT W (write)                             │
//  │  addr_w[4:0]                                │
//  │  data_w[63:0]                               │
//  │  wen   ──►                                  │
//  │  valid_w ──►                                │
//  │  ◄── ready_w                                │
//  └─────────────────────────────────────────────┘
//
//  Handshake protocol  (same as AXI-style)
//  ─────────────────────────────────────────────
//  A transaction completes when BOTH valid AND ready are high
//  in the same cycle.
//
//  Read ports  : combinational / single-cycle latency.
//                ready_a / ready_b go high immediately when
//                the file is not stalled.
//
//  Write port  : registered — data appears on the next tick().
//                ready_w goes high when the write port is free.
//
//  Register naming  (RV64 ISA §2.1)
//  ─────────────────────────────────────────────
//  x0  = zero   x1  = ra    x2  = sp    x3  = gp
//  x4  = tp     x5  = t0    x6  = t1    x7  = t2
//  x8  = s0/fp  x9  = s1    x10 = a0    x11 = a1
//  x12 = a2     x13 = a3    x14 = a4    x15 = a5
//  x16 = a6     x17 = a7    x18 = s2    x19 = s3
//  x20 = s4     x21 = s5    x22 = s6    x23 = s7
//  x24 = s8     x25 = s9    x26 = s10   x27 = s11
//  x28 = t3     x29 = t4    x30 = t5    x31 = t6
// ============================================================

class regfile {

// ──────────────────────────────────────────────────────────────
//  PUBLIC INTERFACE  (ports visible to the pipeline)
// ──────────────────────────────────────────────────────────────
public:

    // ── Read Port A ──────────────────────────────────────────
    struct ReadPort {
        uint8_t  addr  = 0;      // register address  [4:0]
        bool     valid = false;  // master drives: "I want to read"
        // ── driven back by regfile ──
        uint64_t data  = 0;      // read data out
        bool     ready = false;  // regfile: "data is valid"
    };

    // ── Write Port W ─────────────────────────────────────────
    struct WritePort {
        uint8_t  addr  = 0;      // destination register [4:0]
        uint64_t data  = 0;      // write data
        bool     wen   = false;  // write enable
        bool     valid = false;  // master: "I have valid write data"
        // ── driven back by regfile ──
        bool     ready = false;  // regfile: "I can accept this write"
    };

    // Exposed ports — pipeline stages drive these directly
    ReadPort  port_a;   // ID stage, source rs1
    ReadPort  port_b;   // ID stage, source rs2
    WritePort port_w;   // WB stage, destination rd

    // ── Constructor ──────────────────────────────────────────
    regfile() {
        reset();
    }

    // ── reset ────────────────────────────────────────────────
    // Clears all registers to 0, resets all port signals.
    void reset() {
        for (int i = 0; i < NUM_REGS; ++i)
            regs_[i] = 0;

        port_a = ReadPort{};
        port_b = ReadPort{};
        port_w = WritePort{};

        stalled_  = false;
        pending_w_valid_  = false;
        pending_w_addr_   = 0;
        pending_w_data_   = 0;
    }

    // ─────────────────────────────────────────────────────────
    //  tick()
    //  ─────
    //  Call once per clock cycle AFTER the pipeline has set up
    //  all port signals for this cycle.
    //
    //  Sequence inside one cycle:
    //    1. Evaluate read ports  → combinational, instant.
    //    2. Commit pending write from previous tick (registered).
    //    3. Latch new write request if handshake completes.
    //    4. Update ready signals for next cycle.
    // ─────────────────────────────────────────────────────────
    void tick() {

        // ── Step 1 : commit the write that was latched last tick ──
        if (pending_w_valid_) {
            if (pending_w_addr_ != 0)            // x0 is hardwired 0
                regs_[pending_w_addr_] = pending_w_data_;
            pending_w_valid_ = false;
        }

        // ── Step 2 : evaluate read port A (combinational) ────
        port_a.ready = false;
        port_a.data  = 0;
        if (port_a.valid && !stalled_) {
            assert((port_a.addr & 0xE0) == 0 && "addr_a out of range [4:0]");
            port_a.data  = regs_[port_a.addr];   // x0 always returns 0
            port_a.ready = true;
        }

        // ── Step 3 : evaluate read port B (combinational) ────
        port_b.ready = false;
        port_b.data  = 0;
        if (port_b.valid && !stalled_) {
            assert((port_b.addr & 0xE0) == 0 && "addr_b out of range [4:0]");
            port_b.data  = regs_[port_b.addr];
            port_b.ready = true;
        }

        // ── Step 4 : write port handshake ────────────────────
        //  Handshake fires when valid AND ready are both high.
        //  ready_w is high unless we already have a pending write
        //  buffered (shouldn't happen in a correctly stalled pipe,
        //  but guard it anyway).
        port_w.ready = !pending_w_valid_;

        if (port_w.valid && port_w.ready && port_w.wen) {
            // Latch — will be committed at the START of next tick
            assert((port_w.addr & 0xE0) == 0 && "addr_w out of range [4:0]");
            pending_w_valid_ = true;
            pending_w_addr_  = port_w.addr;
            pending_w_data_  = port_w.data;
        }
    }

    // ─────────────────────────────────────────────────────────
    //  stall() / unstall()
    //  ──────────────────
    //  Called by the hazard detection unit.
    //  While stalled: read ready signals go low (no new reads
    //  complete), write port stays open so WB can still retire.
    // ─────────────────────────────────────────────────────────
    void stall()   { stalled_ = true;  }
    void unstall() { stalled_ = false; }
    bool is_stalled() const { return stalled_; }

    // ─────────────────────────────────────────────────────────
    //  read_combinational()
    //  ────────────────────
    //  Direct bypass read — used by the forwarding unit or
    //  debug probes.  Does NOT use the handshake ports.
    //  Always returns the current (post-last-tick) value.
    // ─────────────────────────────────────────────────────────
    uint64_t read_combinational(uint8_t addr) const {
        assert((addr & 0xE0) == 0 && "addr out of range [4:0]");
        return regs_[addr];   // regs_[0] is always 0
    }

    // ─────────────────────────────────────────────────────────
    //  dump()
    //  ──────
    //  Debug utility — prints all 32 registers in the standard
    //  RV ABI format to stdout.
    // ─────────────────────────────────────────────────────────
    void dump() const {
        static const char* abi[] = {
            "zero","ra","sp","gp","tp","t0","t1","t2",
            "s0","s1","a0","a1","a2","a3","a4","a5",
            "a6","a7","s2","s3","s4","s5","s6","s7",
            "s8","s9","s10","s11","t3","t4","t5","t6"
        };
        printf("\n===== Register File Dump ========================\n");
        for (int i = 0; i < NUM_REGS; i += 2) {
            printf("||  x%-2d %-4s = 0x%016llX   "
                   "x%-2d %-4s = 0x%016llX  ||\n",
                   i,   abi[i],   (unsigned long long)regs_[i],
                   i+1, abi[i+1], (unsigned long long)regs_[i+1]);
        }
        printf("=====================================================\n");
    }

// ──────────────────────────────────────────────────────────────
//  PRIVATE STATE  (invisible outside the black box)
// ──────────────────────────────────────────────────────────────
private:

    static constexpr int NUM_REGS = 32;

    // The actual 32×64-bit register array.
    // regs_[0] is always read as 0; writes to it are discarded.
    uint64_t regs_[NUM_REGS];

    // Stall flag — set by hazard unit
    bool stalled_;

    // Single-entry write buffer (registered write port)
    bool     pending_w_valid_;
    uint8_t  pending_w_addr_;
    uint64_t pending_w_data_;

    // ── x0 invariant guard ───────────────────────────────────
    // Called after every write commit to enforce x0==0.
    // (Belt-and-suspenders — the addr!=0 check above is enough,
    //  but this makes the invariant explicit for simulation.)
    void enforce_x0() {
        regs_[0] = 0;
    }
};


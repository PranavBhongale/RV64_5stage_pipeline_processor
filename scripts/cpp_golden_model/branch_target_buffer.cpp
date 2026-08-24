#include <cstdint>
#include <cstdio>

// ============================================================
//  Branch Target Buffer (BTB)
//  ─────────────────────────────────────────────────────────
//  Direct-mapped, 64 entries.
//
//  Entry layout:
//  ┌────────┬──────────────────┬──────────────────┬────────┐
//  │ valid  │   tag [63:8]     │  target [63:0]   │ state  │
//  │  1 bit │  56 bits         │  64 bits — FULL  │  2 bit │
//  └────────┴──────────────────┴──────────────────┴────────┘
//
//  Tag [63:8]   — pc[1:0] always 00 (4-byte aligned, no C ext)
//                 pc[7:2] is the index — implicit, not stored
//                 pc[63:8] is enough to uniquely identify the
//                 branch PC within its slot.
//
//  Target [63:0] — FULL 64-bit. The target can be anywhere
//                  in the address space. No compression allowed.
//
//  Index = pc[7:2]  (6 bits → 64 slots)
//
//  2-bit saturating counter
//  ─────────────────────────────────────────────────────────
//   11 → Strongly Taken     (ST)
//   10 → Weakly   Taken     (WT)
//   01 → Weakly   Not-Taken (WN)
//   00 → Strongly Not-Taken (SN)
//
//  Port diagram
//  ┌─────────────────────────────────────────────────────┐
//  │                     BTB                             │
//  │  LOOKUP PORT (IF stage)                             │
//  │   pc_i        [63:0] ──►                            │
//  │   lookup_valid_i      ──►                           │
//  │   ◄── lookup_ready_o                                │
//  │   ◄── hit_o                                         │
//  │   ◄── target_o [63:0]   full 64-bit target          │
//  │   ◄── state_o   [1:0]   2-bit counter value         │
//  │                                                     │
//  │  UPDATE PORT (EX stage — after branch resolves)     │
//  │   update_pc_i     [63:0] ──►                        │
//  │   update_target_i [63:0] ──►  full 64-bit           │
//  │   update_taken_i         ──►                        │
//  │   update_valid_i         ──►                        │
//  │   ◄── update_ready_o                                │
//  └─────────────────────────────────────────────────────┘
// ============================================================

class BTB {

public:

    // ── 2-bit saturating counter
    enum State : uint8_t {
        STRONGLY_NOT_TAKEN = 0b00,
        WEAKLY_NOT_TAKEN   = 0b01,
        WEAKLY_TAKEN       = 0b10,
        STRONGLY_TAKEN     = 0b11,
    };

    // ── Lookup Port (IF stage)
    uint64_t pc_i           = 0;
    bool     lookup_valid_i = false;

    bool     lookup_ready_o = false;
    bool     hit_o          = false;
    uint64_t target_o       = 0;       // full 64-bit target
    State    state_o        = STRONGLY_NOT_TAKEN;

    // ── Update Port (EX stage)
    uint64_t update_pc_i     = 0;
    uint64_t update_target_i = 0;      // full 64-bit target
    bool     update_taken_i  = false;
    bool     update_valid_i  = false;

    bool     update_ready_o  = false;

    // ── Constructor
    BTB() { reset(); }

    void reset() {
        for (int i = 0; i < NUM_ENTRIES; i++) {
            entries_[i].valid  = false;
            entries_[i].tag    = 0;
            entries_[i].target = 0;
            entries_[i].state  = WEAKLY_TAKEN;
        }
        pc_i            = 0;  lookup_valid_i  = false;
        lookup_ready_o  = false; hit_o         = false;
        target_o        = 0;  state_o         = STRONGLY_NOT_TAKEN;
        update_pc_i     = 0;  update_target_i = 0;
        update_taken_i  = false; update_valid_i = false;
        update_ready_o  = false;
    }

    //  tick()
    //  Lookup  → combinational (result same cycle).
    //  Update  → registered   (visible next cycle).
    //  Both ports work independently every cycle.
    void tick() {

        // ── Lookup (combinational)
        lookup_ready_o = true;
        hit_o          = false;
        target_o       = 0;
        state_o        = STRONGLY_NOT_TAKEN;

        if (lookup_valid_i) {
            uint8_t  idx = index_of(pc_i);
            uint64_t tag = tag_of(pc_i);
            Entry&   e   = entries_[idx];

            if (e.valid && e.tag == tag) {
                hit_o    = true;
                target_o = e.target;   // full 64-bit — no reconstruction
                state_o  = e.state;
            }
        }

        // ── Update (registered)
        update_ready_o = true;

        if (update_valid_i) {
            uint8_t  idx = index_of(update_pc_i);
            uint64_t tag = tag_of(update_pc_i);
            Entry&   e   = entries_[idx];

            e.valid  = true;
            e.tag    = tag;                  // store pc[63:8]
            e.target = update_target_i;      // store full 64-bit target
            e.state  = next_state(e.valid ? e.state : WEAKLY_TAKEN,
                                  update_taken_i);
        }
    }

    // ── dump 
    void dump() const {
        static const char* sn[] = {"SN","WN","WT","ST"};
        printf("\n||======= BTB Dump (%d entries) =====================================\n",
               NUM_ENTRIES);
        printf("||  %-4s  %-16s  %-18s  %-5s  V  ||\n",
               "slot","tag [63:8]","target [63:0]","state");
        printf("||  ====================================================================== ||\n");
        int shown = 0;
        for (int i = 0; i < NUM_ENTRIES; i++) {
            const Entry& e = entries_[i];
            if (!e.valid) continue;
            printf("||  %-4d  0x%014llX  0x%016llX  %-5s  1  ||\n",
                   i, e.tag, e.target, sn[e.state]);
            shown++;
        }
        if (!shown)
            printf("||  (all entries invalid)                                            ||\n");
        printf("===========================================================================\n");
    }

private:

    static constexpr int NUM_ENTRIES = 64;
    static constexpr int INDEX_SHIFT = 2;              // skip pc[1:0]
    static constexpr int INDEX_BITS  = 6;              // log2(64)
    static constexpr int INDEX_MASK  = NUM_ENTRIES-1;  // 0x3F

    struct Entry {
        bool     valid  = false;
        uint64_t tag    = 0;       // pc[63:8]  — 56 bits
        uint64_t target = 0;       // full 64-bit target PC — no truncation
        State    state  = WEAKLY_TAKEN;
    };

    Entry entries_[NUM_ENTRIES];

    // pc[7:2] → slot index
    static uint8_t index_of(uint64_t pc) {
        return static_cast<uint8_t>((pc >> INDEX_SHIFT) & INDEX_MASK);
    }

    // pc[63:8] → tag
    static uint64_t tag_of(uint64_t pc) {
        return pc >> (INDEX_SHIFT + INDEX_BITS);   // >> 8
    }

    // 2-bit saturating counter
    static State next_state(State s, bool taken) {
        if (taken)
            return (s == STRONGLY_TAKEN)     ? STRONGLY_TAKEN
                                             : static_cast<State>(s + 1);
        else
            return (s == STRONGLY_NOT_TAKEN) ? STRONGLY_NOT_TAKEN
                                             : static_cast<State>(s - 1);
    }
};
// ============================================================
//  TOP_MODULE.CPP  —  RV64I+M  5-Stage Pipeline Simulator
//  ─────────────────────────────────────────────────────────
//  Stages : IF → ID → EX → MEM → WB
//
//  Modules instantiated:
//    instruction_fetch          (IF)
//    instruction_decode_unit    (ID)
//    regfile                    (ID/WB)
//    ALU                        (EX)
//    BTB                        (IF/EX)
//    DataAndInstructionMemory   (IF + MEM)
//
//  Pipeline registers (latches between stages):
//    if_id   : IF  → ID
//    id_ex   : ID  → EX
//    ex_mem  : EX  → MEM
//    mem_wb  : MEM → WB
//
//  Control hazards  : flush on branch/jump mispredict
//  Data  hazards    : full stall (no forwarding yet)
// ============================================================

#include <iostream>
#include <cstdint>
#include <cstdio>
using namespace std;

#include "ALU_MODEL.CPP"
#include "branch_target_buffer.cpp"
#include "data_and_instruction_memory.cpp"
#include "RV64_decode_unit.cpp"
#include "instruction_fetch_unit.cpp"
#include "register_file.cpp"

// ============================================================
//  Pipeline register structs
// ============================================================

struct IF_ID_Reg {
    uint64_t pc          = 0;
    uint32_t instruction = 0;
    bool     valid       = false;
};

struct ID_EX_Reg {
    uint64_t         pc         = 0;
    DecodedInstruction decoded   = {};
    uint64_t         rs1_data   = 0;
    uint64_t         rs2_data   = 0;
    bool             valid      = false;
};

struct EX_MEM_Reg {
    uint64_t         pc         = 0;
    DecodedInstruction decoded   = {};
    uint64_t         alu_result = 0;
    uint64_t         rs2_data   = 0;   // for stores
    bool             alu_zero   = false;
    bool             branch_taken = false;
    uint64_t         branch_target = 0;
    bool             valid      = false;
};

struct MEM_WB_Reg {
    uint64_t         pc         = 0;
    DecodedInstruction decoded   = {};
    uint64_t         alu_result = 0;
    uint64_t         mem_data   = 0;
    bool             valid      = false;
};

// ============================================================
//  Helper: resolve branch decision from ALU flags
// ============================================================
static bool evaluate_branch(BranchOp op, bool zero, bool neg,
                             bool overflow, uint64_t a, uint64_t b)
{
    switch (op) {
        case BranchOp::BEQ:  return  zero;
        case BranchOp::BNE:  return !zero;
        // BLT : signed a < b  ↔  neg != overflow
        case BranchOp::BLT:  return (neg != overflow);
        // BGE : signed a >= b ↔  neg == overflow
        case BranchOp::BGE:  return (neg == overflow);
        case BranchOp::BLTU: return (a < b);
        case BranchOp::BGEU: return (a >= b);
        default:             return false;
    }
}

// ============================================================
//  Helper: map MemOp → DataType + read/write enables
// ============================================================
static void mem_op_to_signals(MemOp op,
                               bool& rd_en, bool& wr_en,
                               DataType& dtype,
                               bool& sign_extend)
{
    rd_en = false; wr_en = false;
    dtype = DataType::DWORD;
    sign_extend = false;

    switch (op) {
        case MemOp::LOAD_BYTE:    rd_en=true; dtype=DataType::BYTE;     sign_extend=true;  break;
        case MemOp::LOAD_HALF:    rd_en=true; dtype=DataType::HALFWORD;  sign_extend=true;  break;
        case MemOp::LOAD_WORD:    rd_en=true; dtype=DataType::WORD;      sign_extend=true;  break;
        case MemOp::LOAD_DOUBLE:  rd_en=true; dtype=DataType::DWORD;     sign_extend=false; break;
        case MemOp::LOAD_BYTE_U:  rd_en=true; dtype=DataType::BYTE;     sign_extend=false; break;
        case MemOp::LOAD_HALF_U:  rd_en=true; dtype=DataType::HALFWORD;  sign_extend=false; break;
        case MemOp::LOAD_WORD_U:  rd_en=true; dtype=DataType::WORD;      sign_extend=false; break;
        case MemOp::STORE_BYTE:   wr_en=true; dtype=DataType::BYTE;     break;
        case MemOp::STORE_HALF:   wr_en=true; dtype=DataType::HALFWORD;  break;
        case MemOp::STORE_WORD:   wr_en=true; dtype=DataType::WORD;      break;
        case MemOp::STORE_DOUBLE: wr_en=true; dtype=DataType::DWORD;     break;
        default: break;
    }
}

// ============================================================
//  Helper: sign-extend a loaded value given access width
// ============================================================
static uint64_t sign_extend_load(uint64_t raw, DataType dtype)
{
    switch (dtype) {
        case DataType::BYTE:
            return static_cast<uint64_t>(static_cast<int64_t>(
                       static_cast<int8_t>(raw & 0xFF)));
        case DataType::HALFWORD:
            return static_cast<uint64_t>(static_cast<int64_t>(
                       static_cast<int16_t>(raw & 0xFFFF)));
        case DataType::WORD:
            return static_cast<uint64_t>(static_cast<int64_t>(
                       static_cast<int32_t>(raw & 0xFFFFFFFF)));
        default:
            return raw;
    }
}

// ============================================================
//  Hazard detection unit
//  Returns true if the ID stage must stall this cycle.
//  Stall condition: an instruction in EX or MEM is writing
//  a register that the current ID instruction needs to read.
// ============================================================
static bool hazard_detect(const DecodedInstruction& id,
                           const ID_EX_Reg&  id_ex,
                           const EX_MEM_Reg& ex_mem,
                           const MEM_WB_Reg& mem_wb)
{
    // Check if EX stage writes rd and ID needs it
    if (id_ex.valid && id_ex.decoded.rd_used && id_ex.decoded.rd != 0) {
        if (id.rs1_used && id.rs1 == id_ex.decoded.rd) return true;
        if (id.rs2_used && id.rs2 == id_ex.decoded.rd) return true;
    }
    // Check if MEM stage writes rd and ID needs it
    if (ex_mem.valid && ex_mem.decoded.rd_used && ex_mem.decoded.rd != 0) {
        if (id.rs1_used && id.rs1 == ex_mem.decoded.rd) return true;
        if (id.rs2_used && id.rs2 == ex_mem.decoded.rd) return true;
    }
    // Check if WB stage writes rd and ID needs it (write is still pending this cycle)
    if (mem_wb.valid && mem_wb.decoded.rd_used && mem_wb.decoded.rd != 0) {
        if (id.rs1_used && id.rs1 == mem_wb.decoded.rd) return true;
        if (id.rs2_used && id.rs2 == mem_wb.decoded.rd) return true;
    }
    return false;
}

// ============================================================
//  main — simulation loop
// ============================================================
int main()
{
    // ── Instantiate modules ───────────────────────────────────
    ALU                      alu;
    BTB                      btb;
    DataAndInstructionMemory mem;
    instruction_decode_unit  dec;
    instruction_fetch        ifu;
    regfile                  rf;

    // ── Pipeline registers ────────────────────────────────────
    IF_ID_Reg  if_id,  if_id_next;
    ID_EX_Reg  id_ex,  id_ex_next;
    EX_MEM_Reg ex_mem, ex_mem_next;
    MEM_WB_Reg mem_wb, mem_wb_next;

    // ── PC state ──────────────────────────────────────────────
    uint64_t PC       = 0;        // current fetch PC
    bool     pc_valid = true;     // start fetching immediately

    // ── Stall state (previous cycle) for IFU backpressure ────
    bool     prev_stall = false;

    // ── Simulation parameters ─────────────────────────────────
    const int MAX_CYCLES = 10000;
    bool      halted     = false;

    printf("=== RV64 Pipeline Simulation Start ===\n\n");

    for (int cycle = 0; cycle < MAX_CYCLES && !halted; ++cycle)
    {
        printf("===== Cycle %4d   PC=0x%016llX ==========================\n",
               cycle, PC);

        // ══════════════════════════════════════════════════════
        //  STAGE 1: IF — Instruction Fetch
        // ══════════════════════════════════════════════════════

        // Drive IFU inputs
        ifu.pc       = PC;
        ifu.pc_valid = pc_valid;

        // Connect IFU ↔ instruction memory
        mem.instruction_address = ifu.imem_addr;
        mem.instruction_valid   = ifu.imem_req;
        mem.instructionMemoryTick();
        ifu.imem_data  = mem.instruction_data;
        ifu.imem_ready = mem.instruction_ready;

        // IFU back-pressure: hold SEND_DECODE if pipeline was stalled last cycle
        ifu.out_ready = !prev_stall;

        ifu.tick();
           
        // Latch IF/ID pipeline register (next cycle value)
        if_id_next.valid       = ifu.out_valid;
        if_id_next.pc          = ifu.out_pc;
        if_id_next.instruction = ifu.out_instruction;

        // BTB lookup for branch prediction
        btb.pc_i           = PC;
        btb.lookup_valid_i = pc_valid;
        btb.tick();

        // ══════════════════════════════════════════════════════
        //  STAGE 2: ID — Instruction Decode + Register Read
        // ══════════════════════════════════════════════════════

        dec.in_instruction = if_id.instruction;
        dec.in_pc          = if_id.pc;
        dec.in_valid       = if_id.valid;
        dec.tick();

        const DecodedInstruction& d = dec.decoded;
      
        // Register file read (combinational)
        rf.port_a.addr  = d.rs1;
        rf.port_a.valid = d.rs1_used && if_id.valid;
        rf.port_b.addr  = d.rs2;
        rf.port_b.valid = d.rs2_used && if_id.valid;

        // ── Data hazard detection ─────────────────────────────
        bool stall = if_id.valid && hazard_detect(d, id_ex, ex_mem, mem_wb);
            printf(
            "ID pc=%llX rs1=%d rs2=%d rd=%d stall=%d\n",
            if_id.pc,
            d.rs1,
            d.rs2,
            d.rd,
            stall
            );
        if (stall) {
            printf("  [STALL] data hazard — inserting bubble\n");
            // Freeze IF/ID; insert NOP bubble into ID/EX
            if_id_next     = if_id;       // keep IF/ID as-is
            id_ex_next     = {};          // bubble (valid=false)
        } else {
            rf.tick();    // commit pending write + update read ports
            id_ex_next.pc       = if_id.pc;
            id_ex_next.decoded  = d;
            id_ex_next.rs1_data = rf.port_a.data;
            id_ex_next.rs2_data = rf.port_b.data;
            id_ex_next.valid    = if_id.valid && d.valid;
        }

        // ══════════════════════════════════════════════════════
        //  STAGE 3: EX — Execute
        // ══════════════════════════════════════════════════════

        const DecodedInstruction& dx = id_ex.decoded;
       printf("EX: rd=%d rs1=%d imm=%lld op=%d valid=%d\n",
       dx.rd,
       dx.rs1,
       dx.imm,
       (int)dx.alu_op,
       id_ex.valid);
        // ── Operand A mux (rs1 or PC) ─────────────────────────
        uint64_t alu_a = id_ex.rs1_data;
        if (dx.instr_type == InstrType::U_TYPE && dx.alu_op == ALU_OP::ALU_AUIPC)
            alu_a = id_ex.pc;   // AUIPC: A = PC
        if (dx.jump && dx.instr_type == InstrType::J_TYPE)
            alu_a = id_ex.pc + 4;  // JAL: pass PC+4 as return address via PASS_A

        // ── Operand B mux (rs2 or immediate) ─────────────────
        // Branch instructions compare rs1 vs rs2; imm is only the branch offset
        uint64_t alu_b = (dx.imm_used && !dx.branch) ? static_cast<uint64_t>(dx.imm)
                                       : id_ex.rs2_data;

        // ── Drive ALU ─────────────────────────────────────────
        alu.valid_i  = id_ex.valid;
        alu.ready_i  = true;
        alu.a_i      = alu_a;
        alu.b_i      = alu_b;
        alu.alu_op_i = dx.alu_op;
        alu.tick();

        // ── Branch/Jump resolution ────────────────────────────
        bool     branch_taken  = false;
        uint64_t branch_target = 0;
        if (id_ex.valid && dx.branch) {
            branch_taken = evaluate_branch(dx.branch_op,
                               alu.zero_o, alu.neg_o, alu.overflow_o,
                               id_ex.rs1_data, id_ex.rs2_data);
            branch_target = id_ex.pc + static_cast<uint64_t>(dx.imm);
        }
        if (id_ex.valid && dx.jump) {
            branch_taken = true;
            if (dx.instr_type == InstrType::I_TYPE) {
                // JALR: target = (rs1 + imm) & ~1
                branch_target = (id_ex.rs1_data +
                                 static_cast<uint64_t>(dx.imm)) & ~1ULL;
            } else {
                // JAL: target = PC + imm
                branch_target = id_ex.pc + static_cast<uint64_t>(dx.imm);
            }
        }
            printf("Branch PC = 0x%llX  imm = %lld  target = 0x%llX  taken = %d\n",
                id_ex.pc,
                dx.imm,
                branch_target,
                branch_taken);
        // ── BTB update ────────────────────────────────────────
        btb.update_valid_i  = id_ex.valid && (dx.branch || dx.jump);
        btb.update_pc_i     = id_ex.pc;
        btb.update_target_i = branch_target;
        btb.update_taken_i  = branch_taken;
        // btb.tick() already called; update applies next cycle via tick()
        // We re-tick to commit the update (models registered update port)
        ////////////btb.tick();

        // ── PC redirect on branch/jump ────────────────────────
        if (branch_taken) {
            PC       = branch_target;
            pc_valid = true;
            ifu.flush_i = true;
            // Flush the two instructions that entered the pipe after the branch
            if_id_next = {};
            if (!stall)
               id_ex_next = {};
            printf("  [BRANCH] taken → target 0x%016llX — flushing IF/ID\n",
                   branch_target);
        }

        // Halt on ECALL/EBREAK
        if (id_ex.valid && dx.sys_call &&
            (dx.sys_op == SysOp::ECALL || dx.sys_op == SysOp::EBREAK)) {
            printf("  [HALT] ECALL/EBREAK encountered at PC=0x%016llX\n",
                   id_ex.pc);
            halted = true;
        }

        // Latch EX/MEM pipeline register
        ex_mem_next.pc            = id_ex.pc;
        ex_mem_next.decoded       = dx;
        ex_mem_next.alu_result    = alu.result_o;
        ex_mem_next.rs2_data      = id_ex.rs2_data;
        ex_mem_next.alu_zero      = alu.zero_o;
        ex_mem_next.branch_taken  = branch_taken;
        ex_mem_next.branch_target = branch_target;
        ex_mem_next.valid         = id_ex.valid;
        printf("[EX->MEM] PC=%llX alu=%llX rs2_data=%llX\n",
       ex_mem_next.pc,
       ex_mem_next.alu_result,
       ex_mem_next.rs2_data);
        // ══════════════════════════════════════════════════════
        //  STAGE 4: MEM — Data Memory Access
        // ══════════════════════════════════════════════════════

        const DecodedInstruction& dm = ex_mem.decoded;

        bool     mem_rd_en   = false;
        bool     mem_wr_en   = false;
        DataType mem_dtype   = DataType::DWORD;
        bool     mem_sext    = false;
        uint64_t mem_rd_data = 0;

        if (ex_mem.valid && dm.mem_op != MemOp::NONE) {
            mem_op_to_signals(dm.mem_op, mem_rd_en, mem_wr_en,
                              mem_dtype, mem_sext);

            mem.data_address = ex_mem.alu_result;
            mem.read_enable  = mem_rd_en;
            mem.write_enable = mem_wr_en;
            mem.access_type  = mem_dtype;
            mem.write_data   = ex_mem.rs2_data;
            mem.dataMemoryTick();

            if(mem_wr_en)
            {
                printf(
                    "[STORE] PC=%llX addr=%llX data=%llX rs2_data=%llX\n",
                    ex_mem.pc,
                    mem.data_address,
                    mem.write_data,
                    ex_mem.rs2_data
                );
            }
            if (mem_rd_en) {
                mem_rd_data = mem_sext
                    ? sign_extend_load(mem.read_data, mem_dtype)
                    : mem.read_data;
            }
        } else {
            // Quiesce memory lines
            mem.read_enable  = false;
            mem.write_enable = false;
            mem.dataMemoryTick();
        }

        // Latch MEM/WB pipeline register
        mem_wb_next.pc         = ex_mem.pc;
        mem_wb_next.decoded    = dm;
        mem_wb_next.alu_result = ex_mem.alu_result;
        mem_wb_next.mem_data   = mem_rd_data;
        mem_wb_next.valid      = ex_mem.valid;

        // ══════════════════════════════════════════════════════
        //  STAGE 5: WB — Write-Back
        // ══════════════════════════════════════════════════════

        const DecodedInstruction& dw = mem_wb.decoded;

        if (mem_wb.valid && dw.rd_used && dw.rd != 0) {
            // Select write-back data: memory load or ALU result
            bool is_load = (dw.mem_op != MemOp::NONE && dw.mem_read);
            uint64_t wb_data = is_load ? mem_wb.mem_data
                                       : mem_wb.alu_result;

            rf.port_w.addr  = dw.rd;
            rf.port_w.data  = wb_data;
            rf.port_w.wen   = true;
            rf.port_w.valid = true;

            printf("  [WB] x%d ← 0x%016llX\n", dw.rd, wb_data);
        } else {
            rf.port_w.wen   = false;
            rf.port_w.valid = false;
        }

        // Register file tick commits the write latched last cycle
        // (rf.tick() was already called in ID; if stalled, call again
        //  just for WB commit — the stall path skips the ID tick)
        if (stall) rf.tick();

        // ══════════════════════════════════════════════════════
        //  Advance PC (only when IFU delivered a valid instruction)
        // ══════════════════════════════════════════════════════
        if (!branch_taken && !stall && ifu.out_valid) {
            PC += 4;
            pc_valid = true;
        }

        // Save stall for next cycle's IFU back-pressure
        prev_stall = stall;

        // ══════════════════════════════════════════════════════
        //  Clock edge: advance all pipeline registers
        // ══════════════════════════════════════════════════════
        if_id  = if_id_next;
        id_ex  = id_ex_next;
        ex_mem = ex_mem_next;
        mem_wb = mem_wb_next;

        // Reset next-cycle values to bubble defaults
        if_id_next  = {};
        id_ex_next  = {};
        ex_mem_next = {};
        mem_wb_next = {};

    } // end simulation loop

    printf("\n=== Simulation %s after %d cycles ===\n\n",
           halted ? "halted" : "completed (max cycles)", MAX_CYCLES);

    // ── Final state dumps ─────────────────────────────────────
    rf.dump();
    btb.dump();
    alu.dump();

    return 0;
}


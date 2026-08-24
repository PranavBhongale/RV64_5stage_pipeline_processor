
`timescale 1ns/1ps
package decode_pkg;



    //  Instruction format types
    typedef enum logic [2:0] {
        R_TYPE   = 3'd0,
        I_TYPE   = 3'd1,
        S_TYPE   = 3'd2,
        B_TYPE   = 3'd3,
        U_TYPE   = 3'd4,
        J_TYPE   = 3'd5,
        CSR_TYPE = 3'd6,
        SYS_TYPE = 3'd7
    } instr_type_e;





    //  Memory operation
     typedef enum logic [3:0] {
        MEM_NONE        = 4'd0,
        // Signed loads
        LOAD_BYTE       = 4'd1,   // LB   8-bit  sign-extend
        LOAD_HALF       = 4'd2,   // LH   16-bit sign-extend
        LOAD_WORD       = 4'd3,   // LW   32-bit sign-extend
        LOAD_DOUBLE     = 4'd4,   // LD   64-bit
        // Unsigned / zero-extend loads
        LOAD_BYTE_U     = 4'd5,   // LBU
        LOAD_HALF_U     = 4'd6,   // LHU
        LOAD_WORD_U     = 4'd7,   // LWU  32-bit zero-extend (RV64)
        // Stores
        STORE_BYTE      = 4'd8,   // SB
        STORE_HALF      = 4'd9,   // SH
        STORE_WORD      = 4'd10,  // SW
        STORE_DOUBLE    = 4'd11   // SD
    } mem_op_e;

    //  Branch condition
    typedef enum logic [2:0] {
        BR_NONE  = 3'd0,
        BR_BEQ   = 3'd1,
        BR_BNE   = 3'd2,
        BR_BLT   = 3'd3,
        BR_BGE   = 3'd4,
        BR_BLTU  = 3'd5,
        BR_BGEU  = 3'd6
    } branch_op_e;

    //  CSR operation
    typedef enum logic [2:0] {
        CSR_NONE  = 3'd0,
        CSR_CSRRW  = 3'd1,
        CSR_CSRRS  = 3'd2,
        CSR_CSRRC  = 3'd3,
        CSR_CSRRWI = 3'd4,
        CSR_CSRRSI = 3'd5,
        CSR_CSRRCI = 3'd6
    } csr_op_e;

    //  System / privileged operation
    typedef enum logic [2:0] {
        SYS_NONE    = 3'd0,
        SYS_ECALL   = 3'd1,
        SYS_EBREAK  = 3'd2,
        SYS_FENCE   = 3'd3,
        SYS_FENCE_I = 3'd4,
        SYS_MRET    = 3'd5,
        SYS_SRET    = 3'd6,
        SYS_WFI     = 3'd7
    } sys_op_e;

    //  Decoded instruction bundle
    //  Passed as a single struct on the output bus.
    typedef struct packed {
        // classification
        instr_type_e  instr_type;   // [2:0]
        mem_op_e      mem_op;       // [3:0]
        branch_op_e   branch_op;    // [2:0]
        csr_op_e      csr_op;       // [2:0]
        sys_op_e      sys_op;       // [2:0]

        // register addresses
        logic [4:0]   rs1;
        logic [4:0]   rs2;
        logic [4:0]   rd;

        // immediate (sign-extended 64-bit)
        logic signed [63:0] imm;

        // CSR address (12-bit)
        logic [11:0]  csr_addr;

        // zimm field (5-bit unsigned, CSR immediate variants)
        logic [4:0]   zimm;

        // control flags
        logic  rs1_used;
        logic  rs2_used;
        logic  rd_used;
        logic  imm_used;
        logic  mem_read;
        logic  mem_write;
        logic  branch;
        logic  jump;
        logic  csr_access;
        logic  sys_call;
    } decoded_instr_t;


  typedef enum logic [1:0] {
    BYTE     = 2'b00,
    HALFWORD = 2'b01,
    WORD     = 2'b10,
    DWORD    = 2'b11
  } data_type_t;


endpackage

# C → RV64IM Compiler
### For use with `rv64im_assembler.py`

---

## Quick Start

```bash
python3 c_compiler.py program.c          # → program.asm
python3 c_compiler.py program.c -o out.asm
python3 c_compiler.py program.c --dump-ast    # inspect the parse tree
python3 c_compiler.py program.c --dump-ir     # inspect raw emitted lines
```

Then feed directly into your assembler:
```bash
python3 rv64im_assembler.py program.asm  # → imem.hex + dmem.hex
```

---

## Project Files

| File             | Role                                    |
|------------------|-----------------------------------------|
| `c_compiler.py`  | Entry point, argument parsing           |
| `lexer.py`       | Tokenizer (C → tokens)                  |
| `parser.py`      | Recursive-descent parser (tokens → AST) |
| `ast_nodes.py`   | All AST node dataclasses                |
| `codegen.py`     | AST → RV64IM assembly                   |
| `test_compiler.py` | 20-case automated test suite          |

---

## Supported C Features

### Types
| C type  | Register width | Load / Store |
|---------|---------------|--------------|
| `char`  | 64-bit (sign-ext) | LB / SB  |
| `int`   | 64-bit (sign-ext) | LW / SW  |
| `long`  | 64-bit            | LD / SD  |
| `void`  | (return only)     | —        |
| `T*`    | 64-bit pointer    | LD / SD  |
| `T[]`   | decays to pointer | —        |

### Expressions
- Integer literals (decimal, hex `0x…`, octal `0…`, char `'a'`)
- String literals → `.asciz` in `.data`
- Arithmetic: `+  -  *  /  %`
- Bitwise: `&  |  ^  ~  <<  >>`
- Comparison: `==  !=  <  >  <=  >=`
- Logical: `&&  ||  !` (short-circuit)
- Assignment: `=  +=  -=  *=  /=  %=  &=  |=  ^=  <<=  >>=`
- Prefix `++` / `--`
- Postfix `++` / `--`
- Ternary `? :`
- `sizeof(type)` / `sizeof(expr)`
- Cast `(type)expr`
- Unary `&` (address-of), `*` (dereference)
- Array subscript `a[i]`
- Function calls (up to 8 arguments via `a0–a7`)

### Statements
- `if` / `else if` / `else`
- `while`, `do-while`, `for`
- `break`, `continue`
- `return`
- Local variable declaration with optional initializer
- Compound blocks `{ … }`

### Functions
- Multiple functions per file
- Recursion (stack-based, callee saves `ra` and `fp`)
- Up to 8 parameters (RV64 ABI: `a0–a7`)
- `void` return type
- Forward declarations

### Global Variables
- Scalar globals → `.word 0` / `.dword 0` etc.
- Global arrays → `.zero N`
- Constant initialisers → emitted inline in `.data`

---

## Generated ABI

```
Prologue:
    ADDI  sp, sp, -<frame>
    SD    ra, <frame-8>(sp)
    SD    s0, <frame-16>(sp)
    ADDI  s0, sp, <frame>
    SD    a0, -8(s0)       ← store each param to its stack slot
    SD    a1, -16(s0)
    ...

Epilogue:
    LD    ra, <frame-8>(sp)
    LD    s0, <frame-16>(sp)
    ADDI  sp, sp, <frame>
    JALR  zero, ra, 0
```

- All locals are **fp-relative** (via `s0`)
- Temporaries: `t0–t5` (freely clobbered)
- `t6` is reserved as the global-address scratch register
- Arguments arrive in `a0–a7`; return value leaves in `a0`
- Stack is **16-byte aligned** at all calls

---

## Limitations (by design — simulation scope)

- No `struct` / `union`
- No `float` / `double`
- No `switch` / `case`
- No multi-dimensional arrays
- No `#define` macros (preprocessor lines are skipped)
- No standard library (no `printf` etc. — use ECALL or stub functions)
- No pointer-to-function
- More than 8 function arguments: first 8 in registers; rest unsupported

---

## Example: Fibonacci

**Input (`fib.c`)**
```c
int fib(int n) {
    if (n <= 1) return n;
    return fib(n - 1) + fib(n - 2);
}
int main() {
    return fib(10);
}
```

**Output (`fib.asm`)** — excerpt:
```asm
    .text
    .global fib
fib:
    # ── prologue ─────────────────────────────
    ADDI     sp, sp, -32
    SD       ra, 24(sp)
    SD       s0, 16(sp)
    ADDI     s0, sp, 32
    SD       a0, -8(s0)
    # ── body ────────────────────────────────
    # if (line 2)
    ...
    CALL     fib
    ...
.Lfib_end:
    # ── epilogue ────────────────────────────
    LD       ra, 24(sp)
    LD       s0, 16(sp)
    ADDI     sp, sp, 32
    JALR     zero, ra, 0
```

---

## Running the Tests

```bash
python3 test_compiler.py
```

Tests 20 C programs covering: arithmetic, if/else, while, for, do-while,
recursion, global variables, arrays, bitwise ops, logical ops, compound
assignment, ternary, break/continue, nested calls, and Tower of Hanoi.

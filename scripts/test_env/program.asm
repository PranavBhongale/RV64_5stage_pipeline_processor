.text
main:
    addi x1, x0, 10      # x1 = 10
    addi x2, x0, 20      # x2 = 20

    add  x3, x1, x2      # x3 = x1 + x2 = 30

    lui  x4, 0x10000     # x4 = 0x10000000 (data memory base)
    sd   x3, 0(x4)       # store 30 at address 0x10000000

loop:
    beq  x0, x0, loop    # infinite loop


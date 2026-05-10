// Deterministic RV32I smoke program for tb_risc_v.
// It avoids compiler-generated call/return sequences by emitting
// the exact instructions expected by the testbench.

void _start(void) __attribute__((naked, section(".text")));

void _start(void) {
    __asm__ volatile(
        ".word 0x00500093\n" // addi x1, x0, 5
        ".word 0x00a00113\n" // addi x2, x0, 10
        ".word 0x002081b3\n" // add  x3, x1, x2
        ".word 0x00302023\n" // sw   x3, 0(x0)
        ".word 0x00000213\n" // addi x4, x0, 0
        ".word 0x00000293\n" // addi x5, x0, 0
        ".word 0x00800313\n" // addi x6, x0, 8
        ".word 0x00520233\n" // add  x4, x4, x5
        ".word 0x00128293\n" // addi x5, x5, 1
        ".word 0xfe62cce3\n" // blt  x5, x6, loop
        ".word 0x00402023\n" // sw   x4, 0(x0)
        ".word 0x00002383\n" // lw   x7, 0(x0)
        ".word 0x00138393\n" // addi x7, x7, 1
        ".word 0x00702023\n" // sw   x7, 0(x0)
        ".word 0xfe000ae3\n" // beq  x0, x0, spin
    );
}


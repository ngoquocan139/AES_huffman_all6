typedef unsigned int uint32_t;
typedef unsigned char uint8_t;
typedef unsigned short uint16_t_alias;

#define RESULT_SIGNATURE 0x43505548u

void _start(void) __attribute__((naked, section(".text")));
int main(void) __attribute__((noreturn));

static void write_result(uint32_t idx, uint32_t value)
{
    uint32_t addr = idx * 4u;
    __asm__ volatile("sw %1, 0(%0)" :: "r"(addr), "r"(value) : "memory");
}

static uint32_t exercise_mem_offsets(void)
{
    volatile uint8_t *base8 = (volatile uint8_t *)0x00000300u;
    volatile uint16_t_alias *half0 = (volatile uint16_t_alias *)0x00000310u;
    volatile uint16_t_alias *half2 = (volatile uint16_t_alias *)0x00000312u;
    volatile uint32_t *word0 = (volatile uint32_t *)0x00000320u;
    uint32_t error = 0u;
    uint32_t v0;
    uint32_t v1;
    uint32_t v2;
    uint32_t v3;

    base8[0] = 0x11u;
    base8[1] = 0x82u;
    base8[2] = 0x33u;
    base8[3] = 0xf4u;
    *half0 = (uint16_t_alias)0x4567u;
    *half2 = (uint16_t_alias)0x89abu;
    *word0 = 0x13579bdfu;

    __asm__ volatile("lbu %0, 0(%1)" : "=r"(v0) : "r"(base8));
    __asm__ volatile("lbu %0, 1(%1)" : "=r"(v1) : "r"(base8));
    __asm__ volatile("lbu %0, 2(%1)" : "=r"(v2) : "r"(base8));
    __asm__ volatile("lbu %0, 3(%1)" : "=r"(v3) : "r"(base8));
    if ((v0 != 0x11u) || (v1 != 0x82u) || (v2 != 0x33u) || (v3 != 0xf4u))
        error |= 1u << 0;

    __asm__ volatile("lb %0, 1(%1)" : "=r"(v1) : "r"(base8));
    __asm__ volatile("lb %0, 3(%1)" : "=r"(v3) : "r"(base8));
    if ((v1 != 0xffffff82u) || (v3 != 0xfffffff4u))
        error |= 1u << 1;

    __asm__ volatile("lhu %0, 0(%1)" : "=r"(v0) : "r"(half0));
    __asm__ volatile("lhu %0, 2(%1)" : "=r"(v2) : "r"(half0));
    if ((v0 != 0x4567u) || (v2 != 0x89abu))
        error |= 1u << 2;

    __asm__ volatile("lh %0, 2(%1)" : "=r"(v2) : "r"(half0));
    if (v2 != 0xffff89abu)
        error |= 1u << 3;

    /*
     * These two operations intentionally hit MEM-stage misaligned branches.
     * The core has no trap flow yet; the test only needs the RTL branch to
     * execute and then continues to publish a clean signature.
     */
    __asm__ volatile("sh %0, 1(%1)" :: "r"(0x55aau), "r"(base8) : "memory");
    __asm__ volatile("sw %0, 2(%1)" :: "r"(0xa5a55a5au), "r"(base8) : "memory");
    __asm__ volatile("lh %0, 1(%1)" : "=r"(v1) : "r"(base8));
    __asm__ volatile("lw %0, 2(%1)" : "=r"(v2) : "r"(base8));

    return error;
}

static uint32_t exercise_forwarding(void)
{
    uint32_t out0;
    uint32_t out1;
    uint32_t out2;
    uint32_t out3;
    uint32_t *mem = (uint32_t *)0x00000340u;

    __asm__ volatile(
        "li   t0, 0x12345000\n"
        "addi t0, t0, 0x678\n"
        "add  t1, t0, t0\n"
        "xor  t2, t1, t0\n"
        "sw   t2, 0(%[mem])\n"
        "lw   t3, 0(%[mem])\n"
        "add  t4, t3, t0\n"
        "sw   t4, 4(%[mem])\n"
        "jal  t5, 1f\n"
        "addi t6, zero, 0x7f\n"
        "1:\n"
        "add  %[out0], t5, t5\n"
        "add  %[out1], t4, t3\n"
        "add  %[out2], t0, t1\n"
        "add  %[out3], t2, t3\n"
        : [out0] "=r"(out0),
          [out1] "=r"(out1),
          [out2] "=r"(out2),
          [out3] "=r"(out3)
        : [mem] "r"(mem)
        : "t0", "t1", "t2", "t3", "t4", "t5", "t6", "memory");

    return out0 ^ out1 ^ out2 ^ out3 ^ mem[1];
}

void _start(void)
{
    __asm__ volatile(
        "li sp, 0x00007f00\n"
        "jal zero, main\n"
    );
}

int main(void)
{
    uint32_t mem_error;
    uint32_t fwd_mix;
    uint32_t error_mask = 0u;

    mem_error = exercise_mem_offsets();
    fwd_mix = exercise_forwarding();

    if (mem_error != 0u)
        error_mask |= 1u << 0;
    if (fwd_mix == 0u)
        error_mask |= 1u << 1;

    write_result(3u, fwd_mix);
    write_result(2u, mem_error);
    write_result(1u, error_mask);
    write_result(0u, RESULT_SIGNATURE);

    while (1) {
    }
}

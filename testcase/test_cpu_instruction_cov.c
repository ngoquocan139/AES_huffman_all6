typedef unsigned int uint32_t;
typedef unsigned char uint8_t;
typedef unsigned short uint16_t_alias;
typedef signed int int32_t;

#define RESULT_SIGNATURE 0x43505543u

void _start(void) __attribute__((naked, section(".text")));
int main(void) __attribute__((noreturn));

static void write_result(uint32_t idx, uint32_t value)
{
    uint32_t addr = idx * 4u;
    __asm__ volatile("sw %1, 0(%0)" :: "r"(addr), "r"(value) : "memory");
}

static uint32_t exercise_r_type(uint32_t a, uint32_t sh)
{
    uint32_t add_v;
    uint32_t sub_v;
    uint32_t sll_v;
    uint32_t slt_v;
    uint32_t sltu_v;
    uint32_t xor_v;
    uint32_t srl_v;
    uint32_t sra_v;
    uint32_t or_v;
    uint32_t and_v;

    __asm__ volatile(
        "add  %[add_v],  %[a], %[sh]\n"
        "sub  %[sub_v],  %[a], %[sh]\n"
        "sll  %[sll_v],  %[a], %[sh]\n"
        "slt  %[slt_v],  %[a], %[sh]\n"
        "sltu %[sltu_v], %[a], %[sh]\n"
        "xor  %[xor_v],  %[a], %[sh]\n"
        "srl  %[srl_v],  %[a], %[sh]\n"
        "sra  %[sra_v],  %[a], %[sh]\n"
        "or   %[or_v],   %[a], %[sh]\n"
        "and  %[and_v],  %[a], %[sh]\n"
        : [add_v] "=&r"(add_v),
          [sub_v] "=&r"(sub_v),
          [sll_v] "=&r"(sll_v),
          [slt_v] "=&r"(slt_v),
          [sltu_v] "=&r"(sltu_v),
          [xor_v] "=&r"(xor_v),
          [srl_v] "=&r"(srl_v),
          [sra_v] "=&r"(sra_v),
          [or_v] "=&r"(or_v),
          [and_v] "=&r"(and_v)
        : [a] "r"(a), [sh] "r"(sh));

    return add_v ^ sub_v ^ sll_v ^ slt_v ^ sltu_v ^
           xor_v ^ srl_v ^ sra_v ^ or_v ^ and_v;
}

static uint32_t exercise_i_type(uint32_t a)
{
    uint32_t r = 0u;
    uint32_t tmp;

    __asm__ volatile("addi %0, %1, -17" : "=r"(tmp) : "r"(a));
    r ^= tmp;
    __asm__ volatile("slti %0, %1, -1" : "=r"(tmp) : "r"(a));
    r ^= tmp;
    __asm__ volatile("sltiu %0, %1, 16" : "=r"(tmp) : "r"(a));
    r ^= tmp;
    __asm__ volatile("xori %0, %1, 0x55" : "=r"(tmp) : "r"(a));
    r ^= tmp;
    __asm__ volatile("ori %0, %1, 0x2a" : "=r"(tmp) : "r"(a));
    r ^= tmp;
    __asm__ volatile("andi %0, %1, 0x7f" : "=r"(tmp) : "r"(a));
    r ^= tmp;
    __asm__ volatile("slli %0, %1, 3" : "=r"(tmp) : "r"(a));
    r ^= tmp;
    __asm__ volatile("srli %0, %1, 2" : "=r"(tmp) : "r"(a));
    r ^= tmp;
    __asm__ volatile("srai %0, %1, 2" : "=r"(tmp) : "r"(a));
    r ^= tmp;

    return r;
}

static uint32_t exercise_branches(uint32_t a, uint32_t b)
{
    uint32_t score = 0u;

    __asm__ volatile(
        "beq  %[a], %[a], 1f\n"
        "ori  %[score], %[score], 0x100\n"
        "1:\n"
        "ori  %[score], %[score], 0x001\n"
        "bne  %[a], %[b], 2f\n"
        "ori  %[score], %[score], 0x200\n"
        "2:\n"
        "ori  %[score], %[score], 0x002\n"
        "blt  %[a], %[b], 3f\n"
        "ori  %[score], %[score], 0x400\n"
        "3:\n"
        "ori  %[score], %[score], 0x004\n"
        "bge  %[b], %[a], 4f\n"
        "ori  %[score], %[score], 0x400\n"
        "4:\n"
        "ori  %[score], %[score], 0x008\n"
        "bltu %[a], %[b], 5f\n"
        "ori  %[score], %[score], 0x080\n"
        "5:\n"
        "ori  %[score], %[score], 0x010\n"
        "bgeu %[b], %[a], 6f\n"
        "ori  %[score], %[score], 0x080\n"
        "6:\n"
        "ori  %[score], %[score], 0x020\n"
        : [score] "+r"(score)
        : [a] "r"(a), [b] "r"(b));

    return score;
}

static uint32_t exercise_load_store(void)
{
    volatile uint32_t *word_p = (volatile uint32_t *)0x00000100u;
    volatile uint16_t_alias *half_p = (volatile uint16_t_alias *)0x00000104u;
    volatile uint8_t *byte_p = (volatile uint8_t *)0x00000106u;
    uint32_t lbu_v;
    uint32_t lhu_v;
    int32_t lb_v;
    int32_t lh_v;

    *word_p = 0xa1b2c3d4u;
    *half_p = (uint16_t_alias)0xe595u;
    *byte_p = 0x7au;

    __asm__ volatile("lbu %0, 0(%1)" : "=r"(lbu_v) : "r"(word_p));
    __asm__ volatile("lb  %0, 3(%1)" : "=r"(lb_v) : "r"(word_p));
    __asm__ volatile("lhu %0, 4(%1)" : "=r"(lhu_v) : "r"(word_p));
    __asm__ volatile("lh  %0, 4(%1)" : "=r"(lh_v) : "r"(word_p));

    if (lbu_v != 0x000000d4u)
        return 0xffffffffu;
    if ((uint32_t)lb_v != 0xffffffa1u)
        return 0xfffffffeu;
    if (lhu_v != 0x0000e595u)
        return 0xfffffffdu;
    if ((uint32_t)lh_v != 0xffffe595u)
        return 0xfffffffcu;

    return lhu_v;
}

void _start(void) {
    __asm__ volatile(
        "li sp, 0x00007f00\n"
        "jal zero, main\n"
    );
}

int main(void) {
    uint32_t error_mask = 0u;
    uint32_t r_mix;
    uint32_t i_mix;
    uint32_t branch_score;
    uint32_t mem_mix;
    uint32_t lui_v;
    uint32_t jalr_cookie = 0u;

    __asm__ volatile("lui %0, 0x12345" : "=r"(lui_v));
    r_mix = exercise_r_type(0x89abcdefu, 5u);
    i_mix = exercise_i_type(0x00000123u);
    branch_score = exercise_branches(1u, 2u);
    mem_mix = exercise_load_store();

    if (r_mix != 0xcd79bdffu)
        error_mask |= (1u << 0);
    if (i_mix == 0u)
        error_mask |= (1u << 1);
    if (branch_score != 0x0000003fu)
        error_mask |= (1u << 2);
    if (mem_mix != 0x0000e595u)
        error_mask |= (1u << 3);
    if (lui_v != 0x12345000u)
        error_mask |= (1u << 4);

    __asm__ volatile(
        "la t0, 1f\n"
        "jalr zero, 0(t0)\n"
        "ori %[cookie], %[cookie], 0x100\n"
        "1:\n"
        "ori %[cookie], %[cookie], 0x1\n"
        : [cookie] "+r"(jalr_cookie)
        :
        : "t0");

    if (jalr_cookie != 1u)
        error_mask |= (1u << 5);

    write_result(5u, i_mix);
    write_result(4u, branch_score);
    write_result(3u, mem_mix);
    write_result(2u, r_mix);
    write_result(1u, error_mask);
    write_result(0u, RESULT_SIGNATURE);

    while (1) {
    }
}

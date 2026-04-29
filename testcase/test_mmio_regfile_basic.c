typedef unsigned int uint32_t;

#define DMA_BASE_ADDR       0x40000000u
#define DMA_CONTROL         (*(volatile uint32_t *)(DMA_BASE_ADDR + 0x00u))
#define DMA_STATUS          (*(volatile uint32_t *)(DMA_BASE_ADDR + 0x04u))
#define DMA_SRC_ADDR        (*(volatile uint32_t *)(DMA_BASE_ADDR + 0x08u))
#define DMA_DST_ADDR        (*(volatile uint32_t *)(DMA_BASE_ADDR + 0x0Cu))
#define DMA_LEN_BYTES       (*(volatile uint32_t *)(DMA_BASE_ADDR + 0x10u))
#define DMA_MODE            (*(volatile uint32_t *)(DMA_BASE_ADDR + 0x14u))
#define DMA_BLOCK_CFG       (*(volatile uint32_t *)(DMA_BASE_ADDR + 0x18u))
#define DMA_IV0             (*(volatile uint32_t *)(DMA_BASE_ADDR + 0x28u))
#define DMA_IV1             (*(volatile uint32_t *)(DMA_BASE_ADDR + 0x2Cu))
#define DMA_IV2             (*(volatile uint32_t *)(DMA_BASE_ADDR + 0x30u))
#define DMA_IV3             (*(volatile uint32_t *)(DMA_BASE_ADDR + 0x34u))

#define RESULT_SIGNATURE    0x52454731u

void _start(void) __attribute__((naked, section(".text")));
int main(void) __attribute__((noreturn));

static void write_result(uint32_t idx, uint32_t value)
{
    uint32_t addr = idx * 4u;
    __asm__ volatile("sw %1, 0(%0)" :: "r"(addr), "r"(value) : "memory");
}

void _start(void) {
    __asm__ volatile(
        "li sp, 0x00007f00\n"
        "j main\n"
    );
}

int main(void) {
    uint32_t error_mask = 0u;
    uint32_t status_reset;
    uint32_t status_cfg;
    uint32_t status_after_reset;
    uint32_t mode_readback;
    uint32_t block_readback;
    uint32_t iv0_readback;
    uint32_t iv1_readback;
    uint32_t iv2_readback;
    uint32_t iv3_readback;

    status_reset = DMA_STATUS;

    DMA_SRC_ADDR = 0x00000400u;
    DMA_DST_ADDR = 0x00002000u;
    DMA_LEN_BYTES = 0x00000040u;
    DMA_MODE = 0x0000000du;
    DMA_BLOCK_CFG = 0x00000020u;
    DMA_IV0 = 0x11223344u;
    DMA_IV1 = 0x55667788u;
    DMA_IV2 = 0x99aabbccu;
    DMA_IV3 = 0xddeeff00u;

    status_cfg = DMA_STATUS;
    mode_readback = DMA_MODE;
    block_readback = DMA_BLOCK_CFG;
    iv0_readback = DMA_IV0;
    iv1_readback = DMA_IV1;
    iv2_readback = DMA_IV2;
    iv3_readback = DMA_IV3;

    if (status_reset != 0x00000000u)
        error_mask |= (1u << 0);
    if (status_cfg != 0x000000d8u)
        error_mask |= (1u << 1);
    if (mode_readback != 0x0000000du)
        error_mask |= (1u << 2);
    if (block_readback != 0x00000020u)
        error_mask |= (1u << 3);
    if (iv0_readback != 0x11223344u)
        error_mask |= (1u << 4);
    if (iv1_readback != 0x55667788u)
        error_mask |= (1u << 5);
    if (iv2_readback != 0x99aabbccu)
        error_mask |= (1u << 6);
    if (iv3_readback != 0xddeeff00u)
        error_mask |= (1u << 7);

    DMA_CONTROL = 0x0000000cu;
    DMA_CONTROL = 0x00000002u;
    status_after_reset = DMA_STATUS;
    write_result(4u, status_after_reset);

    if (status_after_reset != 0x00000000u)
        error_mask |= (1u << 8);
    if (DMA_MODE != 0x00000000u)
        error_mask |= (1u << 9);
    if (DMA_BLOCK_CFG != 0x00000020u)
        error_mask |= (1u << 10);
    if ((DMA_IV0 | DMA_IV1 | DMA_IV2 | DMA_IV3) != 0x00000000u)
        error_mask |= (1u << 11);

    write_result(2u, status_reset);
    write_result(3u, status_cfg);
    write_result(5u, mode_readback);
    write_result(6u, block_readback);
    write_result(7u, iv0_readback);
    write_result(8u, iv1_readback);
    write_result(9u, iv2_readback);
    write_result(10u, iv3_readback);
    write_result(1u, error_mask);
    write_result(0u, RESULT_SIGNATURE);

    while (1) {
    }
}

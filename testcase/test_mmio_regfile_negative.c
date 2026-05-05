typedef unsigned int uint32_t;
typedef unsigned char uint8_t;

#define DMA_BASE_ADDR       0x40000000u
#define DMA_CONTROL         (*(volatile uint32_t *)(DMA_BASE_ADDR + 0x00u))
#define DMA_STATUS          (*(volatile uint32_t *)(DMA_BASE_ADDR + 0x04u))
#define DMA_SRC_ADDR        (*(volatile uint32_t *)(DMA_BASE_ADDR + 0x08u))
#define DMA_DST_ADDR        (*(volatile uint32_t *)(DMA_BASE_ADDR + 0x0Cu))
#define DMA_LEN_BYTES       (*(volatile uint32_t *)(DMA_BASE_ADDR + 0x10u))
#define DMA_MODE            (*(volatile uint32_t *)(DMA_BASE_ADDR + 0x14u))
#define DMA_BLOCK_CFG       (*(volatile uint32_t *)(DMA_BASE_ADDR + 0x18u))
#define DMA_BYTES_DONE      (*(volatile uint32_t *)(DMA_BASE_ADDR + 0x1Cu))
#define DMA_DEBUG           (*(volatile uint32_t *)(DMA_BASE_ADDR + 0x20u))

#define RESULT_SIGNATURE    0x4e454731u

void _start(void) __attribute__((naked, section(".text")));
int main(void) __attribute__((noreturn));

static void write_result(uint32_t idx, uint32_t value)
{
    uint32_t addr = idx * 4u;
    __asm__ volatile("sw %1, 0(%0)" :: "r"(addr), "r"(value) : "memory");
}

static void clear_error(void)
{
    DMA_CONTROL = 0x00000008u;
}

void _start(void) {
    __asm__ volatile(
        "li sp, 0x00007f00\n"
        "j main\n"
    );
}

int main(void) {
    uint32_t error_mask = 0u;
    uint32_t status_after_bad_start;
    uint32_t status_after_readonly_write;
    uint32_t status_after_invalid_addr;
    uint32_t status_after_reserved_mode;
    uint32_t status_after_bad_block_start;
    uint32_t mode_after_partial_store;
    uint32_t block_after_bad_cfg;
    volatile uint32_t *invalid_reg = (volatile uint32_t *)(DMA_BASE_ADDR + 0x000000fcu);
    volatile uint8_t *mode_byte0 = (volatile uint8_t *)(DMA_BASE_ADDR + 0x14u);

    DMA_CONTROL = 0x00000001u;
    status_after_bad_start = DMA_STATUS;
    if ((status_after_bad_start & 0x00000004u) == 0u)
        error_mask |= (1u << 0);

    clear_error();
    DMA_STATUS = 0xffffffffu;
    status_after_readonly_write = DMA_STATUS;
    if ((status_after_readonly_write & 0x00000004u) == 0u)
        error_mask |= (1u << 1);

    clear_error();
    *invalid_reg = 0x12345678u;
    status_after_invalid_addr = DMA_STATUS;
    if ((status_after_invalid_addr & 0x00000004u) == 0u)
        error_mask |= (1u << 2);

    clear_error();
    DMA_MODE = 0x00000010u;
    status_after_reserved_mode = DMA_STATUS;
    if ((status_after_reserved_mode & 0x00000004u) == 0u)
        error_mask |= (1u << 3);
    if (DMA_MODE != 0x00000000u)
        error_mask |= (1u << 4);

    clear_error();
    DMA_SRC_ADDR = 0x00002000u;
    DMA_DST_ADDR = 0x00004000u;
    DMA_LEN_BYTES = 0x00000040u;
    DMA_MODE = 0x0000000du;
    DMA_BLOCK_CFG = 0x00000000u;
    block_after_bad_cfg = DMA_BLOCK_CFG;
    DMA_CONTROL = 0x00000001u;
    status_after_bad_block_start = DMA_STATUS;
    if ((status_after_bad_block_start & 0x00000004u) == 0u)
        error_mask |= (1u << 5);
    if (block_after_bad_cfg != 0x00000000u)
        error_mask |= (1u << 6);

    clear_error();
    DMA_BLOCK_CFG = 0x00000020u;
    DMA_MODE = 0x0000000du;
    *mode_byte0 = 0xffu;
    mode_after_partial_store = DMA_MODE;
    if (mode_after_partial_store != 0x0000000du)
        error_mask |= (1u << 7);

    clear_error();
    DMA_BYTES_DONE = 0x00000001u;
    if ((DMA_STATUS & 0x00000004u) == 0u)
        error_mask |= (1u << 8);

    clear_error();
    DMA_DEBUG = 0x00000001u;
    if ((DMA_STATUS & 0x00000004u) == 0u)
        error_mask |= (1u << 9);

    write_result(2u, status_after_bad_start);
    write_result(3u, status_after_readonly_write);
    write_result(4u, status_after_invalid_addr);
    write_result(5u, status_after_reserved_mode);
    write_result(6u, block_after_bad_cfg);
    write_result(7u, mode_after_partial_store);
    write_result(8u, status_after_bad_block_start);
    write_result(1u, error_mask);
    write_result(0u, RESULT_SIGNATURE);

    while (1) {
    }
}

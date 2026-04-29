typedef unsigned int uint32_t;

#define DMA_BASE_ADDR       0x40000000u
#define DMA_CONTROL         (*(volatile uint32_t *)(DMA_BASE_ADDR + 0x00u))
#define DMA_STATUS          (*(volatile uint32_t *)(DMA_BASE_ADDR + 0x04u))
#define DMA_SRC_ADDR        (*(volatile uint32_t *)(DMA_BASE_ADDR + 0x08u))
#define DMA_DST_ADDR        (*(volatile uint32_t *)(DMA_BASE_ADDR + 0x0Cu))
#define DMA_LEN_BYTES       (*(volatile uint32_t *)(DMA_BASE_ADDR + 0x10u))
#define DMA_MODE            (*(volatile uint32_t *)(DMA_BASE_ADDR + 0x14u))
#define DMA_BLOCK_CFG       (*(volatile uint32_t *)(DMA_BASE_ADDR + 0x18u))

#define RESULT_SIGNATURE    0x4d4f4445u

void _start(void) __attribute__((naked, section(".text")));
int main(void) __attribute__((noreturn));

static void write_result(uint32_t idx, uint32_t value)
{
    uint32_t addr = idx * 4u;
    __asm__ volatile("sw %1, 0(%0)" :: "r"(addr), "r"(value) : "memory");
}

static uint32_t expected_status(uint32_t mode)
{
    uint32_t direction = mode & 0x3u;
    uint32_t cfg_valid = ((direction == 1u) || (direction == 2u)) ? 0x8u : 0u;
    return cfg_valid | ((mode & 0x3u) << 4u) | ((mode & 0xcu) << 4u);
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
    uint32_t status_1;
    uint32_t status_5;
    uint32_t status_9;
    uint32_t status_d;
    uint32_t status_2;
    uint32_t status_0;
    uint32_t status_3;
    uint32_t status_reserved;

    DMA_SRC_ADDR = 0x00000400u;
    DMA_DST_ADDR = 0x00002000u;
    DMA_LEN_BYTES = 0x00000020u;
    DMA_BLOCK_CFG = 0x00000020u;

    DMA_MODE = 0x00000001u;
    status_1 = DMA_STATUS;
    if (status_1 != expected_status(0x1u))
        error_mask |= (1u << 0);

    DMA_MODE = 0x00000005u;
    status_5 = DMA_STATUS;
    if (status_5 != expected_status(0x5u))
        error_mask |= (1u << 1);

    DMA_MODE = 0x00000009u;
    status_9 = DMA_STATUS;
    if (status_9 != expected_status(0x9u))
        error_mask |= (1u << 2);

    DMA_MODE = 0x0000000du;
    status_d = DMA_STATUS;
    if (status_d != expected_status(0xdu))
        error_mask |= (1u << 3);

    DMA_MODE = 0x00000002u;
    status_2 = DMA_STATUS;
    if (status_2 != expected_status(0x2u))
        error_mask |= (1u << 4);

    DMA_MODE = 0x00000000u;
    status_0 = DMA_STATUS;
    if (status_0 != expected_status(0x0u))
        error_mask |= (1u << 5);

    DMA_MODE = 0x00000003u;
    status_3 = DMA_STATUS;
    if (status_3 != expected_status(0x3u))
        error_mask |= (1u << 6);

    clear_error();
    DMA_MODE = 0x00000010u;
    status_reserved = DMA_STATUS;
    if ((status_reserved & 0x00000004u) == 0u)
        error_mask |= (1u << 7);

    write_result(2u, status_1);
    write_result(3u, status_5);
    write_result(4u, status_9);
    write_result(5u, status_d);
    write_result(6u, status_2);
    write_result(7u, status_0);
    write_result(8u, status_3);
    write_result(9u, status_reserved);
    write_result(1u, error_mask);
    write_result(0u, RESULT_SIGNATURE);

    while (1) {
    }
}

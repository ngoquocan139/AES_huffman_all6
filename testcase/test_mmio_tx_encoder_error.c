typedef unsigned int uint32_t;

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

#define SRC_BASE_ADDR       0x00000400u
#define TX_DST_BASE_ADDR    0x00002000u
#define RESULT_BASE_ADDR    0x00000000u
#define RESULT_WORD(idx)    (*(volatile uint32_t *)(RESULT_BASE_ADDR + ((idx) * 4u)))

#define RESULT_SIGNATURE    0x54584552u
#define MAX_POLLS           100000u

void _start(void) __attribute__((naked, section(".text")));
int main(void) __attribute__((noreturn));

void _start(void) {
    __asm__ volatile(
        "li sp, 0x00007f00\n"
        "j main\n"
    );
}

int main(void) {
    uint32_t error_mask = 0u;
    uint32_t status_before;
    uint32_t status_after;
    uint32_t bytes_done;
    uint32_t debug_after;
    uint32_t polls = 0u;

    DMA_SRC_ADDR = SRC_BASE_ADDR;
    DMA_DST_ADDR = TX_DST_BASE_ADDR;
    DMA_LEN_BYTES = 0x00000240u;
    DMA_MODE = 0x00000009u;
    DMA_BLOCK_CFG = 0x00000020u;

    status_before = DMA_STATUS;
    DMA_CONTROL = 0x00000001u;

    do {
        status_after = DMA_STATUS;
        polls++;
    } while (((status_after & 0x00000004u) == 0u) && (polls < MAX_POLLS));

    bytes_done = DMA_BYTES_DONE;
    debug_after = DMA_DEBUG;

    if (status_before != 0x00000098u)
        error_mask |= (1u << 0);
    if ((status_after & 0x00000004u) == 0u)
        error_mask |= (1u << 1);
    if ((debug_after & 0x00000ff0u) != 0x00000060u)
        error_mask |= (1u << 2);
    if (polls >= MAX_POLLS)
        error_mask |= (1u << 3);

    RESULT_WORD(2) = status_before;
    RESULT_WORD(3) = status_after;
    RESULT_WORD(4) = bytes_done;
    RESULT_WORD(5) = debug_after;
    RESULT_WORD(6) = polls;
    RESULT_WORD(1) = error_mask;
    RESULT_WORD(0) = RESULT_SIGNATURE;

    while (1) {
    }
}

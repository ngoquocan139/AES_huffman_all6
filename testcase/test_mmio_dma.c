typedef unsigned int uint32_t;

#define DMA_BASE_ADDR       0x40000000u
#define DMA_CONTROL         (*(volatile uint32_t *)(DMA_BASE_ADDR + 0x00u))
#define DMA_STATUS          (*(volatile uint32_t *)(DMA_BASE_ADDR + 0x04u))
#define DMA_SRC_ADDR        (*(volatile uint32_t *)(DMA_BASE_ADDR + 0x08u))
#define DMA_DST_ADDR        (*(volatile uint32_t *)(DMA_BASE_ADDR + 0x0Cu))
#define DMA_LEN_BYTES       (*(volatile uint32_t *)(DMA_BASE_ADDR + 0x10u))
#define DMA_MODE           (*(volatile uint32_t *)(DMA_BASE_ADDR + 0x14u))
#define DMA_BLOCK_CFG       (*(volatile uint32_t *)(DMA_BASE_ADDR + 0x18u))
#define DMA_BYTES_DONE      (*(volatile uint32_t *)(DMA_BASE_ADDR + 0x1Cu))
#define DMA_DEBUG           (*(volatile uint32_t *)(DMA_BASE_ADDR + 0x20u))
#define DMA_CIPHERTEXT_BYTES_PRODUCED (*(volatile uint32_t *)(DMA_BASE_ADDR + 0x24u))
#define DMA_IV0             (*(volatile uint32_t *)(DMA_BASE_ADDR + 0x28u))
#define DMA_IV1             (*(volatile uint32_t *)(DMA_BASE_ADDR + 0x2Cu))
#define DMA_IV2             (*(volatile uint32_t *)(DMA_BASE_ADDR + 0x30u))
#define DMA_IV3             (*(volatile uint32_t *)(DMA_BASE_ADDR + 0x34u))

#define INPUT_LEN_ADDR      (*(volatile uint32_t *)(0x00000040u))
#define SRC_BASE_ADDR       0x00000400u
#define TX_DST_BASE_ADDR    0x00002000u
#define RX_DST_BASE_ADDR    0x00004000u
#define RESULT_BASE_ADDR    0x00000000u
#define RESULT_WORD(idx)    (*(volatile uint32_t *)(RESULT_BASE_ADDR + ((idx) * 4u)))

/* Whole-file TX modes still require a valid BLOCK_CFG value, but do not split by it. */
#define TEST_BLOCK_SIZE     0x00000020u
#define TEST_MODE_TX_COMPRESS_AES  0x00000009u
#define TEST_MODE_TX_COMPRESS_ONLY 0x0000000du
#define TEST_MODE_RX        0x00000002u
#define RESULT_SIGNATURE    0x44525831u
#define EXPECTED_TX_IDLE    0x00000098u
#define EXPECTED_TX_DONE    0x0000009au
#define EXPECTED_RX_IDLE    0x00000028u
#define EXPECTED_RX_DONE    0x0000002au
#define MAX_POLLS           2000000u

void _start(void) __attribute__((naked, section(".text")));
int main(void) __attribute__((noreturn));

static volatile uint32_t sw_iv_counter = 0x10203040u;

static uint32_t rotl32(uint32_t value, uint32_t shift)
{
    return (value << shift) | (value >> (32u - shift));
}

static void write_demo_iv(uint32_t input_len)
{
    uint32_t mix;

    sw_iv_counter = sw_iv_counter + 1u;
    mix = input_len ^ SRC_BASE_ADDR ^ TX_DST_BASE_ADDR ^ RX_DST_BASE_ADDR;
    mix = mix ^ sw_iv_counter ^ 0x43424331u;

    /*
     * Demo IV generation by RV32I software.
     * This is deterministic for simulation; real FPGA security needs TRNG,
     * host-provided nonce, or a non-volatile monotonic counter.
     */
    mix = mix ^ (mix << 13);
    mix = mix ^ (mix >> 17);
    mix = mix ^ (mix << 5);

    DMA_IV0 = 0x43424331u;
    DMA_IV1 = mix ^ 0x3a5c742eu;
    DMA_IV2 = rotl32(DMA_IV1 ^ 0x9e3779b9u, 7u);
    DMA_IV3 = rotl32(DMA_IV2 + 0x3c6ef372u, 17u);
}

static uint32_t run_dma(uint32_t src,
                        uint32_t dst,
                        uint32_t len,
                        uint32_t mode,
                        uint32_t *status_before,
                        uint32_t *status_after,
                        uint32_t *bytes_done,
                        uint32_t *debug_after)
{
    uint32_t polls = 0u;
    uint32_t saw_busy = 0u;
    uint32_t completion_progress = 0u;

    DMA_SRC_ADDR  = src;
    DMA_DST_ADDR  = dst;
    DMA_LEN_BYTES = len;
    DMA_MODE      = mode;
    DMA_BLOCK_CFG = TEST_BLOCK_SIZE;

    *status_before = DMA_STATUS;
    DMA_CONTROL = 0x00000001u;

    while (1) {
        *status_after = DMA_STATUS;
        if (((*status_after) & 1u) != 0u)
            saw_busy = 1u;
        if (((*status_after) & (1u << 2)) != 0u)
            break;
        if (((( *status_after) & 1u) == 0u) &&
            (((*status_after) & (1u << 1)) != 0u)) {
            if ((mode & 0x3u) == 0x1u)
                completion_progress = DMA_CIPHERTEXT_BYTES_PRODUCED;
            else
                completion_progress = DMA_BYTES_DONE;

            if ((saw_busy != 0u) || (completion_progress != 0u))
                break;
        }
        polls = polls + 1u;
        if (polls >= MAX_POLLS)
            break;
    }

    *bytes_done  = DMA_BYTES_DONE;
    *debug_after = 0u;
    return polls;
}

void _start(void) {
    __asm__ volatile(
        "li sp, 0x00007f00\n"
        "j main\n"
    );
}

int main(void) {
    volatile uint32_t *src_words = (volatile uint32_t *)SRC_BASE_ADDR;
    volatile uint32_t *tx_words  = (volatile uint32_t *)TX_DST_BASE_ADDR;
    volatile uint32_t *rx_words  = (volatile uint32_t *)RX_DST_BASE_ADDR;

    uint32_t error_mask = 0u;
    uint32_t tx_status_before;
    uint32_t tx_status_after;
    uint32_t tx_bytes_done;
    uint32_t tx_debug;
    uint32_t tx_polls;
    uint32_t tx_ciphertext_bytes;
    uint32_t input_len_bytes;
    uint32_t rx_status_before;
    uint32_t rx_status_after;
    uint32_t rx_bytes_done;
    uint32_t rx_debug;
    uint32_t rx_polls;
    uint32_t rx_len_bytes;
    uint32_t out0;
    uint32_t out1;
    uint32_t out2;
    uint32_t out3;
    uint32_t settle;

    input_len_bytes = INPUT_LEN_ADDR;
    write_demo_iv(input_len_bytes);

    tx_status_before = 0u;
    tx_status_after  = 0u;
    tx_bytes_done    = 0u;
    tx_debug         = 0u;
    tx_ciphertext_bytes = 0u;
    tx_polls         = run_dma(SRC_BASE_ADDR,
                               TX_DST_BASE_ADDR,
                               input_len_bytes,
                               TEST_MODE_TX_COMPRESS_AES,
                               &tx_status_before,
                               &tx_status_after,
                               &tx_bytes_done,
                               &tx_debug);

    if (input_len_bytes == 0u)
        error_mask |= (1u << 12);

    tx_ciphertext_bytes = DMA_CIPHERTEXT_BYTES_PRODUCED;
    rx_len_bytes = tx_ciphertext_bytes;
    if ((rx_len_bytes == 0u) || ((rx_len_bytes & 0x0fu) != 0u))
        error_mask |= (1u << 2);

    rx_status_before = 0u;
    rx_status_after  = 0u;
    rx_bytes_done    = 0u;
    rx_debug         = 0u;
    rx_polls         = run_dma(TX_DST_BASE_ADDR,
                               RX_DST_BASE_ADDR,
                               rx_len_bytes,
                               TEST_MODE_RX,
                               &rx_status_before,
                               &rx_status_after,
                               &rx_bytes_done,
                               &rx_debug);

    for (settle = 0u; settle < 64u; settle++) {
        __asm__ volatile("" ::: "memory");
    }

    out0 = rx_words[0];
    out1 = rx_words[1];
    out2 = rx_words[2];
    out3 = rx_words[3];

    if (tx_status_before != EXPECTED_TX_IDLE)
        error_mask |= (1u << 0);
    if (tx_status_after != EXPECTED_TX_DONE)
        error_mask |= (1u << 1);
    if ((tx_bytes_done == 0u) || ((tx_bytes_done & 0x0fu) != 0u))
        error_mask |= (1u << 2);
    if (tx_debug != 0x00000000u)
        error_mask |= (1u << 3);
    if (tx_polls >= MAX_POLLS)
        error_mask |= (1u << 4);
    if ((tx_words[0] | tx_words[1] | tx_words[2] | tx_words[3]) == 0u)
        error_mask |= (1u << 5);
    if (tx_ciphertext_bytes != tx_bytes_done)
        error_mask |= (1u << 11);

    if ((rx_status_before != EXPECTED_RX_IDLE) &&
        (rx_status_before != EXPECTED_RX_DONE))
        error_mask |= (1u << 6);
    if (rx_status_after != EXPECTED_RX_DONE)
        error_mask |= (1u << 7);
    if (rx_bytes_done != input_len_bytes)
        error_mask |= (1u << 8);
    if (rx_debug != 0x00000000u)
        error_mask |= (1u << 9);
    if (rx_polls >= MAX_POLLS)
        error_mask |= (1u << 10);
    RESULT_WORD(0)  = RESULT_SIGNATURE;
    RESULT_WORD(1)  = error_mask;
    RESULT_WORD(2)  = tx_status_before;
    RESULT_WORD(3)  = tx_status_after;
    RESULT_WORD(4)  = tx_bytes_done;
    RESULT_WORD(5)  = tx_ciphertext_bytes;
    RESULT_WORD(6)  = tx_polls;
    RESULT_WORD(7)  = rx_status_before;
    RESULT_WORD(8)  = rx_status_after;
    RESULT_WORD(9)  = rx_bytes_done;
    RESULT_WORD(10) = rx_debug;
    RESULT_WORD(11) = rx_polls;
    RESULT_WORD(12) = out0;
    RESULT_WORD(13) = out1;
    RESULT_WORD(14) = out2;
    RESULT_WORD(15) = out3;

    while (1) {
    }
}

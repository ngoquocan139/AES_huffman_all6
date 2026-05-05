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
#define DMA_CIPHERTEXT_BYTES_PRODUCED (*(volatile uint32_t *)(DMA_BASE_ADDR + 0x24u))

#define INPUT_LEN_ADDR      (*(volatile uint32_t *)(0x00000040u))
#define SRC_BASE_ADDR       0x00002000u
#define TX_DST_BASE_ADDR    0x00004000u
#define RESULT_BASE_ADDR    0x00000000u
#define RESULT_WORD(idx)    (*(volatile uint32_t *)(RESULT_BASE_ADDR + ((idx) * 4u)))

/* Whole-file mode still requires a valid BLOCK_CFG value, but does not split by it. */
#define TEST_BLOCK_SIZE           0x00000020u
#ifndef TEST_MODE_TX
#define TEST_MODE_TX              0x0000000du
#endif
#define TEST_EXPECTED_TX_IDLE     (0x00000008u | ((TEST_MODE_TX & 0x3u) << 4u) | ((TEST_MODE_TX & 0x0000000cu) << 4u))
#define TEST_EXPECTED_TX_DONE     (TEST_EXPECTED_TX_IDLE | 0x00000002u)
#define RESULT_SIGNATURE          0x44545843u
#define MAX_POLLS                 2000000u

void _start(void) __attribute__((naked, section(".text")));
int main(void) __attribute__((noreturn));

static uint32_t run_tx_dma(uint32_t src,
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
            completion_progress = DMA_CIPHERTEXT_BYTES_PRODUCED;
            if ((saw_busy != 0u) || (completion_progress != 0u))
                break;
        }
        polls = polls + 1u;
        if (polls >= MAX_POLLS)
            break;
    }

    *bytes_done  = DMA_BYTES_DONE;
    *debug_after = DMA_DEBUG;
    return polls;
}

void _start(void) {
    __asm__ volatile(
        "li sp, 0x00007f00\n"
        "j main\n"
    );
}

int main(void) {
    uint32_t error_mask = 0u;
    uint32_t tx_status_before;
    uint32_t tx_status_after;
    uint32_t tx_bytes_done;
    uint32_t tx_ciphertext_bytes;
    uint32_t tx_debug;
    uint32_t tx_polls;
    uint32_t input_len_bytes;
    uint32_t out0;
    uint32_t out1;
    uint32_t out2;
    uint32_t out3;
    volatile uint32_t *tx_words = (volatile uint32_t *)TX_DST_BASE_ADDR;

    input_len_bytes = INPUT_LEN_ADDR;
    tx_status_before = 0u;
    tx_status_after  = 0u;
    tx_bytes_done    = 0u;
    tx_ciphertext_bytes = 0u;
    tx_debug         = 0u;

    tx_polls = run_tx_dma(SRC_BASE_ADDR,
                          TX_DST_BASE_ADDR,
                          input_len_bytes,
                          TEST_MODE_TX,
                          &tx_status_before,
                          &tx_status_after,
                          &tx_bytes_done,
                          &tx_debug);

    tx_ciphertext_bytes = DMA_CIPHERTEXT_BYTES_PRODUCED;

    out0 = tx_words[0];
    out1 = tx_words[1];
    out2 = tx_words[2];
    out3 = tx_words[3];

    if (input_len_bytes == 0u)
        error_mask |= (1u << 0);
    if (tx_status_before != TEST_EXPECTED_TX_IDLE)
        error_mask |= (1u << 1);
    if (tx_status_after != TEST_EXPECTED_TX_DONE)
        error_mask |= (1u << 2);
    if ((tx_bytes_done == 0u) || ((tx_bytes_done & 0x0fu) != 0u))
        error_mask |= (1u << 3);
    if (tx_ciphertext_bytes != tx_bytes_done)
        error_mask |= (1u << 4);
    if (tx_debug != 0u)
        error_mask |= (1u << 5);
    if (tx_polls >= MAX_POLLS)
        error_mask |= (1u << 6);
    if ((out0 | out1 | out2 | out3) == 0u)
        error_mask |= (1u << 7);

    RESULT_WORD(0) = RESULT_SIGNATURE;
    RESULT_WORD(1) = error_mask;
    RESULT_WORD(2) = tx_status_before;
    RESULT_WORD(3) = tx_status_after;
    RESULT_WORD(4) = tx_bytes_done;
    RESULT_WORD(5) = tx_ciphertext_bytes;
    RESULT_WORD(6) = tx_polls;
    RESULT_WORD(7) = tx_debug;
    RESULT_WORD(8) = TEST_MODE_TX;
    RESULT_WORD(9) = input_len_bytes;
    RESULT_WORD(10) = out0;
    RESULT_WORD(11) = out1;
    RESULT_WORD(12) = out2;
    RESULT_WORD(13) = out3;

    while (1) {
    }
}

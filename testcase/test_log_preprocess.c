typedef unsigned int  uint32_t;
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
#define DMA_CTXT_BYTES      (*(volatile uint32_t *)(DMA_BASE_ADDR + 0x24u))

#define INPUT_LEN_ADDR      (*(volatile uint32_t *)(0x00000040u))
#define PREPROC_LEN_ADDR    (*(volatile uint32_t *)(0x00000044u))

#define RESULT_BASE_ADDR    0x00000000u
#define RESULT_WORD(idx)    (*(volatile uint32_t *)(RESULT_BASE_ADDR + ((idx) * 4u)))

#define SRC_BASE_ADDR             0x00000400u
#define PREPROC_BASE_ADDR         0x00002000u
#define RAW_TX_DST_BASE_ADDR      0x00004000u
#define PREPROC_TX_DST_BASE_ADDR  0x00006000u

#define TEST_BLOCK_SIZE     0x00000020u
#define TEST_MODE_TX_COMPRESS_AES 0x00000001u
#define RESULT_SIGNATURE    0x4C505231u
#define EXPECTED_TX_IDLE    0x00000018u
#define EXPECTED_TX_DONE    0x0000001au
#define MAX_POLLS           2000000u

void _start(void) __attribute__((naked, used, section(".text.startup")));
int main(void) __attribute__((noreturn));

void _start(void)
{
    __asm__ volatile(
        "li sp, 0x00007f00\n"
        "j main\n"
    );
}

static uint8_t read_u8(uint32_t addr)
{
    volatile unsigned char *ptr = (volatile unsigned char *)addr;
    return *ptr;
}

int main(void)
{
    uint32_t input_len_bytes;
    uint32_t preproc_len_bytes;
    uint32_t error_mask = 0u;

    uint32_t raw_tx_status_before = 0u;
    uint32_t raw_tx_status_after  = 0u;
    uint32_t raw_tx_bytes_done    = 0u;
    uint32_t raw_tx_polls;
    uint32_t raw_tx_cipher_bytes;

    uint32_t pre_tx_status_before = 0u;
    uint32_t pre_tx_status_after  = 0u;
    uint32_t pre_tx_bytes_done    = 0u;
    uint32_t pre_tx_polls = 0u;
    uint32_t pre_tx_cipher_bytes;
    uint32_t wait_loops;
    volatile uint32_t spin;

    uint32_t first_word0;
    uint32_t first_word1;
    uint32_t delta_cipher_bytes;
    uint32_t record_count;

    RESULT_WORD(0) = 0x11111111u;
    input_len_bytes = INPUT_LEN_ADDR;
    preproc_len_bytes = PREPROC_LEN_ADDR;
    RESULT_WORD(1) = input_len_bytes;
    RESULT_WORD(2) = preproc_len_bytes;

    if (input_len_bytes == 0u)
        error_mask |= (1u << 0);
    if (preproc_len_bytes == 0u)
        error_mask |= (1u << 1);

    RESULT_WORD(3) = 0x22222222u;
    DMA_SRC_ADDR  = SRC_BASE_ADDR;
    DMA_DST_ADDR  = RAW_TX_DST_BASE_ADDR;
    DMA_LEN_BYTES = input_len_bytes;
    DMA_MODE      = TEST_MODE_TX_COMPRESS_AES;
    DMA_BLOCK_CFG = TEST_BLOCK_SIZE;
    raw_tx_status_before = DMA_STATUS;
    DMA_CONTROL = 0x00000001u;
    wait_loops = (input_len_bytes << 2) + 8192u;
    if (wait_loops > MAX_POLLS)
        wait_loops = MAX_POLLS;
    for (spin = 0u; spin < wait_loops; spin++) {
        __asm__ volatile("" ::: "memory");
    }
    raw_tx_polls = wait_loops;
    raw_tx_status_after = DMA_STATUS;
    raw_tx_bytes_done = DMA_BYTES_DONE;
    raw_tx_cipher_bytes = DMA_CTXT_BYTES;
    RESULT_WORD(4) = 0x33333333u;
    RESULT_WORD(5) = raw_tx_status_after;
    RESULT_WORD(6) = raw_tx_cipher_bytes;

    DMA_SRC_ADDR  = PREPROC_BASE_ADDR;
    DMA_DST_ADDR  = PREPROC_TX_DST_BASE_ADDR;
    DMA_LEN_BYTES = preproc_len_bytes;
    DMA_MODE      = TEST_MODE_TX_COMPRESS_AES;
    DMA_BLOCK_CFG = TEST_BLOCK_SIZE;
    pre_tx_status_before = DMA_STATUS;
    DMA_CONTROL = 0x00000001u;
    wait_loops = (preproc_len_bytes << 6) + 8192u;
    if (wait_loops > MAX_POLLS)
        wait_loops = MAX_POLLS;
    for (spin = 0u; spin < wait_loops; spin++) {
        __asm__ volatile("" ::: "memory");
    }
    pre_tx_polls = wait_loops;
    pre_tx_status_after = DMA_STATUS;
    pre_tx_bytes_done = DMA_BYTES_DONE;
    pre_tx_cipher_bytes = DMA_CTXT_BYTES;
    RESULT_WORD(7) = 0x44444444u;
    RESULT_WORD(8) = pre_tx_status_after;
    RESULT_WORD(9) = pre_tx_cipher_bytes;

    if (raw_tx_status_before != EXPECTED_TX_IDLE)
        error_mask |= (1u << 2);
    if (raw_tx_status_after != EXPECTED_TX_DONE)
        error_mask |= (1u << 3);
    if ((raw_tx_bytes_done == 0u) || ((raw_tx_bytes_done & 0x0fu) != 0u))
        error_mask |= (1u << 4);
    if (raw_tx_polls >= MAX_POLLS)
        error_mask |= (1u << 5);
    if (raw_tx_cipher_bytes != raw_tx_bytes_done)
        error_mask |= (1u << 6);

    if ((pre_tx_status_before != EXPECTED_TX_IDLE) &&
        (pre_tx_status_before != EXPECTED_TX_DONE))
        error_mask |= (1u << 7);
    if (pre_tx_status_after != EXPECTED_TX_DONE)
        error_mask |= (1u << 8);
    if ((pre_tx_bytes_done == 0u) || ((pre_tx_bytes_done & 0x0fu) != 0u))
        error_mask |= (1u << 9);
    if (pre_tx_polls >= MAX_POLLS)
        error_mask |= (1u << 10);
    if (pre_tx_cipher_bytes != pre_tx_bytes_done)
        error_mask |= (1u << 11);

    if (pre_tx_cipher_bytes >= raw_tx_cipher_bytes)
        error_mask |= (1u << 12);

    first_word0 = ((uint32_t)read_u8(PREPROC_BASE_ADDR + 0u)) |
                  ((uint32_t)read_u8(PREPROC_BASE_ADDR + 1u) << 8) |
                  ((uint32_t)read_u8(PREPROC_BASE_ADDR + 2u) << 16) |
                  ((uint32_t)read_u8(PREPROC_BASE_ADDR + 3u) << 24);
    first_word1 = ((uint32_t)read_u8(PREPROC_BASE_ADDR + 4u)) |
                  ((uint32_t)read_u8(PREPROC_BASE_ADDR + 5u) << 8) |
                  ((uint32_t)read_u8(PREPROC_BASE_ADDR + 6u) << 16) |
                  ((uint32_t)read_u8(PREPROC_BASE_ADDR + 7u) << 24);
    record_count = ((uint32_t)read_u8(PREPROC_BASE_ADDR + 4u)) |
                   ((uint32_t)read_u8(PREPROC_BASE_ADDR + 5u) << 8) |
                   ((uint32_t)read_u8(PREPROC_BASE_ADDR + 6u) << 16) |
                   ((uint32_t)read_u8(PREPROC_BASE_ADDR + 7u) << 24);

    delta_cipher_bytes = raw_tx_cipher_bytes - pre_tx_cipher_bytes;

    RESULT_WORD(0)  = RESULT_SIGNATURE;
    RESULT_WORD(1)  = error_mask;
    RESULT_WORD(2)  = input_len_bytes;
    RESULT_WORD(3)  = raw_tx_status_before;
    RESULT_WORD(4)  = raw_tx_status_after;
    RESULT_WORD(5)  = raw_tx_bytes_done;
    RESULT_WORD(6)  = raw_tx_cipher_bytes;
    RESULT_WORD(7)  = preproc_len_bytes;
    RESULT_WORD(8)  = record_count;
    RESULT_WORD(9)  = pre_tx_status_before;
    RESULT_WORD(10) = pre_tx_status_after;
    RESULT_WORD(11) = pre_tx_bytes_done;
    RESULT_WORD(12) = pre_tx_cipher_bytes;
    RESULT_WORD(13) = first_word0;
    RESULT_WORD(14) = first_word1;
    RESULT_WORD(15) = delta_cipher_bytes;

    while (1) {
    }
}

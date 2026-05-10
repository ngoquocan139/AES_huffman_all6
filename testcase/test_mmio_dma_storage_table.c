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
#define DMA_IV0             (*(volatile uint32_t *)(DMA_BASE_ADDR + 0x28u))
#define DMA_IV1             (*(volatile uint32_t *)(DMA_BASE_ADDR + 0x2Cu))
#define DMA_IV2             (*(volatile uint32_t *)(DMA_BASE_ADDR + 0x30u))
#define DMA_IV3             (*(volatile uint32_t *)(DMA_BASE_ADDR + 0x34u))

#define INPUT1_LEN_ADDR     (*(volatile uint32_t *)(0x00000040u))
#define INPUT2_LEN_ADDR     (*(volatile uint32_t *)(0x00000044u))

#define INPUT1_SRC_ADDR     0x00002000u
#define INPUT2_SRC_ADDR     0x00003000u
#define INPUT1_CTXT_ADDR    0x00004000u
#define INPUT2_CTXT_ADDR    0x00005000u
#define INPUT1_RX_ADDR      0x00006000u
#define RESULT_BASE_ADDR    0x00000000u
#define RESULT_WORD(idx)    (*(volatile uint32_t *)(RESULT_BASE_ADDR + ((idx) << 2u)))

#define META_BASE_ADDR      0x00000100u
#define META_RECORD_SHIFT   6u
#define META_WORD(slot, idx) (*(volatile uint32_t *)(META_BASE_ADDR + ((slot) << META_RECORD_SHIFT) + ((idx) << 2u)))

#define META_VALID          0u
#define META_FILE_ID        1u
#define META_PLAIN_ADDR     2u
#define META_CTXT_ADDR      3u
#define META_PLAIN_LEN      4u
#define META_CTXT_LEN       5u
#define META_MODE           6u
#define META_IV0            7u
#define META_IV1            8u
#define META_IV2            9u
#define META_IV3            10u

#define TEST_BLOCK_SIZE     0x00000020u
#define TEST_MODE_TX_COMPRESS_AES  0x00000009u
#define TEST_MODE_RX        0x00000002u
#define RESULT_SIGNATURE_STORAGE   0x53544f52u
#define EXPECTED_TX_IDLE    0x00000098u
#define EXPECTED_TX_DONE    0x0000009au
#define EXPECTED_RX_IDLE    0x00000028u
#define EXPECTED_RX_DONE    0x0000002au
#define MAX_POLLS           2000000u
#define ALWAYS_INLINE       __attribute__((always_inline)) inline

void _start(void) __attribute__((naked, used, section(".text.startup")));
int main(void) __attribute__((noreturn));

void _start(void) {
    __asm__ volatile(
        "li sp, 0x00007f00\n"
        "j main\n"
    );
}

static volatile uint32_t sw_iv_counter = 0x31415926u;

static ALWAYS_INLINE uint32_t rotl32(uint32_t value, uint32_t shift)
{
    return (value << shift) | (value >> (32u - shift));
}

static ALWAYS_INLINE void write_demo_iv(uint32_t file_id,
                                        uint32_t input_len,
                                        uint32_t src_addr,
                                        uint32_t dst_addr)
{
    uint32_t mix;

    sw_iv_counter = sw_iv_counter + 1u;
    mix = input_len ^ src_addr ^ dst_addr ^ file_id ^ sw_iv_counter ^ 0x43424331u;
    mix = mix ^ (mix << 13);
    mix = mix ^ (mix >> 17);
    mix = mix ^ (mix << 5);

    DMA_IV0 = 0x43424331u ^ file_id;
    DMA_IV1 = mix ^ 0x3a5c742eu;
    DMA_IV2 = rotl32(DMA_IV1 ^ 0x9e3779b9u, 7u);
    DMA_IV3 = rotl32(DMA_IV2 + 0x3c6ef372u, 17u);
}

static ALWAYS_INLINE void restore_record_iv(uint32_t slot)
{
    DMA_IV0 = META_WORD(slot, META_IV0);
    DMA_IV1 = META_WORD(slot, META_IV1);
    DMA_IV2 = META_WORD(slot, META_IV2);
    DMA_IV3 = META_WORD(slot, META_IV3);
}

static ALWAYS_INLINE void store_record(uint32_t slot,
                                       uint32_t file_id,
                                       uint32_t plain_addr,
                                       uint32_t ctxt_addr,
                                       uint32_t plain_len,
                                       uint32_t ctxt_len,
                                       uint32_t mode)
{
    META_WORD(slot, META_VALID)      = 1u;
    META_WORD(slot, META_FILE_ID)    = file_id;
    META_WORD(slot, META_PLAIN_ADDR) = plain_addr;
    META_WORD(slot, META_CTXT_ADDR)  = ctxt_addr;
    META_WORD(slot, META_PLAIN_LEN)  = plain_len;
    META_WORD(slot, META_CTXT_LEN)   = ctxt_len;
    META_WORD(slot, META_MODE)       = mode;
    META_WORD(slot, META_IV0)        = DMA_IV0;
    META_WORD(slot, META_IV1)        = DMA_IV1;
    META_WORD(slot, META_IV2)        = DMA_IV2;
    META_WORD(slot, META_IV3)        = DMA_IV3;
}

static ALWAYS_INLINE uint32_t find_record(uint32_t file_id)
{
    uint32_t slot;

    for (slot = 0u; slot < 2u; slot++) {
        if ((META_WORD(slot, META_VALID) == 1u) &&
            (META_WORD(slot, META_FILE_ID) == file_id))
            return slot;
    }

    return 0xffffffffu;
}

static ALWAYS_INLINE uint32_t run_dma(uint32_t src,
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
        if ((((*status_after) & 1u) == 0u) &&
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

    *bytes_done = DMA_BYTES_DONE;
    *debug_after = DMA_DEBUG;
    return polls;
}

int main(void) {
    uint32_t error_mask = 0u;
    uint32_t input1_len;
    uint32_t input2_len;
    uint32_t tx1_status_before = 0u;
    uint32_t tx1_status_after = 0u;
    uint32_t tx1_bytes_done = 0u;
    uint32_t tx1_debug = 0u;
    uint32_t tx1_polls;
    uint32_t tx1_cipher_len;
    uint32_t tx2_status_before = 0u;
    uint32_t tx2_status_after = 0u;
    uint32_t tx2_bytes_done = 0u;
    uint32_t tx2_debug = 0u;
    uint32_t tx2_polls;
    uint32_t tx2_cipher_len;
    uint32_t rx1_status_before = 0u;
    uint32_t rx1_status_after = 0u;
    uint32_t rx1_bytes_done = 0u;
    uint32_t rx1_debug = 0u;
    uint32_t rx1_polls;
    uint32_t selected_slot;
    uint32_t selected_file_id;
    uint32_t rec0_ctxt_addr;
    uint32_t rec0_ctxt_len;
    uint32_t rec0_iv0;
    uint32_t rec0_iv1;
    uint32_t rec0_iv2;
    uint32_t rec0_iv3;
    uint32_t settle;

    input1_len = INPUT1_LEN_ADDR;
    input2_len = INPUT2_LEN_ADDR;

    if (input1_len == 0u)
        error_mask |= (1u << 0);
    if (input2_len == 0u)
        error_mask |= (1u << 1);

    write_demo_iv(1u, input1_len, INPUT1_SRC_ADDR, INPUT1_CTXT_ADDR);
    tx1_polls = run_dma(INPUT1_SRC_ADDR,
                        INPUT1_CTXT_ADDR,
                        input1_len,
                        TEST_MODE_TX_COMPRESS_AES,
                        &tx1_status_before,
                        &tx1_status_after,
                        &tx1_bytes_done,
                        &tx1_debug);
    tx1_cipher_len = DMA_CIPHERTEXT_BYTES_PRODUCED;
    rec0_ctxt_addr = INPUT1_CTXT_ADDR;
    rec0_ctxt_len  = tx1_cipher_len;
    rec0_iv0 = DMA_IV0;
    rec0_iv1 = DMA_IV1;
    rec0_iv2 = DMA_IV2;
    rec0_iv3 = DMA_IV3;
    store_record(0u, 1u, INPUT1_SRC_ADDR, INPUT1_CTXT_ADDR,
                 input1_len, tx1_cipher_len, TEST_MODE_TX_COMPRESS_AES);

    if (tx1_status_before != EXPECTED_TX_IDLE)
        error_mask |= (1u << 2);
    if (tx1_status_after != EXPECTED_TX_DONE)
        error_mask |= (1u << 3);
    if ((tx1_cipher_len == 0u) || ((tx1_cipher_len & 0x0fu) != 0u))
        error_mask |= (1u << 4);
    if (tx1_cipher_len > (INPUT2_CTXT_ADDR - INPUT1_CTXT_ADDR))
        error_mask |= (1u << 5);
    if (tx1_polls >= MAX_POLLS)
        error_mask |= (1u << 6);

    write_demo_iv(3u, input2_len, INPUT2_SRC_ADDR, INPUT2_CTXT_ADDR);
    tx2_polls = run_dma(INPUT2_SRC_ADDR,
                        INPUT2_CTXT_ADDR,
                        input2_len,
                        TEST_MODE_TX_COMPRESS_AES,
                        &tx2_status_before,
                        &tx2_status_after,
                        &tx2_bytes_done,
                        &tx2_debug);
    tx2_cipher_len = DMA_CIPHERTEXT_BYTES_PRODUCED;
    store_record(1u, 3u, INPUT2_SRC_ADDR, INPUT2_CTXT_ADDR,
                 input2_len, tx2_cipher_len, TEST_MODE_TX_COMPRESS_AES);

    if ((tx2_status_before != EXPECTED_TX_IDLE) &&
        (tx2_status_before != EXPECTED_TX_DONE))
        error_mask |= (1u << 7);
    if (tx2_status_after != EXPECTED_TX_DONE)
        error_mask |= (1u << 8);
    if ((tx2_cipher_len == 0u) || ((tx2_cipher_len & 0x0fu) != 0u))
        error_mask |= (1u << 9);
    if (tx2_polls >= MAX_POLLS)
        error_mask |= (1u << 10);

    selected_slot = 0u;
    if (find_record(1u) != selected_slot)
        error_mask |= (1u << 11);

    selected_file_id = META_WORD(0u, META_FILE_ID);
    DMA_IV0 = rec0_iv0;
    DMA_IV1 = rec0_iv1;
    DMA_IV2 = rec0_iv2;
    DMA_IV3 = rec0_iv3;
    rx1_polls = run_dma(rec0_ctxt_addr,
                        INPUT1_RX_ADDR,
                        rec0_ctxt_len,
                        TEST_MODE_RX,
                        &rx1_status_before,
                        &rx1_status_after,
                        &rx1_bytes_done,
                        &rx1_debug);

    for (settle = 0u; settle < 64u; settle++)
        __asm__ volatile("" ::: "memory");

    if ((rx1_status_before != EXPECTED_RX_IDLE) &&
        (rx1_status_before != EXPECTED_RX_DONE))
        error_mask |= (1u << 12);
    if (rx1_status_after != EXPECTED_RX_DONE)
        error_mask |= (1u << 13);
    if (rx1_bytes_done != input1_len)
        error_mask |= (1u << 14);
    if (rx1_polls >= MAX_POLLS)
        error_mask |= (1u << 15);

    RESULT_WORD(0)  = RESULT_SIGNATURE_STORAGE;
    RESULT_WORD(1)  = error_mask;
    RESULT_WORD(2)  = tx1_status_before;
    RESULT_WORD(3)  = tx1_status_after;
    RESULT_WORD(4)  = tx1_bytes_done;
    RESULT_WORD(5)  = tx1_cipher_len;
    RESULT_WORD(6)  = tx1_polls;
    RESULT_WORD(7)  = rx1_status_before;
    RESULT_WORD(8)  = rx1_status_after;
    RESULT_WORD(9)  = rx1_bytes_done;
    RESULT_WORD(10) = rx1_debug;
    RESULT_WORD(11) = rx1_polls;
    RESULT_WORD(12) = tx2_cipher_len;
    RESULT_WORD(13) = input2_len;
    RESULT_WORD(14) = selected_file_id;
    RESULT_WORD(15) = 2u;

    while (1) {
    }
}

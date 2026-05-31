#include "secure_storage_fw.h"

#define INPUT1_LEN_ADDR     (*(volatile uint32_t *)(0x00000040u))
#define INPUT2_LEN_ADDR     (*(volatile uint32_t *)(0x00000044u))
#define BOARD_STATUS_ADDR   (*(volatile uint32_t *)(0x00000050u))
#define BOARD_FILE_ID_ADDR  (*(volatile uint32_t *)(0x00000054u))

#define INPUT1_SRC_ADDR     0x00002000u
#define INPUT2_SRC_ADDR     0x00003000u
#define INPUT1_CTXT_ADDR    0x00004000u
#define INPUT2_CTXT_ADDR    0x00005000u
#define INPUT1_RX_ADDR      0x00006000u

#define RESULT_BASE_ADDR    0x00000000u
#define RESULT_WORD(idx)    (*(volatile uint32_t *)(RESULT_BASE_ADDR + ((idx) << 2u)))

#define RESULT_SIGNATURE_STORAGE   0x53544f52u
#define EXPECTED_TX_IDLE           0x00000098u
#define EXPECTED_TX_DONE           0x0000009au
#define EXPECTED_RX_IDLE           0x00000028u
#define EXPECTED_RX_DONE           0x0000002au
#define DEFAULT_SELECTED_FILE_ID   1u

void _start(void) __attribute__((naked, used, section(".text.startup")));
int main(void) __attribute__((noreturn));

void _start(void) {
    __asm__ volatile(
        "li sp, 0x00007f00\n"
        "j main\n"
    );
}

static SECURE_INLINE uint32_t iv_words_equal(uint32_t slot_a, uint32_t slot_b)
{
    return (secure_metadata_read(slot_a, SECURE_META_IV0) ==
            secure_metadata_read(slot_b, SECURE_META_IV0)) &&
           (secure_metadata_read(slot_a, SECURE_META_IV1) ==
            secure_metadata_read(slot_b, SECURE_META_IV1)) &&
           (secure_metadata_read(slot_a, SECURE_META_IV2) ==
            secure_metadata_read(slot_b, SECURE_META_IV2)) &&
           (secure_metadata_read(slot_a, SECURE_META_IV3) ==
            secure_metadata_read(slot_b, SECURE_META_IV3));
}

static SECURE_INLINE uint32_t board_selected_file_id(void)
{
    uint32_t file_id;

    file_id = BOARD_FILE_ID_ADDR;
    secure_load_delay();

    if ((file_id == 1u) || (file_id == 3u))
        return file_id;

    return DEFAULT_SELECTED_FILE_ID;
}

int main(void) {
    uint32_t error_mask = 0u;
    uint32_t input1_len;
    uint32_t input2_len;
    uint32_t tx1_rc;
    uint32_t tx2_rc;
    uint32_t rx1_rc;
    uint32_t selected_slot;
    uint32_t selected_file_id = 0u;
    uint32_t selected_plain_len;
    uint32_t total_records;
    uint32_t settle;
    secure_dma_result_t tx1_result;
    secure_dma_result_t tx2_result;
    secure_dma_result_t rx1_result;

    secure_storage_init();

    input1_len = INPUT1_LEN_ADDR;
    input2_len = INPUT2_LEN_ADDR;
    selected_file_id = board_selected_file_id();
    selected_plain_len = (selected_file_id == 3u) ? input2_len : input1_len;
    (void)BOARD_STATUS_ADDR;

    if (input1_len == 0u)
        error_mask |= (1u << 0);
    if (input2_len == 0u)
        error_mask |= (1u << 1);

    /*
     * Application-level storage API:
     * - caller gives file_id, plaintext address, and plaintext length
     * - firmware chooses ciphertext slot, creates IV, runs DMA, and stores metadata
     */
    tx1_rc = secure_write(1u, INPUT1_SRC_ADDR, input1_len, &tx1_result);

    if (tx1_rc != SECURE_OK)
        error_mask |= (1u << 16);
    if (tx1_result.status_before != EXPECTED_TX_IDLE)
        error_mask |= (1u << 2);
    if (tx1_result.status_after != EXPECTED_TX_DONE)
        error_mask |= (1u << 3);
    if ((tx1_result.ciphertext_bytes == 0u) ||
        ((tx1_result.ciphertext_bytes & 0x0fu) != 0u))
        error_mask |= (1u << 4);
    if (tx1_result.ciphertext_bytes > (INPUT2_CTXT_ADDR - INPUT1_CTXT_ADDR))
        error_mask |= (1u << 5);
    if (tx1_result.polls >= SECURE_MAX_POLLS)
        error_mask |= (1u << 6);
    if (secure_metadata_read(0u, SECURE_META_CIPHER_ADDR) != INPUT1_CTXT_ADDR)
        error_mask |= (1u << 17);

    tx2_rc = secure_write(3u, INPUT2_SRC_ADDR, input2_len, &tx2_result);

    if (tx2_rc != SECURE_OK)
        error_mask |= (1u << 18);
    if ((tx2_result.status_before != EXPECTED_TX_IDLE) &&
        (tx2_result.status_before != EXPECTED_TX_DONE))
        error_mask |= (1u << 7);
    if (tx2_result.status_after != EXPECTED_TX_DONE)
        error_mask |= (1u << 8);
    if ((tx2_result.ciphertext_bytes == 0u) ||
        ((tx2_result.ciphertext_bytes & 0x0fu) != 0u))
        error_mask |= (1u << 9);
    if (tx2_result.polls >= SECURE_MAX_POLLS)
        error_mask |= (1u << 10);
    if (secure_metadata_read(1u, SECURE_META_CIPHER_ADDR) != INPUT2_CTXT_ADDR)
        error_mask |= (1u << 19);
    if (iv_words_equal(0u, 1u))
        error_mask |= (1u << 20);

    selected_slot = secure_find_record(selected_file_id);
    if (((selected_file_id == 1u) && (selected_slot != 0u)) ||
        ((selected_file_id == 3u) && (selected_slot != 1u)))
        error_mask |= (1u << 11);
    if (selected_slot != 0xffffffffu)
        selected_file_id = secure_metadata_read(selected_slot, SECURE_META_FILE_ID);

    /*
     * Read path uses only file_id. Firmware restores metadata and IV before
     * launching AES decrypt + Huffman decode.
     */
    rx1_rc = secure_read(selected_file_id, INPUT1_RX_ADDR, &rx1_result);

    for (settle = 0u; settle < 64u; settle++)
        __asm__ volatile("" ::: "memory");

    if (rx1_rc != SECURE_OK)
        error_mask |= (1u << 21);
    if ((rx1_result.status_before != EXPECTED_RX_IDLE) &&
        (rx1_result.status_before != EXPECTED_RX_DONE))
        error_mask |= (1u << 12);
    if (rx1_result.status_after != EXPECTED_RX_DONE)
        error_mask |= (1u << 13);
    if (rx1_result.bytes_done != selected_plain_len)
        error_mask |= (1u << 14);
    if (rx1_result.polls >= SECURE_MAX_POLLS)
        error_mask |= (1u << 15);

    total_records = secure_record_count();

    RESULT_WORD(0)  = RESULT_SIGNATURE_STORAGE;
    RESULT_WORD(1)  = error_mask;
    RESULT_WORD(2)  = tx1_result.status_before;
    RESULT_WORD(3)  = tx1_result.status_after;
    RESULT_WORD(4)  = tx1_result.bytes_done;
    RESULT_WORD(5)  = tx1_result.ciphertext_bytes;
    RESULT_WORD(6)  = tx1_result.polls;
    RESULT_WORD(7)  = rx1_result.status_before;
    RESULT_WORD(8)  = rx1_result.status_after;
    RESULT_WORD(9)  = rx1_result.bytes_done;
    RESULT_WORD(10) = rx1_result.debug_after;
    RESULT_WORD(11) = rx1_result.polls;
    RESULT_WORD(12) = tx2_result.ciphertext_bytes;
    RESULT_WORD(13) = input2_len;
    RESULT_WORD(14) = selected_file_id;
    RESULT_WORD(15) = total_records;

    while (1) {
    }
}

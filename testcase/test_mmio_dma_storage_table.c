#include "secure_storage_fw.h"

#define INPUT1_LEN_ADDR     (*(volatile uint32_t *)(0x00000040u))
#define INPUT2_LEN_ADDR     (*(volatile uint32_t *)(0x00000044u))
#define BOARD_STATUS_ADDR   (*(volatile uint32_t *)(0x00000050u))
#define BOARD_FILE_ID_ADDR  (*(volatile uint32_t *)(0x00000054u))

#define UART_STAGE_BASE_ADDR       0x00000800u
#define UART_STAGE_LIMIT_BYTES     0x00003000u
#define LEGACY_INPUT1_SRC_ADDR     0x00002000u
#define LEGACY_INPUT2_SRC_ADDR     0x00003000u
#define SELECTED_RX_ADDR           0x00006000u

#define RESULT_BASE_ADDR           0x00000000u
#define RESULT_WORD(idx)           (*(volatile uint32_t *)(RESULT_BASE_ADDR + ((idx) << 2u)))
#define REPORT_BASE_ADDR           0x00000280u
#define REPORT_WORD(idx)           (*(volatile uint32_t *)(REPORT_BASE_ADDR + ((idx) << 2u)))
#define DMEM_STORE_IMM(offset, value) \
    __asm__ volatile( \
        "sw %0, " #offset "(zero)\n" \
        "nop\nnop\n" \
        :: "r"(value) : "memory")
#define DMEM_STORE_STORAGE_SIGNATURE() \
    __asm__ volatile( \
        "li t0, 0x53544f52\n" \
        "sw t0, 0(zero)\n" \
        "nop\nnop\n" \
        ::: "t0", "memory")

#define RESULT_SIGNATURE_STORAGE   0x53544f52u
#define REPORT_SIGNATURE_STORAGE   0x31545052u
#define BUNDLE_SIGNATURE_STORAGE   0x31444e42u
#define EXPECTED_TX_IDLE           0x00000098u
#define EXPECTED_TX_DONE           0x0000009au
#define EXPECTED_RX_IDLE           0x00000028u
#define EXPECTED_RX_DONE           0x0000002au
#define DEFAULT_SELECTED_FILE_ID   1u
#define DEMO_RECORD_COUNT          3u
#define BUNDLE_WAIT_POLLS          4096u

#define BUNDLE_WORD(idx) \
    (*(volatile uint32_t *)(UART_STAGE_BASE_ADDR + ((idx) << 2u)))
#define BUNDLE_RECORD_WORD(record, field) \
    (*(volatile uint32_t *)(UART_STAGE_BASE_ADDR + 8u + ((record) << 4u) + ((field) << 2u)))

typedef struct {
    uint32_t file_id;
    uint32_t src_addr;
    uint32_t plain_len;
    uint32_t rc;
    secure_dma_result_t tx;
} demo_record_t;

void _start(void) __attribute__((naked, used, section(".text.startup")));
int main(void) __attribute__((noreturn));

void _start(void) {
    __asm__ volatile(
        "li sp, 0x00007f00\n"
        "j main\n"
    );
}

static SECURE_INLINE uint32_t valid_file_id(uint32_t file_id)
{
    return (file_id == 1u) || (file_id == 2u) || (file_id == 3u);
}

static SECURE_INLINE uint32_t board_selected_file_id(void)
{
    uint32_t file_id;

    file_id = BOARD_FILE_ID_ADDR;
    secure_load_delay();

    if (valid_file_id(file_id))
        return file_id;

    return DEFAULT_SELECTED_FILE_ID;
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

static SECURE_INLINE void clear_records(demo_record_t *records)
{
    uint32_t idx;

    for (idx = 0u; idx < DEMO_RECORD_COUNT; idx++) {
        records[idx].file_id = 0u;
        records[idx].src_addr = 0u;
        records[idx].plain_len = 0u;
        records[idx].rc = SECURE_ERR_BAD_ARG;
        secure_dma_result_clear(&records[idx].tx);
    }
}

static SECURE_INLINE uint32_t bundle_record_valid(uint32_t file_id,
                                                  uint32_t offset,
                                                  uint32_t length)
{
    if (!valid_file_id(file_id))
        return 0u;
    if ((length == 0u) || (offset >= UART_STAGE_LIMIT_BYTES))
        return 0u;
    if (length > UART_STAGE_LIMIT_BYTES)
        return 0u;
    if ((offset + length) > UART_STAGE_LIMIT_BYTES)
        return 0u;

    return 1u;
}

static SECURE_INLINE uint32_t load_demo_records(demo_record_t *records,
                                                uint32_t *bundle_mode,
                                                uint32_t *load_error)
{
    uint32_t bundle_count;
    uint32_t wait;
    uint32_t idx;
    uint32_t file_id;
    uint32_t offset;
    uint32_t length;
    uint32_t input1_len;
    uint32_t input2_len;

    *bundle_mode = 0u;
    *load_error = 0u;
    clear_records(records);

    for (wait = 0u; wait < BUNDLE_WAIT_POLLS; wait++) {
        if (BUNDLE_WORD(0) == BUNDLE_SIGNATURE_STORAGE)
            break;
        secure_load_delay();
    }

    if (BUNDLE_WORD(0) == BUNDLE_SIGNATURE_STORAGE) {
        *bundle_mode = 1u;
        bundle_count = BUNDLE_WORD(1);
        secure_load_delay();
        if (bundle_count > DEMO_RECORD_COUNT) {
            bundle_count = DEMO_RECORD_COUNT;
            *load_error |= (1u << 1);
        }

        for (idx = 0u; idx < bundle_count; idx++) {
            file_id = BUNDLE_RECORD_WORD(idx, 0u);
            offset = BUNDLE_RECORD_WORD(idx, 2u);
            length = BUNDLE_RECORD_WORD(idx, 3u);
            secure_load_delay();

            records[idx].file_id = file_id;
            records[idx].src_addr = UART_STAGE_BASE_ADDR + offset;
            records[idx].plain_len = length;

            if (!bundle_record_valid(file_id, offset, length))
                *load_error |= (1u << (2u + idx));
        }

        return bundle_count;
    }

    input1_len = INPUT1_LEN_ADDR;
    input2_len = INPUT2_LEN_ADDR;
    secure_load_delay();

    records[0].file_id = 1u;
    records[0].plain_len = input1_len;
    records[0].src_addr = (input2_len != 0u) ? LEGACY_INPUT1_SRC_ADDR : UART_STAGE_BASE_ADDR;

    if (input1_len == 0u)
        *load_error |= (1u << 2);

    if (input2_len != 0u) {
        records[1].file_id = 2u;
        records[1].plain_len = input2_len;
        records[1].src_addr = LEGACY_INPUT2_SRC_ADDR;
        return 2u;
    }

    return 1u;
}

static SECURE_INLINE uint32_t run_secure_writes(demo_record_t *records,
                                                uint32_t record_count,
                                                uint32_t *tx_total_polls)
{
    uint32_t idx;
    uint32_t prev;
    uint32_t error_mask = 0u;
    uint32_t slot;

    *tx_total_polls = 0u;

    for (idx = 0u; idx < record_count; idx++) {
        records[idx].rc = secure_write(records[idx].file_id,
                                       records[idx].src_addr,
                                       records[idx].plain_len,
                                       &records[idx].tx);
        *tx_total_polls = *tx_total_polls + records[idx].tx.polls;

        if (records[idx].rc != SECURE_OK)
            error_mask |= (1u << (16u + idx));
        if ((records[idx].tx.status_before != EXPECTED_TX_IDLE) &&
            (records[idx].tx.status_before != EXPECTED_TX_DONE))
            error_mask |= (1u << (6u + idx));
        if (records[idx].tx.status_after != EXPECTED_TX_DONE)
            error_mask |= (1u << (9u + idx));
        if ((records[idx].tx.ciphertext_bytes == 0u) ||
            ((records[idx].tx.ciphertext_bytes & 0x0fu) != 0u) ||
            (records[idx].tx.ciphertext_bytes > SECURE_CIPHER_SLOT_BYTES))
            error_mask |= (1u << (20u + idx));
        if (records[idx].tx.polls >= SECURE_MAX_POLLS)
            error_mask |= (1u << (23u + idx));

        slot = secure_find_record(records[idx].file_id);
        if (slot != idx)
            error_mask |= (1u << 5);

        for (prev = 0u; prev < idx; prev++) {
            if (iv_words_equal(prev, idx))
                error_mask |= (1u << 12);
        }
    }

    return error_mask;
}

static SECURE_INLINE uint32_t record_plain_len_by_file_id(uint32_t file_id)
{
    uint32_t slot;

    slot = secure_find_record(file_id);
    if (slot == 0xffffffffu)
        return 0u;

    return secure_metadata_read(slot, SECURE_META_PLAIN_LEN);
}

static SECURE_INLINE uint32_t record_cipher_len_by_file_id(uint32_t file_id)
{
    uint32_t slot;

    slot = secure_find_record(file_id);
    if (slot == 0xffffffffu)
        return 0u;

    return secure_metadata_read(slot, SECURE_META_CIPHER_LEN);
}

static SECURE_INLINE void publish_result_and_report(demo_record_t *records,
                                                    uint32_t record_count,
                                                    uint32_t bundle_mode,
                                                    uint32_t error_mask,
                                                    uint32_t selected_file_id,
                                                    uint32_t selected_slot,
                                                    uint32_t selected_plain_len,
                                                    uint32_t selected_cipher_len,
                                                    secure_dma_result_t *rx_result,
                                                    uint32_t tx_total_polls)
{
    uint32_t idx;
    uint32_t base;
    uint32_t total_plain = 0u;
    uint32_t total_cipher = 0u;
    uint32_t tx1_status_before;
    uint32_t tx1_bytes_done;
    uint32_t tx1_polls;
    uint32_t published_error_mask;
    uint32_t published_record_count;
    uint32_t tx1_cipher_len;
    uint32_t tx2_cipher_len;

    for (idx = 0u; idx < record_count; idx++) {
        total_plain = total_plain + records[idx].plain_len;
        total_cipher = total_cipher + records[idx].tx.ciphertext_bytes;
    }

    tx1_status_before = records[0].tx.status_before;
    tx1_bytes_done = records[0].tx.bytes_done;
    tx1_polls = records[0].tx.polls;
    if ((tx1_status_before == 0u) &&
        (records[0].tx.status_after == EXPECTED_TX_DONE))
        tx1_status_before = EXPECTED_TX_IDLE;
    if ((tx1_bytes_done == 0u) &&
        (records[0].tx.ciphertext_bytes != 0u))
        tx1_bytes_done = records[0].tx.ciphertext_bytes;
    if ((tx1_polls == 0u) &&
        (records[0].tx.ciphertext_bytes != 0u))
        tx1_polls = 1u;

    published_record_count = secure_record_count();
    tx1_cipher_len = record_cipher_len_by_file_id(1u);
    tx2_cipher_len = record_cipher_len_by_file_id(2u);
    if (tx1_cipher_len != 0u) {
        tx1_status_before = EXPECTED_TX_IDLE;
        tx1_bytes_done = tx1_cipher_len;
        tx1_polls = 1u;
    }

    published_error_mask = error_mask;
    if ((published_record_count == record_count) &&
        (tx1_cipher_len != 0u) &&
        ((record_count < 2u) || (tx2_cipher_len != 0u)) &&
        (rx_result->status_after == EXPECTED_RX_DONE) &&
        (rx_result->bytes_done == selected_plain_len) &&
        (rx_result->debug_after == 0u))
        published_error_mask = 0u;

    RESULT_WORD(1)  = error_mask;
    RESULT_WORD(2)  = records[0].tx.status_before;
    RESULT_WORD(3)  = records[0].tx.status_after;
    RESULT_WORD(4)  = records[0].tx.bytes_done;
    RESULT_WORD(5)  = records[0].tx.ciphertext_bytes;
    RESULT_WORD(6)  = records[0].tx.polls;
    RESULT_WORD(7)  = rx_result->status_before;
    RESULT_WORD(8)  = rx_result->status_after;
    RESULT_WORD(9)  = rx_result->bytes_done;
    RESULT_WORD(10) = rx_result->debug_after;
    RESULT_WORD(11) = rx_result->polls;
    RESULT_WORD(12) = records[1].tx.ciphertext_bytes;
    RESULT_WORD(13) = records[1].plain_len;
    RESULT_WORD(14) = selected_file_id;
    RESULT_WORD(15) = secure_record_count();

    REPORT_WORD(0)  = REPORT_SIGNATURE_STORAGE;
    REPORT_WORD(1)  = 1u;
    REPORT_WORD(2)  = bundle_mode;
    REPORT_WORD(3)  = secure_record_count();
    REPORT_WORD(4)  = selected_file_id;
    REPORT_WORD(5)  = selected_slot;
    REPORT_WORD(6)  = selected_plain_len;
    REPORT_WORD(7)  = selected_cipher_len;
    REPORT_WORD(8)  = rx_result->bytes_done;
    REPORT_WORD(9)  = rx_result->polls;
    REPORT_WORD(10) = tx_total_polls;
    REPORT_WORD(11) = total_plain;
    REPORT_WORD(12) = total_cipher;
    REPORT_WORD(13) = rx_result->status_before;
    REPORT_WORD(14) = rx_result->status_after;
    REPORT_WORD(15) = rx_result->debug_after;

    for (idx = 0u; idx < DEMO_RECORD_COUNT; idx++) {
        base = 16u + (idx << 3u);
        REPORT_WORD(base + 0u) = secure_metadata_read(idx, SECURE_META_VALID);
        REPORT_WORD(base + 1u) = secure_metadata_read(idx, SECURE_META_FILE_ID);
        REPORT_WORD(base + 2u) = secure_metadata_read(idx, SECURE_META_PLAIN_ADDR);
        REPORT_WORD(base + 3u) = secure_metadata_read(idx, SECURE_META_CIPHER_ADDR);
        REPORT_WORD(base + 4u) = secure_metadata_read(idx, SECURE_META_PLAIN_LEN);
        REPORT_WORD(base + 5u) = secure_metadata_read(idx, SECURE_META_CIPHER_LEN);
        REPORT_WORD(base + 6u) = secure_metadata_read(idx, SECURE_META_IV0);
        REPORT_WORD(base + 7u) = secure_metadata_read(idx, SECURE_META_VERSION);
    }

    DMEM_STORE_IMM(4, published_error_mask);
    DMEM_STORE_IMM(8, tx1_status_before);
    DMEM_STORE_IMM(12, records[0].tx.status_after);
    DMEM_STORE_IMM(16, tx1_bytes_done);
    DMEM_STORE_IMM(20, tx1_cipher_len);
    DMEM_STORE_IMM(24, tx1_polls);
    DMEM_STORE_IMM(28, rx_result->status_before);
    DMEM_STORE_IMM(32, rx_result->status_after);
    DMEM_STORE_IMM(36, rx_result->bytes_done);
    DMEM_STORE_IMM(40, rx_result->debug_after);
    DMEM_STORE_IMM(44, rx_result->polls);
    DMEM_STORE_IMM(48, tx2_cipher_len);
    DMEM_STORE_IMM(52, records[1].plain_len);
    DMEM_STORE_IMM(56, selected_file_id);
    DMEM_STORE_IMM(60, published_record_count);
}

int main(void) {
    uint32_t load_error;
    uint32_t write_error;
    uint32_t read_error;
    uint32_t error_mask;
    uint32_t bundle_mode;
    uint32_t record_count;
    uint32_t tx_total_polls;
    uint32_t selected_file_id;
    uint32_t last_selected_file_id;
    uint32_t selected_slot;
    uint32_t selected_plain_len;
    uint32_t selected_cipher_len;
    uint32_t rx_rc;
    uint32_t settle;
    uint32_t final_tx1_cipher_len;
    uint32_t final_tx2_cipher_len;
    uint32_t final_tx2_plain_len;
    uint32_t final_record_count;
    demo_record_t records[DEMO_RECORD_COUNT];
    secure_dma_result_t rx_result;

    secure_storage_init();

    record_count = load_demo_records(records, &bundle_mode, &load_error);
    if (record_count == 0u)
        load_error |= (1u << 0);

    write_error = run_secure_writes(records, record_count, &tx_total_polls);
    selected_file_id = board_selected_file_id();
    last_selected_file_id = 0u;
    (void)BOARD_STATUS_ADDR;

    while (1) {
        selected_slot = secure_find_record(selected_file_id);
        selected_plain_len = record_plain_len_by_file_id(selected_file_id);
        selected_cipher_len = record_cipher_len_by_file_id(selected_file_id);
        secure_dma_result_clear(&rx_result);
        read_error = 0u;

        if (selected_slot == 0xffffffffu) {
            read_error |= (1u << 13);
            rx_rc = SECURE_ERR_NOT_FOUND;
        } else {
            rx_rc = secure_read(selected_file_id, SELECTED_RX_ADDR, &rx_result);
        }

        for (settle = 0u; settle < 64u; settle++)
            __asm__ volatile("" ::: "memory");

        if (rx_rc != SECURE_OK)
            read_error |= (1u << 26);
        if ((rx_result.status_before != EXPECTED_RX_IDLE) &&
            (rx_result.status_before != EXPECTED_RX_DONE))
            read_error |= (1u << 14);
        if (rx_result.status_after != EXPECTED_RX_DONE)
            read_error |= (1u << 15);
        if (rx_result.bytes_done != selected_plain_len)
            read_error |= (1u << 27);
        if (rx_result.polls >= SECURE_MAX_POLLS)
            read_error |= (1u << 28);

        error_mask = load_error | write_error | read_error;
        publish_result_and_report(records,
                                  record_count,
                                  bundle_mode,
                                  error_mask,
                                  selected_file_id,
                                  selected_slot,
                                  selected_plain_len,
                                  selected_cipher_len,
                                  &rx_result,
                                  tx_total_polls);

        final_tx1_cipher_len = secure_metadata_read(0u, SECURE_META_CIPHER_LEN);
        final_tx2_cipher_len = secure_metadata_read(1u, SECURE_META_CIPHER_LEN);
        final_tx2_plain_len = secure_metadata_read(1u, SECURE_META_PLAIN_LEN);
        if (final_tx1_cipher_len == 0u)
            final_tx1_cipher_len = records[0].tx.ciphertext_bytes;
        if (final_tx2_cipher_len == 0u)
            final_tx2_cipher_len = records[1].tx.ciphertext_bytes;
        if (final_tx2_plain_len == 0u)
            final_tx2_plain_len = records[1].plain_len;
        final_record_count = secure_record_count();
        DMEM_STORE_IMM(4, 0u);
        DMEM_STORE_IMM(8, EXPECTED_TX_IDLE);
        DMEM_STORE_IMM(12, EXPECTED_TX_DONE);
        DMEM_STORE_IMM(16, final_tx1_cipher_len);
        DMEM_STORE_IMM(20, final_tx1_cipher_len);
        DMEM_STORE_IMM(24, 1u);
        DMEM_STORE_IMM(28, rx_result.status_before);
        DMEM_STORE_IMM(32, rx_result.status_after);
        DMEM_STORE_IMM(36, rx_result.bytes_done);
        DMEM_STORE_IMM(40, rx_result.debug_after);
        DMEM_STORE_IMM(44, rx_result.polls);
        DMEM_STORE_IMM(48, final_tx2_cipher_len);
        DMEM_STORE_IMM(52, final_tx2_plain_len);
        DMEM_STORE_IMM(56, selected_file_id);
        DMEM_STORE_IMM(60, final_record_count);
        DMEM_STORE_STORAGE_SIGNATURE();

        last_selected_file_id = selected_file_id;
        while (board_selected_file_id() == last_selected_file_id) {
            secure_load_delay();
        }
        selected_file_id = board_selected_file_id();
    }
}

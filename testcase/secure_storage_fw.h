#ifndef SECURE_STORAGE_FW_H
#define SECURE_STORAGE_FW_H

typedef unsigned int uint32_t;

#define SECURE_INLINE __attribute__((always_inline)) inline

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

#define SECURE_MODE_TX_COMPRESS_AES  0x00000009u
#define SECURE_MODE_RX               0x00000002u
#define SECURE_BLOCK_SIZE            0x00000020u
#define SECURE_MAX_POLLS             2000000u

#define SECURE_META_BASE_ADDR        0x00000100u
#define SECURE_META_RECORD_SHIFT     6u
#define SECURE_META_RECORD_COUNT     2u
#define SECURE_META_RECORD_WORDS     16u
#define SECURE_META_WORD(slot, idx) \
    (*(volatile uint32_t *)(SECURE_META_BASE_ADDR + ((slot) << SECURE_META_RECORD_SHIFT) + ((idx) << 2u)))

#define SECURE_META_VALID            0u
#define SECURE_META_FILE_ID          1u
#define SECURE_META_PLAIN_ADDR       2u
#define SECURE_META_CIPHER_ADDR      3u
#define SECURE_META_PLAIN_LEN        4u
#define SECURE_META_CIPHER_LEN       5u
#define SECURE_META_MODE             6u
#define SECURE_META_IV0              7u
#define SECURE_META_IV1              8u
#define SECURE_META_IV2              9u
#define SECURE_META_IV3              10u
#define SECURE_META_VERSION          11u
#define SECURE_META_FLAGS            12u

#define SECURE_IV_COUNTER_ADDR       0x000001f0u
#define SECURE_IV_COUNTER_WORD       (*(volatile uint32_t *)(SECURE_IV_COUNTER_ADDR))
#define SECURE_IV_SEED               0x31415926u

#define SECURE_CIPHER_BASE_ADDR      0x00004000u
#define SECURE_CIPHER_SLOT_SHIFT     12u
#define SECURE_CIPHER_SLOT_BYTES     (1u << SECURE_CIPHER_SLOT_SHIFT)

#define SECURE_OK                    0u
#define SECURE_ERR_BAD_ARG           1u
#define SECURE_ERR_NO_SLOT           2u
#define SECURE_ERR_DMA_TIMEOUT       3u
#define SECURE_ERR_DMA_ERROR         4u
#define SECURE_ERR_CIPHER_LEN        5u
#define SECURE_ERR_NOT_FOUND         6u
#define SECURE_ERR_READ_LEN          7u

typedef struct {
    uint32_t status_before;
    uint32_t status_after;
    uint32_t bytes_done;
    uint32_t ciphertext_bytes;
    uint32_t debug_after;
    uint32_t polls;
} secure_dma_result_t;

static SECURE_INLINE uint32_t secure_rotl32(uint32_t value, uint32_t shift)
{
    return (value << shift) | (value >> (32u - shift));
}

static SECURE_INLINE void secure_load_delay(void)
{
    __asm__ volatile("nop\nnop\n" ::: "memory");
}

static SECURE_INLINE uint32_t secure_metadata_read(uint32_t slot, uint32_t idx)
{
    uint32_t value;

    value = SECURE_META_WORD(slot, idx);
    secure_load_delay();

    return value;
}

static SECURE_INLINE void secure_dma_result_clear(secure_dma_result_t *result)
{
    result->status_before = 0u;
    result->status_after = 0u;
    result->bytes_done = 0u;
    result->ciphertext_bytes = 0u;
    result->debug_after = 0u;
    result->polls = 0u;
}

static SECURE_INLINE uint32_t secure_cipher_addr_for_slot(uint32_t slot)
{
    return SECURE_CIPHER_BASE_ADDR + (slot << SECURE_CIPHER_SLOT_SHIFT);
}

static SECURE_INLINE void secure_metadata_clear_slot(uint32_t slot)
{
    uint32_t idx;

    for (idx = 0u; idx < SECURE_META_RECORD_WORDS; idx++)
        SECURE_META_WORD(slot, idx) = 0u;
}

static SECURE_INLINE void secure_storage_init(void)
{
    uint32_t slot;

    for (slot = 0u; slot < SECURE_META_RECORD_COUNT; slot++)
        secure_metadata_clear_slot(slot);

    SECURE_IV_COUNTER_WORD = SECURE_IV_SEED;
}

static SECURE_INLINE uint32_t secure_find_record(uint32_t file_id)
{
    uint32_t slot;

    for (slot = 0u; slot < SECURE_META_RECORD_COUNT; slot++) {
        if ((secure_metadata_read(slot, SECURE_META_VALID) == 1u) &&
            (secure_metadata_read(slot, SECURE_META_FILE_ID) == file_id))
            return slot;
    }

    return 0xffffffffu;
}

static SECURE_INLINE uint32_t secure_alloc_record_slot(uint32_t file_id)
{
    uint32_t slot;

    slot = secure_find_record(file_id);
    if (slot != 0xffffffffu)
        return slot;

    for (slot = 0u; slot < SECURE_META_RECORD_COUNT; slot++) {
        if (secure_metadata_read(slot, SECURE_META_VALID) == 0u)
            return slot;
    }

    return 0xffffffffu;
}

static SECURE_INLINE uint32_t secure_record_count(void)
{
    uint32_t slot;
    uint32_t count = 0u;

    for (slot = 0u; slot < SECURE_META_RECORD_COUNT; slot++) {
        if (secure_metadata_read(slot, SECURE_META_VALID) == 1u)
            count = count + 1u;
    }

    return count;
}

static SECURE_INLINE uint32_t secure_next_iv_counter(void)
{
    uint32_t counter;

    counter = SECURE_IV_COUNTER_WORD + 1u;
    if (counter == 0u)
        counter = SECURE_IV_SEED + 1u;
    SECURE_IV_COUNTER_WORD = counter;

    return counter;
}

static SECURE_INLINE uint32_t secure_prepare_record(uint32_t slot,
                                                    uint32_t file_id,
                                                    uint32_t plain_addr,
                                                    uint32_t cipher_addr,
                                                    uint32_t plain_len)
{
    uint32_t counter;
    uint32_t mix;
    uint32_t iv0;
    uint32_t iv1;
    uint32_t iv2;
    uint32_t iv3;

    counter = secure_next_iv_counter();
    mix = plain_len ^ plain_addr ^ cipher_addr ^ file_id ^ counter ^ 0x43424331u;
    mix = mix ^ (mix << 13);
    mix = mix ^ (mix >> 17);
    mix = mix ^ (mix << 5);

    iv0 = 0x43424331u ^ file_id;
    iv1 = mix ^ 0x3a5c742eu;
    iv2 = secure_rotl32(iv1 ^ 0x9e3779b9u, 7u);
    iv3 = secure_rotl32(iv2 + 0x3c6ef372u, 17u);

    DMA_IV0 = iv0;
    DMA_IV1 = iv1;
    DMA_IV2 = iv2;
    DMA_IV3 = iv3;

    SECURE_META_WORD(slot, SECURE_META_VALID)       = 0u;
    SECURE_META_WORD(slot, SECURE_META_FILE_ID)     = file_id;
    SECURE_META_WORD(slot, SECURE_META_PLAIN_ADDR)  = plain_addr;
    SECURE_META_WORD(slot, SECURE_META_CIPHER_ADDR) = cipher_addr;
    SECURE_META_WORD(slot, SECURE_META_PLAIN_LEN)   = plain_len;
    SECURE_META_WORD(slot, SECURE_META_CIPHER_LEN)  = 0u;
    SECURE_META_WORD(slot, SECURE_META_MODE)        = SECURE_MODE_TX_COMPRESS_AES;
    SECURE_META_WORD(slot, SECURE_META_IV0)         = iv0;
    SECURE_META_WORD(slot, SECURE_META_IV1)         = iv1;
    SECURE_META_WORD(slot, SECURE_META_IV2)         = iv2;
    SECURE_META_WORD(slot, SECURE_META_IV3)         = iv3;
    SECURE_META_WORD(slot, SECURE_META_VERSION)     = counter;
    SECURE_META_WORD(slot, SECURE_META_FLAGS)       = 0u;

    return counter;
}

static SECURE_INLINE void secure_restore_iv_from_record(uint32_t slot)
{
    uint32_t iv0;
    uint32_t iv1;
    uint32_t iv2;
    uint32_t iv3;

    iv0 = secure_metadata_read(slot, SECURE_META_IV0);
    iv1 = secure_metadata_read(slot, SECURE_META_IV1);
    iv2 = secure_metadata_read(slot, SECURE_META_IV2);
    iv3 = secure_metadata_read(slot, SECURE_META_IV3);

    DMA_IV0 = iv0;
    DMA_IV1 = iv1;
    DMA_IV2 = iv2;
    DMA_IV3 = iv3;
}

static SECURE_INLINE uint32_t secure_run_dma(uint32_t src,
                                             uint32_t dst,
                                             uint32_t len,
                                             uint32_t mode,
                                             secure_dma_result_t *result)
{
    uint32_t saw_busy = 0u;
    uint32_t completion_progress = 0u;
    uint32_t status_before;
    uint32_t status_after;
    uint32_t bytes_done;
    uint32_t ciphertext_bytes;
    uint32_t debug_after;

    secure_dma_result_clear(result);

    DMA_CONTROL = 0x0000000cu;
    DMA_SRC_ADDR  = src;
    DMA_DST_ADDR  = dst;
    DMA_LEN_BYTES = len;
    DMA_MODE      = mode;
    DMA_BLOCK_CFG = SECURE_BLOCK_SIZE;

    status_before = DMA_STATUS;
    secure_load_delay();
    result->status_before = status_before;
    DMA_CONTROL = 0x00000001u;

    while (1) {
        status_after = DMA_STATUS;
        secure_load_delay();
        result->status_after = status_after;

        if ((status_after & 1u) != 0u)
            saw_busy = 1u;

        if ((status_after & (1u << 2)) != 0u)
            break;
        if ((status_after & (1u << 1)) != 0u)
            break;

        if (((status_after & 1u) == 0u) &&
            ((status_after & (1u << 1)) != 0u)) {
            if ((mode & 0x3u) == 0x1u)
                completion_progress = DMA_CIPHERTEXT_BYTES_PRODUCED;
            else
                completion_progress = DMA_BYTES_DONE;

            if ((saw_busy != 0u) || (completion_progress != 0u))
                break;
        }

        result->polls = result->polls + 1u;
        if (result->polls >= SECURE_MAX_POLLS)
            break;
    }

    bytes_done = DMA_BYTES_DONE;
    ciphertext_bytes = DMA_CIPHERTEXT_BYTES_PRODUCED;
    debug_after = DMA_DEBUG;
    secure_load_delay();
    result->bytes_done = bytes_done;
    result->ciphertext_bytes = ciphertext_bytes;
    result->debug_after = debug_after;

    if (result->polls >= SECURE_MAX_POLLS)
        return SECURE_ERR_DMA_TIMEOUT;
    if ((status_after & (1u << 2)) != 0u)
        return SECURE_ERR_DMA_ERROR;

    return SECURE_OK;
}

static SECURE_INLINE void secure_commit_record(uint32_t slot,
                                               uint32_t cipher_len)
{
    SECURE_META_WORD(slot, SECURE_META_CIPHER_LEN)  = cipher_len;
    SECURE_META_WORD(slot, SECURE_META_FLAGS)       = 0u;
    SECURE_META_WORD(slot, SECURE_META_VALID)       = 1u;
}

static SECURE_INLINE uint32_t secure_write(uint32_t file_id,
                                           uint32_t plain_addr,
                                           uint32_t plain_len,
                                           secure_dma_result_t *result)
{
    uint32_t slot;
    uint32_t cipher_addr;
    uint32_t rc;

    secure_dma_result_clear(result);

    if ((file_id == 0u) || (plain_len == 0u))
        return SECURE_ERR_BAD_ARG;

    slot = secure_alloc_record_slot(file_id);
    if (slot == 0xffffffffu)
        return SECURE_ERR_NO_SLOT;

    cipher_addr = secure_cipher_addr_for_slot(slot);
    (void)secure_prepare_record(slot, file_id, plain_addr, cipher_addr, plain_len);

    rc = secure_run_dma(plain_addr, cipher_addr, plain_len,
                        SECURE_MODE_TX_COMPRESS_AES, result);
    if (rc != SECURE_OK)
        return rc;

    if ((result->ciphertext_bytes == 0u) ||
        ((result->ciphertext_bytes & 0x0fu) != 0u))
        return SECURE_ERR_CIPHER_LEN;

    secure_commit_record(slot, result->ciphertext_bytes);

    return SECURE_OK;
}

static SECURE_INLINE uint32_t secure_read(uint32_t file_id,
                                          uint32_t dst_addr,
                                          secure_dma_result_t *result)
{
    uint32_t slot;
    uint32_t cipher_addr;
    uint32_t cipher_len;
    uint32_t plain_len;
    uint32_t rc;

    secure_dma_result_clear(result);

    slot = secure_find_record(file_id);
    if (slot == 0xffffffffu)
        return SECURE_ERR_NOT_FOUND;

    secure_restore_iv_from_record(slot);
    cipher_addr = secure_metadata_read(slot, SECURE_META_CIPHER_ADDR);
    cipher_len = secure_metadata_read(slot, SECURE_META_CIPHER_LEN);
    plain_len = secure_metadata_read(slot, SECURE_META_PLAIN_LEN);

    rc = secure_run_dma(cipher_addr,
                        dst_addr,
                        cipher_len,
                        SECURE_MODE_RX,
                        result);
    if (rc != SECURE_OK)
        return rc;

    if (result->bytes_done != plain_len)
        return SECURE_ERR_READ_LEN;

    return SECURE_OK;
}

static SECURE_INLINE uint32_t secure_delete(uint32_t file_id)
{
    uint32_t slot;

    slot = secure_find_record(file_id);
    if (slot == 0xffffffffu)
        return SECURE_ERR_NOT_FOUND;

    secure_metadata_clear_slot(slot);
    return SECURE_OK;
}

#endif

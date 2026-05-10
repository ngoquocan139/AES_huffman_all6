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

#define MAGIC_SPH1                0x31485053u
#define PREPROC_HEADER_BYTES      16u
#define PREPROC_RECORD_BYTES      20u
#define TEST_BLOCK_SIZE           0x00000020u
#define TEST_MODE_TX_COMPRESS_AES 0x00000001u
#define RESULT_SIGNATURE          0x53505231u
#define EXPECTED_TX_IDLE          0x00000018u
#define EXPECTED_TX_DONE          0x0000001au
#define MAX_POLLS                 2000000u

void _start(void) __attribute__((naked, used, section(".text.startup")));
int main(void) __attribute__((noreturn));

static uint8_t read_u8(uint32_t addr)
{
    volatile uint8_t *ptr = (volatile uint8_t *)addr;
    return *ptr;
}

static void write_u8(uint32_t addr, uint8_t data)
{
    volatile uint8_t *ptr = (volatile uint8_t *)addr;
    *ptr = data;
}

static void write_le16(uint32_t addr, uint32_t value)
{
    write_u8(addr + 0u, (uint8_t)(value & 0xffu));
    write_u8(addr + 1u, (uint8_t)((value >> 8) & 0xffu));
}

static void write_le32(uint32_t addr, uint32_t value)
{
    write_u8(addr + 0u, (uint8_t)(value & 0xffu));
    write_u8(addr + 1u, (uint8_t)((value >> 8) & 0xffu));
    write_u8(addr + 2u, (uint8_t)((value >> 16) & 0xffu));
    write_u8(addr + 3u, (uint8_t)((value >> 24) & 0xffu));
}

static uint32_t parse_u32_field(uint32_t *pos, uint32_t input_len)
{
    uint32_t value = 0u;
    uint8_t ch;

    while (*pos < input_len) {
        ch = read_u8(SRC_BASE_ADDR + *pos);
        if ((ch >= (uint8_t)'0') && (ch <= (uint8_t)'9')) {
            value = (value * 10u) + (uint32_t)(ch - (uint8_t)'0');
            *pos = *pos + 1u;
        } else {
            break;
        }
    }
    return value;
}

static void skip_delims(uint32_t *pos, uint32_t input_len)
{
    uint8_t ch;
    while (*pos < input_len) {
        ch = read_u8(SRC_BASE_ADDR + *pos);
        if ((ch == (uint8_t)',') || (ch == (uint8_t)'\n') || (ch == (uint8_t)'\r')) {
            *pos = *pos + 1u;
        } else {
            break;
        }
    }
}

static uint32_t run_tx_dma(uint32_t src,
                           uint32_t dst,
                           uint32_t len,
                           uint32_t *status_before,
                           uint32_t *status_after,
                           uint32_t *bytes_done)
{
    uint32_t polls = 0u;
    uint32_t saw_busy = 0u;
    uint32_t completion_progress = 0u;

    DMA_SRC_ADDR  = src;
    DMA_DST_ADDR  = dst;
    DMA_LEN_BYTES = len;
    DMA_MODE      = TEST_MODE_TX_COMPRESS_AES;
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
            completion_progress = DMA_CTXT_BYTES;
            if ((saw_busy != 0u) || (completion_progress != 0u))
                break;
        }
        polls = polls + 1u;
        if (polls >= MAX_POLLS)
            break;
    }

    *bytes_done = DMA_BYTES_DONE;
    return polls;
}

void _start(void)
{
    __asm__ volatile(
        "li sp, 0x00007f00\n"
        "j main\n"
    );
}

int main(void)
{
    uint32_t pos = 0u;
    uint32_t input_len = INPUT_LEN_ADDR;
    uint32_t record_count = 0u;
    uint32_t preproc_len;
    uint32_t out_addr = PREPROC_BASE_ADDR + PREPROC_HEADER_BYTES;
    uint32_t error_mask = 0u;

    uint32_t delta_ms;
    uint32_t patient_id;
    uint32_t encounter_id;
    uint32_t device_id;
    uint32_t bed_id;
    uint32_t red;
    uint32_t ir;
    uint32_t spo2_x10;
    uint32_t hr;
    uint32_t rr;
    uint32_t alert_flags;

    uint32_t raw_status_before = 0u;
    uint32_t raw_status_after = 0u;
    uint32_t raw_bytes_done = 0u;
    uint32_t raw_cipher_bytes = 0u;
    uint32_t raw_polls = 0u;

    uint32_t pre_status_before = 0u;
    uint32_t pre_status_after = 0u;
    uint32_t pre_bytes_done = 0u;
    uint32_t pre_cipher_bytes = 0u;
    uint32_t pre_polls = 0u;

    if (input_len == 0u)
        error_mask |= (1u << 0);

    while (pos < input_len) {
        skip_delims(&pos, input_len);
        if (pos >= input_len)
            break;

        delta_ms     = parse_u32_field(&pos, input_len); skip_delims(&pos, input_len);
        patient_id   = parse_u32_field(&pos, input_len); skip_delims(&pos, input_len);
        encounter_id = parse_u32_field(&pos, input_len); skip_delims(&pos, input_len);
        device_id    = parse_u32_field(&pos, input_len); skip_delims(&pos, input_len);
        bed_id       = parse_u32_field(&pos, input_len); skip_delims(&pos, input_len);
        red          = parse_u32_field(&pos, input_len); skip_delims(&pos, input_len);
        ir           = parse_u32_field(&pos, input_len); skip_delims(&pos, input_len);
        spo2_x10     = parse_u32_field(&pos, input_len); skip_delims(&pos, input_len);
        hr           = parse_u32_field(&pos, input_len); skip_delims(&pos, input_len);
        rr           = parse_u32_field(&pos, input_len); skip_delims(&pos, input_len);
        alert_flags  = parse_u32_field(&pos, input_len); skip_delims(&pos, input_len);

        write_le16(out_addr + 0u, delta_ms);
        write_le16(out_addr + 2u, patient_id);
        write_le32(out_addr + 4u, encounter_id);
        write_u8  (out_addr + 8u, (uint8_t)device_id);
        write_u8  (out_addr + 9u, (uint8_t)bed_id);
        write_le16(out_addr + 10u, red);
        write_le16(out_addr + 12u, ir);
        write_le16(out_addr + 14u, spo2_x10);
        write_u8  (out_addr + 16u, (uint8_t)hr);
        write_u8  (out_addr + 17u, (uint8_t)rr);
        write_le16(out_addr + 18u, alert_flags);

        out_addr = out_addr + PREPROC_RECORD_BYTES;
        record_count = record_count + 1u;
    }

    preproc_len = PREPROC_HEADER_BYTES + (record_count * PREPROC_RECORD_BYTES);
    write_le32(PREPROC_BASE_ADDR + 0u, MAGIC_SPH1);
    write_le32(PREPROC_BASE_ADDR + 4u, record_count);
    write_le32(PREPROC_BASE_ADDR + 8u, PREPROC_RECORD_BYTES);
    write_le32(PREPROC_BASE_ADDR + 12u, 0u);
    PREPROC_LEN_ADDR = preproc_len;

    raw_polls = run_tx_dma(SRC_BASE_ADDR, RAW_TX_DST_BASE_ADDR, input_len,
                           &raw_status_before, &raw_status_after, &raw_bytes_done);
    raw_cipher_bytes = DMA_CTXT_BYTES;

    pre_polls = run_tx_dma(PREPROC_BASE_ADDR, PREPROC_TX_DST_BASE_ADDR, preproc_len,
                           &pre_status_before, &pre_status_after, &pre_bytes_done);
    pre_cipher_bytes = DMA_CTXT_BYTES;

    if (record_count == 0u)
        error_mask |= (1u << 1);
    if (raw_status_before != EXPECTED_TX_IDLE)
        error_mask |= (1u << 2);
    if (raw_status_after != EXPECTED_TX_DONE)
        error_mask |= (1u << 3);
    if ((raw_bytes_done == 0u) || ((raw_bytes_done & 0x0fu) != 0u))
        error_mask |= (1u << 4);
    if (raw_cipher_bytes != raw_bytes_done)
        error_mask |= (1u << 5);
    if (raw_polls >= MAX_POLLS)
        error_mask |= (1u << 6);

    if ((pre_status_before != EXPECTED_TX_IDLE) && (pre_status_before != EXPECTED_TX_DONE))
        error_mask |= (1u << 7);
    if (pre_status_after != EXPECTED_TX_DONE)
        error_mask |= (1u << 8);
    if ((pre_bytes_done == 0u) || ((pre_bytes_done & 0x0fu) != 0u))
        error_mask |= (1u << 9);
    if (pre_cipher_bytes != pre_bytes_done)
        error_mask |= (1u << 10);
    if (pre_polls >= MAX_POLLS)
        error_mask |= (1u << 11);
    if (pre_cipher_bytes >= raw_cipher_bytes)
        error_mask |= (1u << 12);

    RESULT_WORD(0)  = RESULT_SIGNATURE;
    RESULT_WORD(1)  = error_mask;
    RESULT_WORD(2)  = input_len;
    RESULT_WORD(3)  = preproc_len;
    RESULT_WORD(4)  = record_count;
    RESULT_WORD(5)  = raw_status_before;
    RESULT_WORD(6)  = raw_status_after;
    RESULT_WORD(7)  = raw_bytes_done;
    RESULT_WORD(8)  = raw_cipher_bytes;
    RESULT_WORD(9)  = pre_status_before;
    RESULT_WORD(10) = pre_status_after;
    RESULT_WORD(11) = pre_bytes_done;
    RESULT_WORD(12) = pre_cipher_bytes;
    RESULT_WORD(13) = MAGIC_SPH1;
    RESULT_WORD(14) = raw_polls;
    RESULT_WORD(15) = pre_polls;

    while (1) {
    }
}

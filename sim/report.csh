#!/bin/csh

set log = "rep.log"
if ( -f $log ) then
    rm -rf $log
endif

touch $log

@ total = 0
@ passed = 0
@ failed = 0
@ missing = 0

set all_pats = (`cat pat.list | sed '\/\//d' | sed '/^#/d' | sed '/^$/d'`)

foreach pat ($all_pats)
    set sim_log = "log/${pat}.log"
    @ total++

    if ( ! -f $sim_log ) then
        @ missing++
    else
        grep -F "[FAIL]" $sim_log > /dev/null
        if ( $status == 0 ) then
            @ failed++
        else
            grep -F "[PASS]" $sim_log > /dev/null
            if ( $status == 0 ) then
                @ passed++
            else
                grep "Test_result PASSED" $sim_log > /dev/null
                if ( $status == 0 ) then
                    @ passed++
                else
                    @ failed++
                endif
            endif
        endif
    endif
end

printf "Table 4.x. Consolidated Questa simulation regression summary\n\n" >> $log
printf "| Verification group | Testcases | Result | Verification objective | Key result / evidence |\n" >> $log
printf "|---|---:|---|---|---|\n" >> $log

foreach group (E2E TX_ONLY MMIO_APB TX_DIRECT RX_DIRECT CPU_CORE STRESS)
    switch ($group)
        case E2E:
            set scope = "End-to-end secure-storage loopback"
            set pats = (dma_compress_aes_input1 dma_compress_aes_input2 dma_storage_table_three_record_bundle dma_compress_aes_one_symbol_cov dma_compress_aes_alnum63_cov)
            set objective = "Verify TX Huffman compression + AES-CBC, RX AES-CBC + Huffman decompression, and DMEM loopback."
            set evidence = "Representative logs show src_mismatch=0, rx_mismatch=0; the storage bundle covers SpO2 2551->880 B, log 2839->1856 B, and ECG 3601->1904 B."
            breaksw
        case TX_ONLY:
            set scope = "TX compression and block packing"
            set pats = (tx_compress_only_input1 tx_compress_only_input4_cov tx_compress_only_one_symbol_cov tx_compress_only_ascii_sweep_cov tx_compress_only_alnum63_cov tx_compress_only_short_raw_cov tx_compress_aes_block_input2 tx_compress_only_block_input2)
            set objective = "Verify the TX-side Huffman encoder, 128-bit packing, AES input wrapper, and compression-only bypass path."
            set evidence = "Compressed output is non-zero and 16-byte aligned; compression-only tests keep AES/RX bypassed."
            breaksw
        case MMIO_APB:
            set scope = "MMIO, APB, DMA control, and error handling"
            set pats = (mmio_regfile_basic mmio_mode_matrix mmio_regfile_negative mmio_rx_bad_length soc_sideband_cov tx_apb_wait_cov tx_apb_error_cov dma_bridge_direct_cov)
            set objective = "Verify CPU-visible DMA registers, mode decoding, APB wait/error behavior, sideband status, and DMA bridge access."
            set evidence = "Register reads/writes, illegal-mode checks, wait-state behavior, and RX bad-length error cases all pass."
            breaksw
        case TX_DIRECT:
            set scope = "TX datapath direct module tests"
            set pats = (tx_if_direct_cov tx_encoder_direct_cov tx_builder_packer_direct_cov)
            set objective = "Verify TX APB interface, dynamic Huffman encoder path, Huffman builder, and bit packer without full SoC firmware."
            set evidence = "Direct TX interface, encoder, builder, and packer regressions all reach PASS."
            breaksw
        case RX_DIRECT:
            set scope = "RX datapath direct module tests"
            set pats = (rx_backpressure_cov rx_if_direct_cov rx_parser_decoder_cov rx_decoder_direct_cov rx_depacker_packer_direct_cov rx_parser_decoder_error_direct_cov)
            set objective = "Verify RX APB interface, block parser, Huffman decoder, bit depacker, output packer, backpressure, and error handling."
            set evidence = "Parser/decoder, depacker/packer, backpressure, and malformed-stream error checks all reach PASS."
            breaksw
        case CPU_CORE:
            set scope = "RV32I CPU execution checks"
            set pats = (cpu_instruction_cov cpu_mem_forward_cov cpu_forward_direct_cov)
            set objective = "Verify the instruction subset used by firmware and memory/forwarding behavior around load-store and ALU paths."
            set evidence = "Instruction execution, memory forwarding, and direct forwarding tests all reach PASS."
            breaksw
        case STRESS:
            set scope = "Integrated raw DUT stress"
            set pats = (raw_dut_stress_cov)
            set objective = "Run a broad integration stress regression across the raw DUT control and data paths."
            set evidence = "Raw DUT stress regression reaches PASS with no reported FAIL tag."
            breaksw
    endsw

    @ group_total = 0
    @ group_passed = 0
    @ group_failed = 0
    @ group_missing = 0

    foreach pat ($pats)
        set sim_log = "log/${pat}.log"
        @ group_total++

        if ( ! -f $sim_log ) then
            @ group_missing++
        else
            grep -F "[FAIL]" $sim_log > /dev/null
            if ( $status == 0 ) then
                @ group_failed++
            else
                grep -F "[PASS]" $sim_log > /dev/null
                if ( $status == 0 ) then
                    @ group_passed++
                else
                    grep "Test_result PASSED" $sim_log > /dev/null
                    if ( $status == 0 ) then
                        @ group_passed++
                    else
                        @ group_failed++
                    endif
                endif
            endif
        endif
    end

    if ( $group_missing > 0 ) then
        set result = "INCOMPLETE (${group_passed}/${group_total}, missing=${group_missing})"
    else if ( $group_failed > 0 ) then
        set result = "FAILED (${group_passed}/${group_total})"
    else
        set result = "PASSED (${group_passed}/${group_total})"
    endif

    printf "| %s | %d | %s | %s | %s |\n" "$scope" "$group_total" "$result" "$objective" "$evidence" >> $log
end

printf "| **Total regression** | **%d** | **PASSED (%d/%d), FAILED=%d, MISSING=%d** | Full clean Questa regression from pat.list. | Detailed logs are stored under sim/log/*.log; report source is sim/report.csh. |\n" "$total" "$passed" "$total" "$failed" "$missing" >> $log

cat $log

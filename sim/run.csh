#!/bin/csh

set cov = 1

if( ($#argv > 0) && ("$1" == "cov") ) then
    set cov = 1
endif

make clean

foreach pat (`cat pat.list | sed '\/\//d' | sed '/^#/d' | sed '/^$/d'`)
    set tb_name = ""
    set c_src = ""
    set run_args = ""

    switch ($pat)
        case dma_compress_aes_input1:
            set tb_name = "test_bench"
            set c_src = "test_mmio_dma.c"
            set run_args = "+CASE_NAME=dma_compress_aes_input1 +INPUT_FILE=input1.txt"
            breaksw
        case dma_compress_aes_input2:
            set tb_name = "test_bench"
            set c_src = "test_mmio_dma.c"
            set run_args = "+CASE_NAME=dma_compress_aes_input2 +INPUT_FILE=input2.txt"
            breaksw
        case dma_compress_aes_input3:
            set tb_name = "test_bench"
            set c_src = "test_mmio_dma.c"
            set run_args = "+CASE_NAME=dma_compress_aes_input3 +INPUT_FILE=input3.txt"
            breaksw
        case dma_storage_table_three_record_bundle:
            set tb_name = "test_bench"
            set c_src = "test_mmio_dma_storage_table.c"
            set run_args = "+CASE_NAME=dma_storage_table_three_record_bundle +INPUT_FILE=input1.txt +INPUT_FILE2=input2.txt +INPUT_FILE3=mitdb_112_mlii_10s_delta2_var.bin +INPUT_BINARY +STORAGE_BUNDLE +STORAGE_TRACE"
            breaksw
        case dma_compress_aes_one_symbol_cov:
            set tb_name = "test_bench"
            set c_src = "test_mmio_dma.c"
            set run_args = "+CASE_NAME=dma_compress_aes_one_symbol_cov +INPUT_FILE=input_cov_one_symbol.txt"
            breaksw
        case dma_compress_aes_alnum63_cov:
            set tb_name = "test_bench"
            set c_src = "test_mmio_dma.c"
            set run_args = "+CASE_NAME=dma_compress_aes_alnum63_cov +INPUT_FILE=input_cov_alnum63.txt"
            breaksw
        case dma_compress_aes_input4_cov_debug:
            set tb_name = "test_bench"
            set c_src = "test_mmio_dma.c"
            set run_args = "+CASE_NAME=dma_compress_aes_input4_cov_debug +INPUT_FILE=input4_cov.txt"
            breaksw
        case tx_compress_only_input1:
            set tb_name = "test_bench"
            set c_src = "test_mmio_tx_only.c"
            set run_args = "+CASE_NAME=tx_compress_only_input1 +INPUT_FILE=input1.txt"
            breaksw
        case tx_compress_only_input4_cov:
            set tb_name = "test_bench"
            set c_src = "test_mmio_tx_only.c"
            set run_args = "+CASE_NAME=tx_compress_only_input4_cov +INPUT_FILE=input4_cov.txt"
            breaksw
        case tx_compress_only_one_symbol_cov:
            set tb_name = "test_bench"
            set c_src = "test_mmio_tx_only.c"
            set run_args = "+CASE_NAME=tx_compress_only_one_symbol_cov +INPUT_FILE=input_cov_one_symbol.txt"
            breaksw
        case tx_compress_only_ascii_sweep_cov:
            set tb_name = "test_bench"
            set c_src = "test_mmio_tx_only.c"
            set run_args = "+CASE_NAME=tx_compress_only_ascii_sweep_cov +INPUT_FILE=input_cov_ascii_sweep.txt"
            breaksw
        case tx_compress_only_alnum63_cov:
            set tb_name = "test_bench"
            set c_src = "test_mmio_tx_only.c"
            set run_args = "+CASE_NAME=tx_compress_only_alnum63_cov +INPUT_FILE=input_cov_alnum63.txt"
            breaksw
        case tx_compress_only_short_raw_cov:
            set tb_name = "test_bench"
            set c_src = "test_mmio_tx_only.c"
            set run_args = "+CASE_NAME=tx_compress_only_short_raw_cov +INPUT_FILE=input_cov_short_raw.txt"
            breaksw
        case tx_compress_aes_block_input2:
            set tb_name = "test_bench"
            set c_src = "test_mmio_tx_only_aes_block.c"
            set run_args = "+CASE_NAME=tx_compress_aes_block_input2 +INPUT_FILE=input2.txt"
            breaksw
        case tx_compress_only_block_input2:
            set tb_name = "test_bench"
            set c_src = "test_mmio_tx_only_compress_block.c"
            set run_args = "+CASE_NAME=tx_compress_only_block_input2 +INPUT_FILE=input2.txt"
            breaksw
        case mmio_regfile_basic:
            set tb_name = "test_bench"
            set c_src = "test_mmio_regfile_basic.c"
            set run_args = "+CASE_NAME=mmio_regfile_basic"
            breaksw
        case mmio_mode_matrix:
            set tb_name = "test_bench"
            set c_src = "test_mmio_mode_matrix.c"
            set run_args = "+CASE_NAME=mmio_mode_matrix"
            breaksw
        case mmio_regfile_negative:
            set tb_name = "test_bench"
            set c_src = "test_mmio_regfile_negative.c"
            set run_args = "+CASE_NAME=mmio_regfile_negative"
            breaksw
        case mmio_rx_bad_length:
            set tb_name = "test_bench"
            set c_src = "test_mmio_rx_bad_length.c"
            set run_args = "+CASE_NAME=mmio_rx_bad_length"
            breaksw
        case soc_sideband_cov:
            set tb_name = "test_bench"
            set c_src = "test_mmio_regfile_basic.c"
            set run_args = "+CASE_NAME=soc_sideband_cov +SIDEBAND_COV"
            breaksw
        case tx_apb_wait_cov:
            set tb_name = "test_bench"
            set c_src = "test_mmio_tx_only.c"
            set run_args = "+CASE_NAME=tx_apb_wait_cov +INPUT_FILE=input1.txt +TX_APB_WAIT_COV"
            breaksw
        case tx_if_direct_cov:
            set tb_name = "test_bench"
            set c_src = "test_mmio_regfile_basic.c"
            set run_args = "+CASE_NAME=tx_if_direct_cov +INPUT_FILE=input1.txt +TX_IF_DIRECT_COV"
            breaksw
        case tx_encoder_direct_cov:
            set tb_name = "test_bench"
            set c_src = "test_mmio_regfile_basic.c"
            set run_args = "+CASE_NAME=tx_encoder_direct_cov +INPUT_FILE=input1.txt +TX_ENCODER_DIRECT_COV"
            breaksw
        case tx_builder_packer_direct_cov:
            set tb_name = "test_bench"
            set c_src = "test_mmio_regfile_basic.c"
            set run_args = "+CASE_NAME=tx_builder_packer_direct_cov +INPUT_FILE=input1.txt +TX_BUILDER_PACKER_DIRECT_COV"
            breaksw
        case rx_backpressure_cov:
            set tb_name = "test_bench"
            set c_src = "test_mmio_dma.c"
            set run_args = "+CASE_NAME=rx_backpressure_cov +INPUT_FILE=input1.txt +RX_APB_WAIT_COV +RX_STREAM_BACKPRESSURE_COV"
            breaksw
        case tx_apb_error_cov:
            set tb_name = "test_bench"
            set c_src = "test_mmio_tx_apb_error.c"
            set run_args = "+CASE_NAME=tx_apb_error_cov +INPUT_FILE=input1.txt +TX_APB_ERROR_COV"
            breaksw
        case rx_if_direct_cov:
            set tb_name = "test_bench"
            set c_src = "test_mmio_regfile_basic.c"
            set run_args = "+CASE_NAME=rx_if_direct_cov +INPUT_FILE=input1.txt +RX_IF_DIRECT_COV"
            breaksw
        case rx_parser_decoder_cov:
            set tb_name = "test_bench"
            set c_src = "test_mmio_regfile_basic.c"
            set run_args = "+CASE_NAME=rx_parser_decoder_cov +INPUT_FILE=input1.txt +RX_PARSE_DECODE_COV"
            breaksw
        case rx_decoder_direct_cov:
            set tb_name = "test_bench"
            set c_src = "test_mmio_regfile_basic.c"
            set run_args = "+CASE_NAME=rx_decoder_direct_cov +INPUT_FILE=input1.txt +RX_DECODER_DIRECT_COV"
            breaksw
        case rx_depacker_packer_direct_cov:
            set tb_name = "test_bench"
            set c_src = "test_mmio_regfile_basic.c"
            set run_args = "+CASE_NAME=rx_depacker_packer_direct_cov +INPUT_FILE=input1.txt +RX_DEPACKER_PACKER_DIRECT_COV"
            breaksw
        case rx_parser_decoder_error_direct_cov:
            set tb_name = "test_bench"
            set c_src = "test_mmio_regfile_basic.c"
            set run_args = "+CASE_NAME=rx_parser_decoder_error_direct_cov +INPUT_FILE=input1.txt +RX_PARSE_DECODE_ERROR_DIRECT_COV"
            breaksw
        case cpu_instruction_cov:
            set tb_name = "test_bench"
            set c_src = "test_cpu_instruction_cov.c"
            set run_args = "+CASE_NAME=cpu_instruction_cov +INPUT_FILE=input1.txt"
            breaksw
        case cpu_mem_forward_cov:
            set tb_name = "test_bench"
            set c_src = "test_cpu_mem_forward_cov.c"
            set run_args = "+CASE_NAME=cpu_mem_forward_cov +INPUT_FILE=input1.txt"
            breaksw
        case cpu_forward_direct_cov:
            set tb_name = "test_bench"
            set c_src = "test_mmio_regfile_basic.c"
            set run_args = "+CASE_NAME=cpu_forward_direct_cov +INPUT_FILE=input1.txt +CPU_FORWARD_DIRECT_COV"
            breaksw
        case dma_bridge_direct_cov:
            set tb_name = "test_bench"
            set c_src = "test_mmio_regfile_basic.c"
            set run_args = "+CASE_NAME=dma_bridge_direct_cov +INPUT_FILE=input1.txt +DMA_BRIDGE_DIRECT_COV"
            breaksw
        case raw_dut_stress_cov:
            set tb_name = "test_bench"
            set c_src = "test_mmio_regfile_basic.c"
            set run_args = "+CASE_NAME=raw_dut_stress_cov +INPUT_FILE=input1.txt +SIDEBAND_COV +TX_IF_DIRECT_COV +TX_ENCODER_DIRECT_COV +TX_BUILDER_PACKER_DIRECT_COV +RX_IF_DIRECT_COV +RX_PARSE_DECODE_COV +RX_DECODER_DIRECT_COV +RX_DEPACKER_PACKER_DIRECT_COV +RX_PARSE_DECODE_ERROR_DIRECT_COV +CPU_FORWARD_DIRECT_COV +DMA_BRIDGE_DIRECT_COV +RAW_DUT_STRESS_COV"
            breaksw
        default:
            echo "[FAIL] unknown pattern in pat.list: $pat"
            exit 1
    endsw

    echo "============================================================"
    echo "PATTERN: $pat"
    echo "TB_NAME: $tb_name"
    echo "C_SRC  : $c_src"
    echo "ARGS   : $run_args"
    echo "============================================================"

    make compile C_SRC=${c_src}

    if ( $cov == 1 ) then
        make all_cov TESTNAME=${pat} TB_NAME=${tb_name} RUN_ARGS="${run_args}"
    else
        make all TESTNAME=${pat} TB_NAME=${tb_name} RUN_ARGS="${run_args}"
    endif
end

if ( $cov == 1 ) then
    make gen_cov
endif

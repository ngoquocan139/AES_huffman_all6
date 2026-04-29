#!/bin/csh

set cov = 0

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
        case dma_compress_aes_input2_debug:
            set tb_name = "test_bench"
            set c_src = "test_mmio_dma.c"
            set run_args = "+CASE_NAME=dma_compress_aes_input2_debug +INPUT_FILE=input2.txt"
            breaksw
        case dma_compress_aes_input3:
            set tb_name = "test_bench"
            set c_src = "test_mmio_dma.c"
            set run_args = "+CASE_NAME=dma_compress_aes_input3 +INPUT_FILE=input3.txt"
            breaksw
        case dma_compress_aes_input4_cov_debug:
            set tb_name = "test_bench"
            set c_src = "test_mmio_dma.c"
            set run_args = "+CASE_NAME=dma_compress_aes_input4_cov_debug +INPUT_FILE=input4_cov.txt"
            breaksw
        case tx_compress_only_input1:
            set tb_name = "tb_rv32_soc_tx_only"
            set c_src = "test_mmio_tx_only.c"
            set run_args = "+CASE_NAME=tx_compress_only_input1 +INPUT_FILE=input1.txt"
            breaksw
        case tx_compress_only_input4_cov:
            set tb_name = "tb_rv32_soc_tx_only"
            set c_src = "test_mmio_tx_only.c"
            set run_args = "+CASE_NAME=tx_compress_only_input4_cov +INPUT_FILE=input4_cov.txt"
            breaksw
        case tx_compress_aes_block_input3:
            set tb_name = "tb_rv32_soc_tx_only"
            set c_src = "test_mmio_tx_only_aes_block.c"
            set run_args = "+CASE_NAME=tx_compress_aes_block_input3 +INPUT_FILE=input3.txt"
            breaksw
        case tx_compress_only_block_input3:
            set tb_name = "tb_rv32_soc_tx_only"
            set c_src = "test_mmio_tx_only_compress_block.c"
            set run_args = "+CASE_NAME=tx_compress_only_block_input3 +INPUT_FILE=input3.txt"
            breaksw
        case mmio_regfile_basic:
            set tb_name = "tb_rv32_soc_mmio_regfile"
            set c_src = "test_mmio_regfile_basic.c"
            set run_args = "+CASE_NAME=mmio_regfile_basic"
            breaksw
        case mmio_mode_matrix:
            set tb_name = "tb_rv32_soc_mmio_regfile"
            set c_src = "test_mmio_mode_matrix.c"
            set run_args = "+CASE_NAME=mmio_mode_matrix"
            breaksw
        case mmio_regfile_negative:
            set tb_name = "tb_rv32_soc_mmio_regfile"
            set c_src = "test_mmio_regfile_negative.c"
            set run_args = "+CASE_NAME=mmio_regfile_negative"
            breaksw
        case host_preprocess_input4_cov_debug:
            set tb_name = "tb_rv32_log_preprocess"
            set c_src = "test_log_preprocess.c"
            set run_args = "+CASE_NAME=host_preprocess_input4_cov_debug +INPUT_FILE=input4_cov.txt"
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

#!/bin/csh

set log = "rep.log"
if ( -f $log ) then
    rm -rf $log
endif

touch $log

@ count = 0
@ total = 0
@ remain = 0

printf "|---------------------------------------------------------------------------------------------------------------|\n" >> $log
printf "|%-32s |%-30s |%-20s |%-20s |\n" " PAT_NAME" " RUN_DATE" " RESULT" " LOG" >> $log
printf "|---------------------------------------------------------------------------------------------------------------|\n" >> $log

foreach pat (`cat pat.list | sed '\/\//d' | sed '/^#/d' | sed '/^$/d'`)
    set sim_log = "log/${pat}.log"
    set res = "NA"
    set tm = "NA"

    if ( ! -f $sim_log ) then
        echo "can not find $sim_log"
    else
        set tm = "DONE"

        grep -F "[FAIL]" $sim_log > /dev/null
        if ( $status == 0 ) then
            set res = "FAILED"
        else
            grep -F "[PASS]" $sim_log > /dev/null
            if ( $status == 0 ) then
                set res = "PASSED"
            else
                grep "Test_result PASSED" $sim_log > /dev/null
                if ( $status == 0 ) then
                    set res = "PASSED"
                endif
            endif
        endif
    endif

    printf "|%-32s |%-30s |%-20s |%-20s |\n" " $pat" " $tm" " $res" " $sim_log" >> $log
    printf "|---------------------------------------------------------------------------------------------------------------|\n" >> $log

    if ( "$res" == "PASSED" ) then
        @ count++
    endif

    @ total++
end

set remain = `expr $total \- $count`

echo "TOTAL/PASSED/REMAIN:${total}/${count}/${remain}" >> $log

printf "\n" >> $log
printf "|---------------------------------------------------------------------------------------------------------------|\n" >> $log
printf "| SOC 4.5 END-TO-END MAIN TESTCASES                                                                            |\n" >> $log
printf "|---------------------------------------------------------------------------------------------------------------|\n" >> $log
printf "|%-32s |%-10s | %-68s |\n" " TESTNAME" " RESULT" " KEY DETAILS" >> $log
printf "|---------------------------------------------------------------------------------------------------------------|\n" >> $log

foreach pat (dma_compress_aes_input1 dma_compress_aes_input2 dma_compress_aes_alnum63_cov)
    set sim_log = "log/${pat}.log"
    set res = "NA"

    if ( -f $sim_log ) then
        grep -F "[FAIL]" $sim_log > /dev/null
        if ( $status == 0 ) then
            set res = "FAILED"
        else
            grep -F "[PASS] rv32_soc_unified_test" $sim_log > /dev/null
            if ( $status == 0 ) then
                set res = "PASSED"
            else
                set res = "NO_PASS_TAG"
            endif
        endif

        printf "| %-31s | %-9s | log=%-64s |\n" "$pat" "$res" "$sim_log" >> $log
        grep -m 1 "^# input_file=" $sim_log | sed 's/^# /|                                  |            | /; s/$/ |/' >> $log
        grep -m 1 "^# BENCHMARK" $sim_log | sed 's/^# /|                                  |            | /; s/$/ |/' >> $log
        grep -m 1 "^# THROUGHPUT" $sim_log | sed 's/^# /|                                  |            | /; s/$/ |/' >> $log
        grep -m 1 "^# PAYLOAD" $sim_log | sed 's/^# /|                                  |            | /; s/$/ |/' >> $log
        grep -m 1 "^# STORAGE" $sim_log | sed 's/^# /|                                  |            | /; s/$/ |/' >> $log
        grep -m 1 "^# LOOPBACK" $sim_log | sed 's/^# /|                                  |            | /; s/$/ |/' >> $log
        grep -m 1 "^# SUMMARY:" $sim_log | sed 's/^# /|                                  |            | /; s/$/ |/' >> $log
        grep -m 1 "^# FILES" $sim_log | sed 's/^# /|                                  |            | /; s/$/ |/' >> $log
        echo "|                                  |            | archived=loopback/${pat}_summary.txt dmem_dump/${pat}_{src,tx,rx}.txt |" >> $log
    else
        printf "|%-32s |%-10s |%-68s |\n" " $pat" " MISSING" " missing $sim_log" >> $log
    endif

    printf "|---------------------------------------------------------------------------------------------------------------|\n" >> $log
end

cat $log

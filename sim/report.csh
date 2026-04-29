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
cat $log

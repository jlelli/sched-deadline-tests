#!/bin/bash
. ../utils.sh
TFULL=`basename $0`
TNAME=${TFULL%.*}
TDESC="
###########################################
#  
#    test: $TNAME
#
#    This test doesn't do anything,
#    it is just a skeleton to demonstrate
#    how to properly build tests.
#
###########################################

"
TRACE=${1-0}
EVENTS="sched_wakeup* sched_switch sched_migrate*"

print_test_info

dump_on_oops
trace_start

trace_write "start $TNAME"

trace_write "end $TNAME"
trace_stop
trace_extract

exit 0

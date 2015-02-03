#!/bin/bash
. ../utils.sh
TFULL=`basename $0`
TNAME=${TFULL%.*}
TDESC="
##############################################
#
#    test: $TNAME
#
#    Stress SCHED_DEADLINE's yield semantic
#    by running a task that perform a tight
#    loop with yields for 5s.
#
##############################################

"
TRACE=${1-0}
EVENTS="sched_wakeup* sched_switch sched_migrate*"

print_test_info

dump_on_oops
trace_start

trace_write "start $TNAME"
./periodic_yield
trace_write "end $TNAME"

trace_stop
trace_extract

exit 0

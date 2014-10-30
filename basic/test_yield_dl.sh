#!/bin/bash
. ../utils.sh
TDESC="
##############################################
#
#    Stress SCHED_DEADLINE's yield semantic
#
##############################################

"
TNAME="test_yield_dl"
TRACE=${1-0}
EVENTS="sched_wakeup* sched_switch sched_migrate*"

print_test_info

dump_on_oops
trace_start

./periodic_yield

trace_stop
trace_extract

exit 0

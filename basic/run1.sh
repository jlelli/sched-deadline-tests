#!/bin/bash
. ../utils.sh
TDESC="
###########################################
#
#    Run cpuhog inside a SCHED_DEADLINE
#    reservation
#
###########################################

"
TNAME="run1"
TRACE=${1-0}
EVENTS="sched_wakeup* sched_switch sched_migrate*"

print_test_info

dump_on_oops
trace_start

trace_write "Launch pthread_test inherit"

schedtool -E -t 10000000:100000000 -e ./cpuhog &
sleep 10
PID=$(pgrep cpuhog)
kill -9 $PID

trace_stop
trace_extract

exit 0

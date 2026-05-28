#!/bin/bash
. ../../lib/utils.sh
TFULL=`basename $0`
TNAME=${TFULL%.*}
TDESC="
###########################################
#  
#    test: $TNAME
#
#    Run cpuhog inside a SCHED_DEADLINE
#    reservation
#
###########################################

"
TRACE=${1-0}
SLEEP=${2-10}
EVENTS="sched_wakeup* sched_switch sched_migrate*"

print_test_info

dump_on_oops
trace_start

trace_write "start $TNAME"
# budget 10ms, deadline 100ms, period 100ms
chrt -d --sched-runtime 10000000 --sched-deadline 100000000 --sched-period 100000000 0 ./cpuhog &

trace_write "sleep for ${SLEEP}s"
sleep $SLEEP

PID=$(ps -eo comm,pid | grep '^cpuhog' | awk '{ print $2 }')
trace_write "kill $PID"
kill -9 $PID >/dev/null 2>&1

trace_write "end $TNAME"
trace_stop
trace_extract

exit 0

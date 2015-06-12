#!/bin/bash
. ../utils.sh
TFULL=`basename $0`
TNAME=${TFULL%.*}
TDESC="
###########################################
#  
#    test: $TNAME
#
#    ...
#
###########################################

"
TRACE=${1-0}
EVENTS="sched_wakeup* sched_switch sched_migrate* sched_pi_setprio"
CPUSET_DIR=/sys/fs/cgroup

tear_down() {
  trace_write "kill $PID"
  kill -9 $PID
  
  trace_stop
  trace_extract
}

print_test_info

dump_on_oops
trace_start

trace_write "TEST $TNAME START"

trace_write "Launch pthread_test [inherit]"
./pthread_test inherit

trace_write "PASS"
trace_write "TEST $TNAME FINISH"
tear_down
sleep 1

exit 0

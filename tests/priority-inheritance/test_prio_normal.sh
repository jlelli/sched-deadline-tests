#!/bin/bash
. ../../lib/utils.sh
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
EVENTS="sched_wakeup* sched_switch sched_migrate*"
CPUSET_DIR=/sys/fs/cgroup

tear_down() {
  if [ -n "$PID" ] && kill -0 $PID 2>/dev/null; then
    trace_write "kill $PID"
    kill -9 $PID 2>/dev/null
  fi

  trace_stop
  trace_extract
}

print_test_info

dump_on_oops
trace_start

trace_write "TEST $TNAME START"

trace_write "Launch pthread_test [normal]"
./pthread_test &
PID=$!

trace_write "pid: $PID"
trace_write "Sleep for 5s to let test run"
sleep 5

trace_write "Sending SIGINT to pthread_test"
kill -INT $PID
wait $PID
RES=$?

if [ $RES -eq 0 ]; then
  trace_write "PASS"
else
  trace_write "FAIL: pthread_test exited with $RES"
  tear_down
  exit 1
fi
trace_write "TEST $TNAME FINISH"
tear_down
sleep 1

exit 0

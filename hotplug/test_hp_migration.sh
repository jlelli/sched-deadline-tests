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
RUNS=${2-10}
EVENTS="sched_wakeup* sched_switch sched_migrate*"

tear_down() {
  trace_write "kill ${PID}"
  kill -9 ${PID}
  
  trace_stop
  trace_extract
  enable_ac
}

print_test_info

dump_on_oops
trace_start

trace_write "start $TNAME"

trace_write "disabling admission control"
echo -1 > /proc/sys/kernel/sched_rt_runtime_us

CPUS="1,2,3,4"
for i in $(seq 1 ${RUNS}); do
  trace_write "run ${i}"

  schedtool -a ${CPUS} -E -t 50000:100000 -e ./cpuhog &
  PID=$!
  CPU=$(ps -o pid,psr | grep ${PID} | awk ' {print $2} ')
  trace_write "task ${PID} runs on CPU ${CPU}"
  
  sleep 1
  trace_write "turning off CPU ${CPU}"
  echo 0 > /sys/devices/system/cpu/cpu${CPU}/online
  if [ $? -ne 0 ]; then
    trace_write "FAIL: couldn't turn CPU ${CPU} off"
    tear_down
    exit 1
  fi
  
  sleep 1
  kill -9 ${PID}
  trace_write "turning on CPU ${CPU}"
  echo 1 > /sys/devices/system/cpu/cpu${CPU}/online
  sleep 1
done

trace_write "enabling admission control"
echo 950000 > /proc/sys/kernel/sched_rt_runtime_us
if [ $? -ne 0 ]; then
  trace_write "FAIL: couldn't enable AC"
  tear_down
  exit 1
fi

trace_write "PASS"
trace_write "TEST $TNAME FINISH"
trace_stop
trace_extract

exit 0

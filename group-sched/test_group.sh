#!/bin/bash
. ../utils.sh
TFULL=`basename $0`
TNAME=${TFULL%.*}
TDESC="
###############################################################################
#
#    test: $TNAME
#
#    ...
#
###############################################################################

"
TRACE=${1-0}
EVENTS="sched_wakeup* sched_switch sched_migrate*"
CPUSET_DIR=/sys/fs/cgroup

tear_down() {
  trace_write "kill $PID1 and $PID2"
  kill -TERM $PID1 $PID2
  sleep 1

  trace_write "De-configuring groups"
  rmdir ${CPUSET_DIR}/g1
  if [ $? -ne 0 ]; then
    trace_write "ERROR: failed to remove cpusetA"
    exit 1
  fi
  /bin/echo 950000 > ${CPUSET_DIR}/cpu.rt_runtime_us

  trace_stop
  trace_extract
}

print_test_info

mount -t cgroup -o cpu cpu ${CPUSET_DIR}

#dump_on_oops
trace_start

trace_write "Configuring groups"
/bin/echo 500000 > ${CPUSET_DIR}/cpu.rt_runtime_us
mkdir -p ${CPUSET_DIR}/g1
/bin/echo 300000 > ${CPUSET_DIR}/g1/cpu.rt_runtime_us

trace_write "Launch 1 cpuhog process"

schedtool -F -p 10 -e ./burn &
PID1=$!
schedtool -F -p 10 -e ./burn &
PID2=$!
trace_write "pids: $PID1 $PID2"

trace_write "Moving $PID1 and $PID2 into g1"
/bin/echo ${PID1} > ${CPUSET_DIR}/g1/tasks
/bin/echo ${PID2} > ${CPUSET_DIR}/g1/tasks

trace_write "Sleep for 10s"
sleep 10

tear_down
trace_write "PASS"

exit 0

#!/bin/bash
. ../utils.sh
TFULL=`basename $0`
TNAME=${TFULL%.*}
TDESC="
###########################################
#  
#    test: $TNAME
#
#    Launch a cpu hog task. Attach it to
#    a (10,20) reservation. Move it into
#    an exclusive cpuset. Try to change
#    its reservation to (6,20).
#
###########################################

"
TRACE=${1-0}
EVENTS="sched_wakeup* sched_switch sched_migrate*"
CPUSET_DIR=/sys/fs/cgroup

tear_down() {
  trace_write "kill $PID"
  kill -9 $PID
  sleep 1
  rmdir ${CPUSET_DIR}/cpusetA
  
  trace_stop
  trace_extract
}

print_test_info

mount -t cgroup -o cpuset cpuset ${CPUSET_DIR} >/dev/null 2>&1
mkdir -p ${CPUSET_DIR}/cpusetA

dump_on_oops
trace_start

trace_write "Configuring exclusive cpusets"
/bin/echo 1 > ${CPUSET_DIR}/cpuset.cpu_exclusive
/bin/echo 0 > ${CPUSET_DIR}/cpuset.sched_load_balance

trace_write "Configuring cpuset: cpusetA[2]"
/bin/echo 2 >  ${CPUSET_DIR}/cpusetA/cpuset.cpus
/bin/echo 0 > ${CPUSET_DIR}/cpusetA/cpuset.mems
/bin/echo 1 > ${CPUSET_DIR}/cpusetA/cpuset.cpu_exclusive
/bin/echo 1 > ${CPUSET_DIR}/cpusetA/cpuset.mem_exclusive

trace_write "Launch 1 process"

./burn &
PID=$!

trace_write "pid: $PID"

trace_write "Attaching a (10,20) reservation to $PID"

# budget 10ms, period 20ms
#
schedtool -E -t 10000000:20000000 $PID

trace_write "Sleep for 2s"
sleep 2

trace_write "moving ${PID} to cpusetA"

/bin/echo $PID > $CPUSET_DIR/cpusetA/tasks
if [ $? -eq 0 ]; then
  trace_write "Task moved to new cpuset"
else
  trace_write "FAIL: task couldn't attach"
  tear_down
  exit 1
fi

trace_write "Sleep for 2s"
sleep 2

trace_write "Trying to update the reservation of process $PID to (6,20)"

# budget 6ms, same period 20ms
#
schedtool -E -t 6000000:20000000 $PID

# It may fail
if [ $? -eq 0 ]; then
  trace_write "Reservation updated to (6,20)"
else
  echo "FAIL: couldn't change reservation parameters"
  tear_down
  exit 1
fi

trace_write "Sleep for 2s"
sleep 2

trace_write "PASS"
tear_down

exit 0

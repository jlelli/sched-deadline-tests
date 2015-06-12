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
RUNS=5
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

trace_start

trace_write "Configuring exclusive cpusets"
/bin/echo 1 > ${CPUSET_DIR}/cpuset.cpu_exclusive
/bin/echo 0 > ${CPUSET_DIR}/cpuset.sched_load_balance

trace_write "Configuring cpuset: cpusetA[1-3]"
/bin/echo 1-3 >  ${CPUSET_DIR}/cpusetA/cpuset.cpus
/bin/echo 0 > ${CPUSET_DIR}/cpusetA/cpuset.mems
/bin/echo 1 > ${CPUSET_DIR}/cpusetA/cpuset.cpu_exclusive
/bin/echo 1 > ${CPUSET_DIR}/cpusetA/cpuset.mem_exclusive

trace_write "Launch 1 process"

./cpuhog &
PID=$!

trace_write "pid: $PID"

trace_write "Attaching a (10,20) reservation to $PID"

# budget 50us, period 100us
#
schedtool -E -t 50000:100000 $PID

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

ONLINE_CPUS=3
for i in $(seq 1 ${RUNS}); do
  trace_write "run ${i}"
  trace_write "online cpus: ${ONLINE_CPUS}"

  CPU=$(ps -o pid,psr | grep ${PID} | awk ' {print $2} ')
  trace_write "task ${PID} runs on CPU ${CPU}"
  
  sleep 1
  trace_write "turning off CPU ${CPU}"
  echo 0 > /sys/devices/system/cpu/cpu${CPU}/online
  RES=$?
  if [ $ONLINE_CPUS -gt 1 ] && [ $RES -ne 0 ]; then
    trace_write "FAIL: couldn't turn CPU ${CPU} off"
    tear_down
    exit 1
  fi
  if [ $ONLINE_CPUS -eq 1 ] && [ $RES -ne 1 ]; then
    trace_write "FAIL: CPU ${CPU} has been turned off!"
    tear_down
    exit 1
  fi
  
  sleep 1
  if [ $ONLINE_CPUS -gt 1 ]; then
    trace_write "turning on CPU ${CPU}"
    echo 1 > /sys/devices/system/cpu/cpu${CPU}/online
    ONLINE_CPUS=$((ONLINE_CPUS-1))
  fi

  sleep 1
done

trace_write "Sleep for 2s"
sleep 2

trace_write "PASS"
tear_down

exit 0

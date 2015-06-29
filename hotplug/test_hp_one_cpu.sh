#!/bin/bash
. ../utils.sh
TFULL=`basename $0`
TNAME=${TFULL%.*}
TDESC="
###############################################################################
#
#    test: $TNAME
#
#    Create an exclusive cpuset and put a task, attached to a DL reservation,
#    to run into it. Repetedly try to turn off the CPU the task is running on.
#    Check that this always fails.
#
###############################################################################

"
TRACE=${1-0}
RUNS=5
EVENTS="sched_wakeup* sched_switch sched_migrate*"
CPUSET_DIR=/sys/fs/cgroup

tear_down() {
  trace_write "kill $PID"
  kill -TERM $PID
  sleep 1
  rmdir ${CPUSET_DIR}/cpusetA
  if [ $? -ne 0 ]; then
    trace_write "ERROR: failed to remove cpusetA"
    exit 1
  fi

  sleep 1
  trace_write "Moving tasks back in root cpuset"
  for t in `cat ${CPUSET_DIR}/cpuset-work/tasks`; do
    /bin/echo $t > ${CPUSET_DIR}/tasks >/dev/null 2>&1
  done

  sleep 1
  rmdir ${CPUSET_DIR}/cpuset-work
  if [ $? -ne 0 ]; then
    trace_write "ERROR: failed to remove cpuset-work"
    exit 1
  fi

  sleep 1
  trace_write "De-configuring exclusive cpusets"
  /bin/echo 1 > ${CPUSET_DIR}/cpuset.sched_load_balance
  /bin/echo 0 > ${CPUSET_DIR}/cpuset.cpu_exclusive

  trace_stop
  trace_extract
}

print_test_info
dump_on_oops

mount -t cgroup -o cpuset cpuset ${CPUSET_DIR} >/dev/null 2>&1
trace_start

trace_write "Configuring exclusive cpusets"
/bin/echo 1 > ${CPUSET_DIR}/cpuset.cpu_exclusive
/bin/echo 0 > ${CPUSET_DIR}/cpuset.sched_load_balance

mkdir -p ${CPUSET_DIR}/cpusetA
mkdir -p ${CPUSET_DIR}/cpuset-work

trace_write "Configuring cpuset: cpusets-work[0-2]"
/bin/echo 0-2 >  ${CPUSET_DIR}/cpuset-work/cpuset.cpus
/bin/echo 0 > ${CPUSET_DIR}/cpuset-work/cpuset.mems
/bin/echo 1 > ${CPUSET_DIR}/cpuset-work/cpuset.cpu_exclusive

trace_write "Configuring cpuset: cpusetA[3]"
/bin/echo 3 >  ${CPUSET_DIR}/cpusetA/cpuset.cpus
/bin/echo 0 > ${CPUSET_DIR}/cpusetA/cpuset.mems
/bin/echo 1 > ${CPUSET_DIR}/cpusetA/cpuset.cpu_exclusive

trace_write "Moving tasks in cpuset-work"
for t in `cat ${CPUSET_DIR}/tasks`; do
  /bin/echo $t > ${CPUSET_DIR}/cpuset-work/tasks >/dev/null 2>&1
done

trace_write "Launch 1 process"

./cpuhog &
PID=$!

trace_write "pid: $PID"

trace_write "Attaching a (.05,.10) reservation to $PID"

# budget 50us, period 100us
#
schedtool -E -t 50000:100000 $PID

trace_write "Sleep for 1s"
sleep 1

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

ONLINE_CPUS=1
for i in $(seq 1 ${RUNS}); do
  trace_write "run ${i}"
  trace_write "online cpus: ${ONLINE_CPUS}"

  CPU=$(ps -o pid,psr | grep ${PID} | awk ' {print $2} ')
  trace_write "task ${PID} runs on CPU ${CPU}"
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
    trace_write "turning on CPU ${CPU}"
    echo 1 > /sys/devices/system/cpu/cpu${CPU}/online
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

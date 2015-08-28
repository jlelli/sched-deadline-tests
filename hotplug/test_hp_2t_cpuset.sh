#!/bin/bash
. ../utils.sh
TFULL=`basename $0`
TNAME=${TFULL%.*}
TDESC="
###############################################################################
#
#    test: $TNAME
#
#    Create an exclusive cpuset composed of 3 CPUs and put a DL task to run
#    into it. Start turning off CPUs and verify that CPUs can be turned off
#    all but one (the last the task happens to run in).
#
###############################################################################

"
TRACE=${1-0}
RUNS=${2-5}
EVENTS="sched_wakeup* sched_switch sched_migrate*"
CPUSET_DIR=/sys/fs/cgroup

tear_down() {
  trace_write "kill $PID1 $PID2"
  kill -TERM $PID1 $PID2
  sleep 1
  rmdir ${CPUSET_DIR}/cpusetA
  if [ $? -ne 0 ]; then
    trace_write "ERROR: failed to remove cpusetA"
    exit 1
  fi

  sleep 1
  trace_write "Moving tasks back in root cpuset: "
  trace_write "tasks tasks: "
  cat ${CPUSET_DIR}/cpuset-work/tasks
  for t in `cat ${CPUSET_DIR}/cpuset-work/tasks`; do
    /bin/echo $t > ${CPUSET_DIR}/tasks >/dev/null 2>&1
  done
  echo ""
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

mount -t cgroup -o cpuset cpuset ${CPUSET_DIR} >/dev/null 2>&1
trace_start

trace_write "Configuring exclusive cpusets"
/bin/echo 1 > ${CPUSET_DIR}/cpuset.cpu_exclusive
/bin/echo 0 > ${CPUSET_DIR}/cpuset.sched_load_balance

mkdir -p ${CPUSET_DIR}/cpusetA
mkdir -p ${CPUSET_DIR}/cpuset-work

trace_write "Configuring cpuset: cpusets-work[1-2]"
/bin/echo 1-2 >  ${CPUSET_DIR}/cpuset-work/cpuset.cpus
/bin/echo 0 > ${CPUSET_DIR}/cpuset-work/cpuset.mems
/bin/echo 1 > ${CPUSET_DIR}/cpuset-work/cpuset.cpu_exclusive
/bin/echo 1 > ${CPUSET_DIR}/cpuset-work/cpuset.sched_load_balance

trace_write "Configuring cpuset: cpusetA[0,3-4]"
/bin/echo 0,3,4 >  ${CPUSET_DIR}/cpusetA/cpuset.cpus
/bin/echo 0 > ${CPUSET_DIR}/cpusetA/cpuset.mems
/bin/echo 1 > ${CPUSET_DIR}/cpusetA/cpuset.cpu_exclusive
/bin/echo 1 > ${CPUSET_DIR}/cpusetA/cpuset.sched_load_balance

trace_write "Moving tasks in cpuset-work: "
for t in `cat ${CPUSET_DIR}/tasks`; do
  /bin/echo $t > ${CPUSET_DIR}/cpuset-work/tasks >/dev/null 2>&1
done

trace_write "Launch 2 processes"
./cpuhog &
PID1=$!
./cpuhog &
PID2=$!

trace_write "pid1: $PID1"
trace_write "Attaching a (.05,.10) reservation to $PID"
# budget 50us, period 100us
#
schedtool -E -t 50000:100000 $PID1

trace_write "Sleep for 1s"
sleep 1

trace_write "pid2: $PID2"
trace_write "Attaching a (.02,.10) reservation to $PID2"
# budget 20us, period 100us
#
schedtool -E -t 20000:100000 $PID2

trace_write "Sleep for 1s"
sleep 1

trace_write "moving ${PID1} and ${PID2} to cpusetA"

/bin/echo $PID1 > $CPUSET_DIR/cpusetA/tasks
if [ $? -eq 0 ]; then
  trace_write "Task moved to new cpuset"
else
  trace_write "FAIL: task couldn't attach"
  tear_down
  exit 1
fi

/bin/echo $PID2 > $CPUSET_DIR/cpusetA/tasks
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

  #CPU=$(ps -o pid,psr | grep ${PID} | awk ' {print $2} ')
  CPU=$(cat /proc/${PID1}/stat | awk ' {print $39} ')
  trace_write "task ${PID} runs on CPU ${CPU}"
  trace_write "turning off CPU ${CPU}"
  /bin/echo 0 > /sys/devices/system/cpu/cpu${CPU}/online
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

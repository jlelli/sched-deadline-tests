#!/bin/bash
. ../utils.sh
TFULL=`basename $0`
TNAME=${TFULL%.*}
TDESC="
###############################################################################
#
#    test: $TNAME
#
#    Launch a cpu hog task. Attach it to a (10,20) reservation. Move it into an
#    exclusive cpuset. Try to change its reservation to (6,20).
#
###############################################################################

"
TRACE=${1-0}
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

  trace_write "Moving all tasks back in root cpuset"
  for t in `cat ${CPUSET_DIR}/cpusetB/tasks`; do
    /bin/echo $t > ${CPUSET_DIR}/tasks >/dev/null 2>&1
  done
  sleep 1
  rmdir ${CPUSET_DIR}/cpusetB
  if [ $? -ne 0 ]; then
    trace_write "ERROR: failed to remove cpusetB"
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

mount -t cgroup -o cpuset cpuset ${CPUSET_DIR}

dump_on_oops
trace_start

trace_write "Configuring exclusive cpusets"
/bin/echo 1 > ${CPUSET_DIR}/cpuset.cpu_exclusive
/bin/echo 0 > ${CPUSET_DIR}/cpuset.sched_load_balance

mkdir -p ${CPUSET_DIR}/cpusetA
mkdir -p ${CPUSET_DIR}/cpusetB

trace_write "Configuring cpuset: cpusetA[3]"
/bin/echo 3 >  ${CPUSET_DIR}/cpusetA/cpuset.cpus
/bin/echo 0 > ${CPUSET_DIR}/cpusetA/cpuset.mems
/bin/echo 1 > ${CPUSET_DIR}/cpusetA/cpuset.cpu_exclusive

trace_write "Configuring cpuset: cpusetB[0-2,4]"
/bin/echo 0,1,2,4 >  ${CPUSET_DIR}/cpusetB/cpuset.cpus
/bin/echo 0 > ${CPUSET_DIR}/cpusetB/cpuset.mems
/bin/echo 1 > ${CPUSET_DIR}/cpusetB/cpuset.cpu_exclusive
/bin/echo 1 > ${CPUSET_DIR}/cpusetB/cpuset.sched_load_balance

trace_write "Moving all tasks in cpusetB"
for t in `cat ${CPUSET_DIR}/tasks`; do
	/bin/echo $t > ${CPUSET_DIR}/cpusetB/tasks >/dev/null 2>&1
done

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

tear_down
trace_write "PASS"

exit 0

#!/bin/bash
. ../../lib/utils.sh
. ../../lib/cgroup_helpers.sh
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
  trace_write "kill $PID"
  kill -TERM $PID
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
  cleanup_cpuset ${CPUSET_DIR} cpusetA
  cleanup_cpuset ${CPUSET_DIR} cpuset-work

  trace_stop
  trace_extract
}

print_test_info

# cgroups v1: mount cpuset, v2: already mounted at /sys/fs/cgroup
if [ "$(detect_cgroup_version)" = "v1" ]; then
    mount -t cgroup -o cpuset cpuset ${CPUSET_DIR} >/dev/null 2>&1
fi

trace_start
test_start

trace_write "Configuring exclusive cpusets"
setup_cpuset ${CPUSET_DIR} cpuset-work "1-2" 0
setup_cpuset ${CPUSET_DIR} cpusetA "3-5" 0

trace_write "Moving tasks in cpuset-work"
# Note: in cgroups v2, tasks are moved automatically to children when created

trace_write "Launch 1 process"

./cpuhog &
PID=$!

trace_write "pid: $PID"

trace_write "Attaching a (.05,.10) reservation to $PID"

# budget 50us, period 100us
#
chrt -d --sched-runtime 50000000 --sched-deadline 100000000 --sched-period 100000000 -p 0 $PID

trace_write "Sleep for 1s"
sleep 1

trace_write "moving ${PID} to cpusetA"

move_task_to_cgroup ${CPUSET_DIR} cpusetA $PID
if [ $? -eq 0 ]; then
  trace_write "Task moved to new cpuset"
else
  test_fail "task couldn't attach"
  tear_down
  exit 1
fi

trace_write "Sleep for 2s"
sleep 2

ONLINE_CPUS=3
OFFLINE_CPUS=""
for i in $(seq 1 ${RUNS}); do
  trace_write "run ${i}"
  trace_write "online cpus: ${ONLINE_CPUS}"

  #CPU=$(ps -o pid,psr | grep ${PID} | awk ' {print $2} ')
  CPU=$(cat /proc/${PID}/stat | awk ' {print $39} ')
  trace_write "task ${PID} runs on CPU ${CPU}"
  trace_write "turning off CPU ${CPU}"
  /bin/echo 0 > /sys/devices/system/cpu/cpu${CPU}/online
  RES=$?
  if [ $ONLINE_CPUS -gt 1 ] && [ $RES -ne 0 ]; then
    test_fail "couldn't turn CPU ${CPU} off"
    # Turn back on any CPUs we turned off
    for c in $OFFLINE_CPUS; do
      echo 1 > /sys/devices/system/cpu/cpu${c}/online
    done
    tear_down
    exit 1
  fi
  if [ $ONLINE_CPUS -eq 1 ] && [ $RES -ne 1 ]; then
    test_fail "CPU ${CPU} has been turned off!"
    trace_write "turning on CPU ${CPU}"
    echo 1 > /sys/devices/system/cpu/cpu${CPU}/online
    # Turn back on any CPUs we turned off
    for c in $OFFLINE_CPUS; do
      echo 1 > /sys/devices/system/cpu/cpu${c}/online
    done
    tear_down
    exit 1
  fi

  sleep 1
  if [ $ONLINE_CPUS -gt 1 ]; then
    # Don't turn it back on yet - keep it offline
    OFFLINE_CPUS="$OFFLINE_CPUS $CPU"
    ONLINE_CPUS=$((ONLINE_CPUS-1))
  fi

  sleep 1
done

# Turn all CPUs back on
trace_write "Turning CPUs back on"
for c in $OFFLINE_CPUS; do
  trace_write "turning on CPU ${c}"
  echo 1 > /sys/devices/system/cpu/cpu${c}/online
done

trace_write "Sleep for 2s"
sleep 2

test_pass
tear_down

exit 0

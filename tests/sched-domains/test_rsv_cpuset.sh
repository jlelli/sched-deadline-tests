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
  kill -TERM $PID 2>/dev/null
  sleep 1

  trace_write "De-configuring exclusive cpusets"
  cleanup_cpuset ${CPUSET_DIR} cpusetA
  cleanup_cpuset ${CPUSET_DIR} cpusetB

  trace_stop
  trace_extract
}

print_test_info

# cgroups v1: mount cpuset, v2: already mounted at /sys/fs/cgroup
if [ "$(detect_cgroup_version)" = "v1" ]; then
    mount -t cgroup -o cpuset cpuset ${CPUSET_DIR} >/dev/null 2>&1
fi

dump_on_oops
trace_start
test_start

trace_write "Configuring exclusive cpusets"
trace_write "Configuring cpuset: cpusetA[3]"
setup_cpuset ${CPUSET_DIR} cpusetA "3" 0

trace_write "Configuring cpuset: cpusetB[0-2,4]"
setup_cpuset ${CPUSET_DIR} cpusetB "0-2,4" 0

trace_write "Launch 1 process"

./burn &
PID=$!

trace_write "pid: $PID"

trace_write "Attaching a (10,20) reservation to $PID"

# budget 10ms, period 20ms
#
chrt -d --sched-runtime 10000000 --sched-deadline 20000000 --sched-period 20000000 -p 0 $PID

trace_write "Sleep for 2s"
sleep 2

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

trace_write "Trying to update the reservation of process $PID to (6,20)"

# budget 6ms, same period 20ms
#
chrt -d --sched-runtime 6000000 --sched-deadline 20000000 --sched-period 20000000 -p 0 $PID

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
test_pass

exit 0

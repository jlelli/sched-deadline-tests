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
#    Test AC over exclusive cpusets.
#
#    Launch 3 cpu hog tasks. Attach them to several reservations. Try to move
#    them into an exclusive cpuset. Last one has to fail as it doesn't fit with
#    its researvation parameters. Decrease now the bandwidth of the first one
#    to make for the last one. Move last one into the exclusive cpuset.
#
###############################################################################

"
TRACE=${1-0}
EVENTS="sched_wakeup* sched_switch sched_migrate*"
CPUSET_DIR=/sys/fs/cgroup

pass() {
  test_pass
}

tear_down() {
  trace_write "kill $PID1 $PID2 $PID3"
  kill -TERM $PID1 $PID2 $PID3 2>/dev/null
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

trace_write "Configuring cpuset: cpusetB[0-2]"
setup_cpuset ${CPUSET_DIR} cpusetB "0-2" 0

trace_write "Launch 3 processes"

./burn &
PID1=$!
./burn &
PID2=$!
./burn &
PID3=$!

trace_write "Sleep for 2s"
sleep 2

trace_write "Attaching a (9,20) reservation to $PID1"
# budget 9ms, period 20ms (45% CPU)
# With 5% fair_server: 45% + 5% = 50% < 95% - should fit
chrt -d --sched-runtime 9000000 --sched-deadline 20000000 --sched-period 20000000 -p 0 $PID1
if [ $? -ne 0 ]; then
  test_fail "couldn't attach $PID1 to (9,20)"
  tear_down
  exit 1
fi

trace_write "Sleep for 1s"
sleep 1

trace_write "Attaching a (7,20) reservation to $PID2"
# budget 7ms, period 20ms (35% CPU)
# Total: 45% + 35% = 80%, with fair_server: 80% + 5% = 85% < 95% - should fit
chrt -d --sched-runtime 7000000 --sched-deadline 20000000 --sched-period 20000000 -p 0 $PID2
if [ $? -ne 0 ]; then
  test_fail "couldn't attach $PID2 to (7,20)"
  tear_down
  exit 1
fi

trace_write "Sleep for 1s"
sleep 1

trace_write "Attaching a (4,20) reservation to $PID3"
# budget 4ms, period 20ms (20% CPU)
# Total would be: 80% + 20% = 100%, with fair_server: 100% + 5% = 105% > 95%
chrt -d --sched-runtime 4000000 --sched-deadline 20000000 --sched-period 20000000 -p 0 $PID3
if [ $? -ne 0 ]; then
  test_fail "couldn't attach $PID3 to (4,20)"
  tear_down
  exit 1
fi

trace_write "Sleep for 1s"
sleep 1

trace_write "moving ${PID1} to cpusetA"

move_task_to_cgroup ${CPUSET_DIR} cpusetA $PID1
if [ $? -eq 0 ]; then
  trace_write "OK: task moved to new cpuset"
else
  test_fail "task couldn't attach"
  tear_down
  exit 1
fi

trace_write "moving ${PID2} to cpusetA"

move_task_to_cgroup ${CPUSET_DIR} cpusetA $PID2
if [ $? -eq 0 ]; then
  trace_write "OK: task moved to new cpuset"
else
  test_fail "task couldn't attach"
  tear_down
  exit 1
fi

trace_write "moving ${PID3} to cpusetA"

move_task_to_cgroup ${CPUSET_DIR} cpusetA $PID3
if [ $? -eq 0 ]; then
  test_fail "task moved to new cpuset"
  tear_down
  exit 1
else
  trace_write "OK: task couldn't attach"
fi

trace_write "Sleep for 2s"
sleep 2

trace_write "Trying to update the reservation of $PID1 to (5,20)"

# budget 5ms, same period 20ms (25% CPU)
# This reduces total from 80% to 60% (25% + 35%)
# With fair_server: 60% + 5% = 65%, leaving room for PID3's 20%
# Total would be: 60% + 20% = 80%, with fair_server: 80% + 5% = 85% < 95% - should fit
chrt -d --sched-runtime 5000000 --sched-deadline 20000000 --sched-period 20000000 -p 0 $PID1
if [ $? -ne 0 ]; then
  test_fail "couldn't attach $PID1 to (5,20)"
  tear_down
  exit 1
fi

trace_write "moving ${PID3} to cpusetA"

move_task_to_cgroup ${CPUSET_DIR} cpusetA $PID3
if [ $? -eq 0 ]; then
  trace_write "OK: task moved to new cpuset"
else
  test_fail "task couldn't attach"
  tear_down
  exit 1
fi

trace_write "Sleep for 2s"
sleep 2

tear_down
test_pass

exit 0

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
#    Test AC over exclusive cpusets. Test inter-cpusets migrations and
#    bandwidth updates.
#
#    Launch 4 cpu hog tasks. Attach them to several reservations. Try to move
#    them into two exclusive cpusets. Try to change cpusets mask. Try to see if
#    tasks can be moved around once masks are changed.
#
###############################################################################

"
TRACE=${1-0}
EVENTS="sched_wakeup* sched_switch sched_migrate*"
CPUSET_DIR=/sys/fs/cgroup

tear_down() {
  trace_write "kill $PID1 $PID2 $PID3 $PID4"
  kill -TERM $PID1 $PID2 $PID3 $PID4 2>/dev/null
  sleep 1

  trace_write "De-configuring exclusive cpusets"
  cleanup_cpuset ${CPUSET_DIR} cpusetA
  cleanup_cpuset ${CPUSET_DIR} cpusetB
  cleanup_cpuset ${CPUSET_DIR} cpuset-work

  trace_stop
  trace_extract
}

tear_down_nokill() {
  trace_write "De-configuring exclusive cpusets"
  cleanup_cpuset ${CPUSET_DIR} cpuset-work

  trace_stop
  trace_extract
}

print_test_info

# cgroups v1: mount cpuset, v2: already mounted at /sys/fs/cgroup
if [ "$(detect_cgroup_version)" = "v1" ]; then
    mount -t cgroup -o cpuset cpuset ${CPUSET_DIR} >/dev/null 2>&1
fi

enable_ac
dump_on_oops
trace_start
trace_write "TEST $TNAME START"

trace_write "Configuring exclusive cpusets"
trace_write "Configuring cpuset: cpuset-work[3]"
setup_cpuset ${CPUSET_DIR} cpuset-work "3" 0

trace_write "Configuring cpuset: cpusetA[0]"
setup_cpuset ${CPUSET_DIR} cpusetA "0" 0

trace_write "Configuring cpuset: cpusetB[1-2]"
setup_cpuset ${CPUSET_DIR} cpusetB "1-2" 0

trace_write "Launch 4 processes"

./burn &
PID1=$!
./burn &
PID2=$!
./burn &
PID3=$!
./burn &
PID4=$!

trace_write "pids: $PID1 $PID2 $PID3 $PID4"

trace_write "Attaching a (10,20) reservation to $PID1"
# budget 10ms, period 20ms
#
chrt -d --sched-runtime 10000000 --sched-deadline 20000000 --sched-period 20000000 -p 0 $PID1
if [ $? -ne 0 ]; then
  trace_write "FAIL: couldn't attach $PID1 to (10,20)"
  tear_down
  exit 1
fi

trace_write "Sleep for 1s"
sleep 2

trace_write "moving ${PID1} to cpusetA"
move_task_to_cgroup ${CPUSET_DIR} cpusetA $PID1
if [ $? -eq 0 ]; then
  trace_write "OK: task moved to new cpuset"
else
  trace_write "FAIL: task couldn't attach"
  tear_down
  exit 1
fi

trace_write "Sleep for 1s"
sleep 1

trace_write "Attaching a (12,20) reservation to $PID2"
# budget 12ms, period 20ms
#
chrt -d --sched-runtime 12000000 --sched-deadline 20000000 --sched-period 20000000 -p 0 $PID2
if [ $? -ne 0 ]; then
  trace_write "FAIL: couldn't attach $PID2 to (12,20)"
  tear_down
  exit 1
fi

trace_write "Sleep for 1s"
sleep 1

trace_write "moving ${PID2} to cpusetB"
move_task_to_cgroup ${CPUSET_DIR} cpusetB $PID2
if [ $? -eq 0 ]; then
  trace_write "OK: task moved to new cpuset"
else
  trace_write "FAIL: task couldn't attach"
  tear_down
  exit 1
fi

trace_write "Sleep for 1s"
sleep 1

trace_write "Attaching a (6,20) reservation to $PID3"
# budget 6ms, period 20ms
#
chrt -d --sched-runtime 6000000 --sched-deadline 20000000 --sched-period 20000000 -p 0 $PID3
if [ $? -ne 0 ]; then
  trace_write "FAIL: couldn't attach $PID3 to (6,20)"
  tear_down
  exit 1
fi

trace_write "Sleep for 1s"
sleep 1

trace_write "moving ${PID3} to cpusetB"
move_task_to_cgroup ${CPUSET_DIR} cpusetB $PID3
if [ $? -eq 0 ]; then
  trace_write "OK: task moved to new cpuset"
else
  trace_write "FAIL: task couldn't attach"
  tear_down
  exit 1
fi
trace_write "Sleep for 1s"
sleep 1

trace_write "Attaching a (10,20) reservation to $PID4"
# budget 10ms, period 20ms
#
chrt -d --sched-runtime 10000000 --sched-deadline 20000000 --sched-period 20000000 -p 0 $PID4
if [ $? -ne 0 ]; then
  trace_write "FAIL: couldn't attach $PID4 to (10,20)"
  tear_down
  exit 1
fi

trace_write "Sleep for 1s"
sleep 1

trace_write "moving ${PID4} to cpusetB"
move_task_to_cgroup ${CPUSET_DIR} cpusetB $PID4
if [ $? -eq 0 ]; then
  trace_write "OK: task moved to new cpuset"
else
  trace_write "FAIL: task couldn't attach"
  tear_down
  exit 1
fi

trace_write "Sleep for 1s"
sleep 1

trace_write "trying to move ${PID2} to cpusetA"
move_task_to_cgroup ${CPUSET_DIR} cpusetA $PID2
if [ $? -eq 0 ]; then
  trace_write "FAIL: task moved to new cpuset"
  tear_down
  exit 1
else
  trace_write "OK: task couldn't attach"
fi

trace_write "Sleep for 1s"
sleep 1

trace_write "trying to change cpusetB cpumask to 2"
/bin/echo 2 >  ${CPUSET_DIR}/cpusetB/cpuset.cpus
if [ $? -eq 0 ]; then
  trace_write "FAIL: cpusetB cpumask changed"
  trace_write "Sleep for 1s"
  sleep 1
  tear_down
  exit 1
else
  trace_write "OK: cpusetB cpumask couldn't be changed"
fi

trace_write "Sleep for 1s"
sleep 1

trace_write "Modifing to (1,20) $PID4 reservation"
# budget 1ms, period 20ms
#
chrt -d --sched-runtime 1000000 --sched-deadline 20000000 --sched-period 20000000 -p 0 $PID4
if [ $? -ne 0 ]; then
  trace_write "FAIL: couldn't modify $PID4 to (1,20)"
  tear_down
  exit 1
fi

trace_write "Sleep for 1s"
sleep 1

trace_write "trying to move ${PID2} to cpusetA (borrowing CPU 1 from cpusetB)"
/bin/echo 2 >  ${CPUSET_DIR}/cpusetB/cpuset.cpus
if [ $? -eq 0 ]; then
  trace_write "OK: CPU 1 removed from cpusetB"
else
  trace_write "FAIL: couldn't remove CPU 1"
  trace_write "Sleep for 1s"
  sleep 1
  tear_down
  exit 1
fi
/bin/echo 0-1 >  ${CPUSET_DIR}/cpusetA/cpuset.cpus
if [ $? -eq 0 ]; then
  trace_write "OK: CPU 1 attached to cpusetA"
else
  trace_write "FAIL: couldn't attach CPU 1"
  trace_write "Sleep for 1s"
  sleep 1
  tear_down
  exit 1
fi
move_task_to_cgroup ${CPUSET_DIR} cpusetA $PID2
if [ $? -eq 0 ]; then
  trace_write "OK: task moved to new cpuset"
else
  trace_write "FAIL: task couldn't attach"
  trace_write "Sleep for 1s"
  sleep 1
  tear_down
  exit 1
fi

trace_write "Sleep for 1s"
sleep 1

trace_write "kill $PID1 $PID2 $PID3 $PID4"
kill -9 $PID1 $PID2 $PID3 $PID4

trace_write "Sleep for 1s"
sleep 1

rmdir ${CPUSET_DIR}/cpusetA
if [ $? -eq 0 ]; then
  trace_write "OK: cpusetA removed"
else
  trace_write "FAIL: cpusetA couldn't be removed"
  trace_write "Sleep for 1s"
  sleep 1
  tear_down_nokill
  exit 1
fi

rmdir ${CPUSET_DIR}/cpusetB
if [ $? -eq 0 ]; then
  trace_write "OK: cpusetB removed"
else
  trace_write "FAIL: cpusetB couldn't be removed"
  trace_write "Sleep for 1s"
  sleep 1
  tear_down_nokill
  exit 1
fi

trace_write "PASS"
trace_write "TEST $TNAME FINISH"

tear_down_nokill

exit 0

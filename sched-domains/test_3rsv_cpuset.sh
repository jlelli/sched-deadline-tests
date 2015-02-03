#!/bin/bash
. ../utils.sh
TFULL=`basename $0`
TNAME=${TFULL%.*}
TDESC="
###########################################
#  
#    test: $TNAME
#
#    Test AC over exclusive cpusets.
#
#    Launch 3 cpu hog tasks. Attach them to
#    several reservations. Try to move them
#    into an exclusive cpuset. Last one has
#    to fail as it doesn't fit with its
#    researvation parameters. Decrease now
#    the bandwidth of the first one to make
#    for the last one. Move last one into
#    the exclusive cpuset.
#
###########################################

"
TRACE=${1-0}
EVENTS="sched_wakeup* sched_switch sched_migrate*"
CPUSET_DIR=/sys/fs/cgroup

tear_down() {
  trace_write "kill $PID"
  kill -9 $PID1 $PID2 $PID3
  
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

trace_write "Launch 3 processes"

./burn &
PID1=$!
./burn &
PID2=$!
./burn &
PID3=$!

trace_write "pids: $PID1 $PID2 $PID3"

trace_write "Attaching a (10,20) reservation to $PID1"
# budget 10ms, period 20ms
#
schedtool -E -t 10000000:20000000 $PID1
if [ $? -ne 0 ]; then
  trace_write "FAIL: couldn't attachd $PID1 to (10,20)"
  tear_down
  exit 1
fi

trace_write "Sleep for 1s"
sleep 1

trace_write "Attaching a (8,20) reservation to $PID2"
# budget 8ms, period 20ms
#
schedtool -E -t 8000000:20000000 $PID2
if [ $? -ne 0 ]; then
  trace_write "FAIL: couldn't attachd $PID2 to (8,20)"
  tear_down
  exit 1
fi

trace_write "Sleep for 1s"
sleep 1

trace_write "Attaching a (4,20) reservation to $PID3"
# budget 4ms, period 20ms
#
schedtool -E -t 4000000:20000000 $PID3
if [ $? -ne 0 ]; then
  trace_write "FAIL: couldn't attachd $PID2 to (8,20)"
  tear_down
  exit 1
fi

trace_write "Sleep for 1s"
sleep 1

trace_write "moving ${PID1} to cpusetA"

/bin/echo $PID1 > $CPUSET_DIR/cpusetA/tasks
if [ $? -eq 0 ]; then
  trace_write "OK: task moved to new cpuset"
else
  trace_write "FAIL: task couldn't attach"
  tear_down
  exit 1
fi

trace_write "moving ${PID2} to cpusetA"

/bin/echo $PID2 > $CPUSET_DIR/cpusetA/tasks
if [ $? -eq 0 ]; then
  trace_write "OK: task moved to new cpuset"
else
  trace_write "FAIL: task couldn't attach"
  tear_down
  exit 1
fi

trace_write "moving ${PID3} to cpusetA"

/bin/echo $PID3 > $CPUSET_DIR/cpusetA/tasks
if [ $? -eq 0 ]; then
  trace_write "FAIL: task moved to new cpuset"
  tear_down
  exit 1
else
  trace_write "OK: task couldn't attach"
fi

trace_write "Sleep for 2s"
sleep 2

trace_write "Trying to update the reservation of $PID1 to (6,20)"

# budget 6ms, same period 20ms
#
schedtool -E -t 6000000:20000000 $PID1
if [ $? -ne 0 ]; then
  trace_write "FAIL: couldn't attachd $PID1 to (6,20)"
  tear_down
  exit 1
fi

trace_write "moving ${PID3} to cpusetA"

/bin/echo $PID3 > $CPUSET_DIR/cpusetA/tasks
if [ $? -eq 0 ]; then
  trace_write "OK: task moved to new cpuset"
else
  trace_write "FAIL: task couldn't attach"
  tear_down
  exit 1
fi

trace_write "Sleep for 2s"
sleep 2

trace_write "PASS"
tear_down

exit 0

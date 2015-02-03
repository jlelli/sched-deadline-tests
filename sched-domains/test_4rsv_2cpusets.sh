#!/bin/bash
. ../utils.sh
TFULL=`basename $0`
TNAME=${TFULL%.*}
TDESC="
###########################################
#  
#    test: $TNAME
#
#    Test AC over exclusive cpusets. Test
#    inter-cpusets migrations and bandwidth
#    updates.
#
#    Launch 4 cpu hog tasks. Attach them to
#    several reservations. Try to move them
#    into two exclusive cpusets. Try to
#    change cpusets mask. Try to see if
#    tasks can be moved around once masks
#    are changed.
#
###########################################

"
TRACE=${1-0}
EVENTS="sched_wakeup* sched_switch sched_migrate*"
CPUSET_DIR=/sys/fs/cgroup

tear_down() {
  trace_write "kill $PID1 $PID2 $PID3 $PID4"
  kill -9 $PID1 $PID2 $PID3 $PID4
  
  trace_stop
  trace_extract
}

print_test_info

mount -t cgroup -o cpuset cpuset ${CPUSET_DIR} >/dev/null 2>&1
if [ -d "${CPUSET_DIR}/cpuset-work" ]; then
  rmdir ${CPUSET_DIR}/cpuset-work
fi
mkdir ${CPUSET_DIR}/cpuset-work

if [ -d "${CPUSET_DIR}/cpusetA" ]; then
  rmdir ${CPUSET_DIR}/cpusetA
fi
mkdir ${CPUSET_DIR}/cpusetA

if [ -d "${CPUSET_DIR}/cpusetB" ]; then
  rmdir ${CPUSET_DIR}/cpusetB
fi
mkdir ${CPUSET_DIR}/cpusetB

enable_ac
dump_on_oops
trace_start

trace_write "Configuring exclusive cpusets"
/bin/echo 1 > ${CPUSET_DIR}/cpuset.cpu_exclusive
/bin/echo 0 > ${CPUSET_DIR}/cpuset.sched_load_balance

# create cpuset-work
trace_write "Configuring cpuset: cpuset-work[3-4]"
/bin/echo 3-4 >  ${CPUSET_DIR}/cpuset-work/cpuset.cpus
/bin/echo 0 > ${CPUSET_DIR}/cpuset-work/cpuset.mems
/bin/echo 1 > ${CPUSET_DIR}/cpuset-work/cpuset.cpu_exclusive
echo $$ > ${CPUSET_DIR}/cpuset-work/tasks

# create cpusetA
trace_write "Configuring cpuset: cpusetA[0]"
/bin/echo 0 >  ${CPUSET_DIR}/cpusetA/cpuset.cpus
/bin/echo 0 > ${CPUSET_DIR}/cpusetA/cpuset.mems
/bin/echo 1 > ${CPUSET_DIR}/cpusetA/cpuset.cpu_exclusive

# create cpusetB
trace_write "Configuring cpuset: cpusetB[1-2]"
/bin/echo 1-2 >  ${CPUSET_DIR}/cpusetB/cpuset.cpus
/bin/echo 0 > ${CPUSET_DIR}/cpusetB/cpuset.mems
/bin/echo 1 > ${CPUSET_DIR}/cpusetB/cpuset.cpu_exclusive

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
schedtool -E -t 10000000:20000000 $PID1
if [ $? -ne 0 ]; then
  trace_write "FAIL: couldn't attach $PID1 to (10,20)"
  tear_down
  exit 1
fi

trace_write "Sleep for 1s"
sleep 1

trace_write "Attaching a (12,20) reservation to $PID2"

# budget 12ms, period 20ms
#
schedtool -E -t 12000000:20000000 $PID2
if [ $? -ne 0 ]; then
  trace_write "FAIL: couldn't attach $PID2 to (12,20)"
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
  trace_write "FAIL: couldn't attach $PID3 to (4,20)"
  tear_down
  exit 1
fi

trace_write "Sleep for 1s"
sleep 1

trace_write "Attaching a (8,20) reservation to $PID4"

# budget 8ms, period 20ms
#
schedtool -E -t 8000000:20000000 $PID4
if [ $? -ne 0 ]; then
  trace_write "FAIL: couldn't attach $PID4 to (4,20)"
  tear_down
  exit 1
fi

trace_write "Sleep for 2s"
sleep 2

trace_write "moving ${PID1} to cpusetA"

/bin/echo $PID1 > $CPUSET_DIR/cpusetA/tasks
if [ $? -eq 0 ]; then
  trace_write "OK: task moved to new cpuset"
else
  trace_write "FAIL: task couldn't attach"
  tear_down
  exit 1
fi

trace_write "Sleep for 1s"
sleep 1

trace_write "moving ${PID2} to cpusetB"

/bin/echo $PID2 > $CPUSET_DIR/cpusetB/tasks
if [ $? -eq 0 ]; then
  trace_write "OK: task moved to new cpuset"
else
  trace_write "FAIL: task couldn't attach"
  tear_down
  exit 1
fi

trace_write "Sleep for 1s"
sleep 1

trace_write "moving ${PID3} to cpusetB"

/bin/echo $PID3 > $CPUSET_DIR/cpusetB/tasks
if [ $? -eq 0 ]; then
  trace_write "OK: task moved to new cpuset"
else
  trace_write "FAIL: task couldn't attach"
  tear_down
  exit 1
fi

trace_write "Sleep for 1s"
sleep 1

trace_write "moving ${PID4} to cpusetB"

/bin/echo $PID4 > $CPUSET_DIR/cpusetB/tasks
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

/bin/echo $PID2 > $CPUSET_DIR/cpusetA/tasks
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

trace_write "trying to move ${PID2} to cpusetA (borrowing CPU 3 from cpuset-work)"

/bin/echo 4 >  ${CPUSET_DIR}/cpuset-work/cpuset.cpus
/bin/echo 0,3 >  ${CPUSET_DIR}/cpusetA/cpuset.cpus
/bin/echo $PID2 > $CPUSET_DIR/cpusetA/tasks
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

trace_write "trying (again) to change cpusetB cpumask to 2"

/bin/echo 2 >  ${CPUSET_DIR}/cpusetB/cpuset.cpus
if [ $? -eq 0 ]; then
  trace_write "OK: cpusetB cpumask changed"
else
  trace_write "FAIL: cpusetB cpumask couldn't be changed"
  trace_write "Sleep for 1s"
  sleep 1
  tear_down
  exit 1
fi

trace_write "Sleep for 1s"
sleep 1

trace_write "PASS"
tear_down

exit 0

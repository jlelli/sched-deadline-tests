#!/bin/bash
. ../utils.sh
TDESC="
##############################################################################
#
#        Create 2 exclusive cpusets: A:cpu0 B:cpu1-3.
#        Assign task to them.
#        Try to update cpumasks.
#
##############################################################################

"
TNAME="run4"
TRACE=$1
EVENTS="sched_wakeup* sched_switch sched_migrate*"
CPUSET_DIR=/sys/fs/cgroup

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
trace_start

trace_write "/bin/echo 1 > ${CPUSET_DIR}/cpuset.cpu_exclusive"
/bin/echo 1 > ${CPUSET_DIR}/cpuset.cpu_exclusive
trace_write "/bin/echo 0 > ${CPUSET_DIR}/cpuset.sched_load_balance"
/bin/echo 0 > ${CPUSET_DIR}/cpuset.sched_load_balance

# create cpuset-work
trace_write "/bin/echo 3-4 >  ${CPUSET_DIR}/cpuset-work/cpuset.cpus"
/bin/echo 3-4 >  ${CPUSET_DIR}/cpuset-work/cpuset.cpus
trace_write "/bin/echo 0 > ${CPUSET_DIR}/cpuset-work/cpuset.mems"
/bin/echo 0 > ${CPUSET_DIR}/cpuset-work/cpuset.mems
trace_write "/bin/echo 1 > ${CPUSET_DIR}/cpuset-work/cpuset.cpu_exclusive"
/bin/echo 1 > ${CPUSET_DIR}/cpuset-work/cpuset.cpu_exclusive
echo $$ > ${CPUSET_DIR}/cpuset-work/tasks

# create cpusetA
trace_write "/bin/echo 0 >  ${CPUSET_DIR}/cpusetA/cpuset.cpus"
/bin/echo 0 >  ${CPUSET_DIR}/cpusetA/cpuset.cpus
trace_write "/bin/echo 0 > ${CPUSET_DIR}/cpusetA/cpuset.mems"
/bin/echo 0 > ${CPUSET_DIR}/cpusetA/cpuset.mems
trace_write "/bin/echo 1 > ${CPUSET_DIR}/cpusetA/cpuset.cpu_exclusive"
/bin/echo 1 > ${CPUSET_DIR}/cpusetA/cpuset.cpu_exclusive

# create cpusetB
trace_write "/bin/echo 1-2 >  ${CPUSET_DIR}/cpusetB/cpuset.cpus"
/bin/echo 1-2 >  ${CPUSET_DIR}/cpusetB/cpuset.cpus
trace_write "/bin/echo 0 > ${CPUSET_DIR}/cpusetB/cpuset.mems"
/bin/echo 0 > ${CPUSET_DIR}/cpusetB/cpuset.mems
trace_write "/bin/echo 1 > ${CPUSET_DIR}/cpusetB/cpuset.cpu_exclusive"
/bin/echo 1 > ${CPUSET_DIR}/cpusetB/cpuset.cpu_exclusive

echo "Launch 4 processes"
trace_write "Launch 4 processes"

./burn &
PID1=$!
./burn &
PID2=$!
./burn &
PID3=$!
./burn &
PID4=$!

trace_write "PIDs: $PID1 $PID2 $PID3 $PID4"

trace_write "Moving $PID1 to SCHED_DEADLINE"

# budget 10ms, period 20ms
#
#./sched_setattr $PID1 20000000 10000000
schedtool -E -t 10000000:20000000 $PID1
if [ $? -ne 0 ]; then
  kill $PID1 $PID2 $PID3 $PID4
  test_failed
fi

sleep 1

trace_write "Moving $PID2 to SCHED_DEADLINE"

# budget 12ms, period 20ms
#
schedtool -E -t 12000000:20000000 $PID2
if [ $? -ne 0 ]; then
  kill $PID1 $PID2 $PID3 $PID4
  test_failed
fi

sleep 1

trace_write "Moving $PID3 to SCHED_DEADLINE"

# budget 4ms, period 20ms
#
#./sched_setattr $PID3 20000000 4000000
schedtool -E -t 4000000:20000000 $PID3
if [ $? -ne 0 ]; then
  kill $PID1 $PID2 $PID3 $PID4
  test_failed
fi

sleep 1

trace_write "Moving $PID4 to SCHED_DEADLINE"

# budget 8ms, period 20ms
#
#./sched_setattr $PID2 20000000 8000000
schedtool -E -t 8000000:20000000 $PID4
if [ $? -ne 0 ]; then
  kill $PID1 $PID2 $PID3 $PID4
  test_failed
fi

sleep 5

trace_write "moving ${PID1} to cpuset cpusetA"

/bin/echo $PID1 > $CPUSET_DIR/cpusetA/tasks
if [ $? -eq 0 ]; then
  trace_write "Task moved to new cpuset"
else
  trace_write "Task couldn't attach"
  kill $PID1 $PID2 $PID3 $PID4
  test_failed
fi

sleep 1

trace_write "moving ${PID2} to cpuset cpusetB"

trace_write "/bin/echo $PID2 > $CPUSET_DIR/cpusetB/tasks"
/bin/echo $PID2 > $CPUSET_DIR/cpusetB/tasks
if [ $? -eq 0 ]; then
  trace_write "Task moved to new cpuset"
else
  trace_write "Task couldn't attach"
  kill $PID1 $PID2 $PID3 $PID4
  test_failed
fi

sleep 1

trace_write "moving ${PID3} to cpuset cpusetB"

trace_write "/bin/echo $PID3 > $CPUSET_DIR/cpusetB/tasks"
/bin/echo $PID3 > $CPUSET_DIR/cpusetB/tasks
if [ $? -eq 0 ]; then
  trace_write "Task moved to new cpuset"
else
  trace_write "Task couldn't attach"
  kill $PID1 $PID2 $PID3 $PID4
  test_failed
fi

sleep 1

trace_write "moving ${PID4} to cpuset cpusetB"

trace_write "/bin/echo $PID4 > $CPUSET_DIR/cpusetB/tasks"
/bin/echo $PID4 > $CPUSET_DIR/cpusetB/tasks
if [ $? -eq 0 ]; then
  trace_write "Task moved to new cpuset"
else
  trace_write "Task couldn't attach"
  kill $PID1 $PID2 $PID3 $PID4
  test_failed
fi

sleep 1

trace_write "trying to move ${PID2} to cpusetA"

trace_write "/bin/echo $PID2 > $CPUSET_DIR/cpusetA/tasks"
/bin/echo $PID2 > $CPUSET_DIR/cpusetA/tasks
if [ $? -eq 0 ]; then
  trace_write "Task moved to new cpuset"
  kill $PID1 $PID2 $PID3 $PID4
  test_failed
else
  trace_write "Task couldn't attach"
fi

sleep 1

trace_write "trying to change cpusetB cpumask to 2"

trace_write "/bin/echo 2 >  ${CPUSET_DIR}/cpusetB/cpuset.cpus"
/bin/echo 2 >  ${CPUSET_DIR}/cpusetB/cpuset.cpus
if [ $? -eq 0 ]; then
  trace_write "cpusetB cpumask changed"
  sleep 1
  kill $PID1 $PID2 $PID3 $PID4
  test_failed
else
  trace_write "cpusetB cpumask couldn't be changed"
fi

sleep 1

trace_write "trying to move ${PID2} to cpusetA (borrowing CPU4 from cpuset-work)"

trace_write "/bin/echo 4 >  ${CPUSET_DIR}/cpuset-work/cpuset.cpus"
/bin/echo 4 >  ${CPUSET_DIR}/cpuset-work/cpuset.cpus
trace_write "/bin/echo 0,3 >  ${CPUSET_DIR}/cpusetA/cpuset.cpus"
/bin/echo 0,3 >  ${CPUSET_DIR}/cpusetA/cpuset.cpus
trace_write "/bin/echo $PID2 > $CPUSET_DIR/cpusetA/tasks"
/bin/echo $PID2 > $CPUSET_DIR/cpusetA/tasks
if [ $? -eq 0 ]; then
  trace_write "Task moved to new cpuset"
else
  trace_write "Task couldn't attach"
  sleep 1
  kill $PID1 $PID2 $PID3 $PID4
  test_failed
fi

sleep 1

trace_write "trying (again) to change cpusetB cpumask to 2"

trace_write "/bin/echo 2 >  ${CPUSET_DIR}/cpusetB/cpuset.cpus"
/bin/echo 2 >  ${CPUSET_DIR}/cpusetB/cpuset.cpus
if [ $? -eq 0 ]; then
  trace_write "cpusetB cpumask changed"
else
  trace_write "cpusetB cpumask couldn't be changed"
  sleep 1
  kill $PID1 $PID2 $PID3 $PID4
  test_failed
fi

sleep 1

kill $PID1 $PID2 $PID3 $PID4
test_passed

trace_stop
trace_extract

exit 0

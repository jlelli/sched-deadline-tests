#!/bin/bash
. ../utils.sh

TNAME="cpuset"
TRACE=$1
EVENTS="sched_wakeup* sched_switch sched_migrate*"
CPUSET_DIR=/sys/fs/cgroup

mount -t cgroup -o cpuset cpuset ${CPUSET_DIR} >/dev/null 2>&1
mkdir -p ${CPUSET_DIR}/cpu0

trace_start

trace_write "/bin/echo 1 > ${CPUSET_DIR}/cpuset.cpu_exclusive"
/bin/echo 1 > ${CPUSET_DIR}/cpuset.cpu_exclusive
trace_write "/bin/echo 0 > ${CPUSET_DIR}/cpuset.sched_load_balance"
/bin/echo 0 > ${CPUSET_DIR}/cpuset.sched_load_balance

trace_write "/bin/echo 2 >  ${CPUSET_DIR}/cpu0/cpuset.cpus"
/bin/echo 2 >  ${CPUSET_DIR}/cpu0/cpuset.cpus
trace_write "/bin/echo 0 > ${CPUSET_DIR}/cpu0/cpuset.mems"
/bin/echo 0 > ${CPUSET_DIR}/cpu0/cpuset.mems
trace_write "/bin/echo 1 > ${CPUSET_DIR}/cpu0/cpuset.cpu_exclusive"
/bin/echo 1 > ${CPUSET_DIR}/cpu0/cpuset.cpu_exclusive
trace_write "/bin/echo 1 > ${CPUSET_DIR}/cpu0/cpuset.mem_exclusive"
/bin/echo 1 > ${CPUSET_DIR}/cpu0/cpuset.mem_exclusive

echo $$ > ${CPUSET_DIR}/tasks

echo "Launch 3 processes"
trace_write "Launch 3 processes"

./burn &
PID1=$!
./burn &
PID2=$!
./burn &
PID3=$!

echo "PIDs: $PID1 $PID2 $PID3"
trace_write "PIDs: $PID1 $PID2 $PID3"

echo "Moving $PID1 to SCHED_DEADLINE"
trace_write "Moving $PID1 to SCHED_DEADLINE"

# budget 10ms, period 20ms
#
./sched_setattr $PID1 20000000 10000000
if [ $? -ne 0 ]; then
  kill $PID1 $PID2 $PID3
  test_failed
fi

sleep 1

echo "Moving $PID2 to SCHED_DEADLINE"
trace_write "Moving $PID2 to SCHED_DEADLINE"

# budget 8ms, period 20ms
#
./sched_setattr $PID2 20000000 8000000
if [ $? -ne 0 ]; then
  kill $PID1 $PID2 $PID3
  test_failed
fi

sleep 1

echo "Moving $PID3 to SCHED_DEADLINE"
trace_write "Moving $PID3 to SCHED_DEADLINE"

# budget 4ms, period 20ms
#
./sched_setattr $PID3 20000000 4000000
if [ $? -ne 0 ]; then
  kill $PID1 $PID2 $PID3
  test_failed
fi

sleep 1

echo "moving ${PID1} to cpuset"
trace_write "moving ${PID1} to cpuset"

trace_write "/bin/echo $PID1 > $CPUSET_DIR/cpu0/tasks"
/bin/echo $PID1 > $CPUSET_DIR/cpu0/tasks
if [ $? -eq 0 ]; then
  echo "Task moved to new cpuset"
  trace_write "Task moved to new cpuset"
else
  echo "Task couldn't attach"
  trace_write "Task couldn't attach"
  kill $PID1 $PID2 $PID3
  test_failed
fi

echo "moving ${PID2} to cpuset"
trace_write "moving ${PID2} to cpuset"

trace_write "/bin/echo $PID2 > $CPUSET_DIR/cpu0/tasks"
/bin/echo $PID2 > $CPUSET_DIR/cpu0/tasks
if [ $? -eq 0 ]; then
  echo "Task moved to new cpuset"
  trace_write "Task moved to new cpuset"
else
  echo "Task couldn't attach"
  trace_write "Task couldn't attach"
  kill $PID1 $PID2 $PID3
  test_failed
fi

echo "moving ${PID3} to cpuset"
trace_write "moving ${PID3} to cpuset"

trace_write "/bin/echo $PID3 > $CPUSET_DIR/cpu0/tasks"
/bin/echo $PID3 > $CPUSET_DIR/cpu0/tasks
if [ $? -eq 0 ]; then
  echo "Task moved to new cpuset"
  trace_write "Task moved to new cpuset"
  kill $PID1 $PID2 $PID3
  test_failed
else
  echo "Task couldn't attach"
  trace_write "Task couldn't attach"
fi

#cat $CPUSET_DIR/cpu0/tasks

sleep 2

echo "Trying to update the budget of process 1"
trace_write "Trying to update the budget of process 1"

# budget 6ms, same period 20ms
#
./sched_setattr $PID1 20000000 6000000
if [ $? -ne 0 ]; then
  kill $PID1 $PID2 $PID3
  test_failed
fi

echo "moving ${PID3} to cpuset"
trace_write "moving ${PID3} to cpuset"

trace_write "/bin/echo $PID3 > $CPUSET_DIR/cpu0/tasks"
/bin/echo $PID3 > $CPUSET_DIR/cpu0/tasks
if [ $? -eq 0 ]; then
  echo "Task moved to new cpuset"
  trace_write "Task moved to new cpuset"
else
  echo "Task couldn't attach"
  trace_write "Task couldn't attach"
  kill $PID1 $PID2 $PID3
  test_failed
fi

kill $PID1 $PID2 $PID3
trace_write "kill $PID1 $PID2 $PID3"

test_passed

trace_stop
trace_extract

exit 0

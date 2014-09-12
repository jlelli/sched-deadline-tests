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
/bin/echo 2-4 >  ${CPUSET_DIR}/cpu0/cpuset.cpus
trace_write "/bin/echo 0 > ${CPUSET_DIR}/cpu0/cpuset.mems"
/bin/echo 0 > ${CPUSET_DIR}/cpu0/cpuset.mems
trace_write "/bin/echo 1 > ${CPUSET_DIR}/cpu0/cpuset.cpu_exclusive"
/bin/echo 1 > ${CPUSET_DIR}/cpu0/cpuset.cpu_exclusive
trace_write "/bin/echo 1 > ${CPUSET_DIR}/cpu0/cpuset.mem_exclusive"
/bin/echo 1 > ${CPUSET_DIR}/cpu0/cpuset.mem_exclusive

echo $$ > ${CPUSET_DIR}/tasks
echo "Tasks in the exclusive cpuset are:"
cat ${CPUSET_DIR}/cpu0/tasks

echo "Launch 4 processes"
trace_write "Launch 4 processes"

rt-app -t 20000:10000:f -t 20000:8000:f -t 20000:4000:f -t 20000:4000:f -D30 >/dev/null 2>&1 &
PIDS=`ps --no-headers -L -o tid -p$(pgrep -x rt-app)`
PID1=$(echo $PIDS | awk '{ print $2 }')
PID2=$(echo $PIDS | awk '{ print $3 }')
PID3=$(echo $PIDS | awk '{ print $4 }')
PID4=$(echo $PIDS | awk '{ print $5 }')

trace_write "PIDs: $PID1 $PID2 $PID3 $PID4"

sleep 10

echo "moving ${PID3} to cpuset cpu0"
trace_write "moving ${PID3} to cpuset cpu0"

trace_write "/bin/echo $PID3 > $CPUSET_DIR/cpu0/tasks"
/bin/echo $PID3 > $CPUSET_DIR/cpu0/tasks
if [ $? -eq 0 ]; then
  echo "Task moved to new cpuset"
  trace_write "Task moved to new cpuset"
else
  echo "Task couldn't attach"
  trace_write "Task couldn't attach"
  kill $PID1 $PID2 $PID3 $PID4
  test_failed
fi

sleep 1

echo "moving ${PID4} to cpuset cpu0"
trace_write "moving ${PID4} to cpuset cpu0"

trace_write "/bin/echo $PID4 > $CPUSET_DIR/cpu0/tasks"
/bin/echo $PID4 > $CPUSET_DIR/cpu0/tasks
if [ $? -eq 0 ]; then
  echo "Task moved to new cpuset"
  trace_write "Task moved to new cpuset"
else
  echo "Task couldn't attach"
  trace_write "Task couldn't attach"
  kill $PID1 $PID2 $PID3 $PID4
  test_failed
fi

sleep 2

kill $PID1 $PID2 $PID3 $PID4
trace_write "kill $PID1 $PID2 $PID3 $PID4"

test_passed

trace_stop
trace_extract

exit 0

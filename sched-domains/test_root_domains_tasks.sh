#!/bin/bash
. ../utils.sh
TFULL=`basename $0`
TNAME=${TFULL%.*}
TDESC="
###############################################################################
#
#    test: $TNAME
#
#    TODO
#
###############################################################################

"
TRACE=${1-0}
EVENTS="sched_wakeup* sched_switch sched_migrate*"
CPUSET_DIR=/sys/fs/cgroup

tear_down() {
  trace_stop
  trace_extract
}

print_test_info

mount -t cgroup -o cpuset cpuset ${CPUSET_DIR}

dump_on_oops
trace_start

trace_write "Launch 3 processes"
./burn &
PID1=$!
./burn &
PID2=$!
./burn &
PID3=$!
trace_write "pids: $PID1 $PID2 $PID3"

# 1: budget 20ms, period 200ms (104857 bw)
#
trace_write "Attaching a (20,200) reservation to $PID1"
schedtool -E -t 20000000:200000000 $PID1
# 2: budget 10ms, period 200ms (52423 bw)
#
trace_write "Attaching a (10,200) reservation to $PID2"
schedtool -E -t 10000000:200000000 $PID2
# 3: budget 10ms, period 50ms (209715 bw)
#
trace_write "Attaching a (10,50) reservation to $PID3"
schedtool -E -t 10000000:50000000 $PID3

grep dl_ /proc/sched_debug
trace_write "Sleep for 1s"
sleep 1

trace_write "disabling sched_load_balance"
echo 0 >/sys/fs/cgroup/cpuset.sched_load_balance
grep dl_ /proc/sched_debug
trace_write "Sleep for 1s"
sleep 1

trace_write "enabling sched_load_balance"
echo 1 >/sys/fs/cgroup/cpuset.sched_load_balance
grep dl_ /proc/sched_debug
trace_write "Sleep for 1s"
sleep 1

trace_write "creating my_cpuset"
mkdir -p ${CPUSET_DIR}/my_cpuset
grep dl_ /proc/sched_debug
trace_write "Sleep for 1s"
sleep 1

trace_write "disabling sched_load_balance"
echo 0 >/sys/fs/cgroup/cpuset.sched_load_balance
grep dl_ /proc/sched_debug
trace_write "Sleep for 1s"
sleep 1

trace_write "enabling sched_load_balance"
echo 1 >/sys/fs/cgroup/cpuset.sched_load_balance
grep dl_ /proc/sched_debug
trace_write "Sleep for 1s"
sleep 1

trace_write "Moving task $PID1 in my_cpuset"
/bin/echo $PID1 > ${CPUSET_DIR}/my_cpuset/cgroup.procs >/dev/null 2>&1

trace_write "disabling sched_load_balance"
echo 0 >/sys/fs/cgroup/cpuset.sched_load_balance
grep dl_ /proc/sched_debug
trace_write "Sleep for 1s"
sleep 1

trace_write "enabling sched_load_balance"
echo 1 >/sys/fs/cgroup/cpuset.sched_load_balance
grep dl_ /proc/sched_debug
trace_write "Sleep for 1s"
sleep 1

trace_write "turning off CPU1"
/bin/echo 0 > /sys/devices/system/cpu/cpu1/online
trace_write "turning off CPU3"
/bin/echo 0 > /sys/devices/system/cpu/cpu3/online
grep dl_ /proc/sched_debug
trace_write "Sleep for 1s"
sleep 1

trace_write "disabling sched_load_balance"
echo 0 >/sys/fs/cgroup/cpuset.sched_load_balance
grep dl_ /proc/sched_debug
trace_write "Sleep for 1s"
sleep 1

trace_write "enabling sched_load_balance"
echo 1 >/sys/fs/cgroup/cpuset.sched_load_balance
grep dl_ /proc/sched_debug
trace_write "Sleep for 1s"
sleep 1

trace_write "turning on CPU1"
/bin/echo 1 > /sys/devices/system/cpu/cpu1/online
trace_write "turning on CPU3"
/bin/echo 1 > /sys/devices/system/cpu/cpu3/online
grep dl_ /proc/sched_debug
trace_write "Sleep for 1s"
sleep 1

trace_write "kill $PID1 $PID2 $PID3"
kill -TERM $PID1 $PID2 $PID3

rmdir ${CPUSET_DIR}/my_cpuset
if [ $? -ne 0 ]; then
  trace_write "ERROR: failed to remove my_cpuset"
  exit 1
fi

sleep 1
grep dl_ /proc/sched_debug

tear_down

exit 0

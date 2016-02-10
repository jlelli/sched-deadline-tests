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

trace_write "Launch 1 process"
./burn &
PID=$!
trace_write "pid: $PID"

# budget 20ms, period 200ms (104857 bw)
#
trace_write "Attaching a (20,200) reservation to $PID"
schedtool -E -t 20000000:200000000 $PID

trace_write "Sleep for 1s"
sleep 1
grep -A4 dl_rq /proc/sched_debug

trace_write "disabling sched_load_balance"
echo 0 >/sys/fs/cgroup/cpuset.sched_load_balance
trace_write "Sleep for 1s"
sleep 1
grep -A4 dl_rq /proc/sched_debug

trace_write "enabling sched_load_balance"
echo 1 >/sys/fs/cgroup/cpuset.sched_load_balance
trace_write "Sleep for 1s"
sleep 1
grep -A4 dl_rq /proc/sched_debug

trace_write "turning off CPU1"
/bin/echo 0 > /sys/devices/system/cpu/cpu1/online
trace_write "turning off CPU3"
/bin/echo 0 > /sys/devices/system/cpu/cpu3/online
trace_write "Sleep for 1s"
sleep 1
grep -A4 dl_rq /proc/sched_debug

trace_write "turning on CPU1"
/bin/echo 1 > /sys/devices/system/cpu/cpu1/online
trace_write "turning on CPU3"
/bin/echo 1 > /sys/devices/system/cpu/cpu3/online
trace_write "Sleep for 1s"
sleep 1
grep -A4 dl_rq /proc/sched_debug

trace_write "creating my_cpuset"
mkdir -p ${CPUSET_DIR}/my_cpuset
trace_write "Sleep for 1s"
sleep 1
grep -A4 dl_rq /proc/sched_debug

trace_write "Configuring exclusive cpusets"
/bin/echo 1 > ${CPUSET_DIR}/cpuset.cpu_exclusive
/bin/echo 0 > ${CPUSET_DIR}/cpuset.sched_load_balance

trace_write "Configuring cpuset: cpusetA[3]"
/bin/echo 3 >  ${CPUSET_DIR}/my_cpuset/cpuset.cpus
/bin/echo 0 > ${CPUSET_DIR}/my_cpuset/cpuset.mems
/bin/echo 1 > ${CPUSET_DIR}/my_cpuset/cpuset.cpu_exclusive

trace_write "Moving task $PID in my_cpuset"
/bin/echo $PID > ${CPUSET_DIR}/my_cpuset/cgroup.procs
trace_write "Sleep for 1s"
sleep 1
grep -A4 dl_rq /proc/sched_debug

trace_write "kill $PID"
kill -TERM $PID
sleep 1
grep -A4 dl_rq /proc/sched_debug

trace_write "Deconfiguring exclusive cpusets"
rmdir ${CPUSET_DIR}/my_cpuset
sleep 1
/bin/echo 1 > ${CPUSET_DIR}/cpuset.sched_load_balance
/bin/echo 0 > ${CPUSET_DIR}/cpuset.cpu_exclusive
grep -A4 dl_rq /proc/sched_debug

tear_down

exit 0

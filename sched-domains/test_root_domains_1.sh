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

for i in `seq 0 100`; do
  # budget 20ms, period 200ms (104857 bw)
  #
  trace_write "Attaching a (20,200) reservation to $PID"
  schedtool -E -t 20000000:200000000 $PID

  # back to NORMAL
  #
  trace_write "Back to NORMAL $PID"
  schedtool -N $PID
done

trace_write "Sleep for 1s"
sleep 1
grep -A4 dl_rq /proc/sched_debug

# budget 20ms, period 200ms (104857 bw)
#
trace_write "Attaching a (20,200) reservation to $PID"
schedtool -E -t 20000000:200000000 $PID
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

trace_write "Configuring cpuset: my_cpuset[3]"
/bin/echo 3 >  ${CPUSET_DIR}/my_cpuset/cpuset.cpus
/bin/echo 0 > ${CPUSET_DIR}/my_cpuset/cpuset.mems
/bin/echo 1 > ${CPUSET_DIR}/my_cpuset/cpuset.cpu_exclusive

trace_write "Moving task $PID in my_cpuset"
/bin/echo $PID > ${CPUSET_DIR}/my_cpuset/cgroup.procs
trace_write "Sleep for 1s"
sleep 1
grep -A4 dl_rq /proc/sched_debug

for i in `seq 0 100`; do
  # back to NORMAL
  #
  trace_write "Back to NORMAL $PID"
  schedtool -N $PID

  # budget 20ms, period 200ms (104857 bw)
  #
  trace_write "Attaching a (20,200) reservation to $PID"
  schedtool -E -t 20000000:200000000 $PID
done

trace_write "Moving task $PID in root cpuset"
/bin/echo $PID > ${CPUSET_DIR}/cgroup.procs
sleep 1

trace_write "Deconfiguring exclusive cpusets"
rmdir ${CPUSET_DIR}/my_cpuset
sleep 1
/bin/echo 1 > ${CPUSET_DIR}/cpuset.sched_load_balance
/bin/echo 0 > ${CPUSET_DIR}/cpuset.cpu_exclusive

trace_write "kill $PID"
kill -TERM $PID
sleep 1
grep -A4 dl_rq /proc/sched_debug

tear_down

exit 0

#!/bin/bash
. ../utils.sh
TFULL=`basename $0`
TNAME=${TFULL%.*}
TDESC="
###############################################################################
#
#    test: $TNAME
#
#    ...
#
###############################################################################

"
TRACE=${1-0}
EVENTS="sched_wakeup* sched_switch sched_migrate*"
CPUSET_DIR=/sys/fs/cgroup

tear_down() {
  trace_write "De-configuring groups"
  rmdir ${CPUSET_DIR}/group1
  if [ $? -ne 0 ]; then
    trace_write "ERROR: failed to remove cpusetA"
    exit 1
  fi
  /bin/echo 950000 > ${CPUSET_DIR}/cpu.rt_runtime_us

  trace_stop
  trace_extract
}

print_test_info

mount -t cgroup -o cpu cpu ${CPUSET_DIR}

trace_start

trace_write "Configuring groups"
/bin/echo 500000 > ${CPUSET_DIR}/cpu.rt_runtime_us
mkdir -p ${CPUSET_DIR}/group1
/bin/echo 300000 > ${CPUSET_DIR}/group1/cpu.rt_runtime_us

trace_write "Sleep for 1s"
sleep 1

trace_write "Launch rt-app process"
rt-app example2.json &
PID=$!

trace_write "Sleep for 1s"
sleep 1

trace_write "Moving $PID into group1"
/bin/echo $PID > ${CPUSET_DIR}/group1/cgroup.procs
sleep 5

tear_down
trace_write "PASS"

exit 0

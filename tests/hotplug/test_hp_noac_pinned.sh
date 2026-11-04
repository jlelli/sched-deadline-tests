#!/bin/bash
. ../../lib/utils.sh
TFULL=`basename $0`
TNAME=${TFULL%.*}
TDESC="
###############################################################################
#
#    test: $TNAME
#
#    Regression test for dl_task_root_domain_cpu() BUG_ON during CPU
#    hot-unplug. With admission control disabled, pin a DL task to a
#    single non-boot CPU and offline it. The task's cpus_mask will have
#    no active CPUs when set_cpus_allowed_dl() runs, which used to
#    trigger BUG_ON(cpu >= nr_cpu_ids) in dl_task_root_domain_cpu().
#
#    Verify the kernel handles this gracefully (no crash, no WARN).
#
###############################################################################

"
TRACE=${1-0}
RUNS=${2-3}
EVENTS="sched_wakeup* sched_switch sched_migrate*"
# Pick a non-boot CPU to pin and offline
TARGET_CPU=1

tear_down() {
  trace_write "kill ${PID}"
  kill -9 ${PID} 2>/dev/null
  wait ${PID} 2>/dev/null

  trace_write "turning on CPU ${TARGET_CPU}"
  echo 1 > /sys/devices/system/cpu/cpu${TARGET_CPU}/online

  enable_ac
  trace_stop
  trace_extract
}

print_test_info
dump_on_oops

trace_start
test_start
dmesg_save_cursor

trace_write "disabling admission control"
disable_ac

for i in $(seq 1 ${RUNS}); do
  trace_write "run ${i}"

  # Ensure target CPU is online
  echo 1 > /sys/devices/system/cpu/cpu${TARGET_CPU}/online
  sleep 0.5

  # Start cpuhog pinned to TARGET_CPU with SCHED_DEADLINE
  trace_write "launching DL task pinned to CPU ${TARGET_CPU}"
  taskset -c ${TARGET_CPU} chrt -d \
    --sched-runtime 50000000 \
    --sched-deadline 100000000 \
    --sched-period 100000000 \
    0 ./cpuhog &
  PID=$!
  trace_write "pid: ${PID}"
  sleep 1

  # Verify the task is actually on TARGET_CPU
  CPU=$(cat /proc/${PID}/stat 2>/dev/null | awk '{print $39}')
  trace_write "task ${PID} running on CPU ${CPU}"

  # Offline the CPU the task is pinned to
  trace_write "turning off CPU ${TARGET_CPU}"
  echo 0 > /sys/devices/system/cpu/cpu${TARGET_CPU}/online
  if [ $? -ne 0 ]; then
    test_fail "couldn't turn CPU ${TARGET_CPU} off"
    tear_down
    exit 1
  fi

  sleep 1

  # Check dmesg for BUG/WARN/oops
  if ! dmesg_check_crash; then
    test_fail "kernel crash detected after offlining CPU ${TARGET_CPU}"
    tear_down
    exit 1
  fi

  # Task should still be alive, migrated to another CPU
  if kill -0 ${PID} 2>/dev/null; then
    NEW_CPU=$(cat /proc/${PID}/stat 2>/dev/null | awk '{print $39}')
    trace_write "task ${PID} migrated to CPU ${NEW_CPU}"
  else
    trace_write "task ${PID} exited (acceptable)"
  fi

  kill -9 ${PID} 2>/dev/null
  wait ${PID} 2>/dev/null

  trace_write "turning on CPU ${TARGET_CPU}"
  echo 1 > /sys/devices/system/cpu/cpu${TARGET_CPU}/online
  sleep 1
done

enable_ac

test_pass
trace_stop
trace_extract

exit 0

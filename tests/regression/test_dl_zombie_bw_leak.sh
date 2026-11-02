#!/bin/bash
. ../../lib/utils.sh
TFULL=`basename $0`
TNAME=${TFULL%.*}
TDESC="
###############################################################################
#
#    test: $TNAME
#
#    Test that sched_setattr(SCHED_DEADLINE) on a zombie task is rejected.
#    Without the fix, each call leaks total_bw that nothing releases.
#
#    Reported by Weiheng Qiu.
#
###############################################################################

"
TRACE=${1-0}
EVENTS="sched_wakeup* sched_switch sched_setscheduler"

tear_down() {
  trace_stop
  trace_extract
}

if [ ! -f /sys/kernel/debug/sched/debug ]; then
  print_test_info
  test_skip "debugfs sched/debug not available"
  exit 0
fi

print_test_info
dump_on_oops

trace_start

test_start
trace_write "Running test_dl_zombie_bw_leak"

./test_dl_zombie_bw_leak
RES=$?

if [ $RES -eq 0 ]; then
  test_pass
  tear_down
  exit 0
else
  test_fail "test_dl_zombie_bw_leak exited with $RES"
  tear_down
  exit 1
fi

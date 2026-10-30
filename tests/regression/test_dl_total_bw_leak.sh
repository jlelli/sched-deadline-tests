#!/bin/bash
. ../../lib/utils.sh
TFULL=`basename $0`
TNAME=${TFULL%.*}
TDESC="
###############################################################################
#
#    test: $TNAME
#
#    Test for SCHED_DEADLINE total_bw leak on class change while not queued.
#    When a DL task is switched to another policy while sleeping or stopped,
#    its bandwidth must be released from the root domain's total_bw.
#
#    Reported by Tejun Heo.
#    See: https://lore.kernel.org/all/2b5fb3f22bca6aa383be8f4781923392@kernel.org/
#
###############################################################################

"
TRACE=${1-0}
EVENTS="sched_wakeup* sched_switch sched_migrate* sched_setscheduler"

tear_down() {
  trace_stop
  trace_extract
}

# Check prerequisites
if [ ! -f /sys/kernel/debug/sched/debug ]; then
  print_test_info
  test_skip "debugfs sched/debug not available"
  exit 0
fi

print_test_info
dump_on_oops

trace_start

test_start
trace_write "Running test_dl_total_bw_leak"

./test_dl_total_bw_leak
RES=$?

if [ $RES -eq 0 ]; then
  test_pass

  tear_down
  exit 0
else
  test_fail "test_dl_total_bw_leak exited with $RES"
  tear_down
  exit 1
fi

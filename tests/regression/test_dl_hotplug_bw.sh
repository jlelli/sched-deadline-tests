#!/bin/bash
. ../../lib/utils.sh
TFULL=`basename $0`
TNAME=${TFULL%.*}
TDESC="
###############################################################################
#
#    test: $TNAME
#
#    Test DL total_bw release after CPU hotplug.
#    A sleeping DL task whose CPU is offlined must have its bandwidth
#    correctly released from the right root domain when leaving DL.
#
#    Reported by Tejun Heo.
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
if [ $(nproc) -lt 2 ]; then
  print_test_info
  test_skip "need at least 2 CPUs"
  exit 0
fi

if [ ! -f /sys/kernel/debug/sched/debug ]; then
  print_test_info
  test_skip "debugfs sched/debug not available"
  exit 0
fi

print_test_info
dump_on_oops

trace_start

test_start
trace_write "Running test_dl_hotplug_bw"

./test_dl_hotplug_bw
RES=$?

if [ $RES -eq 0 ]; then
  test_pass
  tear_down
  exit 0
else
  test_fail "test_dl_hotplug_bw exited with $RES"
  tear_down
  exit 1
fi

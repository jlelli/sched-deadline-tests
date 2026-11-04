#!/bin/bash
. ../../lib/utils.sh
TFULL=`basename $0`
TNAME=${TFULL%.*}
TDESC="
###############################################################################
#
#    test: $TNAME
#
#    Test DL bandwidth accounting across cpuset partition moves.
#    A sleeping DL task moved into a partition and back should leave
#    total_bw unchanged in both domains.
#
#    Reported by Weiheng Qiu.
#
###############################################################################

"
TRACE=${1-0}
EVENTS="sched_wakeup* sched_switch sched_migrate*"

tear_down() {
  trace_stop
  trace_extract
}

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
trace_write "Running test_dl_cpuset_bw_move"

run_test_safe 60 ./test_dl_cpuset_bw_move
RES=$?

if [ $RES -eq 0 ]; then
  test_pass
  tear_down
  exit 0
else
  test_fail "test_dl_cpuset_bw_move exited with $RES"
  tear_down
  exit 1
fi

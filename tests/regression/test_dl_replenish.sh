#!/bin/bash
. ../../lib/utils.sh
TFULL=`basename $0`
TNAME=${TFULL%.*}
TDESC="
###############################################################################
#
#    test: $TNAME
#
#    Test for SCHED_DEADLINE replenishment bug.
#    This reproduces a kernel bug in the deadline replenishment logic
#    where tasks may not be properly replenished after throttling.
#
###############################################################################

"
TRACE=${1-0}
EVENTS="sched_wakeup* sched_switch sched_migrate*"

tear_down() {
  trace_stop
  trace_extract
}

print_test_info
dump_on_oops

trace_start

test_start
trace_write "Running test_dl_replenish_bug"

./test_dl_replenish_bug
RES=$?

if [ $RES -eq 0 ]; then
  test_pass
  
  tear_down
  exit 0
else
  test_fail "test_dl_replenish_bug exited with $RES"
  tear_down
  exit 1
fi

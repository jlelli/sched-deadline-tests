#!/bin/bash
. ../../lib/utils.sh
TFULL=`basename $0`
TNAME=${TFULL%.*}
TDESC="
###############################################################################
#
#    test: $TNAME
#
#    Test that sched_setattr(OTHER, KEEP_PARAMS) on a DL task is rejected.
#    Without the fix, this corrupts total_bw bandwidth accounting.
#
#    Reported by Tejun Heo.
#
###############################################################################

"
TRACE=${1-0}
EVENTS="sched_wakeup* sched_switch sched_setscheduler"

tear_down() {
  trace_stop
  trace_extract
}

print_test_info
dump_on_oops

trace_start

test_start
trace_write "Running test_dl_keep_params_underflow"

./test_dl_keep_params_underflow
RES=$?

if [ $RES -eq 0 ]; then
  test_pass
  tear_down
  exit 0
else
  test_fail "test_dl_keep_params_underflow exited with $RES"
  tear_down
  exit 1
fi

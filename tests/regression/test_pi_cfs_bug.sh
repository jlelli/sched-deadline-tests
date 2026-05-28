#!/bin/bash
. ../../lib/utils.sh
TFULL=`basename $0`
TNAME=${TFULL%.*}
TDESC="
###############################################################################
#
#    test: $TNAME
#
#    Test for SCHED_DEADLINE priority inheritance bug with CFS tasks.
#    This reproduces a kernel bug where a DL task blocking on a mutex held
#    by a CFS task doesn't properly boost the CFS task's priority.
#
###############################################################################

"
TRACE=${1-0}
EVENTS="sched_wakeup* sched_switch sched_pi_setprio"

tear_down() {
  trace_stop
  trace_extract
}

print_test_info
dump_on_oops

trace_start

test_start
trace_write "Running pi-cfs-bug-repro"

./pi-cfs-bug-repro
RES=$?

if [ $RES -eq 0 ]; then
  test_pass
  
  tear_down
  exit 0
else
  test_fail "pi-cfs-bug-repro exited with $RES"
  tear_down
  exit 1
fi

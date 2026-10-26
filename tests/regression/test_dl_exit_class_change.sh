#!/bin/bash
. ../../lib/utils.sh
TFULL=`basename $0`
TNAME=${TFULL%.*}
TDESC="
###############################################################################
#
#    test: $TNAME
#
#    Regression test for the SCHED_DEADLINE this_bw double subtraction bug
#    hit when the scheduling class of a dying task is changed.
#
#    A parent parked on one CPU races sched_setscheduler(child,
#    SCHED_OTHER) against its SCHED_DEADLINE child's last schedule() on
#    another CPU (after do_task_dead() stored TASK_DEAD but before
#    __schedule() dequeued the child).  On an unfixed kernel the class
#    change makes the scheduler subtract the child's bandwidth from the
#    runqueue's this_bw twice, which WARNs and corrupts the per-CPU
#    bandwidth accounting until reboot.
#
#    See docs/BUGS.md, this_bw Double Subtraction on Class Change of a
#    Dying Task.
#
###############################################################################
"
TRACE=${1-0}
EVENTS="sched_wakeup* sched_switch sched_migrate*"

BIN=test_dl_exit_class_change

# The bug is visible only as WARN_ON_ONCE splats from the deadline
# bandwidth accounting helpers (__sub_rq_bw/__add_running_bw), reported
# at the call sites that inline them.  Line numbers and exact symbol
# names vary between kernel versions (e.g. sub_rq_bw vs __sub_rq_bw,
# .isra/.part suffixes on older compilers), so match loosely on the
# function names.
WARN_RE='WARNING:.*deadline\.c:[0-9]+.*(task_non_contending|switched_from_dl|enqueue_dl_entity|dequeue_dl_entity|sub_rq_bw|add_rq_bw|add_running_bw|sub_running_bw)'

DMESG_TMP=$(mktemp /tmp/dmesg_${TNAME}.XXXXXX)

tear_down() {
  rm -f "$DMESG_TMP"
  trace_stop
  trace_extract
}

print_test_info
dump_on_oops

trace_start

# Build the reproducer if the top-level Makefile was not run
if [ ! -x "./$BIN" ]; then
  make -s "$BIN" > /dev/null 2>&1 || true
fi
if [ ! -x "./$BIN" ]; then
  echo "TEST_SKIP: $BIN not built (run 'make' at the repository root)"
  test_skip "$BIN not built"
  tear_down
  exit 77
fi

test_start
trace_write "Running $BIN"

./$BIN
RES=$?

if [ $RES -eq 77 ]; then
  echo "TEST_SKIP: $BIN reported missing prerequisites"
  test_skip "$BIN skipped"
  tear_down
  exit 77
fi
if [ $RES -ne 0 ]; then
  test_fail "$BIN exited with $RES"
  tear_down
  exit 1
fi

# The race loop succeeds on its own; the kernel bug is only visible in
# the kernel log.  The warnings are WARN_ON_ONCE (once per call site per
# boot), so scan the whole log instead of a delta: any occurrence means
# this kernel is buggy, or this boot already hit the bug earlier (same
# verdict).  Re-attempting detection on an unfixed kernel requires a
# fresh boot; the VM test runner (tools/run-in-vm.sh) boots fresh and
# clears dmesg for every run.
if ! dmesg > "$DMESG_TMP" 2>/dev/null; then
  echo "TEST_SKIP: cannot read the kernel log"
  test_skip "dmesg not readable"
  tear_down
  exit 77
fi

if grep -E "$WARN_RE" "$DMESG_TMP" > /dev/null; then
  echo "TEST_FAILED: deadline bandwidth accounting warnings found in kernel log"
  echo "--- matching dmesg lines ---"
  grep -E "$WARN_RE" "$DMESG_TMP" | head -20
  echo "--- end ---"
  test_fail "deadline bandwidth accounting warnings in kernel log"
  tear_down
  exit 1
fi

echo "TEST_PASSED"
test_pass

tear_down
exit 0

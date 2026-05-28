#!/bin/bash
. ../../lib/utils.sh
TFULL=`basename $0`
TNAME=${TFULL%.*}
TDESC="
##############################################
#
#    test: $TNAME
#
#    Stress cancel_dl_timer()
#
##############################################

"
TRACE=${1-0}
SWITCHES=${2-30}
EVENTS="sched_wakeup* sched_switch sched_migrate*"

print_test_info

dump_on_oops
trace_start
test_start

./cpuhog &
PID=$!

trace_write "Going to perform $SWITCHES sched_setscheduler on task $PID"
for i in `seq 0 $SWITCHES`; do
  if [[ $((i % 2)) == 0 ]]; then
    usec=$(random 1 10)
    trace_write "setting $PID to (${usec},100) [$(( $SWITCHES - $i)) to go]"
    # budget = usec*1000000, deadline = 100ms, period = 100ms
    chrt -d --sched-runtime ${usec}000000 --sched-deadline 100000000 --sched-period 100000000 -p 0 $PID
  else
    trace_write "setting $PID to normal [$(( $SWITCHES - $i)) to go]"
    chrt -o -p 0 $PID
  fi

  sleep_for=$(random 1 99)
  sleep 0.${sleep_for}
done

echo

kill -9 $PID
test_pass

trace_stop
trace_extract

exit 0

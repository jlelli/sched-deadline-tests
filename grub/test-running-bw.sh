#!/bin/bash
. ../utils.sh

TNAME=$(echo $0 | tr '/' ' ' | tr '.' ' ' | awk '{ print $1 }')
TINFO="Test rq running bandwidth"
BENCHMARK="rt-app"
TRACE=$1
EVENTS="sched_wakeup* sched_switch sched_migrate* sched_stat_running_bw* sched_stat_*_dl"

cleanup() {
  trace_stop
  #enable_ac
  turn_on_cpu 1
  turn_on_cpu 2
  turn_on_cpu 3
  turn_on_cpu 4

  for c in ${ALL_MASK}; do
    set_cpufreq ${c} ondemand
  done

  exit 0
}

trap cleanup SIGINT SIGTERM

print_test_info

trace_start
#disable_ac
turn_off_cpu 1
turn_off_cpu 2
turn_off_cpu 3
turn_off_cpu 4

TASKSET="${TNAME}.json"

#for c in ${A15_MASK}; do
#  # this corresponds to 1024 cap on A15
#  set_cpufreq ${c} userspace 1200000
#done
set_cpufreq 0 userspace 1200000

log "waiting 5 seconds..."
sleep 5
log "running taskset ${TASKSET} (at 1024 cap)"
mkdir -p ./log
${BENCHMARK} ${TASKSET} >> ${TNAME}.out 2>&1

log "${TNAME} execution finished"

trace_stop
trace_extract

cleanup

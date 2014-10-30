#!/bin/bash
A7_FREQS="350000 400000 500000 600000 700000 800000 900000 1000000"
A15_FREQS="500000 600000 700000 800000 900000 1000000 1100000 1200000"
ALL_MASK="0 1 2 3 4"
A7_MASK="2 3 4"
A15_MASK="0 1"
ONE_A7_ONE_A15_NMASK="2 3 4"
TRACE_CMD="trace-cmd"
tracing=0
rt_runtime=-1

print_test_info() {
  if [ -n "$TDESC" ]; then
    echo "$TDESC"
  else
    echo "Test has no description."
  fi
}

trace_start() {
  if [[ -n "$TRACE" && ${TRACE} -eq 1 ]]; then
    tracing=1
    events=""
    for e in ${EVENTS}; do
      events+="-e ${e} "
    done
    ${TRACE_CMD} start ${events} >${TNAME}.out 2>&1
    echo "tracing started"
  fi
}

trace_stop() {
  if [ ${tracing} -eq 1 ]; then
    ${TRACE_CMD} stop >>${TNAME}.out 2>&1
    echo "tracing stopped"
  fi
}

trace_extract() {
  if [ ${tracing} -eq 1 ]; then
    ${TRACE_CMD} extract -o trace-${TNAME}.dat >>${TNAME}.out 2>&1
  fi

  tracing=0
}

trace_write() {
  if [ ${tracing} -eq 1 ]; then
    echo $1 > /sys/kernel/debug/tracing/trace_marker
  fi
}

dump_on_oops() {
  echo 1 > /proc/sys/kernel/ftrace_dump_on_oops
}

test_failed() {
  echo "TEST_FAILED"
  trace_write "TEST_FAILED"
  trace_stop
  trace_extract

  exit 1
}

test_passed() {
  echo "TEST_PASSED"
  trace_write "TEST_PASSED"
}

disable_ac() {
  echo "disabling admission control"
  echo -1 > /proc/sys/kernel/sched_rt_runtime_us
}

enable_ac() {
  echo "enabling admission control"
  echo 950000 > /proc/sys/kernel/sched_rt_runtime_us
}

set_cpufreq() {
  if [ -z "$3" ]; then
    echo "setting CPU$1 to $2 governor"
    trace_write "setting CPU$1 to $2 governor"
  else
    echo "setting CPU$1 to $2 governor at $3 MHz"
    trace_write "setting CPU$1 to $2 governor at $3 MHz"
  fi

  echo $2 > /sys/devices/system/cpu/cpu$1/cpufreq/scaling_governor

  if [ ! -z "$3" ]; then
    echo $3 > /sys/devices/system/cpu/cpu$1/cpufreq/scaling_setspeed
  fi
}

set_runtime_freq_inv() {
  echo "enabling runtime frequency invariance"
  #echo DL_RUNTIME_FI > /sys/kernel/debug/sched_features
  echo ENERGY_AWARE > /sys/kernel/debug/sched_features
}

clear_runtime_freq_inv() {
  echo "disabling runtime frequency invariance"
  #echo NO_DL_RUNTIME_FI > /sys/kernel/debug/sched_features
  echo NO_ENERGY_AWARE > /sys/kernel/debug/sched_features
}

turn_off_cpu() {
  echo "turning off CPU$1"
  trace_write "turning off CPU$1"
  echo 0 > /sys/devices/system/cpu/cpu$1/online
}

turn_on_cpu() {
  echo "turning on CPU$1"
  trace_write "turning on CPU$1"
  echo 1 > /sys/devices/system/cpu/cpu$1/online
}

log() {
  echo $1
  trace_write $1
}

random() {
  local min=${1-1}
  local max=${2-100}

  echo $(( (RANDOM % max) + min))
}

# Written by Locutus for bash demonstration.
# Found at http://it.toolbox.com/blogs/locutus/bash-bits-nibbles-and-bytes-a-rotating-cursor-while-you-wait-22867

rotateCursor()
{
  case $toggle
  in
    1)
      echo -n $1" \ "
      echo -ne "\r"
      toggle="2"
    ;;

    2)
      echo -n $1" | "
      echo -ne "\r"
      toggle="3"
    ;;

    3)
      echo -n $1" / "
      echo -ne "\r"
      toggle="4"
    ;;

    *)
      echo -n $1" - "
      echo -ne "\r"
      toggle="1"
    ;;
  esac
}

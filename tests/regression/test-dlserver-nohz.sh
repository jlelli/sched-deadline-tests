#!/bin/bash
# Test script to reproduce dl-server timer firing on nohz_full isolated CPUs
# Issue: dl-server timers should not fire on isolated CPUs running only SCHED_OTHER tasks

# Source test utilities for test_skip helper
SCRIPT_DIR=$(dirname "$0")
if [ -f "$SCRIPT_DIR/../../lib/utils.sh" ]; then
    . "$SCRIPT_DIR/../../lib/utils.sh"
    TNAME=$(basename "$0" .sh)
fi

set -e

# Configuration
ISOLATED_CPU=2
TEST_DURATION=10
TRACE_EVENTS="timer:hrtimer_start,timer:hrtimer_cancel,timer:hrtimer_expire_entry,timer:tick_stop,sched:sched_switch,sched:sched_wakeup,workqueue:workqueue_queue_work,workqueue:workqueue_activate_work,workqueue:workqueue_execute_start,workqueue:workqueue_execute_end,kprobes:probe_dl_server_start,kprobes:probe_dl_server_start_ret,kprobes:probe_dl_server_stop,kprobes:probe_dl_server_stop_ret"
TRACE_OUTPUT="/home/jlelli/Work/kernel/vng-storage/dlserver-trace-$(date +%Y%m%d-%H%M%S).dat"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_nohz_full() {
    log_info "Checking nohz_full configuration..."

    if [ -f /sys/devices/system/cpu/nohz_full ]; then
        nohz_cpus=$(cat /sys/devices/system/cpu/nohz_full)
        log_info "nohz_full CPUs: $nohz_cpus"
    else
        log_error "/sys/devices/system/cpu/nohz_full not found"
        log_error "Make sure kernel is booted with nohz_full=2-7"
        if [ -n "$TNAME" ]; then
            test_skip "nohz_full not configured"
        fi
        exit 77
    fi

    # Check if isolated CPU is in nohz_full
    if ! echo "$nohz_cpus" | grep -q "$ISOLATED_CPU"; then
        log_error "CPU $ISOLATED_CPU is not in nohz_full list: $nohz_cpus"
        if [ -n "$TNAME" ]; then
            test_skip "CPU $ISOLATED_CPU not in nohz_full list"
        fi
        exit 77
    fi

    log_info "CPU $ISOLATED_CPU is properly configured for nohz_full"
}

setup_tracing() {
    log_info "Setting up tracing with trace-cmd..."

    # Check if trace-cmd is available
    if ! command -v trace-cmd &> /dev/null; then
        log_error "trace-cmd not found. Please install trace-cmd package."
        if [ -n "$TNAME" ]; then
            test_skip "trace-cmd not installed"
        fi
        exit 77
    fi

    # Set up kprobes for dl_server_start and dl_server_stop
    log_info "Setting up kprobes for dl_server_start and dl_server_stop..."

    # Clear any existing kprobes
    echo > /sys/kernel/debug/tracing/kprobe_events 2>/dev/null || true

    # struct sched_dl_entity field offsets (from pahole on build/vmlinux):
    #   dl_runtime: offset 24 (u64)
    #   dl_deadline: offset 32 (u64)
    #   dl_period: offset 40 (u64)
    #   runtime: offset 64 (s64)
    #   deadline: offset 72 (u64)
    #   flags: offset 80 (u32)
    #   bitfields at offset 84 (u32):
    #     dl_throttled: bit 0
    #     dl_yielded: bit 1
    #     dl_non_contending: bit 2
    #     dl_overrun: bit 3
    #     dl_server: bit 4
    #     dl_server_active: bit 5
    #     dl_defer: bit 6
    #     dl_defer_armed: bit 7
    #     dl_defer_running: bit 8
    #     dl_defer_idle: bit 9

    # Add detailed kprobe for dl_server_start entry with dl_se state
    # Read the bitfield u32 at offset 84 to get all the flags
    # dl_timer is at offset 88 (embedded struct hrtimer), timer address will be computed as dl_se + 88
    echo 'p:probe_dl_server_start dl_server_start dl_se=%di dl_runtime=+24(%di):u64 runtime=+64(%di):s64 flags=+84(%di):u32' >> /sys/kernel/debug/tracing/kprobe_events
    log_info "Added dl_server_start probe: dl_se, dl_runtime, runtime, flags"

    # Add kretprobe for dl_server_start to see if it completes or returns early
    echo 'r:probe_dl_server_start_ret dl_server_start' >> /sys/kernel/debug/tracing/kprobe_events

    # Add kprobe for dl_server_stop entry with flags
    echo 'p:probe_dl_server_stop dl_server_stop dl_se=%di flags=+84(%di):u32' >> /sys/kernel/debug/tracing/kprobe_events
    log_info "Added dl_server_stop probe: dl_se, flags"

    # Add kretprobe for dl_server_stop
    echo 'r:probe_dl_server_stop_ret dl_server_stop' >> /sys/kernel/debug/tracing/kprobe_events

    log_info "Kprobes configured (flags decoding: bit5=active, bit0=throttled, bit6=defer, bit7=defer_armed, bit8=defer_running)"

    # Stack trace triggers (disabled by default, uncomment for debugging)
    # Enabling these generates large traces and is mainly useful for debugging specific issues

    # # Enable stack trace trigger for hrtimer_start events with dl_task_timer
    # log_info "Enabling stack trace for dl_task_timer events..."
    # echo '!stacktrace' > /sys/kernel/debug/tracing/events/timer/hrtimer_start/trigger 2>/dev/null || true
    # if ! echo 'stacktrace if function.function == dl_task_timer' > /sys/kernel/debug/tracing/events/timer/hrtimer_start/trigger 2>/dev/null; then
    #     log_warn "Failed to set filtered stacktrace, trying without filter..."
    #     echo 'stacktrace' > /sys/kernel/debug/tracing/events/timer/hrtimer_start/trigger
    #     log_info "Stack trace trigger enabled for all hrtimer_start events (will filter in analysis)"
    # else
    #     log_info "Stack trace trigger enabled for dl_task_timer hrtimer_start events"
    # fi

    # # Enable stack trace for workqueue queue events
    # log_info "Enabling stack trace for workqueue_queue_work events..."
    # echo '!stacktrace' > /sys/kernel/debug/tracing/events/workqueue/workqueue_queue_work/trigger 2>/dev/null || true
    # echo 'stacktrace' > /sys/kernel/debug/tracing/events/workqueue/workqueue_queue_work/trigger
    # log_info "Stack trace trigger enabled for workqueue_queue_work events"

    # # Enable stack trace for hrtimer_cancel events
    # log_info "Enabling stack trace for hrtimer_cancel events..."
    # echo '!stacktrace' > /sys/kernel/debug/tracing/events/timer/hrtimer_cancel/trigger 2>/dev/null || true
    # echo 'stacktrace' > /sys/kernel/debug/tracing/events/timer/hrtimer_cancel/trigger
    # log_info "Stack trace trigger enabled for hrtimer_cancel"

    # Build trace-cmd command with events
    # Each event needs its own -e flag
    EVENT_ARGS=""
    for event in $(echo "$TRACE_EVENTS" | tr ',' ' '); do
        EVENT_ARGS="$EVENT_ARGS -e $event"
    done

    # Trace all CPUs (no -M filter), but we'll analyze only the isolated CPU
    TRACE_CMD_ARGS="$EVENT_ARGS -b 8192 -o $TRACE_OUTPUT"

    log_info "trace-cmd will record: $TRACE_EVENTS"
    log_info "Recording all CPUs (will analyze CPU $ISOLATED_CPU only)"
    log_info "Output file: $TRACE_OUTPUT"
}

cleanup_tracing() {
    # Clear stack trace triggers (if they were enabled)
    # echo '!stacktrace' > /sys/kernel/debug/tracing/events/timer/hrtimer_start/trigger 2>/dev/null || true
    # echo '!stacktrace' > /sys/kernel/debug/tracing/events/timer/hrtimer_cancel/trigger 2>/dev/null || true
    # echo '!stacktrace' > /sys/kernel/debug/tracing/events/workqueue/workqueue_queue_work/trigger 2>/dev/null || true

    # Remove kprobes
    echo > /sys/kernel/debug/tracing/kprobe_events 2>/dev/null || true

    # Stop any remaining trace-cmd instances gracefully
    if pgrep -x trace-cmd > /dev/null 2>&1; then
        log_info "Cleaning up trace-cmd processes..."
        pkill -INT trace-cmd 2>/dev/null || true
        sleep 3

        # Force kill only if still running after grace period
        if pgrep -x trace-cmd > /dev/null 2>&1; then
            log_warn "Force killing trace-cmd processes..."
            pkill -KILL trace-cmd 2>/dev/null || true
        fi
    fi
}

isolate_cpu() {
    log_info "Isolating CPU $ISOLATED_CPU..."

    # Move all tasks away from isolated CPU
    for task in /proc/*/task/*/; do
        tid=$(echo "$task" | cut -d'/' -f5)
        if [ -n "$tid" ] && [ -f "/proc/$tid/task/$tid/comm" ]; then
            # Skip kernel threads that can't be moved
            comm=$(cat "/proc/$tid/task/$tid/comm" 2>/dev/null || echo "")
            if [ -n "$comm" ]; then
                # Try to move to CPU 0-1 (non-isolated)
                taskset -cp 0-1 "$tid" 2>/dev/null || true
            fi
        fi
    done

    # Redirect virtio interrupts away from isolated CPU
    log_info "Redirecting virtio interrupts away from CPU $ISOLATED_CPU..."
    virtio_irq_count=0
    if [ -f /proc/interrupts ]; then
        for irq in $(grep -i virtio /proc/interrupts | awk -F: '{print $1}' | tr -d ' '); do
            if [ -n "$irq" ] && [ -f "/proc/irq/$irq/smp_affinity_list" ]; then
                echo "0-1" > /proc/irq/$irq/smp_affinity_list 2>/dev/null && \
                    log_info "Redirected IRQ $irq to CPUs 0-1" || \
                    log_warn "Failed to redirect IRQ $irq"
                virtio_irq_count=$((virtio_irq_count + 1))
            fi
        done
    fi

    if [ "$virtio_irq_count" -gt 0 ]; then
        log_info "Redirected $virtio_irq_count virtio IRQs"
    else
        log_info "No virtio IRQs found to redirect"
    fi

    log_info "CPU $ISOLATED_CPU isolated"
}

run_test_task() {
    log_info "Starting trace-cmd recording..."

    set -e
    # Start trace-cmd in background
    trace-cmd record $TRACE_CMD_ARGS &
    TRACE_PID=$!
    log_info "trace-cmd started (PID: $TRACE_PID)"

    # Give trace-cmd time to start
    sleep 2

    log_info "Starting isolated task on CPU $ISOLATED_CPU (will settle for 2s before running test for ${TEST_DURATION}s)..."

    # Create a simple CPU-bound task
    # The task itself will wait on CPU 2 for the settling period
    taskset -c "$ISOLATED_CPU" sh -c "
        # Mark start of settling period (we're now on CPU 2)
        echo 'SETTLING_PERIOD_START on CPU $ISOLATED_CPU' > /sys/kernel/debug/tracing/trace_marker 2>/dev/null || true

        # Wait for dl_server to become inactive on the isolated CPU
        # The dl_server period is 1 second, so wait 2+ periods to ensure it's stopped
        sleep 3

        echo 'SETTLING_PERIOD_END on CPU $ISOLATED_CPU' > /sys/kernel/debug/tracing/trace_marker 2>/dev/null || true

        # Mark when task actually starts executing the test workload
        echo 'TEST_TASK_RUNNING on CPU $ISOLATED_CPU' > /sys/kernel/debug/tracing/trace_marker 2>/dev/null || true

        # Run the actual test workload
        end=\$((SECONDS + $TEST_DURATION))
        while [ \$SECONDS -lt \$end ]; do
            : # busy loop
        done

        # Mark when task completes
        echo 'TEST_TASK_COMPLETED on CPU $ISOLATED_CPU' > /sys/kernel/debug/tracing/trace_marker 2>/dev/null || true
    " &

    TEST_PID=$!
    log_info "Test task started (PID: $TEST_PID)"

    # Verify it's running as SCHED_OTHER
    sleep 1
    if [ -f "/proc/$TEST_PID/sched" ]; then
        policy=$(grep "policy" "/proc/$TEST_PID/sched" | awk '{print $3}')
        log_info "Task policy: $policy (0=SCHED_OTHER)"
    fi

    # Wait for test to complete
    wait "$TEST_PID"
    log_info "Test task completed"

    # Stop trace-cmd gracefully - SIGINT tells it to finalize the trace
    log_info "Stopping trace-cmd (this may take a few seconds to finalize trace)..."
    if kill -0 "$TRACE_PID" 2>/dev/null; then
        kill -INT "$TRACE_PID" 2>/dev/null || true
        # Give trace-cmd time to finalize and write the trace file
        # This is critical - trace-cmd needs time to flush buffers and write the .dat file
        for i in {1..10}; do
            if ! kill -0 "$TRACE_PID" 2>/dev/null; then
                log_info "trace-cmd finalized successfully"
                break
            fi
            sleep 1
        done
        # Final wait to ensure it's done
        wait "$TRACE_PID" 2>/dev/null || true
    fi

    # Additional sleep to ensure file is fully written
    sleep 2
}

analyze_trace() {
    log_info "Analyzing trace data..."

    if [ ! -f "$TRACE_OUTPUT" ]; then
        log_error "Trace file not found: $TRACE_OUTPUT"
        return 1
    fi

    # Generate text report from trace.dat
    TRACE_REPORT="/home/jlelli/Work/kernel/vng-storage/dlserver-trace-$(date +%Y%m%d-%H%M%S).txt"
    trace-cmd report "$TRACE_OUTPUT" > "$TRACE_REPORT"

    log_info "Trace binary: $TRACE_OUTPUT (can be opened with kernelshark)"
    log_info "Trace report: $TRACE_REPORT"

    # Extract test window timestamps from trace markers
    log_info "Extracting test window from trace markers..."

    settling_start=$(grep "SETTLING_PERIOD_START" "$TRACE_REPORT" | head -1 | awk '{print $4}' | tr -d ':')
    settling_end=$(grep "SETTLING_PERIOD_END" "$TRACE_REPORT" | head -1 | awk '{print $4}' | tr -d ':')
    test_start=$(grep "TEST_TASK_RUNNING" "$TRACE_REPORT" | head -1 | awk '{print $4}' | tr -d ':')
    test_end=$(grep "TEST_TASK_COMPLETED" "$TRACE_REPORT" | head -1 | awk '{print $4}' | tr -d ':')

    if [ -z "$test_start" ] || [ -z "$test_end" ]; then
        log_warn "Could not find test markers, checking entire trace"
        test_start="0"
        test_end="999999999"
    else
        log_info "Settling period: $settling_start - $settling_end seconds"
        log_info "Test window: $test_start - $test_end seconds"
    fi

    # Initialize variables for summary
    timer_expire_remote=0
    timer_start_remote=0
    timer_cancel_remote=0
    timer_expire_during_test=0
    timer_expire_during_test_on_isolated=0
    timer_expire_during_test_on_remote=0

    # Check for dl_server related timers on isolated CPU only
    log_info "Checking for dl_server timer events on CPU $ISOLATED_CPU during test window..."

    # Filter for events on isolated CPU (CPU column is second field, shown as [NNN])
    # Match with leading zeros, e.g., [002] for CPU 2
    CPU_FILTER="\\[0*${ISOLATED_CPU}\\]"

    # Count all dl_server/dl_task_timer events on isolated CPU
    dl_server_count=$(grep -i "dl_server\|dl_task_timer" "$TRACE_REPORT" | grep -E "$CPU_FILTER" | wc -l)

    # Count dl_server/dl_task_timer events on isolated CPU during test window only
    dl_server_during_test=0
    if [ "$dl_server_count" -gt 0 ]; then
        while read -r line; do
            timestamp=$(echo "$line" | awk '{print $4}' | tr -d ':')
            if [ -n "$timestamp" ]; then
                # Use awk for floating point comparison
                in_window=$(awk -v ts="$timestamp" -v start="$test_start" -v end="$test_end" \
                    'BEGIN { if (ts >= start && ts <= end) print "1"; else print "0" }')
                if [ "$in_window" = "1" ]; then
                    dl_server_during_test=$((dl_server_during_test + 1))
                fi
            fi
        done < <(grep -i "dl_server\|dl_task_timer" "$TRACE_REPORT" | grep -E "$CPU_FILTER")
    fi

    hrtimer_count=$(grep "hrtimer_start" "$TRACE_REPORT" | grep -E "$CPU_FILTER" | wc -l)
    tick_stop_count=$(grep "tick_stop" "$TRACE_REPORT" | grep -E "$CPU_FILTER" | wc -l)
    workqueue_queue_count=$(grep "workqueue_queue_work" "$TRACE_REPORT" | grep -E "$CPU_FILTER" | wc -l)
    workqueue_execute_count=$(grep "workqueue_execute_start" "$TRACE_REPORT" | grep -E "$CPU_FILTER" | wc -l)
    dl_server_start_count=$(grep "probe_dl_server_start:" "$TRACE_REPORT" | grep -E "$CPU_FILTER" | wc -l)
    dl_server_start_ret_count=$(grep "probe_dl_server_start_ret:" "$TRACE_REPORT" | grep -E "$CPU_FILTER" | wc -l)
    dl_server_stop_count=$(grep "probe_dl_server_stop:" "$TRACE_REPORT" | grep -E "$CPU_FILTER" | wc -l)
    dl_server_stop_ret_count=$(grep "probe_dl_server_stop_ret:" "$TRACE_REPORT" | grep -E "$CPU_FILTER" | wc -l)

    echo ""
    echo "===== TRACE ANALYSIS (CPU $ISOLATED_CPU only) ====="
    echo "Trace file: $TRACE_OUTPUT (all CPUs traced)"
    if [ -n "$settling_start" ]; then
        echo "Settling period: $settling_start - $settling_end seconds (wait for dl_server to deactivate)"
    fi
    if [ -n "$test_start" ] && [ "$test_start" != "0" ]; then
        echo "Test window: $test_start - $test_end seconds (isolated task running)"
    fi
    echo "Total dl_server_start calls on CPU $ISOLATED_CPU: $dl_server_start_count (returned: $dl_server_start_ret_count)"
    echo "Total dl_server_stop calls on CPU $ISOLATED_CPU: $dl_server_stop_count (returned: $dl_server_stop_ret_count)"
    echo "Total hrtimer_start events on CPU $ISOLATED_CPU: $hrtimer_count"
    echo "Total tick_stop events on CPU $ISOLATED_CPU: $tick_stop_count"
    echo "Total workqueue_queue_work events on CPU $ISOLATED_CPU: $workqueue_queue_count"
    echo "Total workqueue_execute_start events on CPU $ISOLATED_CPU: $workqueue_execute_count"
    echo "Total dl_server/dl_task_timer events on CPU $ISOLATED_CPU: $dl_server_count"
    echo "dl_server/dl_task_timer events on CPU $ISOLATED_CPU DURING TEST: $dl_server_during_test"
    echo ""
    echo "To view with kernelshark: kernelshark $TRACE_OUTPUT"
    echo ""

    echo ""
    echo "=========================================="
    echo "NOHZ_FULL DL-SERVER ISOLATION TEST RESULTS"
    echo "=========================================="
    echo ""

    if [ "$dl_server_during_test" -gt 0 ]; then
        log_error "FAIL: Found $dl_server_during_test dl_server/dl_task_timer events on CPU $ISOLATED_CPU during test window!"
        echo ""
        echo "===== dl_server/dl_task_timer events on CPU $ISOLATED_CPU during test ====="
        while read -r line; do
            timestamp=$(echo "$line" | awk '{print $4}' | tr -d ':')
            if [ -n "$timestamp" ]; then
                in_window=$(awk -v ts="$timestamp" -v start="$test_start" -v end="$test_end" \
                    'BEGIN { if (ts >= start && ts <= end) print "1"; else print "0" }')
                if [ "$in_window" = "1" ]; then
                    echo "$line"
                fi
            fi
        done < <(grep -i "dl_server\|dl_task_timer" "$TRACE_REPORT" | grep -E "$CPU_FILTER") | head -20
        echo ""
        return 1
    else
        log_info "PASS: No dl_server/dl_task_timer events on CPU $ISOLATED_CPU during test window"

        if [ "$dl_server_count" -gt 0 ]; then
            log_info "Note: Found $dl_server_count dl_server events on CPU $ISOLATED_CPU outside test window (during setup/teardown)"
            echo ""
            echo "===== dl_server/dl_task_timer events on CPU $ISOLATED_CPU (outside test window) ====="
            grep -i "dl_server\|dl_task_timer" "$TRACE_REPORT" | grep -E "$CPU_FILTER" | head -10
        fi

        # Show dl_server_start/stop calls
        if [ "$dl_server_start_count" -gt 0 ] || [ "$dl_server_stop_count" -gt 0 ]; then
            echo ""
            log_info "dl_server calls on CPU $ISOLATED_CPU:"
            log_info "  dl_server_start: $dl_server_start_count entries, $dl_server_start_ret_count returns"
            log_info "  dl_server_stop: $dl_server_stop_count entries, $dl_server_stop_ret_count returns"

            if [ "$dl_server_start_count" -ne "$dl_server_start_ret_count" ]; then
                log_warn "Mismatch: dl_server_start called $dl_server_start_count times but returned $dl_server_start_ret_count times (early returns!)"
            fi

            echo ""
            echo "===== dl_server_start/stop events on CPU $ISOLATED_CPU (all) ====="
            grep "probe_dl_server_" "$TRACE_REPORT" | grep -E "$CPU_FILTER"

            # Check if dl_server_stop was called during settling period
            if [ -n "$settling_start" ] && [ -n "$settling_end" ]; then
                settling_stops=$(grep "probe_dl_server_stop:" "$TRACE_REPORT" | grep -E "$CPU_FILTER" | while read -r line; do
                    ts=$(echo "$line" | awk '{print $4}' | tr -d ':')
                    if [ -n "$ts" ]; then
                        in_settling=$(awk -v ts="$ts" -v start="$settling_start" -v end="$settling_end" \
                            'BEGIN { if (ts >= start && ts <= end) print "1"; else print "0" }')
                        [ "$in_settling" = "1" ] && echo "$line"
                    fi
                done | wc -l)

                if [ "$settling_stops" -gt 0 ]; then
                    log_info "Good: dl_server_stop called $settling_stops times during settling period"
                else
                    log_warn "Note: No dl_server_stop during settling (may already have been inactive)"
                fi
            fi

            # Check if dl_server_start was called when test task started
            if [ -n "$test_start" ]; then
                # Look for dl_server_start shortly after TEST_TASK_RUNNING marker
                start_window_end=$(awk -v start="$test_start" 'BEGIN { printf "%.6f", start + 0.1 }')
                starts_at_test=$(grep "probe_dl_server_start:" "$TRACE_REPORT" | grep -E "$CPU_FILTER" | while read -r line; do
                    ts=$(echo "$line" | awk '{print $4}' | tr -d ':')
                    if [ -n "$ts" ]; then
                        in_window=$(awk -v ts="$ts" -v start="$test_start" -v end="$start_window_end" \
                            'BEGIN { if (ts >= start && ts <= end) print "1"; else print "0" }')
                        [ "$in_window" = "1" ] && echo "$line"
                    fi
                done)

                if [ -n "$starts_at_test" ]; then
                    log_info "Key observation: dl_server_start called when test task woke up:"
                    echo "$starts_at_test"
                else
                    log_warn "Note: No dl_server_start when test task woke up (may already be active)"
                fi
            fi
        else
            log_info "No dl_server_start/stop calls on CPU $ISOLATED_CPU"
        fi

        # Show tick_stop events to verify nohz is working
        if [ "$tick_stop_count" -gt 0 ]; then
            log_info "Good: Found $tick_stop_count tick_stop events on CPU $ISOLATED_CPU (nohz is active)"
            echo ""
            echo "===== Sample tick_stop events on CPU $ISOLATED_CPU (first 5) ====="
            grep "tick_stop" "$TRACE_REPORT" | grep -E "$CPU_FILTER" | head -5
        else
            log_warn "Warning: No tick_stop events found on CPU $ISOLATED_CPU - nohz might not be working"
        fi

        # Show workqueue activity if any
        if [ "$workqueue_queue_count" -gt 0 ] || [ "$workqueue_execute_count" -gt 0 ]; then
            echo ""
            log_info "Found workqueue activity on CPU $ISOLATED_CPU"
            echo "===== Sample workqueue events on CPU $ISOLATED_CPU (first 10) ====="
            grep "workqueue_" "$TRACE_REPORT" | grep -E "$CPU_FILTER" | head -10
        fi

        # Check for dl_timer firing on remote CPUs
        echo ""
        log_info "Checking for dl_timer activity across all CPUs..."

        # Extract the dl_timer address for CPU 2 from probe_dl_server_start events
        # The kprobe prints dl_se, and dl_timer is at offset 88, so timer_addr = dl_se + 88
        # Format: probe_dl_server_start: (...) dl_se=0xffff88803eaae5b0

        echo ""
        echo "===== DEBUG: Extracting CPU $ISOLATED_CPU dl_timer address ====="

        # Find the last probe_dl_server_start event on CPU 2 and extract dl_se
        probe_count=$(grep "probe_dl_server_start:.*dl_se=" "$TRACE_REPORT" | grep -E "$CPU_FILTER" | wc -l)
        log_info "Found $probe_count probe_dl_server_start events on CPU $ISOLATED_CPU"

        dl_se=$(grep "probe_dl_server_start:.*dl_se=" "$TRACE_REPORT" | \
                grep -E "$CPU_FILTER" | \
                tail -1 | \
                grep -oP 'dl_se=0x[0-9a-f]+' | \
                cut -d= -f2)

        if [ -n "$dl_se" ]; then
            log_info "Extracted dl_se=$dl_se from last probe event"

            # Show the actual probe event line
            echo "Last probe event:"
            grep "probe_dl_server_start:.*dl_se=" "$TRACE_REPORT" | grep -E "$CPU_FILTER" | tail -1

            # Calculate timer address: dl_se + 88 (0x58 in hex)
            # Convert hex to decimal, add 88, convert back to hex
            dl_se_dec=$((dl_se))
            timer_addr_dec=$((dl_se_dec + 88))
            dl_timer_addr=$(printf "0x%x" $timer_addr_dec)

            log_info "Calculating timer address: dl_se ($dl_se) + 88 = $dl_timer_addr"
            log_info "  dl_se_dec=$dl_se_dec, timer_addr_dec=$timer_addr_dec"

            # Verify the timer address appears in trace
            timer_events=$(grep "hrtimer=$dl_timer_addr" "$TRACE_REPORT" | wc -l)
            log_info "Verification: Found $timer_events hrtimer events with address $dl_timer_addr"

            if [ "$timer_events" -eq 0 ]; then
                log_warn "WARNING: Calculated timer address not found in trace! Trying fallback..."
                dl_timer_addr=""
            fi
        else
            log_warn "No dl_se found in probe events"
        fi

        if [ -z "$dl_timer_addr" ]; then
            # Fallback: try to find from hrtimer events on CPU 2
            log_info "Fallback: Searching for hrtimer events on CPU $ISOLATED_CPU..."
            dl_timer_addr=$(grep "hrtimer.*function=dl_task_timer" "$TRACE_REPORT" | \
                            grep -E "$CPU_FILTER" | \
                            head -1 | \
                            grep -oP 'hrtimer=0x[0-9a-f]+' | \
                            cut -d= -f2)

            if [ -n "$dl_timer_addr" ]; then
                log_info "Found timer address via fallback: $dl_timer_addr"
            else
                log_warn "Fallback also failed to find timer address"
            fi
        fi

        echo ""

        if [ -n "$dl_timer_addr" ]; then
            log_info "CPU $ISOLATED_CPU dl_timer address: $dl_timer_addr"

            # Count timer events across ALL CPUs (not just isolated CPU)
            timer_start_all=$(grep "hrtimer_start:.*hrtimer=$dl_timer_addr.*dl_task_timer" "$TRACE_REPORT" | wc -l)
            timer_expire_all=$(grep "hrtimer_expire_entry:.*hrtimer=$dl_timer_addr.*dl_task_timer" "$TRACE_REPORT" | wc -l)
            timer_cancel_all=$(grep "hrtimer_cancel:.*hrtimer=$dl_timer_addr" "$TRACE_REPORT" | wc -l)

            # Count timer events on isolated CPU only
            timer_start_isolated=$(grep "hrtimer_start:.*hrtimer=$dl_timer_addr.*dl_task_timer" "$TRACE_REPORT" | grep -E "$CPU_FILTER" | wc -l)
            timer_expire_isolated=$(grep "hrtimer_expire_entry:.*hrtimer=$dl_timer_addr.*dl_task_timer" "$TRACE_REPORT" | grep -E "$CPU_FILTER" | wc -l)
            timer_cancel_isolated=$(grep "hrtimer_cancel:.*hrtimer=$dl_timer_addr" "$TRACE_REPORT" | grep -E "$CPU_FILTER" | wc -l)

            # Count on remote CPUs (all - isolated)
            timer_start_remote=$((timer_start_all - timer_start_isolated))
            timer_expire_remote=$((timer_expire_all - timer_expire_isolated))
            timer_cancel_remote=$((timer_cancel_all - timer_cancel_isolated))

            echo ""
            echo "===== CPU $ISOLATED_CPU dl_timer activity summary ====="
            echo "Timer address: $dl_timer_addr"
            echo ""
            echo "Timer starts:  Total=$timer_start_all  OnCPU$ISOLATED_CPU=$timer_start_isolated  Remote=$timer_start_remote"
            echo "Timer expires: Total=$timer_expire_all  OnCPU$ISOLATED_CPU=$timer_expire_isolated  Remote=$timer_expire_remote"
            echo "Timer cancels: Total=$timer_cancel_all  OnCPU$ISOLATED_CPU=$timer_cancel_isolated  Remote=$timer_cancel_remote"
            echo ""

            if [ "$timer_expire_isolated" -gt 0 ]; then
                log_error "PROBLEM: dl_timer expired $timer_expire_isolated times on CPU $ISOLATED_CPU!"
                echo "This indicates the timer fired on the isolated CPU, breaking nohz_full isolation."
            else
                log_info "GOOD: dl_timer never expired on CPU $ISOLATED_CPU"
            fi

            if [ "$timer_expire_remote" -gt 0 ]; then
                log_info "dl_timer migrated to remote CPUs and expired $timer_expire_remote times there"
                echo ""
                echo "===== Remote CPU timer expirations (showing which CPUs) ====="
                grep "hrtimer_expire_entry:.*hrtimer=$dl_timer_addr.*dl_task_timer" "$TRACE_REPORT" | grep -v -E "$CPU_FILTER" | head -20
            fi

            # Check timer activity during test window
            timer_expire_during_test=0
            timer_expire_during_test_on_isolated=0
            timer_expire_during_test_on_remote=0

            if [ -n "$test_start" ] && [ "$test_start" != "0" ]; then
                echo ""
                log_info "Checking timer activity during test window ($test_start - $test_end seconds)..."

                echo "===== DEBUG: Timer expiration analysis ====="
                log_info "Searching for: hrtimer_expire_entry with hrtimer=$dl_timer_addr"

                total_expires=$(grep "hrtimer_expire_entry:.*hrtimer=$dl_timer_addr.*dl_task_timer" "$TRACE_REPORT" | wc -l)
                log_info "Total timer expirations in entire trace: $total_expires"

                while read -r line; do
                    timestamp=$(echo "$line" | awk '{print $4}' | tr -d ':')
                    cpu=$(echo "$line" | grep -oP '\[\d+\]' | tr -d '[]')
                    if [ -n "$timestamp" ]; then
                        in_window=$(awk -v ts="$timestamp" -v start="$test_start" -v end="$test_end" \
                            'BEGIN { if (ts >= start && ts <= end) print "1"; else print "0" }')
                        if [ "$in_window" = "1" ]; then
                            timer_expire_during_test=$((timer_expire_during_test + 1))
                            if [ "$cpu" = "$ISOLATED_CPU" ]; then
                                timer_expire_during_test_on_isolated=$((timer_expire_during_test_on_isolated + 1))
                                echo "  [IN_WINDOW] ts=$timestamp CPU=$cpu (ISOLATED)"
                            else
                                timer_expire_during_test_on_remote=$((timer_expire_during_test_on_remote + 1))
                                echo "  [IN_WINDOW] ts=$timestamp CPU=$cpu (REMOTE)"
                            fi
                        fi
                    fi
                done < <(grep "hrtimer_expire_entry:.*hrtimer=$dl_timer_addr.*dl_task_timer" "$TRACE_REPORT")

                log_info "Timer expirations during test window: $timer_expire_during_test (OnCPU$ISOLATED_CPU=$timer_expire_during_test_on_isolated, Remote=$timer_expire_during_test_on_remote)"
                echo ""

                if [ "$timer_expire_during_test" -gt 0 ]; then
                    log_warn "dl_timer expired $timer_expire_during_test times during test window (OnCPU$ISOLATED_CPU=$timer_expire_during_test_on_isolated, Remote=$timer_expire_during_test_on_remote)"
                    echo "===== Timer expirations during test window ====="
                    grep "hrtimer_expire_entry:.*hrtimer=$dl_timer_addr.*dl_task_timer" "$TRACE_REPORT" | while read -r line; do
                        timestamp=$(echo "$line" | awk '{print $4}' | tr -d ':')
                        if [ -n "$timestamp" ]; then
                            in_window=$(awk -v ts="$timestamp" -v start="$test_start" -v end="$test_end" \
                                'BEGIN { if (ts >= start && ts <= end) print "1"; else print "0" }')
                            [ "$in_window" = "1" ] && echo "$line"
                        fi
                    done
                else
                    log_info "OPTIMAL: dl_timer did NOT expire during test window"
                    if [ "$timer_expire_remote" -gt 0 ]; then
                        log_info "Note: $timer_expire_remote expirations occurred outside test window (before/after isolated task)"
                    fi
                fi
            fi
        else
            log_warn "Could not find dl_timer address for CPU $ISOLATED_CPU in trace"
        fi

        # Show a sample of what did happen
        if [ "$hrtimer_count" -gt 0 ]; then
            echo ""
            echo "===== Sample hrtimer events on CPU $ISOLATED_CPU (first 10) ====="
            grep "hrtimer_start" "$TRACE_REPORT" | grep -E "$CPU_FILTER" | head -10
        fi

        echo ""
        echo "=========================================="
        echo "SUMMARY"
        echo "=========================================="
        echo ""
        log_info "Test completed successfully for CPU $ISOLATED_CPU"
        echo "- dl_server did NOT interrupt the isolated CPU during test"
        if [ "$timer_expire_during_test_on_remote" -gt 0 ]; then
            echo "- dl_server timer expired $timer_expire_during_test_on_remote times on remote CPUs during test window"
            log_warn "IMPROVEMENT POSSIBLE: Timer could be stopped entirely for nohz_full CPUs with single task"
        elif [ "$timer_expire_remote" -gt 0 ]; then
            echo "- dl_server timer expired $timer_expire_remote times on remote CPUs (but outside test window)"
            log_info "OPTIMAL: Timer activity only during setup/teardown, not during isolated task execution"
        fi
        echo ""
        return 0
    fi
}

# Main execution
main() {
    log_info "Starting dl-server nohz_full test"
    log_info "Isolated CPU: $ISOLATED_CPU"
    log_info "Test duration: ${TEST_DURATION}s"
    echo ""

    # Check we're running as root
    if [ "$(id -u)" -ne 0 ]; then
        log_error "This script must be run as root"
        exit 1
    fi

    # Check nohz_full configuration
    check_nohz_full
    echo ""

    # Setup
    setup_tracing
    isolate_cpu
    echo ""

    # Run test
    run_test_task
    echo ""

    # Analyze results
    if analyze_trace; then
        log_info "Test PASSED"
        cleanup_tracing
        exit 0
    else
        log_error "Test FAILED"
        cleanup_tracing
        exit 1
    fi
}

# Handle cleanup on exit
trap cleanup_tracing EXIT INT TERM

main "$@"

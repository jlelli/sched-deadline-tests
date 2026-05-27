# Kernel Bugs Tested

This document catalogs specific Linux kernel bugs that are tested or reproduced by this test suite.

## Active Regression Tests

### 1. Priority Inheritance Chain Bug with SCHED_DEADLINE

**Test**: `tests/regression/pi-cfs-bug-repro.c`

**Kernel versions affected**: v4.15 and potentially others

**Symptom**: Kernel BUG at `kernel/sched/deadline.c:1405`

**Description**:
A crash occurs when a non-deadline task that has been boosted by a deadline task attempts to boost another non-deadline task through priority inheritance.

**Root cause**:
The boosted SCHED_NORMAL task (N1) incorrectly attempts to use SCHED_DEADLINE boosting parameters when it blocks on another SCHED_NORMAL task (N2). The deadline scheduler's code path is invoked for N2 even though N2 should not become a deadline task.

**Scenario**:
```
Time  | Task N1         | Task N2         | Task D1
------|-----------------|-----------------|------------------
  1   | Lock M1         |                 |
  2   |                 | Lock M2         |
  3   |                 |                 | Block on M1 → boost N1 to DL
  4   | Block on M2     |                 |
      | (tries to boost N2 with DL params)
      | → KERNEL BUG
```

**Fix status**: Check kernel tree for patches addressing this issue.

**How to verify fix**: Run `sudo ./pi-cfs-bug-repro` - should complete without kernel BUG.

---

### 2. Missing ENQUEUE_REPLENISH Flag on De-boost

**Test**: `tests/regression/test_dl_replenish_bug.c`

**Kernel versions affected**: Various kernels before fix

**Symptom**: Kernel warning message:
```
DL de-boosted task PID X: REPLENISH flag missing
```

**Description**:
When a SCHED_DEADLINE task is changed to another scheduling class (e.g., SCHED_IDLE) while another SCHED_DEADLINE task is blocked on a mutex it holds, the boosting mechanism fails to set the ENQUEUE_REPLENISH flag correctly.

**Root cause**:
During the policy change, the task loses its deadline scheduling class but must still inherit from the blocked task. The code path that handles this inheritance forgets to set the ENQUEUE_REPLENISH flag, which is critical for deadline budget management.

**Scenario**:
```
1. Task B (DEADLINE: runtime=5ms, period=10ms) locks mutex
2. Task A (DEADLINE: runtime=10ms, period=20ms) blocks on mutex
3. B has shorter deadline, so no inheritance initially
4. sched_setscheduler() changes B from DEADLINE to IDLE
5. Now B should inherit from A (A has higher priority than IDLE)
6. Missing ENQUEUE_REPLENISH causes warning
```

**Consequences**: Incorrect deadline budget accounting, potential deadline misses.

**Fix status**: Patch should ensure ENQUEUE_REPLENISH is set during de-boost inheritance.

**How to verify fix**: Run `sudo ./test_dl_replenish_bug` - should complete without warning.

---

### 3. DL Server Timer on nohz_full CPUs

**Test**: `tests/regression/test-dlserver-nohz.sh`

**Kernel versions affected**: Kernels with DL server infrastructure

**Symptom**: Unexpected timer interrupts on nohz_full CPUs

**Description**:
The SCHED_DEADLINE server (DL server) infrastructure allows SCHED_NORMAL tasks to be served by a deadline server. However, the server's timer could fire on CPUs configured with `nohz_full`, breaking the nohz_full guarantee that isolated CPUs run without kernel tick interruptions.

**Root cause**:
DL server timer wasn't respecting nohz_full CPU configuration and could be armed on isolated CPUs.

**Consequences**:
- Breaks real-time guarantees for nohz_full CPUs
- Unexpected latency for isolated workloads
- Violates nohz_full contract

**Requirements to reproduce**:
- Kernel boot parameter: `nohz_full=<cpu_list>`
- CPUs isolated from normal scheduling

**Fix status**: DL server timer should avoid nohz_full CPUs.

**How to verify fix**: Run on system with nohz_full configured, check trace for timer interrupts on isolated CPUs.

---

## Historical Bugs (May be tested indirectly)

### CPU Hotplug and Deadline Task Migration

**Tested by**: `tests/hotplug/test_hp_*.sh`

**Issue**: Early SCHED_DEADLINE implementations had various bugs related to CPU hotplug:
- Task migration when assigned CPU goes offline
- Runqueue corruption during migration
- Admission control not updating when CPUs are removed

**Symptoms**: Kernel crashes, task hangs, scheduling anomalies

**Current status**: Modern kernels handle this correctly, but tests verify the functionality.

---

### Scheduling Domain and Root Domain Issues

**Tested by**: `tests/sched-domains/test_root_domains*.sh`

**Issue**: 
- Deadline tasks not migrating correctly between root domains
- Per-root-domain bandwidth accounting bugs
- Admission control miscalculations when domains are modified

**Symptoms**: Tasks stuck on wrong CPUs, admission control rejecting valid configurations

---

### Priority Inheritance Inversion

**Tested by**: `tests/priority-inheritance/test_prio_*.sh`

**Issue**: Various priority inheritance protocol bugs:
- Incorrect deadline parameter inheritance
- Deadlocks in complex locking scenarios
- Boost/de-boost race conditions

**Symptoms**: Priority inversion, system hangs, incorrect scheduling decisions

---

## Bug Report Checklist

If you discover a bug using this test suite:

1. **Kernel version**: Exact version (`uname -r`)
2. **Configuration**: Relevant kernel config options
   - `CONFIG_PREEMPT_RT` or `CONFIG_PREEMPT`
   - `CONFIG_SCHED_DEBUG`
   - CPU isolation parameters (nohz_full, isolcpus)
3. **Hardware**: CPU model, core count
4. **Test**: Exact test command and parameters
5. **Symptom**: Error messages, kernel warnings, oops
6. **Trace**: If available, include ftrace output
7. **Reproducibility**: How reliably does it reproduce?
8. **Bisection**: If possible, bisect to find introducing commit

Example bug report:
```
Kernel: 6.8.0-rc3
Config: CONFIG_PREEMPT=y, nohz_full=2-7
CPU: Intel Xeon, 8 cores
Test: sudo ./test_dl_replenish_bug
Symptom: Warning in dmesg: "DL de-boosted task PID 1234: REPLENISH flag missing"
Trace: Attached test_dl_replenish_bug.dat
Reproducibility: 100% on this kernel
```

---

## Debugging Tips

### Enable Deadline Scheduler Debugging

```bash
# Mount debugfs if not mounted
mount -t debugfs none /sys/kernel/debug

# Enable deadline-specific tracing
cd /sys/kernel/debug/tracing
echo 1 > events/sched/sched_deadline_yield/enable
echo 1 > events/sched/sched_stat_runtime/enable
echo 1 > events/sched/sched_pi_setprio/enable
```

### Check Scheduler Features

```bash
cat /sys/kernel/debug/sched_features
```

### Monitor Deadline Tasks

```bash
# Watch deadline tasks in real-time
watch -n 0.5 'ps -eTo pid,tid,class,rtprio,pri,psr,comm | grep -E "(PID|FF|DLN)"'
```

### Capture Kernel Warnings

```bash
# Monitor dmesg for scheduler warnings
dmesg -w | grep -i -E "(deadline|sched|replenish|PI)"
```

### Use ftrace for Deep Debugging

```bash
cd /sys/kernel/debug/tracing
echo function_graph > current_tracer
echo '*deadline*' > set_ftrace_filter
echo 1 > tracing_on
# Run test
echo 0 > tracing_on
cat trace > /tmp/deadline_trace.txt
```

---

## Contributing Bug Tests

If you find a new SCHED_DEADLINE bug:

1. **Isolate the bug**: Create minimal reproducer
2. **Document it**: Add entry to this file
3. **Write a test**: Add to `tests/regression/`
4. **Verify fix**: Test on kernel with and without the fix
5. **Submit**: Create pull request with:
   - Bug description in this file
   - Regression test
   - Expected behavior documentation

The regression test should:
- Reproduce the bug reliably on affected kernels
- Pass cleanly on fixed kernels
- Include comments explaining the scenario
- Exit with clear pass/fail status
- Capture relevant kernel messages if possible

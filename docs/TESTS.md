# Test Documentation

Detailed description of all tests in the SCHED_DEADLINE test suite.

## Basic Tests (`tests/basic/`)

### test_cpuhog_rsv.sh
**Purpose**: Verify that a CPU-intensive task runs correctly within a SCHED_DEADLINE reservation.

**What it does**:
- Spawns a CPU hog process
- Assigns it SCHED_DEADLINE scheduling with 10ms runtime / 100ms period
- Runs for configurable duration (default 10s)
- Monitors execution

**Expected behavior**: Task should run within its allocated bandwidth without system lockup.

**Kernel versions**: All versions with SCHED_DEADLINE support (≥ 3.14)

---

### test_yield_dl.sh
**Purpose**: Test deadline task yielding behavior.

**What it does**:
- Runs periodic_yield binary with SCHED_DEADLINE
- Task periodically yields the CPU
- Verifies correct rescheduling

**Expected behavior**: Yielding should work correctly without deadlock.

---

### test_cancel_dl_timer.sh
**Purpose**: Test that deadline timers are properly canceled when tasks exit.

**What it does**:
- Starts a deadline task
- Immediately terminates it
- Checks for timer cleanup

**Expected behavior**: No timer leaks or kernel warnings.

---

## Priority Inheritance Tests (`tests/priority-inheritance/`)

### test_prio_inherit.sh
**Purpose**: Verify priority inheritance protocol works correctly with SCHED_DEADLINE tasks.

**What it does**:
- Creates multiple tasks with different deadline parameters
- Uses pthread mutexes to create lock chains
- Verifies that blocked tasks inherit correct deadline parameters

**Expected behavior**: Higher priority (shorter deadline) tasks should boost lower priority tasks holding locks they need.

**Kernel bugs tested**: Priority inversion issues with deadline scheduling.

---

### test_prio_normal.sh
**Purpose**: Test priority inheritance between SCHED_NORMAL and SCHED_DEADLINE tasks.

**What it does**:
- Mixes SCHED_NORMAL and SCHED_DEADLINE tasks
- Tests mutex interactions
- Verifies boosting behavior

**Expected behavior**: SCHED_DEADLINE tasks blocked on SCHED_NORMAL tasks should properly boost them.

---

## Scheduling Domains Tests (`tests/sched-domains/`)

### test_rsv_cpuset.sh
**Purpose**: Test deadline task behavior with CPU affinity and cpusets.

**What it does**:
- Creates cpusets with specific CPU masks
- Assigns deadline tasks to cpusets
- Verifies tasks run on correct CPUs

**Expected behavior**: Tasks respect cpuset boundaries and scheduling domains.

---

### test_3rsv_cpuset.sh
**Purpose**: Test three deadline reservations within a single cpuset.

**What it does**:
- Creates cpuset with multiple CPUs
- Runs three deadline tasks in the cpuset
- Verifies admission control and scheduling

**Expected behavior**: All three reservations should be admitted if total utilization < 100%.

---

### test_4rsv_2cpusets.sh
**Purpose**: Test four deadline reservations split across two cpusets.

**What it does**:
- Creates two separate cpusets
- Runs two deadline tasks in each
- Tests scheduling domain isolation

**Expected behavior**: Each cpuset manages its own admission control independently.

---

### test_root_domains.sh / test_root_domains_1.sh / test_root_domains_tasks.sh
**Purpose**: Test root domain creation and task migration.

**What it does**:
- Manipulates cpusets to create/destroy root domains
- Migrates deadline tasks between domains
- Verifies deadline queues are properly maintained

**Expected behavior**: Tasks migrate correctly, no runqueue corruption.

---

## Hotplug Tests (`tests/hotplug/`)

### test_hp_one_cpu.sh
**Purpose**: Test deadline task behavior when its CPU is hot-unplugged.

**What it does**:
- Assigns deadline task to specific CPU
- Takes that CPU offline
- Verifies task migrates correctly

**Expected behavior**: Task should migrate to another CPU without crashing.

**Kernel bugs tested**: CPU hotplug migration issues with deadline tasks.

---

### test_hp_migration.sh
**Purpose**: Test task migration during CPU hotplug events.

**What it does**:
- Runs deadline task
- Repeatedly hotplugs CPUs
- Monitors task migration

**Expected behavior**: Smooth migration without deadline violations or kernel oops.

---

### test_hp_cpuset.sh / test_hp_2t_cpuset.sh
**Purpose**: Test hotplug interaction with cpusets containing deadline tasks.

**What it does**:
- Creates cpusets with deadline tasks
- Hotplugs CPUs within/outside the cpuset
- Tests admission control updates

**Expected behavior**: Cpuset bandwidth limits adjust correctly to available CPUs.

---

## Group Scheduling Tests (`tests/group-sched/`) - DISABLED

**Status**: These tests are currently **disabled** and not run by default.

**Reason**: SCHED_DEADLINE does not currently have cgroup (control group) support in the Linux kernel. These tests actually validate SCHED_FIFO/RR cgroup bandwidth control, not SCHED_DEADLINE.

### test_group.sh / test_group_periodic.sh / test_group_periods.sh
**Purpose**: Test cgroup CPU bandwidth control for real-time tasks (SCHED_FIFO/RR).

**What they do**:
- Create cgroup hierarchies with CPU bandwidth limits
- Run SCHED_FIFO tasks (not SCHED_DEADLINE)
- Test bandwidth enforcement across groups

**Dependencies**: Requires `schedtool` and `rt-app` (external tools)

**Future**: When SCHED_DEADLINE gains cgroup support, these tests should be updated to use SCHED_DEADLINE instead of SCHED_FIFO.

See `tests/group-sched/README.md` for more details.

---

## GRUB Tests (`tests/grub/`)

GRUB (Greedy Reclamation of Unused Bandwidth) is an algorithm that allows deadline tasks to reclaim unused bandwidth from other tasks.

### test-cpuhog.sh
**Purpose**: Test GRUB bandwidth reclaiming with CPU-intensive tasks.

**What it does**:
- Configures GRUB reclaiming
- Runs CPU hog under SCHED_DEADLINE
- Monitors actual CPU usage vs. reservation

**Expected behavior**: Task can use more than reserved bandwidth when idle bandwidth is available.

---

### test-running-bw.sh
**Purpose**: Test GRUB running bandwidth accounting.

**What it does**:
- Monitors running bandwidth with GRUB enabled
- Verifies correct accounting of reclaimed bandwidth

**Expected behavior**: Bandwidth accounting reflects actual usage including reclaimed bandwidth.

---

## Regression Tests (`tests/regression/`)

These tests reproduce specific kernel bugs to verify fixes.

### pi-cfs-bug-repro.c
**Kernel bug**: Priority inversion when deadline-boosted CFS task boosts another CFS task

**Affected versions**: v4.15 and others

**Description**: 
When a SCHED_NORMAL task (N1) is boosted by a SCHED_DEADLINE task (D1) via priority inheritance, and N1 then blocks another SCHED_NORMAL task (N2) on a mutex, N1 incorrectly tries to boost N2 with its inherited deadline parameters. This triggers a kernel bug at `kernel/sched/deadline.c:1405`.

**Reproduction steps**:
1. N1 locks mutex M1
2. N2 locks mutex M2
3. D1 blocks on M1 (boosts N1 to DEADLINE)
4. N1 blocks on M2 (tries to boost N2 with DEADLINE)
5. Kernel BUG triggered

**Expected with fix**: No kernel BUG, proper handling of the boosting chain.

**Build**: `gcc -o pi-cfs-bug-repro pi-cfs-bug-repro.c -lpthread`

**Run**: `sudo ./pi-cfs-bug-repro`

---

### test_dl_replenish_bug.c
**Kernel bug**: Missing ENQUEUE_REPLENISH flag when deadline task is deboosted

**Description**:
When a SCHED_DEADLINE task (B) holds a PI mutex and is changed to SCHED_IDLE while another SCHED_DEADLINE task (A) is blocked on that mutex, task B should inherit DEADLINE from A. However, the ENQUEUE_REPLENISH flag was missing during this inheritance, causing the warning:
```
DL de-boosted task PID X: REPLENISH flag missing
```

**Reproduction steps**:
1. Task B (DEADLINE, short deadline) holds mutex
2. Task A (DEADLINE, long deadline) blocks on mutex
3. B has higher priority, so no initial inheritance
4. sched_setscheduler() changes B from DEADLINE to IDLE
5. B should now inherit DEADLINE from A with ENQUEUE_REPLENISH

**Expected with fix**: No warning, correct REPLENISH flag set.

**Build**: `gcc -o test_dl_replenish_bug test_dl_replenish_bug.c -lpthread`

**Run**: `sudo ./test_dl_replenish_bug`

---

### test-dlserver-nohz.sh
**Kernel bug**: DL server timer firing on nohz_full CPUs

**Description**:
The SCHED_DEADLINE server infrastructure could cause timers to fire on CPUs configured with `nohz_full`, violating the nohz_full contract that user tasks run without kernel interruptions.

**What it does**:
- Checks for nohz_full configuration
- Runs deadline tasks on nohz_full CPUs
- Monitors for unexpected timer interrupts
- Uses kernel tracing to detect violations

**Expected with fix**: No DL server timers fire on nohz_full CPUs.

**Requirements**: Kernel with `nohz_full` boot parameter set.

**Run**: `sudo ./test-dlserver-nohz.sh`

---

## Tracing Support

Most tests support kernel tracing via ftrace/trace-cmd:

```bash
sudo ./test_name.sh 1  # Enable tracing
```

When tracing is enabled:
- Events are captured in `<testname>.dat`
- Test markers are written to trace buffer
- Useful for debugging test failures
- Can be analyzed with `trace-cmd report <testname>.dat`

Common trace events captured:
- `sched_wakeup*` - Task wakeups
- `sched_switch` - Context switches  
- `sched_migrate*` - Task migrations

---

## Adding New Tests

When adding a new test:

1. **Choose the right category** - Place test in appropriate subdirectory
2. **Follow naming convention** - Use `test_<description>.sh` or `.c`
3. **Use common utilities** - Source `../../lib/utils.sh` for helper functions
4. **Add trace support** - Accept trace enable parameter: `TRACE=${1-0}`
5. **Report results** - Use `test_passed` or `test_failed` from utils.sh
6. **Document it** - Add entry to this file
7. **Update Makefile** - Add build rules if it's a C program

Example test structure:
```bash
#!/bin/bash
. ../../lib/utils.sh

TNAME="test_example"
TDESC="Description of what this test does"
TRACE=${1-0}

print_test_info
trace_start

# Test logic here
trace_write "test step 1"
# ... do something ...

if [ test_condition ]; then
    test_passed
else
    test_failed
fi

trace_stop
trace_extract
```

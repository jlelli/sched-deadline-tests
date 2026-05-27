# Group Scheduling Tests - DISABLED

## Status: Not Active

These tests are **currently disabled** because SCHED_DEADLINE does not yet have cgroup (control group) support in the Linux kernel.

## What These Tests Do

These tests validate CPU bandwidth control for real-time tasks using cgroups:

- **test_group.sh** - Basic cgroup RT bandwidth enforcement
- **test_group_periodic.sh** - Periodic tasks under cgroup limits (uses rt-app)
- **test_group_periods.sh** - Multiple period configurations
- **test_rt_migration.sh** - Task migration between cgroups

## Why They're Disabled

1. **SCHED_DEADLINE lacks cgroup support** - The kernel doesn't currently support putting SCHED_DEADLINE tasks into cgroups with bandwidth limits
2. **Tests use SCHED_FIFO** - These tests actually test SCHED_FIFO/RR, not SCHED_DEADLINE
3. **External dependencies** - Tests require `schedtool` and `rt-app` which aren't standard

## Future Work

When SCHED_DEADLINE gains cgroup support, these tests should be:
1. Updated to use SCHED_DEADLINE instead of SCHED_FIFO
2. Updated to use chrt instead of schedtool
3. Re-enabled in the test suite

## Running Manually

If you want to run these tests for SCHED_FIFO/RR cgroup validation:

```bash
# Install dependencies
sudo apt-get install schedtool rt-app  # Debian/Ubuntu
sudo dnf install schedtool rt-app      # Fedora/RHEL

# Run individual test
cd tests/group-sched
sudo ./test_group.sh
```

Note: These test SCHED_FIFO cgroup support, not SCHED_DEADLINE.

## References

- [SCHED_DEADLINE documentation](https://www.kernel.org/doc/html/latest/scheduler/sched-deadline.html)
- Cgroup support for SCHED_DEADLINE is a TODO item in kernel development

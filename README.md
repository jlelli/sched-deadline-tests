# SCHED_DEADLINE Test Suite

Comprehensive test suite for the Linux kernel's SCHED_DEADLINE real-time scheduling class.

## Overview

This test suite validates various aspects of the SCHED_DEADLINE scheduler, including:

- Basic deadline scheduling behavior
- Priority inheritance with deadline tasks
- CPU hotplug interactions
- Scheduling domains and root domains
- Control group (cgroup) scheduling
- GRUB reclaiming algorithm
- Regression tests for specific kernel bugs

## Requirements

### System Requirements

- Linux kernel with SCHED_DEADLINE support (≥ 3.14)
- Root or CAP_SYS_NICE capability (required for SCHED_DEADLINE)
- Multi-core CPU (recommended for migration/domain tests)

### Build Dependencies

- GCC compiler
- GNU Make
- pthread library
- schedtool (optional, for some tests)
- trace-cmd (optional, for tracing tests)

### Installation

Install dependencies on Fedora/RHEL:
```bash
sudo dnf install gcc make glibc-devel schedtool trace-cmd
```

Install dependencies on Debian/Ubuntu:
```bash
sudo apt-get install gcc make libc6-dev schedtool trace-cmd
```

## Building

Build all tests:
```bash
make
```

Build tests for a specific category:
```bash
cd tests/basic && make
cd tests/priority-inheritance && make
```

Clean build artifacts:
```bash
make clean
```

## Running Tests

### Quick Start

Run all tests on the current system:
```bash
sudo ./run-tests.sh
```

Run tests in a VM (safer, recommended for development):
```bash
./tools/run-in-vm.sh /path/to/kernel
```

See **[VM Testing Guide](docs/VM-TESTING.md)** for automated kernel testing.

Run tests from a specific category:
```bash
sudo ./run-tests.sh --category basic
sudo ./run-tests.sh --category priority-inheritance
```

Run a specific test:
```bash
sudo ./run-tests.sh --test basic/test_cpuhog_rsv.sh
```

### Individual Tests

You can also run individual test scripts directly:
```bash
cd tests/basic
sudo ./test_cpuhog_rsv.sh
```

Some tests support tracing:
```bash
sudo ./test_cpuhog_rsv.sh 1  # Enable tracing
```

### Understanding Test Output

- `TEST_PASSED` - Test completed successfully
- `TEST_FAILED` - Test detected an error or unexpected behavior
- Exit code 0 - Success
- Exit code 1 - Failure

## Test Categories

### Basic Tests (`tests/basic/`)

Fundamental SCHED_DEADLINE behavior:
- CPU hog tasks under deadline reservations
- Periodic yielding tasks
- Deadline timer cancellation

### Priority Inheritance (`tests/priority-inheritance/`)

Tests for priority inheritance protocol with SCHED_DEADLINE:
- Deadline task inheriting from another deadline task
- Mutual exclusion with pthread mutexes

### Scheduling Domains (`tests/sched-domains/`)

Tests for multi-CPU scheduling domains and root domains:
- CPU affinity and cpusets
- Task migration between domains
- Root domain isolation

### Hotplug (`tests/hotplug/`)

CPU hotplug interaction with deadline tasks:
- Online/offline CPU with running deadline tasks
- Migration during hotplug events
- Cpuset interaction with hotplug

### Group Scheduling (`tests/group-sched/`) - DISABLED

**Status**: Currently disabled - SCHED_DEADLINE doesn't have cgroup support yet.

These tests validate cgroup CPU bandwidth for SCHED_FIFO/RR (not SCHED_DEADLINE):
- Group bandwidth enforcement
- Hierarchical scheduling

See `tests/group-sched/README.md` for details.

### GRUB (`tests/grub/`)

Tests for the Greedy Reclamation of Unused Bandwidth (GRUB) algorithm:
- Bandwidth reclaiming
- Running bandwidth accounting

### Regression Tests (`tests/regression/`)

Tests that reproduce specific kernel bugs:

- **pi-cfs-bug-repro.c** - Priority inversion bug when deadline-boosted task boosts another task (v4.15)
- **test_dl_replenish_bug.c** - Missing ENQUEUE_REPLENISH flag when deadline task is deboosted
- **test-dlserver-nohz.sh** - DL server timer firing on nohz_full CPUs

## Documentation

Detailed documentation is available in the `docs/` directory:

- **[docs/TESTS.md](docs/TESTS.md)** - Detailed description of each test
- **[docs/BUGS.md](docs/BUGS.md)** - Kernel bugs tested by this suite
- **[docs/CONTRIBUTING.md](docs/CONTRIBUTING.md)** - Guidelines for adding new tests
- **[docs/VM-TESTING.md](docs/VM-TESTING.md)** - Running tests in VMs for CI/CD

## Tools

The `tools/` directory contains utilities:

- `dl_getparam.c` - Get SCHED_DEADLINE parameters for a task

## Contributing

When adding new tests:

1. Place the test in the appropriate category directory
2. Follow the existing naming convention: `test_<description>.sh` or `test_<description>.c`
3. Use the common utilities from `lib/utils.sh`
4. Add documentation in `docs/TESTS.md`
5. Update this README if adding a new category

## Tracing

Many tests support ftrace integration for detailed kernel tracing:

```bash
sudo ./test_name.sh 1  # Enable tracing
```

Trace files are saved as `<testname>.dat` and can be analyzed with trace-cmd:

```bash
trace-cmd report testname.dat
```

## Troubleshooting

### Permission Denied

SCHED_DEADLINE requires root privileges. Run tests with `sudo`.

### "Operation not permitted" when setting SCHED_DEADLINE

Check if admission control is too restrictive:
```bash
# Disable RT throttling (use with caution)
echo -1 | sudo tee /proc/sys/kernel/sched_rt_runtime_us
```

### Tests Hang or Timeout

Some tests may hang if kernel has bugs in the areas being tested. Use `trace-cmd` to capture kernel state for debugging.

## License

See `LICENSE` file for details.

## References

- [SCHED_DEADLINE documentation](https://www.kernel.org/doc/html/latest/scheduler/sched-deadline.html)
- [Real-Time Linux Wiki](https://wiki.linuxfoundation.org/realtime/start)

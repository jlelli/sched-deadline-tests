# Contributing to SCHED_DEADLINE Test Suite

Thank you for your interest in contributing! This document provides guidelines for adding new tests, reporting bugs, and improving the test suite.

## Getting Started

1. **Fork the repository** (if applicable)
2. **Build the test suite**: `make`
3. **Run existing tests**: `sudo ./run-tests.sh`
4. **Familiarize yourself** with the codebase structure

## Repository Structure

```
sched-deadline-tests/
├── lib/                      # Shared utilities and libraries
│   ├── utils.sh             # Common test helper functions
│   └── test_skeleton.sh     # Template for new tests
├── tests/                   # All test categories
│   ├── basic/              # Basic functionality tests
│   ├── priority-inheritance/  # PI protocol tests
│   ├── sched-domains/      # Scheduling domains tests
│   ├── hotplug/            # CPU hotplug tests
│   ├── group-sched/        # Cgroup scheduling tests
│   ├── grub/               # GRUB algorithm tests
│   └── regression/         # Kernel bug regression tests
├── tools/                  # Utility programs
├── docs/                   # Documentation
│   ├── TESTS.md           # Detailed test descriptions
│   ├── BUGS.md            # Known bugs catalog
│   └── CONTRIBUTING.md    # This file
├── run-tests.sh           # Main test runner
├── Makefile               # Build system
└── README.md              # Main documentation
```

## Types of Contributions

### 1. Bug Reports

When reporting issues with tests:

**Required information:**
- Kernel version (`uname -r`)
- Distribution and version
- Test command that failed
- Complete error output
- Hardware details (CPU model, core count)

**Use this template:**
```markdown
**Test**: test_name.sh
**Kernel**: 6.8.0
**Distribution**: Fedora 40
**Command**: sudo ./run-tests.sh --category basic
**Error output**: 
[paste error here]
**Expected**: [what should happen]
**Actual**: [what actually happened]
```

### 2. New Tests

#### When to Add a Test

Add a new test when:
- You discover a SCHED_DEADLINE bug (add to `tests/regression/`)
- You want to verify specific scheduler behavior
- You're testing a new kernel feature
- Existing tests don't cover a scenario

#### Test Development Process

1. **Choose the right category**
   - `basic/` - Core SCHED_DEADLINE functionality
   - `priority-inheritance/` - PI protocol behavior
   - `sched-domains/` - Multi-CPU, cpuset, domain tests
   - `hotplug/` - CPU online/offline interactions
   - `group-sched/` - Cgroup integration
   - `grub/` - Bandwidth reclaiming
   - `regression/` - Specific kernel bugs

2. **Decide on test type**
   - **Shell script** (`.sh`) - For integration tests, system-level tests
   - **C program** (`.c`) - For precise timing, complex synchronization

3. **Follow naming convention**
   - Shell: `test_<descriptive_name>.sh`
   - C: `test_<descriptive_name>.c` or `<bug_description>.c`
   - Be descriptive: `test_dl_inheritance.sh` not `test1.sh`

#### Writing Shell Tests

Use the test skeleton as a starting point:

```bash
#!/bin/bash
. ../../lib/utils.sh

# Test metadata
TNAME="test_example"
TDESC="
###########################################
#  
#    test: $TNAME
#
#    Brief description of what this test
#    verifies and why it's important
#
###########################################
"

# Parameters
TRACE=${1-0}      # Enable tracing with ./test.sh 1
SLEEP=${2-10}     # Duration parameter with default

# Events to trace (if tracing enabled)
EVENTS="sched_wakeup sched_switch sched_migrate_task"

print_test_info
dump_on_oops      # Set up crash dumps
trace_start       # Start tracing if enabled

trace_write "start $TNAME"

# Main test logic here
# Use schedtool or custom C programs to set SCHED_DEADLINE

# Example: Run deadline task
schedtool -E -t 10000000:100000000 -e ./my_program &
PID=$!

sleep $SLEEP

# Check conditions
if [ some_check ]; then
    test_passed
    EXIT_CODE=0
else
    test_failed
    EXIT_CODE=1
fi

# Cleanup
kill -9 $PID 2>/dev/null

trace_write "end $TNAME"
trace_stop
trace_extract

exit $EXIT_CODE
```

**Available helper functions** (from `lib/utils.sh`):
- `print_test_info` - Display test description
- `trace_start` / `trace_stop` / `trace_extract` - Tracing control
- `trace_write "message"` - Add marker to trace
- `test_passed` / `test_failed` - Report results
- `dump_on_oops` - Configure crash dumps
- `log "message"` - Log to console and trace
- `turn_on_cpu N` / `turn_off_cpu N` - Hotplug helpers
- `disable_ac` / `enable_ac` - Admission control

#### Writing C Tests

For regression tests or precise timing:

```c
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <pthread.h>
#include <sched.h>
#include <sys/syscall.h>
#include <linux/kernel.h>

// SCHED_DEADLINE parameters structure
struct sched_attr {
    __u32 size;
    __u32 sched_policy;
    __u64 sched_flags;
    __s32 sched_nice;
    __u32 sched_priority;
    __u64 sched_runtime;
    __u64 sched_deadline;
    __u64 sched_period;
};

// Syscall wrapper
static int sched_setattr(pid_t pid, const struct sched_attr *attr,
                         unsigned int flags) {
    return syscall(__NR_sched_setattr, pid, attr, flags);
}

int main() {
    struct sched_attr attr = {0};
    
    attr.size = sizeof(attr);
    attr.sched_policy = SCHED_DEADLINE;
    attr.sched_runtime  = 10 * 1000000;  // 10ms
    attr.sched_deadline = 20 * 1000000;  // 20ms  
    attr.sched_period   = 20 * 1000000;  // 20ms
    
    if (sched_setattr(0, &attr, 0) < 0) {
        perror("sched_setattr");
        return 1;
    }
    
    // Test logic here
    
    printf("TEST_PASSED\n");
    return 0;
}
```

**Build in Makefile**:
```makefile
my_test: my_test.c
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)
```

### 3. Documentation Improvements

Documentation contributions are valuable!

- Update `docs/TESTS.md` when adding tests
- Update `docs/BUGS.md` when adding regression tests
- Improve README.md clarity
- Add code comments for complex logic
- Fix typos and grammar

### 4. Build System Improvements

Contributions to Makefiles and build infrastructure:

- Better compiler detection
- Cross-compilation support
- Improved dependency handling
- Additional targets (e.g., `make check`)

## Code Style Guidelines

### Shell Scripts

- Use `#!/bin/bash` shebang
- Source `utils.sh`: `. ../../lib/utils.sh`
- Use meaningful variable names: `DEADLINE_TASK_PID` not `p`
- Quote variables: `"$VARIABLE"` to handle spaces
- Check command success: `|| exit 1` for critical commands
- Add comments for non-obvious logic
- Use consistent indentation (4 spaces)

### C Programs

- Follow kernel coding style where applicable
- Use meaningful names: `deadline_task_thread()` not `dt()`
- Check return values: always check syscall returns
- Free resources: cleanup mutexes, join threads
- Print clear messages: "TEST_PASSED" / "TEST_FAILED"
- Add comments explaining test scenario
- Use `#define` for magic numbers

## Testing Your Contribution

Before submitting:

1. **Build cleanly**: `make clean && make`
   - No compilation warnings
   - All programs build successfully

2. **Test your changes**:
   ```bash
   # Run your new test
   sudo ./run-tests.sh --test <category>/<your_test>.sh
   
   # Verify it works with tracing
   cd tests/<category>
   sudo ./<your_test>.sh 1
   
   # Run full suite to ensure no regressions
   sudo ./run-tests.sh
   ```

3. **Test on target kernel**:
   - If it's a regression test, verify it fails on buggy kernel
   - Verify it passes on fixed kernel
   - Document kernel version requirements

4. **Check documentation**:
   - Update `docs/TESTS.md` with test description
   - Update `docs/BUGS.md` if it's a regression test
   - Update README.md if adding new category

## Submitting Changes

### Commit Messages

Follow kernel-style commit messages:

```
Short (50 chars or less) summary

More detailed explanatory text, if necessary. Wrap it to about 72
characters. The blank line separating the summary from the body is
critical.

Explain the problem this commit solves. Focus on why you are making
this change as opposed to how. The code explains how.

Signed-off-by: Your Name <your.email@example.com>
```

**For test additions:**
```
Add test for deadline task CPU migration

This test verifies that SCHED_DEADLINE tasks correctly migrate
between CPUs when their affinity is changed. It reproduces a bug
found in kernel 5.x where tasks would hang during migration.

The test creates a deadline task pinned to CPU 0, then changes
affinity to CPU 1 and verifies the task continues running.

Signed-off-by: Your Name <your.email@example.com>
```

### Pull Request Checklist

- [ ] Test builds cleanly with `make`
- [ ] Test runs successfully
- [ ] Documentation updated (TESTS.md, BUGS.md if applicable)
- [ ] Commit message follows guidelines
- [ ] Signed-off-by tag included
- [ ] No unrelated changes included
- [ ] If C code: no memory leaks, resources freed
- [ ] If shell: shellcheck passes (if available)

## Code Review Process

Maintainers will review:

1. **Correctness**: Does test actually verify the claim?
2. **Clarity**: Is code readable and well-documented?
3. **Safety**: No dangerous operations (rm -rf, etc.)
4. **Portability**: Works on different kernel versions?
5. **Style**: Follows project conventions?

Be prepared to:
- Answer questions about test design
- Make requested changes
- Rebase if needed
- Add more documentation

## Getting Help

Questions? Need guidance?

- **For test design**: Open an issue describing what you want to test
- **For kernel bugs**: Provide full details (kernel version, config, trace)
- **For build issues**: Include full make output and environment
- **For test failures**: Include test output and dmesg

## Recognition

Contributors will be:
- Listed in git history
- Mentioned in release notes
- Credited in documentation where applicable

Thank you for helping improve SCHED_DEADLINE testing!

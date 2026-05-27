# Running Tests in Virtual Machines

This document explains how to run SCHED_DEADLINE tests in VMs automatically, which is essential for CI/CD and kernel development workflows.

## Why Test in VMs?

- **Safety**: Kernel bugs can crash systems; VMs isolate the damage
- **Automation**: CI pipelines can build and test kernels automatically  
- **Reproducibility**: Consistent environment across different machines
- **Speed**: Quickly test different kernel versions without rebooting

## Quick Start with virtme-ng

The easiest way to test kernels is with **virtme-ng**, a lightweight tool designed for kernel testing.

### 1. Install virtme-ng

```bash
# Install with pip
pip install --user virtme-ng

# Or system-wide
sudo pip install virtme-ng

# Verify installation
vng --version
```

### 2. Build Your Kernel

```bash
cd /path/to/linux-kernel
make defconfig
make -j$(nproc)
```

### 3. Run Tests

```bash
# From sched-deadline-tests directory
./tools/run-in-vm.sh /path/to/linux-kernel
```

That's it! The script will boot your kernel in a VM and run all tests.

## Detailed Usage

### Using run-in-vm.sh

The `tools/run-in-vm.sh` script wraps virtme-ng with test-specific configurations.

**Basic usage:**
```bash
./tools/run-in-vm.sh [OPTIONS] KERNEL_PATH
```

**Examples:**
```bash
# Run all tests
./tools/run-in-vm.sh ~/linux

# Run specific category
./tools/run-in-vm.sh --category basic ~/linux

# Run specific test with tracing
./tools/run-in-vm.sh --test basic/test_cpuhog_rsv.sh --trace ~/linux

# Use more CPUs for migration tests
./tools/run-in-vm.sh --smp 8 ~/linux

# Verbose output
./tools/run-in-vm.sh --verbose ~/linux
```

**Options:**
- `-c, --category CAT` - Run specific test category
- `-t, --test TEST` - Run specific test file
- `-v, --verbose` - Enable verbose output
- `-T, --trace` - Enable kernel tracing in tests
- `-m, --memory SIZE` - VM memory (default: 2G)
- `-s, --smp CPUS` - Number of CPUs (default: 4)
- `--no-kvm` - Disable KVM acceleration
- `--virtme-opts` - Pass additional virtme-ng options

### Full CI Pipeline

For complete CI automation (clone, build, test):

```bash
./tools/ci-kernel-test.sh
```

This script will:
1. Clone the kernel (or use existing directory)
2. Configure with SCHED_DEADLINE support
3. Build the kernel
4. Run tests in VM
5. Report results

**Examples:**
```bash
# Test latest kernel
./tools/ci-kernel-test.sh

# Test specific version
./tools/ci-kernel-test.sh --kernel-branch v6.8

# Use existing kernel
./tools/ci-kernel-test.sh --kernel-dir ~/linux

# Just build, don't test
./tools/ci-kernel-test.sh --kernel-dir ~/linux --build-only

# Just test pre-built kernel
./tools/ci-kernel-test.sh --kernel-dir ~/linux --test-only

# Test specific category
./tools/ci-kernel-test.sh --kernel-dir ~/linux -c regression

# Use custom kernel config
./tools/ci-kernel-test.sh --config my-kernel.config
```

## Kernel Configuration

For SCHED_DEADLINE tests to work, your kernel needs:

**Required:**
- `CONFIG_PREEMPT=y` - Preemptible kernel
- Kernel ≥ 3.14 (when SCHED_DEADLINE was added)

**Recommended:**
- `CONFIG_SCHED_DEBUG=y` - Scheduler debugging
- `CONFIG_DEBUG_KERNEL=y` - General kernel debugging
- `CONFIG_FTRACE=y` - Function tracing
- `CONFIG_FUNCTION_TRACER=y` - Detailed tracing
- `CONFIG_SCHED_TRACER=y` - Scheduler tracing
- `CONFIG_DEBUG_FS=y` - debugfs for sched_features

**For nohz_full tests:**
- `CONFIG_NO_HZ_FULL=y` - Tickless kernel support
- Boot with `nohz_full=2-7` (or appropriate CPU list)

### Automatic Configuration

The `ci-kernel-test.sh` script automatically enables required options:

```bash
./tools/ci-kernel-test.sh --kernel-dir ~/linux
```

Or manually configure your kernel:

```bash
cd ~/linux
make defconfig
scripts/config --enable CONFIG_PREEMPT
scripts/config --enable CONFIG_SCHED_DEBUG
scripts/config --enable CONFIG_FTRACE
make olddefconfig
make -j$(nproc)
```

## Understanding virtme-ng

virtme-ng creates a lightweight VM that:
- Uses your kernel build directly (no installation needed)
- Shares your host filesystem (9p mount)
- Boots in seconds
- Requires minimal memory/disk

**How it works:**
1. Boots your built kernel with QEMU/KVM
2. Mounts your host root filesystem (read-only)
3. Runs commands inside the VM
4. Returns output and exit code

**Advantages over full VMs:**
- No disk image needed
- No kernel installation
- Fast boot (< 5 seconds)
- Minimal overhead
- Perfect for kernel development

## CI Integration

### Self-Hosted Runner

For GitHub Actions or GitLab CI with a dedicated machine:

1. **Set up machine:**
   - Install KVM/QEMU
   - Install virtme-ng
   - Clone test suite

2. **Create workflow** (`.github/workflows/kernel-test.yml`):
```yaml
name: Kernel Tests

on:
  push:
    branches: [ master ]

jobs:
  test:
    runs-on: self-hosted
    
    steps:
    - uses: actions/checkout@v4
    
    - name: Run tests on latest kernel
      run: ./tools/ci-kernel-test.sh --kernel-branch v6.8
```

3. **Register self-hosted runner** with your repository

### Jenkins Pipeline

```groovy
pipeline {
    agent any
    
    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }
        
        stage('Build Kernel & Test') {
            steps {
                sh './tools/ci-kernel-test.sh --kernel-dir /jenkins/kernels/linux'
            }
        }
    }
}
```

### Cron Job

For nightly testing:

```bash
#!/bin/bash
# /etc/cron.daily/kernel-deadline-tests

cd /path/to/sched-deadline-tests
./tools/ci-kernel-test.sh --kernel-dir /path/to/linux | \
    tee /var/log/deadline-tests/$(date +%Y%m%d).log
```

## Advanced Scenarios

### Testing Multiple Kernels

```bash
for version in v6.6 v6.7 v6.8; do
    echo "Testing kernel $version"
    ./tools/ci-kernel-test.sh \
        --kernel-branch $version \
        --clean
done
```

### Bisecting a Bug

```bash
# In your kernel tree
cd ~/linux

git bisect start
git bisect bad HEAD
git bisect good v6.6

git bisect run /path/to/sched-deadline-tests/tools/ci-kernel-test.sh \
    --kernel-dir . \
    --test-only \
    --category regression
```

### Testing Local Patches

```bash
# Apply your patches
cd ~/linux
git am /path/to/patches/*.patch

# Rebuild and test
cd /path/to/sched-deadline-tests
./tools/ci-kernel-test.sh --kernel-dir ~/linux
```

### Custom Kernel Config

```bash
# Create config with your requirements
cd ~/linux
make menuconfig
cp .config /path/to/my-test-config

# Use it for testing
cd /path/to/sched-deadline-tests
./tools/ci-kernel-test.sh \
    --kernel-dir ~/linux \
    --config /path/to/my-test-config
```

## Troubleshooting

### virtme-ng not found

```bash
pip install --user virtme-ng
# Add to PATH if needed
export PATH="$HOME/.local/bin:$PATH"
```

### KVM not available

If you get KVM errors:

```bash
# Check KVM support
lsmod | grep kvm

# Run without KVM (slower)
./tools/run-in-vm.sh --no-kvm ~/linux
```

### Tests fail in VM but not on host

This usually indicates:
- Kernel config differences
- Hardware differences (CPU count, features)
- Timing-dependent bugs

Try:
- Match CPU count: `--smp $(nproc)`
- Check kernel config
- Enable more debugging: `--verbose`

### VM hangs or crashes

If the VM hangs:
- Kernel bug triggered (expected for regression tests!)
- Check dmesg in VM
- Enable crash dumps: kernel boot with `crashkernel=256M`

### Permission denied errors

virtme-ng needs access to /dev/kvm:

```bash
# Add yourself to kvm group
sudo usermod -a -G kvm $USER
# Log out and back in
```

## Performance Considerations

**VM overhead:**
- First boot: ~5-10 seconds
- Subsequent boots: ~2-5 seconds  
- Test execution: +10-20% vs native

**Optimization tips:**
- Use KVM acceleration (30x faster than emulation)
- Allocate enough memory (`--memory 2G` minimum)
- Use multiple CPUs (`--smp 4` or more)
- Keep kernel config minimal (disable unused features)

## Comparison with Other Approaches

| Method | Speed | Isolation | Setup | CI-friendly |
|--------|-------|-----------|-------|-------------|
| virtme-ng | ⚡⚡⚡ | ✓ | Easy | ✓✓✓ |
| QEMU/KVM full VM | ⚡⚡ | ✓✓ | Medium | ✓✓ |
| Container (no kernel) | ⚡⚡⚡ | ✗ | Easy | ✗ |
| Physical reboot | ⚡ | ✓✓ | Hard | ✗ |

**virtme-ng wins for kernel testing** because it combines speed, isolation, and ease of use.

## References

- [virtme-ng documentation](https://github.com/arighi/virtme-ng)
- [QEMU documentation](https://www.qemu.org/docs/master/)
- [Kernel testing best practices](https://www.kernel.org/doc/html/latest/dev-tools/testing-overview.html)

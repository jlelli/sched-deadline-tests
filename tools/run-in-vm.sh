#!/bin/bash
# Run SCHED_DEADLINE tests in a VM using virtme-ng
#
# This script uses virtme-ng to boot a kernel and run the test suite inside it.
# virtme-ng is a lightweight tool for quickly testing kernels in VMs.
#
# Requirements:
#   - virtme-ng installed (pip install virtme-ng)
#   - QEMU/KVM
#   - Kernel built with SCHED_DEADLINE support

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_color() {
    local color=$1
    shift
    echo -e "${color}$@${NC}"
}

usage() {
    cat <<EOF
Usage: $0 [OPTIONS] KERNEL_PATH

Run SCHED_DEADLINE tests in a VM using virtme-ng.

ARGUMENTS:
    KERNEL_PATH           Path to kernel source tree (must be built)
                         Examples: /home/user/linux
                                  /home/user/kernel-rt

OPTIONS:
    -c, --category CAT   Run specific test category
    -t, --test TEST      Run specific test
    -v, --verbose        Enable verbose output
    -T, --trace          Enable kernel tracing in tests
    -m, --memory SIZE    VM memory size (default: 2G)
    -s, --smp CPUS       Number of CPUs (default: 8)
    --no-kvm             Disable KVM acceleration
    --virtme-opts OPTS   Additional virtme-ng options
    -h, --help           Show this help

EXAMPLES:
    # Run all tests on a kernel
    $0 /home/user/linux

    # Run specific category with tracing
    $0 -c basic -T /home/user/linux

    # Run with more CPUs for migration tests
    $0 -s 8 /home/user/linux

    # Run specific test with verbose output
    $0 -v -t basic/test_cpuhog_rsv.sh /home/user/linux

SETUP:
    1. Install virtme-ng:
       pip install --user virtme-ng

    2. Build your kernel with SCHED_DEADLINE support:
       cd /path/to/kernel
       make menuconfig  # Enable CONFIG_SCHED_DEBUG=y
       make -j\$(nproc)

    3. Run tests:
       $0 /path/to/kernel

EOF
    exit 0
}

# Default values
CATEGORY=""
SPECIFIC_TEST=""
VERBOSE=""
TRACE=""
MEMORY="2G"
CPUS="8"
KVM="enabled"
VIRTME_OPTS=""
KERNEL_PATH=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--category)
            CATEGORY="$2"
            shift 2
            ;;
        -t|--test)
            SPECIFIC_TEST="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE="--verbose"
            shift
            ;;
        -T|--trace)
            TRACE="--trace"
            shift
            ;;
        -m|--memory)
            MEMORY="$2"
            shift 2
            ;;
        -s|--smp)
            CPUS="$2"
            shift 2
            ;;
        --no-kvm)
            KVM="disabled"
            shift
            ;;
        --virtme-opts)
            VIRTME_OPTS="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        -*)
            echo "Unknown option: $1"
            usage
            ;;
        *)
            KERNEL_PATH="$1"
            shift
            ;;
    esac
done

# Validate kernel path
if [ -z "$KERNEL_PATH" ]; then
    print_color "$RED" "ERROR: Kernel path required"
    echo
    usage
fi

if [ ! -d "$KERNEL_PATH" ]; then
    print_color "$RED" "ERROR: Kernel path not found: $KERNEL_PATH"
    exit 1
fi

if [ ! -f "$KERNEL_PATH/vmlinux" ] && [ ! -f "$KERNEL_PATH/arch/x86/boot/bzImage" ]; then
    print_color "$RED" "ERROR: Kernel not built. Run 'make' in $KERNEL_PATH first"
    exit 1
fi

# Check for virtme-ng
if ! command -v vng &> /dev/null; then
    print_color "$RED" "ERROR: virtme-ng not found"
    echo
    echo "Install with: pip install --user virtme-ng"
    echo "Or: pip install virtme-ng"
    exit 1
fi

# Get absolute paths
KERNEL_PATH=$(realpath "$KERNEL_PATH")
TEST_DIR=$(realpath "$(dirname "$0")/..")

print_color "$BLUE" "=========================================="
print_color "$BLUE" "SCHED_DEADLINE Test Runner (virtme-ng)"
print_color "$BLUE" "=========================================="
echo
echo "Kernel:       $KERNEL_PATH"
echo "Tests:        $TEST_DIR"
echo "Memory:       $MEMORY"
echo "CPUs:         $CPUS"
echo "KVM:          ${KVM:+enabled}"
[ -n "$CATEGORY" ] && echo "Category:     $CATEGORY"
[ -n "$SPECIFIC_TEST" ] && echo "Test:         $SPECIFIC_TEST"
[ -n "$TRACE" ] && echo "Tracing:      enabled"
echo

# Build test command to run inside VM
# Note: virtme-ng --rwdir mounts at the same path as host, and --cwd sets working dir
# Write dmesg to the shared test directory so it's accessible from host
DMESG_LOG="${TEST_DIR}/dmesg-$(date +%Y%m%d-%H%M%S).log"
TEST_CMD="dmesg -C && make clean && make && ./run-tests.sh"
[ -n "$CATEGORY" ] && TEST_CMD+=" --category $CATEGORY"
[ -n "$SPECIFIC_TEST" ] && TEST_CMD+=" --test $SPECIFIC_TEST"
[ -n "$VERBOSE" ] && TEST_CMD+=" --verbose"
[ -n "$TRACE" ] && TEST_CMD+=" --trace"
TEST_CMD+=" ; dmesg > $DMESG_LOG && echo '=== dmesg saved to $DMESG_LOG ==='"

print_color "$BLUE" "Booting VM and running tests..."
print_color "$YELLOW" "Command: $TEST_CMD"
print_color "$BLUE" "dmesg will be saved to: $DMESG_LOG"
echo

# Change to kernel directory (required by vng)
cd "$KERNEL_PATH"

# Build KVM argument
KVM_ARG=""
if [ "$KVM" = "disabled" ]; then
    KVM_ARG="--disable-kvm"
fi

# Run virtme-ng with test suite mounted
vng --run \
    --force-9p \
    --rwdir "$TEST_DIR" \
    --cwd "$TEST_DIR" \
    --memory "$MEMORY" \
    --cpus "$CPUS" \
    --append "sched_verbose loglevel=8 console=ttyS0" \
    $KVM_ARG \
    $VIRTME_OPTS \
    --exec "$TEST_CMD"

EXIT_CODE=$?

echo
if [ $EXIT_CODE -eq 0 ]; then
    print_color "$GREEN" "=========================================="
    print_color "$GREEN" "Tests completed successfully"
    print_color "$GREEN" "=========================================="
else
    print_color "$RED" "=========================================="
    print_color "$RED" "Tests failed with exit code $EXIT_CODE"
    print_color "$RED" "=========================================="
fi

exit $EXIT_CODE

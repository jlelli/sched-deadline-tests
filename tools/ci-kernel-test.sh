#!/bin/bash
# CI script to build a kernel and run SCHED_DEADLINE tests
#
# This script automates:
# 1. Fetching/updating a kernel source
# 2. Configuring it with SCHED_DEADLINE support
# 3. Building the kernel
# 4. Running tests in a VM using virtme-ng

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
Usage: $0 [OPTIONS]

CI script to build kernel and run SCHED_DEADLINE tests in VM.

OPTIONS:
    --kernel-repo URL      Git URL for kernel (default: torvalds/linux)
    --kernel-branch BRANCH Kernel branch/tag (default: master)
    --kernel-dir PATH      Existing kernel directory (skip clone)
    --config FILE          Use specific kernel config file
    --build-only           Only build kernel, don't run tests
    --test-only            Skip kernel build, just run tests
    -j, --jobs N           Parallel build jobs (default: nproc)
    --clean                Clean build before compiling
    -c, --category CAT     Run specific test category
    -h, --help             Show this help

EXAMPLES:
    # Full CI run: clone, build, test
    $0

    # Test specific kernel version
    $0 --kernel-branch v6.8

    # Use existing kernel directory
    $0 --kernel-dir /home/user/linux

    # Only build kernel
    $0 --build-only --kernel-dir /path/to/linux

    # Only run tests on already-built kernel
    $0 --test-only --kernel-dir /path/to/linux

    # Run specific test category
    $0 --kernel-dir /path/to/linux -c regression

KERNEL CONFIG:
    By default, the script enables:
    - CONFIG_PREEMPT=y
    - CONFIG_SCHED_DEBUG=y
    - CONFIG_DEBUG_KERNEL=y
    - CONFIG_FTRACE=y (for tracing tests)

    You can provide a custom config with --config FILE

EOF
    exit 0
}

# Defaults
KERNEL_REPO="https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git"
KERNEL_BRANCH="master"
KERNEL_DIR=""
CONFIG_FILE=""
BUILD_ONLY=0
TEST_ONLY=0
JOBS=$(nproc)
CLEAN=0
TEST_CATEGORY=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --kernel-repo)
            KERNEL_REPO="$2"
            shift 2
            ;;
        --kernel-branch)
            KERNEL_BRANCH="$2"
            shift 2
            ;;
        --kernel-dir)
            KERNEL_DIR="$2"
            shift 2
            ;;
        --config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        --build-only)
            BUILD_ONLY=1
            shift
            ;;
        --test-only)
            TEST_ONLY=1
            shift
            ;;
        -j|--jobs)
            JOBS="$2"
            shift 2
            ;;
        --clean)
            CLEAN=1
            shift
            ;;
        -c|--category)
            TEST_CATEGORY="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

print_color "$BLUE" "=========================================="
print_color "$BLUE" "SCHED_DEADLINE CI Kernel Tester"
print_color "$BLUE" "=========================================="
echo

# Set up kernel directory
if [ -z "$KERNEL_DIR" ]; then
    KERNEL_DIR="./kernel-test-build"

    if [ ! -d "$KERNEL_DIR" ]; then
        print_color "$YELLOW" "Cloning kernel from $KERNEL_REPO (branch: $KERNEL_BRANCH)..."
        git clone --depth 1 --branch "$KERNEL_BRANCH" "$KERNEL_REPO" "$KERNEL_DIR"
    else
        print_color "$YELLOW" "Updating kernel in $KERNEL_DIR..."
        cd "$KERNEL_DIR"
        git fetch origin "$KERNEL_BRANCH"
        git checkout "$KERNEL_BRANCH"
        git pull
        cd - > /dev/null
    fi
fi

KERNEL_DIR=$(realpath "$KERNEL_DIR")

if [ ! -d "$KERNEL_DIR" ]; then
    print_color "$RED" "ERROR: Kernel directory not found: $KERNEL_DIR"
    exit 1
fi

print_color "$GREEN" "Using kernel: $KERNEL_DIR"
echo

# Build kernel (unless --test-only)
if [ $TEST_ONLY -eq 0 ]; then
    cd "$KERNEL_DIR"

    print_color "$YELLOW" "Configuring kernel..."

    if [ -n "$CONFIG_FILE" ]; then
        # Use provided config
        cp "$CONFIG_FILE" .config
        make olddefconfig
    else
        # Generate minimal config with SCHED_DEADLINE support
        if [ $CLEAN -eq 1 ] || [ ! -f .config ]; then
            make defconfig
        fi

        # Enable required options
        scripts/config --enable CONFIG_PREEMPT
        scripts/config --enable CONFIG_SCHED_DEBUG
        scripts/config --enable CONFIG_DEBUG_KERNEL
        scripts/config --enable CONFIG_FTRACE
        scripts/config --enable CONFIG_FUNCTION_TRACER
        scripts/config --enable CONFIG_SCHED_TRACER
        scripts/config --enable CONFIG_DEBUG_FS

        # Disable modules to speed up build (everything built-in)
        scripts/config --disable CONFIG_MODULES

        make olddefconfig
    fi

    if [ $CLEAN -eq 1 ]; then
        print_color "$YELLOW" "Cleaning previous build..."
        make clean
    fi

    print_color "$YELLOW" "Building kernel with $JOBS jobs..."
    time make -j"$JOBS"

    print_color "$GREEN" "Kernel build complete!"
    echo

    cd - > /dev/null
fi

# Stop here if --build-only
if [ $BUILD_ONLY -eq 1 ]; then
    print_color "$GREEN" "Build complete (--build-only specified)"
    exit 0
fi

# Check kernel is built
if [ ! -f "$KERNEL_DIR/vmlinux" ] && [ ! -f "$KERNEL_DIR/arch/x86/boot/bzImage" ]; then
    print_color "$RED" "ERROR: Kernel not built in $KERNEL_DIR"
    print_color "$RED" "Run without --test-only to build it first"
    exit 1
fi

# Run tests
print_color "$YELLOW" "Running tests in VM..."
echo

TEST_SCRIPT="$(dirname "$0")/run-in-vm.sh"
TEST_ARGS=""
[ -n "$TEST_CATEGORY" ] && TEST_ARGS="--category $TEST_CATEGORY"

"$TEST_SCRIPT" $TEST_ARGS "$KERNEL_DIR"

EXIT_CODE=$?

echo
if [ $EXIT_CODE -eq 0 ]; then
    print_color "$GREEN" "=========================================="
    print_color "$GREEN" "CI run completed successfully!"
    print_color "$GREEN" "=========================================="
else
    print_color "$RED" "=========================================="
    print_color "$RED" "CI run failed"
    print_color "$RED" "=========================================="
fi

exit $EXIT_CODE

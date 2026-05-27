#!/bin/bash
# SCHED_DEADLINE Test Suite Runner
# Discovers and runs tests with filtering and reporting capabilities

set -u

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test result tracking
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0

# Configuration
VERBOSE=0
CATEGORY=""
SPECIFIC_TEST=""
LIST_ONLY=0
TRACE_ENABLE=0
STOP_ON_FAIL=0
OUTPUT_FORMAT="text"  # text, tap, or junit
TEST_TIMEOUT=300      # 5 minutes default timeout per test

# Test categories
CATEGORIES=(
    "basic"
    "priority-inheritance"
    "sched-domains"
    "hotplug"
    # "group-sched"  # Disabled: SCHED_DEADLINE doesn't have cgroup support yet
    "grub"
    "regression"
)

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Run SCHED_DEADLINE test suite.

OPTIONS:
    -c, --category CATEGORY    Run tests from specific category
    -t, --test TEST            Run specific test (path relative to tests/)
    -l, --list                 List available tests and exit
    -v, --verbose              Enable verbose output
    -T, --trace                Enable kernel tracing for tests
    -s, --stop-on-fail         Stop on first test failure
    -f, --format FORMAT        Output format: text, tap, junit (default: text)
    --timeout SECONDS          Timeout per test in seconds (default: 300)
    -h, --help                 Show this help message

CATEGORIES:
    basic                      Basic SCHED_DEADLINE behavior
    priority-inheritance       Priority inheritance tests
    sched-domains             Scheduling domains tests
    hotplug                   CPU hotplug tests
    group-sched               Control group scheduling
    grub                      GRUB reclaiming algorithm
    regression                Kernel bug regression tests

EXAMPLES:
    # Run all tests
    sudo $0

    # Run only basic tests
    sudo $0 --category basic

    # Run specific test
    sudo $0 --test basic/test_cpuhog_rsv.sh

    # List all available tests
    $0 --list

    # Run with tracing enabled
    sudo $0 --trace --category basic

    # Generate TAP output
    sudo $0 --format tap

EOF
    exit 0
}

print_color() {
    local color=$1
    shift
    echo -e "${color}$@${NC}"
}

log_info() {
    print_color "$BLUE" "[INFO] $@"
}

log_pass() {
    print_color "$GREEN" "[PASS] $@"
}

log_fail() {
    print_color "$RED" "[FAIL] $@"
}

log_skip() {
    print_color "$YELLOW" "[SKIP] $@"
}

check_requirements() {
    # Check if running as root
    if [ $EUID -ne 0 ]; then
        print_color "$RED" "ERROR: This test suite must be run as root"
        echo "SCHED_DEADLINE requires CAP_SYS_NICE capability"
        exit 1
    fi

    # Check if tests directory exists
    if [ ! -d "tests" ]; then
        print_color "$RED" "ERROR: tests/ directory not found"
        echo "Please run this script from the repository root"
        exit 1
    fi
}

discover_tests() {
    local category=$1
    local tests_dir="tests"

    if [ -n "$category" ]; then
        tests_dir="tests/$category"
        if [ ! -d "$tests_dir" ]; then
            print_color "$RED" "ERROR: Category '$category' not found"
            exit 1
        fi
    fi

    # Find all executable .sh test files
    find "$tests_dir" -name "test*.sh" -type f -executable | sort
}

list_tests() {
    echo "Available tests:"
    echo
    for category in "${CATEGORIES[@]}"; do
        local tests=$(discover_tests "$category" 2>/dev/null)
        if [ -n "$tests" ]; then
            echo "Category: $category"
            echo "$tests" | sed 's|tests/||' | sed 's/^/  - /'
            echo
        fi
    done
}

run_test() {
    local test_path=$1
    local test_name=$(basename "$test_path")
    local test_dir=$(dirname "$test_path")

    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    if [ $OUTPUT_FORMAT = "text" ]; then
        echo
        print_color "$BLUE" "=========================================="
        print_color "$BLUE" "Running: $test_path"
        print_color "$BLUE" "=========================================="
    fi

    # Change to test directory
    pushd "$test_dir" > /dev/null

    # Run the test
    local output_file="/tmp/test_output_$$.log"
    local start_time=$(date +%s)

    # Run with timeout to prevent hanging tests
    if [ $VERBOSE -eq 1 ]; then
        timeout $TEST_TIMEOUT "./$test_name" $TRACE_ENABLE 2>&1 | tee "$output_file"
        local exit_code=${PIPESTATUS[0]}
    else
        timeout $TEST_TIMEOUT "./$test_name" $TRACE_ENABLE > "$output_file" 2>&1
        local exit_code=$?
    fi

    # Check if test timed out
    if [ $exit_code -eq 124 ]; then
        echo "TEST TIMEOUT after ${TEST_TIMEOUT}s" >> "$output_file"
    fi

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    popd > /dev/null

    # Determine test result
    local result="UNKNOWN"
    if [ $exit_code -eq 124 ]; then
        result="TIMEOUT"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    elif grep -q "TEST_PASSED" "$output_file" || [ $exit_code -eq 0 ]; then
        result="PASS"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    elif grep -q "TEST_FAILED" "$output_file" || [ $exit_code -ne 0 ]; then
        result="FAIL"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi

    # Output result based on format
    case $OUTPUT_FORMAT in
        text)
            if [ "$result" = "PASS" ]; then
                log_pass "$test_path (${duration}s)"
            elif [ "$result" = "TIMEOUT" ]; then
                print_color "$YELLOW" "[TIMEOUT] $test_path (${TEST_TIMEOUT}s)"
                if [ $VERBOSE -eq 0 ]; then
                    echo "--- Last 20 lines of output ---"
                    tail -20 "$output_file"
                    echo "--- End output ---"
                fi
            else
                log_fail "$test_path (${duration}s)"
                if [ $VERBOSE -eq 0 ]; then
                    echo "--- Last 20 lines of output ---"
                    tail -20 "$output_file"
                    echo "--- End output ---"
                fi
            fi
            ;;
        tap)
            local test_num=$TOTAL_TESTS
            if [ "$result" = "PASS" ]; then
                echo "ok $test_num - $test_path"
            else
                echo "not ok $test_num - $test_path"
            fi
            ;;
        junit)
            # JUnit XML will be generated at the end
            ;;
    esac

    rm -f "$output_file"

    # Stop on failure if requested
    if [ "$result" = "FAIL" ] && [ $STOP_ON_FAIL -eq 1 ]; then
        print_color "$RED" "Stopping due to test failure (--stop-on-fail)"
        return 1
    fi

    return 0
}

print_summary() {
    echo
    print_color "$BLUE" "=========================================="
    print_color "$BLUE" "Test Summary"
    print_color "$BLUE" "=========================================="
    echo "Total tests:  $TOTAL_TESTS"
    print_color "$GREEN" "Passed:       $PASSED_TESTS"
    print_color "$RED" "Failed:       $FAILED_TESTS"
    print_color "$YELLOW" "Skipped:      $SKIPPED_TESTS"
    echo

    if [ $FAILED_TESTS -eq 0 ]; then
        print_color "$GREEN" "All tests passed!"
        return 0
    else
        print_color "$RED" "Some tests failed"
        return 1
    fi
}

# Parse command line arguments
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
        -l|--list)
            LIST_ONLY=1
            shift
            ;;
        -v|--verbose)
            VERBOSE=1
            shift
            ;;
        -T|--trace)
            TRACE_ENABLE=1
            shift
            ;;
        -s|--stop-on-fail)
            STOP_ON_FAIL=1
            shift
            ;;
        -f|--format)
            OUTPUT_FORMAT="$2"
            shift 2
            ;;
        --timeout)
            TEST_TIMEOUT="$2"
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

# Validate output format
if [[ ! "$OUTPUT_FORMAT" =~ ^(text|tap|junit)$ ]]; then
    print_color "$RED" "ERROR: Invalid output format: $OUTPUT_FORMAT"
    usage
fi

# Handle list-only mode
if [ $LIST_ONLY -eq 1 ]; then
    list_tests
    exit 0
fi

# Check requirements
check_requirements

# TAP header
if [ $OUTPUT_FORMAT = "tap" ]; then
    echo "TAP version 13"
fi

# Run tests
if [ -n "$SPECIFIC_TEST" ]; then
    # Run specific test
    test_path="tests/$SPECIFIC_TEST"
    if [ ! -f "$test_path" ]; then
        print_color "$RED" "ERROR: Test not found: $test_path"
        exit 1
    fi
    if [ $OUTPUT_FORMAT = "tap" ]; then
        echo "1..1"
    fi
    run_test "$test_path"
else
    # Discover and run tests
    if [ -n "$CATEGORY" ]; then
        tests=$(discover_tests "$CATEGORY")
    else
        tests=$(discover_tests "")
    fi

    # Count tests for TAP
    if [ $OUTPUT_FORMAT = "tap" ]; then
        test_count=$(echo "$tests" | wc -l)
        echo "1..$test_count"
    fi

    # Run each test
    for test in $tests; do
        run_test "$test" || {
            if [ $STOP_ON_FAIL -eq 1 ]; then
                break
            fi
        }
    done
fi

# Print summary and exit with appropriate code
if [ $OUTPUT_FORMAT = "text" ]; then
    print_summary
    exit_code=$?
else
    exit_code=0
    [ $FAILED_TESTS -eq 0 ] || exit_code=1
fi

exit $exit_code

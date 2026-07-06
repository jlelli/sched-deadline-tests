#!/bin/bash
# dl-test-worker.sh — Pipeline worker for SCHED_DEADLINE patch testing
#
# Orchestrates: b4 fetch → git worktree → apply → Sashiko check → build → test → report
#
# Typically launched by dl-test-series (via mutt), but can also be run standalone:
#   ./dl-test-worker.sh --message-id <message-id>
#   ./dl-test-worker.sh --message-id <message-id> --dry-run
#   ./dl-test-worker.sh --message-id <message-id> --branch tip/sched/core

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${BLUE}[$(date +%H:%M:%S)]${NC} $*"; }
ok()   { echo -e "${GREEN}[$(date +%H:%M:%S)] OK:${NC} $*"; }
warn() { echo -e "${YELLOW}[$(date +%H:%M:%S)] WARN:${NC} $*"; }
err()  { echo -e "${RED}[$(date +%H:%M:%S)] ERROR:${NC} $*"; }

die() { err "$@"; exit 1; }

# --- Configuration (from environment or defaults) ---
DL_TEST_WORK_DIR="${DL_TEST_WORK_DIR:-$HOME/Work/kernel/dl-test}"
DL_TEST_SUITE_DIR="${DL_TEST_SUITE_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
DL_TEST_KERNEL_REPO="${DL_TEST_KERNEL_REPO:-https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git}"
DL_TEST_KERNEL_DIR="${DL_TEST_KERNEL_DIR:-$HOME/Work/kernel/dl-test/linux}"
DL_TEST_KERNEL_BRANCH="${DL_TEST_KERNEL_BRANCH:-master}"
SASHIKO_URL="${SASHIKO_URL:-https://sashiko.dev}"
DL_TEST_EMAIL="${DL_TEST_EMAIL:-}"
DL_TEST_SEND_EMAIL="${DL_TEST_SEND_EMAIL:-yes}"
SASHIKO_MAX_RETRIES="${SASHIKO_MAX_RETRIES:-5}"
DL_TEST_VM_CPUS="${DL_TEST_VM_CPUS:-8}"
DL_TEST_VM_MEMORY="${DL_TEST_VM_MEMORY:-2G}"

# --- Parse arguments ---
MSG_ID=""
SUT=0
DRY_RUN=0
KERNEL_BRANCH=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --message-id)
            MSG_ID="$2"
            shift 2
            ;;
        --branch)
            KERNEL_BRANCH="$2"
            shift 2
            ;;
        --sut)
            SUT=1
            shift
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        -h|--help)
            echo "Usage: $0 --message-id <id> [--branch <branch>] [--sut] [--dry-run]"
            exit 0
            ;;
        *)
            die "Unknown option: $1"
            ;;
    esac
done

[ -z "$MSG_ID" ] && die "Missing --message-id"
[ -z "$KERNEL_BRANCH" ] && KERNEL_BRANCH="$DL_TEST_KERNEL_BRANCH"

# Short id for directory names
SHORT_ID=$(echo "$MSG_ID" | sed 's/@.*//' | tr -c '[:alnum:]-' '_' | head -c 40)
SERIES_DIR="$DL_TEST_WORK_DIR/series/$SHORT_ID"
RESULTS_FILE="$SERIES_DIR/results.txt"
RESULTS_JSON="$SERIES_DIR/results.json"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
WORKTREE_DIR=""
BASE_COMMIT=""
MBOX=""
SERIES_SUBJECT=""
TEST_OUTPUT=""
TEST_DMESG=""

mkdir -p "$SERIES_DIR"

# --- Redirect all output to a log file as well ---
LOGFILE="$SERIES_DIR/worker-${TIMESTAMP}.log"
exec > >(tee -a "$LOGFILE") 2>&1

log "=========================================="
log "dl-test-worker starting"
log "=========================================="
log "Message-Id: $MSG_ID"
log "Work dir:   $SERIES_DIR"
log "Kernel:     $DL_TEST_KERNEL_DIR (branch: $KERNEL_BRANCH)"
log "Sashiko:    $SASHIKO_URL"
log "Dry run:    $DRY_RUN"
echo

# Track overall result
OVERALL_RESULT="PASS"
STEP_RESULTS=()

record_step() {
    local step="$1" result="$2" detail="$3"
    STEP_RESULTS+=("$step|$result|$detail")
    if [ "$result" = "FAIL" ]; then
        OVERALL_RESULT="FAIL"
    fi
}

# ==========================================================================
# Step 1: Fetch series with b4
# ==========================================================================
log "Step 1: Fetching series with b4 am..."

B4_DIR="$SERIES_DIR/b4"
mkdir -p "$B4_DIR"

if ! command -v b4 &>/dev/null; then
    die "b4 not found. Install with: pip install b4"
fi

B4_OUTPUT=$(b4 am "$MSG_ID" -o "$B4_DIR" 2>&1) || {
    err "b4 am failed:"
    echo "$B4_OUTPUT"
    record_step "b4-fetch" "FAIL" "b4 am failed"
    OVERALL_RESULT="FAIL"
}

# Find the generated .mbx file
MBOX=$(find "$B4_DIR" -name "*.mbx" -type f 2>/dev/null | head -1)
if [ -z "$MBOX" ]; then
    # b4 might produce .mbox instead
    MBOX=$(find "$B4_DIR" -name "*.mbox" -type f 2>/dev/null | head -1)
fi

if [ -z "$MBOX" ]; then
    err "No mbox file produced by b4"
    echo "$B4_OUTPUT"
    record_step "b4-fetch" "FAIL" "no mbox produced"
    OVERALL_RESULT="FAIL"
else
    PATCH_COUNT=$(grep -c '^From ' "$MBOX" 2>/dev/null || echo 0)
    ok "Fetched series: $PATCH_COUNT patch(es)"
    record_step "b4-fetch" "PASS" "$PATCH_COUNT patches"

    # Extract subject from the mbox
    SERIES_SUBJECT=$(grep -m1 '^Subject:' "$MBOX" | sed 's/^Subject: //')
fi

# Try to extract base-commit from b4 output
BASE_COMMIT=$(echo "$B4_OUTPUT" | grep -i 'base-commit' | grep -oP '[0-9a-f]{12,40}' | head -1 || true)

echo

# ==========================================================================
# Step 2: Query Sashiko for review status
# ==========================================================================
log "Step 2: Querying Sashiko for review..."

SASHIKO_STATUS="unknown"
SASHIKO_ID=""
FINDINGS_CRITICAL=0
FINDINGS_HIGH=0
FINDINGS_MEDIUM=0
FINDINGS_LOW=0
SASHIKO_DETAIL=""

query_sashiko() {
    local detail

    # Get patchset id and status
    detail=$(curl -sf --max-time 15 "${SASHIKO_URL}/api/patchset?id=${MSG_ID}" 2>/dev/null) || return 1

    SASHIKO_ID=$(echo "$detail" | jq -r '.id // empty' 2>/dev/null)
    SASHIKO_STATUS=$(echo "$detail" | jq -r '.status // "unknown"' 2>/dev/null)

    [ -z "$SASHIKO_ID" ] && return 1

    # Get full patch detail (includes reviews with inline findings)
    # and count [Severity: X] markers in the inline review text
    local patch_detail
    patch_detail=$(curl -sf --max-time 30 "${SASHIKO_URL}/api/patch?id=${SASHIKO_ID}" 2>/dev/null) || return 0

    local all_reviews
    all_reviews=$(echo "$patch_detail" | jq -r '[.reviews[]?.inline_review // empty] | join("\n")' 2>/dev/null)

    if [ -n "$all_reviews" ]; then
        FINDINGS_CRITICAL=$(echo "$all_reviews" | grep -c '\[Severity: Critical\]' || true)
        FINDINGS_HIGH=$(echo "$all_reviews" | grep -c '\[Severity: High\]' || true)
        FINDINGS_MEDIUM=$(echo "$all_reviews" | grep -c '\[Severity: Medium\]' || true)
        FINDINGS_LOW=$(echo "$all_reviews" | grep -c '\[Severity: Low\]' || true)
    fi

    return 0
}

fetch_sashiko_details() {
    [ -z "$SASHIKO_ID" ] && return
    local total=$((FINDINGS_CRITICAL + FINDINGS_HIGH))
    [ "$total" -eq 0 ] && return

    # Extract Critical/High findings from the inline reviews
    local patch_detail
    patch_detail=$(curl -sf --max-time 30 "${SASHIKO_URL}/api/patch?id=${SASHIKO_ID}" 2>/dev/null) || return

    SASHIKO_DETAIL=$(echo "$patch_detail" | jq -r '
        [.reviews[]?.inline_review // empty] | join("\n")
    ' 2>/dev/null | grep -A5 '\[Severity: \(Critical\|High\)\]')
}

SASHIKO_FOUND=0
for attempt in $(seq 1 "$SASHIKO_MAX_RETRIES"); do
    if query_sashiko; then
        case "$SASHIKO_STATUS" in
            Reviewed|Failed|Cancelled|Skipped|"Failed To Apply")
                SASHIKO_FOUND=1
                break
                ;;
            Pending|"In Review"|Incomplete)
                if [ "$attempt" -lt "$SASHIKO_MAX_RETRIES" ]; then
                    warn "Sashiko status: $SASHIKO_STATUS (attempt $attempt/$SASHIKO_MAX_RETRIES, retrying in 120s)"
                    sleep 120
                else
                    warn "Sashiko still $SASHIKO_STATUS after $SASHIKO_MAX_RETRIES attempts"
                    SASHIKO_FOUND=1
                fi
                ;;
            *)
                SASHIKO_FOUND=1
                break
                ;;
        esac
    else
        if [ "$attempt" -lt "$SASHIKO_MAX_RETRIES" ]; then
            warn "Sashiko query failed (attempt $attempt/$SASHIKO_MAX_RETRIES, retrying in 120s)"
            sleep 120
        else
            warn "Sashiko not reachable after $SASHIKO_MAX_RETRIES attempts"
        fi
    fi
done

if [ "$SASHIKO_FOUND" -eq 1 ]; then
    ok "Sashiko: $SASHIKO_STATUS (C:$FINDINGS_CRITICAL H:$FINDINGS_HIGH M:$FINDINGS_MEDIUM L:$FINDINGS_LOW)"
    fetch_sashiko_details
    record_step "sashiko" "PASS" "$SASHIKO_STATUS C:$FINDINGS_CRITICAL H:$FINDINGS_HIGH M:$FINDINGS_MEDIUM L:$FINDINGS_LOW"
else
    warn "Series not found on Sashiko"
    record_step "sashiko" "SKIP" "not found"
fi

# Save Sashiko details if we got critical/high findings
if [ -n "$SASHIKO_DETAIL" ]; then
    echo "$SASHIKO_DETAIL" > "$SERIES_DIR/sashiko-review.txt"
    log "Sashiko review details saved to $SERIES_DIR/sashiko-review.txt"
fi

echo

# Stop here in dry-run mode
if [ "$DRY_RUN" -eq 1 ]; then
    log "Dry run complete — skipping build and test steps"
    record_step "build" "SKIP" "dry-run"
    record_step "test" "SKIP" "dry-run"

    # Jump to results
    # (fall through to results section below)
else

# ==========================================================================
# Step 3: Prepare kernel worktree and apply patches
# ==========================================================================
log "Step 3: Preparing kernel and applying patches..."

WORKTREE_DIR="$SERIES_DIR/kernel"

if [ ! -d "$DL_TEST_KERNEL_DIR" ]; then
    log "Cloning kernel repo (this may take a while on first run)..."
    git clone --bare "$DL_TEST_KERNEL_REPO" "$DL_TEST_KERNEL_DIR"
fi

# Fetch latest
log "Fetching latest from origin..."
git -C "$DL_TEST_KERNEL_DIR" fetch origin "$KERNEL_BRANCH" 2>&1 || {
    warn "Could not fetch branch '$KERNEL_BRANCH', trying without branch spec"
    git -C "$DL_TEST_KERNEL_DIR" fetch origin 2>&1
}

# Determine base ref
if [ -n "$BASE_COMMIT" ]; then
    BASE_REF="$BASE_COMMIT"
    log "Using base-commit from series: $BASE_REF"
else
    BASE_REF="origin/$KERNEL_BRANCH"
    log "Using branch head: $BASE_REF"
fi

# Create worktree
if [ -d "$WORKTREE_DIR" ]; then
    log "Removing stale worktree..."
    git -C "$DL_TEST_KERNEL_DIR" worktree remove --force "$WORKTREE_DIR" 2>/dev/null || rm -rf "$WORKTREE_DIR"
fi

WORKTREE_BRANCH="dl-test/${SHORT_ID}"
git -C "$DL_TEST_KERNEL_DIR" worktree add -b "$WORKTREE_BRANCH" "$WORKTREE_DIR" "$BASE_REF" 2>&1 || {
    # Branch might already exist from a previous run
    git -C "$DL_TEST_KERNEL_DIR" branch -D "$WORKTREE_BRANCH" 2>/dev/null || true
    git -C "$DL_TEST_KERNEL_DIR" worktree add -b "$WORKTREE_BRANCH" "$WORKTREE_DIR" "$BASE_REF" 2>&1
}
ok "Worktree created at $WORKTREE_DIR"

# Apply patches
if [ -n "$MBOX" ]; then
    log "Applying patches..."
    GIT_AM_OUTPUT=$(git -C "$WORKTREE_DIR" am "$MBOX" 2>&1) || {
        err "git am failed:"
        echo "$GIT_AM_OUTPUT"
        git -C "$WORKTREE_DIR" am --abort 2>/dev/null || true
        record_step "apply" "FAIL" "git am failed"
        OVERALL_RESULT="FAIL"

        # Skip build and test
        record_step "build" "SKIP" "apply failed"
        record_step "test" "SKIP" "apply failed"
    }

    if ! echo "${STEP_RESULTS[*]}" | grep -q "apply|FAIL"; then
        APPLIED_COUNT=$(git -C "$WORKTREE_DIR" log --oneline "$BASE_REF.." | wc -l)
        ok "Applied $APPLIED_COUNT patch(es)"
        record_step "apply" "PASS" "$APPLIED_COUNT patches applied"
    fi
else
    record_step "apply" "SKIP" "no mbox to apply"
fi

echo

# ==========================================================================
# Step 4: Build kernel (using kb build)
# ==========================================================================
if ! echo "${STEP_RESULTS[*]}" | grep -q "build|SKIP"; then
    log "Step 4: Building kernel..."

    KB="${DL_TEST_KB:-${HOME}/Work/kernel/linux-kernel-utils/kbuild.sh}"

    if [ ! -x "$KB" ]; then
        err "kbuild.sh not found at $KB (set DL_TEST_KB to override)"
        record_step "build" "FAIL" "kbuild.sh not found"
        OVERALL_RESULT="FAIL"
        record_step "test" "SKIP" "build failed"
    else
        cd "$WORKTREE_DIR"

        # Configure: defconfig + virtme-ng support + SCHED_DEADLINE debug options
        SPINNER=0 KERNEL_DIR="$WORKTREE_DIR" "$KB" defconfig 2>&1 | tail -3
        SPINNER=0 KERNEL_DIR="$WORKTREE_DIR" "$KB" vng-config 2>&1 | tail -3

        BUILD_CFG="$WORKTREE_DIR/build/.config"
        scripts/config --file "$BUILD_CFG" --enable CONFIG_PREEMPT
        scripts/config --file "$BUILD_CFG" --enable CONFIG_SCHED_DEBUG
        scripts/config --file "$BUILD_CFG" --enable CONFIG_DEBUG_KERNEL
        scripts/config --file "$BUILD_CFG" --enable CONFIG_FTRACE
        scripts/config --file "$BUILD_CFG" --enable CONFIG_FUNCTION_TRACER
        scripts/config --file "$BUILD_CFG" --enable CONFIG_SCHED_TRACER
        scripts/config --file "$BUILD_CFG" --enable CONFIG_DEBUG_FS

        BUILD_START=$(date +%s)
        if SPINNER=0 KERNEL_DIR="$WORKTREE_DIR" "$KB" build 2>&1 | tail -5; then
            BUILD_END=$(date +%s)
            BUILD_DURATION=$((BUILD_END - BUILD_START))
            ok "Kernel built in ${BUILD_DURATION}s"
            record_step "build" "PASS" "${BUILD_DURATION}s"
        else
            BUILD_END=$(date +%s)
            BUILD_DURATION=$((BUILD_END - BUILD_START))
            err "Kernel build failed after ${BUILD_DURATION}s"
            record_step "build" "FAIL" "build failed after ${BUILD_DURATION}s"
            OVERALL_RESULT="FAIL"
            record_step "test" "SKIP" "build failed"
        fi

        cd - > /dev/null
    fi

    echo
fi

# ==========================================================================
# Step 5: Run tests in VM
# ==========================================================================
if ! echo "${STEP_RESULTS[*]}" | grep -q "test|SKIP"; then
    log "Step 5: Running tests in VM..."

    TEST_OUTPUT="$SERIES_DIR/test-output-${TIMESTAMP}.log"
    TEST_DMESG="$SERIES_DIR/test-dmesg-${TIMESTAMP}.log"

    VM_SCRIPT="${DL_TEST_SUITE_DIR}/tools/run-in-vm.sh"

    # kb build puts output under $WORKTREE_DIR/build/
    KERNEL_BUILD_DIR="$WORKTREE_DIR/build"

    if [ ! -x "$VM_SCRIPT" ]; then
        err "run-in-vm.sh not found at $VM_SCRIPT"
        record_step "test" "FAIL" "run-in-vm.sh not found"
        OVERALL_RESULT="FAIL"
    else
        if "$VM_SCRIPT" \
            --smp "$DL_TEST_VM_CPUS" \
            --memory "$DL_TEST_VM_MEMORY" \
            "$KERNEL_BUILD_DIR" 2>&1 | tee "$TEST_OUTPUT"; then
            # Parse test results from output
            TESTS_TOTAL=$(grep -c '^\[PASS\]\|^\[FAIL\]\|^\[SKIP\]' "$TEST_OUTPUT" 2>/dev/null || echo 0)
            TESTS_PASSED=$(grep -c '^\[PASS\]' "$TEST_OUTPUT" 2>/dev/null || echo 0)
            TESTS_FAILED=$(grep -c '^\[FAIL\]' "$TEST_OUTPUT" 2>/dev/null || echo 0)
            TESTS_SKIPPED=$(grep -c '^\[SKIP\]' "$TEST_OUTPUT" 2>/dev/null || echo 0)
            ok "Tests: $TESTS_PASSED/$TESTS_TOTAL passed, $TESTS_FAILED failed, $TESTS_SKIPPED skipped"
            if [ "$TESTS_FAILED" -gt 0 ]; then
                record_step "test" "FAIL" "$TESTS_PASSED/$TESTS_TOTAL passed, $TESTS_FAILED failed"
            else
                record_step "test" "PASS" "$TESTS_PASSED/$TESTS_TOTAL passed, $TESTS_SKIPPED skipped"
            fi
        else
            err "Test execution failed"
            record_step "test" "FAIL" "VM test execution failed"
            OVERALL_RESULT="FAIL"
        fi
    fi

    echo
fi

# ==========================================================================
# Step 6: Optional SUT testing (placeholder)
# ==========================================================================
if [ "$SUT" -eq 1 ]; then
    log "Step 6: SUT testing requested but not yet implemented"
    warn "Physical SUT testing requires site-specific configuration"
    record_step "sut" "SKIP" "not implemented"
    echo
fi

fi  # end of non-dry-run block

# ==========================================================================
# Results
# ==========================================================================
log "=========================================="
log "Composing results..."
log "=========================================="

SERIES_SUBJECT="${SERIES_SUBJECT:-<unknown subject>}"
HEAD_SHA=""
[ -d "$WORKTREE_DIR" ] && HEAD_SHA=$(git -C "$WORKTREE_DIR" rev-parse --short HEAD 2>/dev/null || true)

# Write human-readable results
cat > "$RESULTS_FILE" <<RESULTS_EOF
Series:     $SERIES_SUBJECT
Message-Id: $MSG_ID
Lore:       https://lore.kernel.org/all/$MSG_ID
Date:       $(date)
Result:     $OVERALL_RESULT

--- Sashiko Review ---
Status:   $SASHIKO_STATUS
Critical: $FINDINGS_CRITICAL
High:     $FINDINGS_HIGH
Medium:   $FINDINGS_MEDIUM
Low:      $FINDINGS_LOW
$([ -n "$SASHIKO_ID" ] && echo "URL:      ${SASHIKO_URL}/#/patch/${SASHIKO_ID}" || echo "URL:      not available")

--- Steps ---
$(for s in "${STEP_RESULTS[@]}"; do
    step=$(echo "$s" | cut -d'|' -f1)
    result=$(echo "$s" | cut -d'|' -f2)
    detail=$(echo "$s" | cut -d'|' -f3)
    printf "%-12s %-6s %s\n" "$step" "$result" "$detail"
done)

--- Paths ---
Work dir:   $SERIES_DIR
Log:        $LOGFILE
$([ -d "$WORKTREE_DIR" ] && echo "Kernel:     $WORKTREE_DIR (HEAD: ${HEAD_SHA:-unknown})")
$([ -f "${TEST_OUTPUT:-}" ] && echo "Test log:   $TEST_OUTPUT")
$([ -f "${TEST_DMESG:-}" ] && echo "dmesg:      $TEST_DMESG")
RESULTS_EOF

# Write JSON results
cat > "$RESULTS_JSON" <<JSON_EOF
{
  "message_id": "$MSG_ID",
  "subject": $(echo "$SERIES_SUBJECT" | jq -Rs .),
  "result": "$OVERALL_RESULT",
  "timestamp": "$(date -Iseconds)",
  "sashiko": {
    "status": "$SASHIKO_STATUS",
    "id": ${SASHIKO_ID:-null},
    "findings_critical": $FINDINGS_CRITICAL,
    "findings_high": $FINDINGS_HIGH,
    "findings_medium": $FINDINGS_MEDIUM,
    "findings_low": $FINDINGS_LOW
  },
  "steps": [
$(for i in "${!STEP_RESULTS[@]}"; do
    s="${STEP_RESULTS[$i]}"
    step=$(echo "$s" | cut -d'|' -f1)
    result=$(echo "$s" | cut -d'|' -f2)
    detail=$(echo "$s" | cut -d'|' -f3)
    comma=","
    [ "$i" -eq $((${#STEP_RESULTS[@]} - 1)) ] && comma=""
    echo "    {\"step\": \"$step\", \"result\": \"$result\", \"detail\": $(echo "$detail" | jq -Rs .)}$comma"
done)
  ],
  "kernel_branch": "$KERNEL_BRANCH",
  "base_commit": "${BASE_COMMIT:-}",
  "head_sha": "${HEAD_SHA:-}",
  "work_dir": "$SERIES_DIR"
}
JSON_EOF

ok "Results written to $RESULTS_FILE"
cat "$RESULTS_FILE"

# ==========================================================================
# Send email notification
# ==========================================================================
if [ "$DL_TEST_SEND_EMAIL" = "yes" ] && [ -n "$DL_TEST_EMAIL" ]; then
    log "Sending result email to $DL_TEST_EMAIL..."

    MAIL_SUBJECT="[DL-TEST] $OVERALL_RESULT: $SERIES_SUBJECT"

    if command -v mail &>/dev/null; then
        mail -s "$MAIL_SUBJECT" "$DL_TEST_EMAIL" < "$RESULTS_FILE" && \
            ok "Email sent" || \
            warn "Failed to send email"
    elif command -v sendmail &>/dev/null; then
        {
            echo "To: $DL_TEST_EMAIL"
            echo "Subject: $MAIL_SUBJECT"
            echo "Content-Type: text/plain; charset=utf-8"
            echo
            cat "$RESULTS_FILE"
        } | sendmail "$DL_TEST_EMAIL" && \
            ok "Email sent" || \
            warn "Failed to send email"
    else
        warn "No mail command found (install mailutils or postfix)"
    fi
fi

echo
if [ "$OVERALL_RESULT" = "PASS" ]; then
    ok "Pipeline complete: PASS"
else
    err "Pipeline complete: FAIL"
fi

exit 0

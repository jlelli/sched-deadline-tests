# Mutt Integration for SCHED_DEADLINE Patch Testing

Trigger the test pipeline directly from mutt when reading a patch series.
Press `,t` on any email in a series to fetch it with `b4`, check Sashiko for
reviews, build a kernel with the patches applied, and run the test suite in
a virtme-ng VM. Results are emailed back to you and saved to disk.

## Setup

### 1. Configuration

Copy the example config and edit it:

```bash
mkdir -p ~/.config/dl-test
cp tools/dl-test.conf.example ~/.config/dl-test/config
$EDITOR ~/.config/dl-test/config
```

Key settings:
- `DL_TEST_REMOTE` — `localhost` for local testing, or `user@host` for a remote server
- `DL_TEST_KERNEL_DIR` — path to a bare clone of the kernel repo (created on first run)
- `DL_TEST_EMAIL` — your email address for result notifications

### 2. Install the dispatcher

Symlink or copy `dl-test-series` to your PATH:

```bash
ln -s $(pwd)/tools/dl-test-series ~/.local/bin/dl-test-series
```

### 3. Add mutt macros

Add to your `~/.muttrc` or `~/.config/mutt/muttrc`:

```muttrc
# Test SCHED_DEADLINE series in VM
macro index ,t "<pipe-message>dl-test-series\n" "Test DL series (VM)"
macro pager ,t "<pipe-message>dl-test-series\n" "Test DL series (VM)"

# Test SCHED_DEADLINE series in VM + physical SUT
macro index ,T "<pipe-message>dl-test-series --sut\n" "Test DL series (VM+SUT)"
macro pager ,T "<pipe-message>dl-test-series --sut\n" "Test DL series (VM+SUT)"
```

### 4. Dependencies

On the machine running the tests (local or remote):

- `b4` — fetch patch series from lore.kernel.org (`pip install b4`)
- `jq` — parse Sashiko API JSON responses
- `curl` — query Sashiko REST API
- `git` — manage kernel worktrees
- `virtme-ng` (`vng`) — run tests in VMs (`pip install virtme-ng`)
- `qemu-system-x86` with KVM support
- `tmux` — detach long-running test jobs
- `mail` or `sendmail` (optional) — send result emails

## Usage

### From mutt

1. Open an email from a LKML patch series you're Cc-ed on
2. Press `,t` to dispatch a test run
3. You'll see a confirmation line with the tmux session name
4. Continue reading mail — results arrive by email when done

### Standalone

Run the worker directly for testing or scripting:

```bash
# Dry run (fetch + Sashiko only, no build/test)
./tools/dl-test-worker.sh --message-id "20260706114823.752313-1-dev@lankhorst.se" --dry-run

# Full run against a specific branch
./tools/dl-test-worker.sh --message-id "20260706114823.752313-1-dev@lankhorst.se" --branch sched/core

# Check on a running job
tmux attach -t dl-test-<short-id>
```

### Checking results

Results are saved under `$DL_TEST_WORK_DIR/series/<short-id>/`:
- `results.txt` — human-readable summary
- `results.json` — machine-readable results
- `sashiko-review.txt` — Sashiko review details (if critical/high findings exist)
- `worker-*.log` — full pipeline output
- `test-output-*.log` — test suite output
- `test-dmesg-*.log` — kernel dmesg from the VM run

## Workflow

```
  mutt (,t)
    │
    ▼
  dl-test-series          (extracts Message-Id, dispatches via tmux)
    │
    ▼
  dl-test-worker.sh       (runs in tmux session)
    ├─ b4 am              (fetch series from lore)
    ├─ Sashiko API query   (check review status + findings)
    ├─ git worktree + am   (apply patches to kernel)
    ├─ make                (build kernel)
    ├─ run-in-vm.sh        (test in virtme-ng VM)
    └─ email results       (send summary to yourself)
```

## Remote server setup

When `DL_TEST_REMOTE` is set to a remote host:
- The dispatcher SSHs to the remote and starts a tmux session there
- All config variables are forwarded via the environment
- Both `dl-test-worker.sh` and the test suite must be available on the remote
- Ensure passwordless SSH is configured (ssh-agent or key-based auth)

To watch a remote job:
```bash
ssh -t user@testbox tmux attach -t dl-test-<short-id>
```

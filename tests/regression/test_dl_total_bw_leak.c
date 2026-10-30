/*
 * Test for SCHED_DEADLINE total_bw leak on class change while not queued
 *
 * Reproduces the bug where a SCHED_DEADLINE task switched to another policy
 * while sleeping or stopped leaks its bandwidth in the root domain's
 * total_bw. Repeating this fills total_bw up to the admission cap, after
 * which sched_setattr(SCHED_DEADLINE) and CPU offline fail with -EBUSY.
 *
 * Three scenarios are tested:
 *   1. Sleeping DL task switched to SCHED_OTHER  (leaks without fix)
 *   2. Stopped DL task switched to SCHED_OTHER   (leaks without fix)
 *   3. Running DL task switched to SCHED_OTHER   (control, no leak)
 *
 * Based on reproducer by Tejun Heo <tj@kernel.org>.
 *
 * Build: gcc -Wall -O2 -o test_dl_total_bw_leak test_dl_total_bw_leak.c
 * Run:   sudo ./test_dl_total_bw_leak
 */

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <signal.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <stdint.h>

#include <sched.h>

#include "../../lib/sched_deadline.h"

/* DL parameters: 2ms runtime / 10ms period = 0.2 CPU */
#define DL_RUNTIME_NS	2000000ULL
#define DL_PERIOD_NS	10000000ULL

/* Expected dl_bw value for the above parameters (2^20 * runtime / period) */
#define EXPECTED_DL_BW	209715ULL

/* Acceptable jitter for total_bw comparison */
#define BW_TOLERANCE	100

#define DEBUGFS_SCHED_DEBUG	"/sys/kernel/debug/sched/debug"

static int read_total_bw(uint64_t *total_bw)
{
	FILE *fp;
	char buf[4096];
	char *pos;

	fp = fopen(DEBUGFS_SCHED_DEBUG, "r");
	if (!fp) {
		fprintf(stderr, "Cannot open %s: %s\n",
			DEBUGFS_SCHED_DEBUG, strerror(errno));
		fprintf(stderr, "Is debugfs mounted? Try: mount -t debugfs none /sys/kernel/debug\n");
		return -1;
	}

	while (fgets(buf, sizeof(buf), fp)) {
		pos = strstr(buf, "dl_bw->total_bw");
		if (!pos)
			continue;

		pos = strchr(pos, ':');
		if (!pos)
			continue;

		if (sscanf(pos + 1, " %lu", (unsigned long *)total_bw) == 1) {
			fclose(fp);
			return 0;
		}
	}

	fclose(fp);
	fprintf(stderr, "Could not find dl_bw->total_bw in %s\n",
		DEBUGFS_SCHED_DEBUG);
	return -1;
}

static int set_dl(pid_t pid, uint64_t runtime, uint64_t period)
{
	struct sched_attr attr = {};

	attr.size = sizeof(attr);
	attr.sched_policy = SCHED_DEADLINE;
	attr.sched_runtime = runtime;
	attr.sched_deadline = period;
	attr.sched_period = period;

	if (sched_setattr(pid, &attr, 0) < 0) {
		fprintf(stderr, "sched_setattr(DL, pid=%d): %s\n",
			pid, strerror(errno));
		return -1;
	}
	return 0;
}

static int set_other(pid_t pid)
{
	struct sched_attr attr = {};

	attr.size = sizeof(attr);
	attr.sched_policy = SCHED_OTHER;

	if (sched_setattr(pid, &attr, 0) < 0) {
		fprintf(stderr, "sched_setattr(OTHER, pid=%d): %s\n",
			pid, strerror(errno));
		return -1;
	}
	return 0;
}

enum trial_mode {
	MODE_SLEEP,	/* child sleeps (not queued) */
	MODE_STOP,	/* child spins, then SIGSTOP'd (not queued) */
	MODE_SPIN,	/* child spins (queued - control case) */
};

/*
 * Run a single trial:
 *   - fork a child in the given mode
 *   - set it to SCHED_DEADLINE
 *   - optionally stop it
 *   - switch it back to SCHED_OTHER
 *   - kill it and measure total_bw delta
 *
 * Returns the leaked bandwidth (should be ~0 if no leak, ~EXPECTED_DL_BW if leak).
 */
static int run_trial(const char *name, enum trial_mode mode, int64_t *leaked)
{
	uint64_t bw_before, bw_after;
	pid_t pid;
	int ret = 0;

	pid = fork();
	if (pid < 0) {
		perror("fork");
		return -1;
	}

	if (pid == 0) {
		/* child */
		if (mode == MODE_SLEEP) {
			while (1)
				sleep(3600);
		} else {
			/* MODE_STOP and MODE_SPIN both spin */
			while (1)
				;
		}
		_exit(0);
	}

	/* parent: let child settle */
	usleep(50000);

	if (read_total_bw(&bw_before) < 0) {
		ret = -1;
		goto kill_child;
	}

	if (set_dl(pid, DL_RUNTIME_NS, DL_PERIOD_NS) < 0) {
		ret = -1;
		goto kill_child;
	}

	if (mode == MODE_STOP) {
		kill(pid, SIGSTOP);
		usleep(20000);
	}

	if (set_other(pid) < 0) {
		ret = -1;
		goto kill_child;
	}

kill_child:
	kill(pid, SIGKILL);
	waitpid(pid, NULL, 0);
	usleep(50000);

	if (ret < 0)
		return ret;

	if (read_total_bw(&bw_after) < 0)
		return -1;

	*leaked = (int64_t)(bw_after - bw_before);

	printf("  %-24s leaked total_bw %7ld (0.2 CPU = %llu)\n",
	       name, (long)*leaked, (unsigned long long)EXPECTED_DL_BW);

	return 0;
}

int main(void)
{
	int64_t leak_sleep, leak_stop, leak_spin;
	int failures = 0;

	if (geteuid() != 0) {
		fprintf(stderr, "This test must run as root\n");
		return 1;
	}

	printf("Testing SCHED_DEADLINE total_bw leak on class change while not queued\n\n");

	if (run_trial("sleeping dl>other", MODE_SLEEP, &leak_sleep) < 0)
		return 1;
	if (run_trial("stopped dl>other", MODE_STOP, &leak_stop) < 0)
		return 1;
	if (run_trial("running dl>other", MODE_SPIN, &leak_spin) < 0)
		return 1;

	printf("\nResults:\n");

	if (leak_sleep > BW_TOLERANCE) {
		printf("  FAIL: sleeping task leaked %ld total_bw\n",
		       (long)leak_sleep);
		failures++;
	} else {
		printf("  PASS: sleeping task did not leak total_bw\n");
	}

	if (leak_stop > BW_TOLERANCE) {
		printf("  FAIL: stopped task leaked %ld total_bw\n",
		       (long)leak_stop);
		failures++;
	} else {
		printf("  PASS: stopped task did not leak total_bw\n");
	}

	if (leak_spin > BW_TOLERANCE) {
		printf("  FAIL: running task leaked %ld total_bw (control case!)\n",
		       (long)leak_spin);
		failures++;
	} else {
		printf("  PASS: running task did not leak total_bw (control)\n");
	}

	printf("\n");

	if (failures) {
		printf("FAIL: %d test(s) failed\n", failures);
		return 1;
	}

	printf("PASS: all tests passed\n");
	return 0;
}

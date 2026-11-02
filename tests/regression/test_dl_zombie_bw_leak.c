/*
 * Test for total_bw leak when setting SCHED_DEADLINE on a zombie
 *
 * sched_setattr(SCHED_DEADLINE) on a task that has exited but has not
 * been reaped (zombie) succeeds and charges the root domain's total_bw.
 * The task never runs again, so nothing releases the bandwidth.
 * Repeating this fills total_bw to the admission cap.
 *
 * Without the fix, sched_setattr succeeds on the zombie (rc == 0).
 * With the fix, it should fail with -ESRCH.
 *
 * Based on reproducer by Weiheng Qiu <weihengqiuu@gmail.com>.
 *
 * Build: gcc -Wall -O2 -o test_dl_zombie_bw_leak test_dl_zombie_bw_leak.c
 * Run:   sudo ./test_dl_zombie_bw_leak
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

#define DL_RUNTIME_NS	5000000ULL
#define DL_PERIOD_NS	20000000ULL
#define EXPECTED_DL_BW	262144LL

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

static pid_t spawn_zombie(void)
{
	siginfo_t si;
	pid_t pid = fork();

	if (pid < 0) {
		perror("fork");
		return -1;
	}

	if (pid == 0)
		_exit(0);

	/*
	 * Wait for exit but leave it unreaped (WNOWAIT).
	 * Give it time to get off the runqueue after exit_notify().
	 */
	waitid(P_PID, pid, &si, WEXITED | WNOWAIT);
	usleep(20000);

	return pid;
}

static char task_state(pid_t pid)
{
	char path[64], buf[512], *p;
	FILE *fp;

	snprintf(path, sizeof(path), "/proc/%d/stat", pid);
	fp = fopen(path, "r");
	if (!fp)
		return '?';
	if (!fgets(buf, sizeof(buf), fp))
		buf[0] = 0;
	fclose(fp);
	p = strrchr(buf, ')');
	return p && p[1] && p[2] ? p[2] : '?';
}

int main(void)
{
	struct sched_attr attr = {};
	uint64_t bw_before, bw_after;
	int64_t delta;
	pid_t pid;
	int ret, failures = 0;

	if (geteuid() != 0) {
		fprintf(stderr, "This test must run as root\n");
		return 1;
	}

	printf("Testing SCHED_DEADLINE rejection on zombie tasks\n\n");

	if (read_total_bw(&bw_before) < 0)
		return 1;

	/*
	 * Test 1: sched_setattr(SCHED_DEADLINE) on a zombie should fail.
	 */
	pid = spawn_zombie();
	if (pid < 0)
		return 1;

	printf("  Zombie task %d (state: %c)\n", pid, task_state(pid));

	attr.size = sizeof(attr);
	attr.sched_policy = SCHED_DEADLINE;
	attr.sched_runtime = DL_RUNTIME_NS;
	attr.sched_deadline = DL_PERIOD_NS;
	attr.sched_period = DL_PERIOD_NS;

	ret = sched_setattr(pid, &attr, 0);
	if (ret < 0 && errno == ESRCH) {
		printf("  PASS: SCHED_DEADLINE on zombie rejected with -ESRCH\n");
	} else if (ret == 0) {
		printf("  FAIL: SCHED_DEADLINE on zombie succeeded (should fail)\n");
		failures++;
	} else {
		printf("  FAIL: unexpected errno %d (%s)\n", errno, strerror(errno));
		failures++;
	}

	/* Reap the zombie */
	waitpid(pid, NULL, 0);
	usleep(50000);

	/*
	 * Test 2: Repeated attempts should not fill total_bw.
	 */
	for (int i = 0; i < 10; i++) {
		pid = spawn_zombie();
		if (pid < 0)
			return 1;

		attr.size = sizeof(attr);
		attr.sched_policy = SCHED_DEADLINE;
		attr.sched_runtime = DL_RUNTIME_NS;
		attr.sched_deadline = DL_PERIOD_NS;
		attr.sched_period = DL_PERIOD_NS;

		sched_setattr(pid, &attr, 0);
		waitpid(pid, NULL, 0);
	}

	usleep(50000);

	if (read_total_bw(&bw_after) < 0)
		return 1;

	delta = (int64_t)(bw_after - bw_before);
	printf("  After 10 zombie DL attempts: total_bw delta = %+ld\n",
	       (long)delta);

	if (delta > BW_TOLERANCE) {
		printf("  FAIL: total_bw leaked %ld\n", (long)delta);
		failures++;
	} else {
		printf("  PASS: total_bw did not leak\n");
	}

	printf("\n");
	if (failures) {
		printf("FAIL: %d test(s) failed\n", failures);
		return 1;
	}

	printf("PASS: all tests passed\n");
	return 0;
}

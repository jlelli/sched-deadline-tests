/*
 * Test for total_bw underflow via SCHED_FLAG_KEEP_PARAMS
 *
 * sched_setattr(SCHED_OTHER, SCHED_FLAG_KEEP_PARAMS) on a sleeping
 * SCHED_DEADLINE task triggers switched_from_dl() even though
 * KEEP_PARAMS prevents the actual class change. Each call spuriously
 * releases the task's bandwidth, driving total_bw negative.
 *
 * Without the fix, the kernel should return -EINVAL for a
 * cross-class sched_setattr with KEEP_PARAMS.
 *
 * Reported by Tejun Heo.
 *
 * Build: gcc -Wall -O2 -o test_dl_keep_params_underflow test_dl_keep_params_underflow.c
 * Run:   sudo ./test_dl_keep_params_underflow
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

#ifndef SCHED_FLAG_KEEP_PARAMS
#define SCHED_FLAG_KEEP_PARAMS	0x10
#endif

#define DL_RUNTIME_NS	2000000ULL
#define DL_PERIOD_NS	10000000ULL
#define EXPECTED_DL_BW	209715LL

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

int main(void)
{
	struct sched_attr attr = {};
	uint64_t bw_before_dl, bw_after_dl, bw_after_keep;
	int64_t delta;
	pid_t pid;
	int ret, failures = 0;

	if (geteuid() != 0) {
		fprintf(stderr, "This test must run as root\n");
		return 1;
	}

	printf("Testing SCHED_FLAG_KEEP_PARAMS cross-class rejection\n\n");

	pid = fork();
	if (pid < 0) {
		perror("fork");
		return 1;
	}

	if (pid == 0) {
		while (1)
			sleep(3600);
		_exit(0);
	}

	usleep(50000);

	if (read_total_bw(&bw_before_dl) < 0)
		goto kill_child_fail;

	/* Set the sleeping child to SCHED_DEADLINE */
	attr.size = sizeof(attr);
	attr.sched_policy = SCHED_DEADLINE;
	attr.sched_runtime = DL_RUNTIME_NS;
	attr.sched_deadline = DL_PERIOD_NS;
	attr.sched_period = DL_PERIOD_NS;

	if (sched_setattr(pid, &attr, 0) < 0) {
		fprintf(stderr, "sched_setattr(DL): %s\n", strerror(errno));
		goto kill_child_fail;
	}

	if (read_total_bw(&bw_after_dl) < 0)
		goto kill_child_fail;

	printf("  After SCHED_DEADLINE set: total_bw delta = %+ld\n",
	       (long)(bw_after_dl - bw_before_dl));

	/*
	 * Test 1: sched_setattr(OTHER, KEEP_PARAMS) should be rejected
	 * with -EINVAL because the class would change.
	 */
	memset(&attr, 0, sizeof(attr));
	attr.size = sizeof(attr);
	attr.sched_policy = SCHED_OTHER;
	attr.sched_flags = SCHED_FLAG_KEEP_PARAMS;

	ret = sched_setattr(pid, &attr, 0);
	if (ret < 0 && errno == EINVAL) {
		printf("  PASS: KEEP_PARAMS cross-class rejected with -EINVAL\n");
	} else if (ret == 0) {
		if (read_total_bw(&bw_after_keep) < 0)
			goto kill_child_fail;

		delta = (int64_t)(bw_after_keep - bw_after_dl);
		if (delta < -BW_TOLERANCE) {
			printf("  FAIL: KEEP_PARAMS accepted and leaked %ld total_bw\n",
			       (long)delta);
			failures++;
		} else {
			printf("  WARN: KEEP_PARAMS accepted (no-op), no leak detected\n");
			failures++;
		}
	} else {
		printf("  FAIL: KEEP_PARAMS rejected with unexpected errno %d (%s)\n",
		       errno, strerror(errno));
		failures++;
	}

	/*
	 * Test 2: Repeated calls should not drive total_bw negative.
	 * On unfixed kernels, each call subtracts EXPECTED_DL_BW.
	 */
	memset(&attr, 0, sizeof(attr));
	attr.size = sizeof(attr);
	attr.sched_policy = SCHED_OTHER;
	attr.sched_flags = SCHED_FLAG_KEEP_PARAMS;

	for (int i = 0; i < 3; i++)
		sched_setattr(pid, &attr, 0);

	if (read_total_bw(&bw_after_keep) < 0)
		goto kill_child_fail;

	delta = (int64_t)(bw_after_keep - bw_before_dl);
	printf("  After 3x KEEP_PARAMS calls: total_bw delta = %+ld\n",
	       (long)delta);

	if (delta < -BW_TOLERANCE) {
		printf("  FAIL: total_bw went negative (underflow by %ld)\n",
		       (long)-delta);
		failures++;
	} else {
		printf("  PASS: total_bw did not underflow\n");
	}

	/* Clean up */
	kill(pid, SIGKILL);
	waitpid(pid, NULL, 0);
	usleep(50000);

	printf("\n");
	if (failures) {
		printf("FAIL: %d test(s) failed\n", failures);
		return 1;
	}

	printf("PASS: all tests passed\n");
	return 0;

kill_child_fail:
	kill(pid, SIGKILL);
	waitpid(pid, NULL, 0);
	return 1;
}

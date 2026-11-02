/*
 * Test for total_bw crash/leak when switching from DL after CPU hotplug
 *
 * A sleeping SCHED_DEADLINE task whose CPU is offlined keeps its
 * task_cpu() pointing to the offline CPU (now in def_root_domain).
 * Switching it to SCHED_OTHER must release total_bw from the correct
 * root domain, not from def_root_domain.
 *
 * Without the fix, this crashes with a divide-by-zero in __dl_sub()
 * (dl_bw_cpus() returns 0 for def_root_domain) or leaks the bandwidth.
 *
 * Reported by Tejun Heo.
 *
 * Build: gcc -Wall -O2 -o test_dl_hotplug_bw test_dl_hotplug_bw.c
 * Run:   sudo ./test_dl_hotplug_bw
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
#include <fcntl.h>

#include <sched.h>

#include "../../lib/sched_deadline.h"

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

static int cpu_set_online(int cpu, int online)
{
	char path[64];
	int fd, ret = 0;
	char val = online ? '1' : '0';

	snprintf(path, sizeof(path), "/sys/devices/system/cpu/cpu%d/online", cpu);
	fd = open(path, O_WRONLY);
	if (fd < 0) {
		fprintf(stderr, "Cannot open %s: %s\n", path, strerror(errno));
		return -1;
	}

	if (write(fd, &val, 1) != 1) {
		fprintf(stderr, "Cannot %s cpu%d: %s\n",
			online ? "online" : "offline", cpu, strerror(errno));
		ret = -1;
	}

	close(fd);
	return ret;
}

static int get_task_cpu(pid_t pid)
{
	char path[64];
	char buf[1024];
	FILE *fp;
	int cpu = -1;

	snprintf(path, sizeof(path), "/proc/%d/stat", pid);
	fp = fopen(path, "r");
	if (!fp)
		return -1;

	if (fgets(buf, sizeof(buf), fp)) {
		/*
		 * Field 39 (1-based) in /proc/pid/stat is the CPU number.
		 * Skip past the comm field (in parens) first.
		 */
		char *p = strrchr(buf, ')');
		if (p) {
			int field = 2;

			p++;
			while (*p && field < 39) {
				if (*p == ' ')
					field++;
				p++;
			}
			if (field == 39)
				cpu = atoi(p);
		}
	}

	fclose(fp);
	return cpu;
}

int main(void)
{
	struct sched_attr attr = {};
	uint64_t bw_before, bw_after;
	int64_t delta;
	pid_t pid;
	int target_cpu;
	int failures = 0;

	if (geteuid() != 0) {
		fprintf(stderr, "This test must run as root\n");
		return 1;
	}

	printf("Testing DL total_bw release after CPU hotplug\n\n");

	/* Fork a sleeping child (wide affinity) */
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

	if (read_total_bw(&bw_before) < 0)
		goto kill_child_fail;

	/* Set the sleeping child to SCHED_DEADLINE (wide affinity) */
	attr.size = sizeof(attr);
	attr.sched_policy = SCHED_DEADLINE;
	attr.sched_runtime = DL_RUNTIME_NS;
	attr.sched_deadline = DL_PERIOD_NS;
	attr.sched_period = DL_PERIOD_NS;

	if (sched_setattr(pid, &attr, 0) < 0) {
		fprintf(stderr, "sched_setattr(DL): %s\n", strerror(errno));
		goto kill_child_fail;
	}

	/*
	 * Find which CPU the sleeping task is on. We can't pin a DL task
	 * to a single CPU, so we discover its current CPU and offline that.
	 */
	target_cpu = get_task_cpu(pid);
	if (target_cpu < 0) {
		fprintf(stderr, "Cannot determine task CPU\n");
		goto kill_child_fail;
	}

	if (target_cpu == 0) {
		printf("  Task is on CPU 0 (cannot offline), skipping\n");
		printf("SKIP: task landed on CPU 0\n");
		kill(pid, SIGKILL);
		waitpid(pid, NULL, 0);
		return 0;
	}

	/* Verify the CPU is offlineable */
	{
		char path[64];

		snprintf(path, sizeof(path),
			 "/sys/devices/system/cpu/cpu%d/online", target_cpu);
		if (access(path, W_OK) != 0) {
			printf("SKIP: CPU %d is not offlineable\n", target_cpu);
			kill(pid, SIGKILL);
			waitpid(pid, NULL, 0);
			return 0;
		}
	}

	printf("  Task sleeping on CPU %d\n", target_cpu);

	/* Offline the CPU — task stays sleeping with stale task_cpu() */
	printf("  Offlining CPU %d...\n", target_cpu);
	if (cpu_set_online(target_cpu, 0) < 0)
		goto restore_cpu;

	usleep(100000);

	/*
	 * Switch the sleeping DL task to SCHED_OTHER.
	 * Without the fix, this crashes with a divide-by-zero in
	 * __dl_sub() because dl_bw_cpus() returns 0 for
	 * def_root_domain, or subtracts from the wrong dl_bw.
	 */
	memset(&attr, 0, sizeof(attr));
	attr.size = sizeof(attr);
	attr.sched_policy = SCHED_OTHER;

	printf("  Switching sleeping DL task to SCHED_OTHER...\n");
	if (sched_setattr(pid, &attr, 0) < 0) {
		fprintf(stderr, "sched_setattr(OTHER): %s\n", strerror(errno));
		goto restore_cpu;
	}

	/* Bring the CPU back online */
	printf("  Onlining CPU %d...\n", target_cpu);
	cpu_set_online(target_cpu, 1);

	kill(pid, SIGKILL);
	waitpid(pid, NULL, 0);
	usleep(100000);

	if (read_total_bw(&bw_after) < 0)
		return 1;

	delta = (int64_t)(bw_after - bw_before);
	printf("\n  total_bw delta after full cycle: %+ld (expect ~0)\n", (long)delta);

	if (delta > BW_TOLERANCE) {
		printf("  FAIL: total_bw leaked %ld\n", (long)delta);
		failures++;
	} else if (delta < -BW_TOLERANCE) {
		printf("  FAIL: total_bw underflowed by %ld\n", (long)-delta);
		failures++;
	} else {
		printf("  PASS: total_bw properly released\n");
	}

	printf("\n");
	if (failures) {
		printf("FAIL: %d test(s) failed\n", failures);
		return 1;
	}

	printf("PASS: all tests passed\n");
	return 0;

restore_cpu:
	cpu_set_online(target_cpu, 1);
kill_child_fail:
	kill(pid, SIGKILL);
	waitpid(pid, NULL, 0);
	return 1;
}

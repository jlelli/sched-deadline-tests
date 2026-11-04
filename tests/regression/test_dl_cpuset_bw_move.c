/*
 * Test for total_bw corruption on cpuset move of a sleeping DL task
 *
 * Moving a sleeping SCHED_DEADLINE task from the root cpuset into an
 * exclusive partition and back (without it running in between) leaves
 * the root domain short by the task's bandwidth. The partition keeps
 * a stale reservation.
 *
 * dl_task_needs_bw_move() uses task_rq(p)->rd to determine the current
 * root domain, but for a sleeping task that's stale — it still points
 * to the CPU the task last ran on. On the move back, it looks like
 * the task is already in the root domain, so no bandwidth transfer
 * happens.
 *
 * Reported by Weiheng Qiu <weihengqiuu@gmail.com>.
 *
 * Build: gcc -Wall -O2 -o test_dl_cpuset_bw_move test_dl_cpuset_bw_move.c
 * Run:   sudo ./test_dl_cpuset_bw_move
 *
 * Needs cgroup v2 with cpuset controller and at least 2 CPUs.
 * Temporarily turns the last CPU into a partition — use a test VM.
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
#include <sys/stat.h>
#include <sys/mount.h>
#include <stdint.h>
#include <fcntl.h>

#include <sched.h>

#include "../../lib/sched_deadline.h"

#define DL_RUNTIME_NS	25000000ULL	/* 25ms / 50ms = 0.5 CPU */
#define DL_PERIOD_NS	50000000ULL
#define BW_UNIT		(1LL << 20)

#define BW_TOLERANCE	100

#define DEBUGFS_SCHED_DEBUG	"/sys/kernel/debug/sched/debug"
#define CG			"/sys/fs/cgroup"
#define PART			CG "/dl-bw-test"

static int put(const char *path, const char *val)
{
	int fd = open(path, O_WRONLY);
	int rc = 0;

	if (fd < 0 || write(fd, val, strlen(val)) < 0)
		rc = -errno;
	if (fd >= 0)
		close(fd);
	return rc;
}

static int move_to_cgroup(pid_t pid, const char *cg)
{
	char path[128], v[32];

	snprintf(path, sizeof(path), "%s/cgroup.procs", cg);
	snprintf(v, sizeof(v), "%d\n", pid);
	return put(path, v);
}

static int read_total_bw_cpu(int cpu, uint64_t *total_bw)
{
	FILE *fp;
	char buf[4096];
	char *pos;
	int cur_cpu = -1, c;

	fp = fopen(DEBUGFS_SCHED_DEBUG, "r");
	if (!fp) {
		fprintf(stderr, "Cannot open %s: %s\n",
			DEBUGFS_SCHED_DEBUG, strerror(errno));
		return -1;
	}

	while (fgets(buf, sizeof(buf), fp)) {
		if (sscanf(buf, "dl_rq[%d]:", &c) == 1) {
			cur_cpu = c;
			continue;
		}

		if (cur_cpu != cpu)
			continue;

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
	fprintf(stderr, "Could not find dl_bw->total_bw for cpu%d\n", cpu);
	return -1;
}

static void cleanup_partition(void)
{
	put(PART "/cpuset.cpus.partition", "member");
	rmdir(PART);
}

int main(void)
{
	struct sched_attr attr = {};
	uint64_t root_bw_start, root_bw_after, part_bw_start, part_bw_after;
	int64_t root_delta, part_delta;
	pid_t pid;
	int iso_cpu;
	int failures = 0;
	int rc;
	char cpu_str[16];
	char buf[64];
	int fd;

	if (geteuid() != 0) {
		fprintf(stderr, "This test must run as root\n");
		return 1;
	}

	iso_cpu = sysconf(_SC_NPROCESSORS_ONLN) - 1;
	if (iso_cpu < 1) {
		printf("SKIP: need at least 2 CPUs\n");
		return 0;
	}

	/* Ensure cgroup v2 is mounted */
	if (access(CG "/cgroup.controllers", F_OK)) {
		if (mount("none", CG, "cgroup2", 0, NULL) < 0) {
			printf("SKIP: cannot mount cgroup v2\n");
			return 0;
		}
	}

	/* Check cpuset controller is available */
	fd = open(CG "/cgroup.controllers", O_RDONLY);
	if (fd < 0) {
		printf("SKIP: cannot read cgroup controllers\n");
		return 0;
	}
	rc = read(fd, buf, sizeof(buf) - 1);
	close(fd);
	if (rc <= 0 || !strstr(buf, "cpuset")) {
		printf("SKIP: cpuset controller not available\n");
		return 0;
	}

	/* Enable cpuset controller */
	put(CG "/cgroup.subtree_control", "+cpuset");

	/* Create partition with the last CPU */
	mkdir(PART, 0755);
	snprintf(cpu_str, sizeof(cpu_str), "%d", iso_cpu);
	put(PART "/cpuset.cpus", cpu_str);
	put(PART "/cpuset.cpus.exclusive", cpu_str);

	rc = put(PART "/cpuset.cpus.partition", "root");
	if (rc < 0) {
		printf("SKIP: cannot create cpuset partition (rc=%d)\n", rc);
		rmdir(PART);
		return 0;
	}

	printf("Testing DL bandwidth accounting across cpuset partition moves\n");
	printf("  CPU %d is an exclusive partition\n\n", iso_cpu);

	/* Spawn a sleeping child and make it SCHED_DEADLINE */
	pid = fork();
	if (pid < 0) {
		perror("fork");
		cleanup_partition();
		return 1;
	}

	if (pid == 0) {
		while (1)
			sleep(3600);
		_exit(0);
	}

	usleep(50000);

	attr.size = sizeof(attr);
	attr.sched_policy = SCHED_DEADLINE;
	attr.sched_runtime = DL_RUNTIME_NS;
	attr.sched_deadline = DL_PERIOD_NS;
	attr.sched_period = DL_PERIOD_NS;

	if (sched_setattr(pid, &attr, 0) < 0) {
		fprintf(stderr, "sched_setattr(DL): %s\n", strerror(errno));
		goto fail;
	}

	/* Record baseline total_bw for both domains */
	if (read_total_bw_cpu(0, &root_bw_start) < 0)
		goto fail;
	if (read_total_bw_cpu(iso_cpu, &part_bw_start) < 0)
		goto fail;

	printf("  Start:    root=%.3f CPU  partition=%.3f CPU\n",
	       (double)root_bw_start / BW_UNIT,
	       (double)part_bw_start / BW_UNIT);

	/* Move sleeping DL task into partition */
	rc = move_to_cgroup(pid, PART);
	if (rc < 0) {
		fprintf(stderr, "  Move to partition failed: %s\n",
			strerror(-rc));
		goto fail;
	}

	usleep(50000);

	/* Move it back to root */
	rc = move_to_cgroup(pid, CG);
	if (rc < 0) {
		fprintf(stderr, "  Move back to root failed: %s\n",
			strerror(-rc));
		goto fail;
	}

	usleep(50000);

	/* Check bandwidth after round-trip */
	if (read_total_bw_cpu(0, &root_bw_after) < 0)
		goto fail;
	if (read_total_bw_cpu(iso_cpu, &part_bw_after) < 0)
		goto fail;

	root_delta = (int64_t)(root_bw_after - root_bw_start);
	part_delta = (int64_t)(part_bw_after - part_bw_start);

	printf("  After:    root=%.3f CPU  partition=%.3f CPU\n",
	       (double)root_bw_after / BW_UNIT,
	       (double)part_bw_after / BW_UNIT);
	printf("  Deltas:   root=%+.3f CPU  partition=%+.3f CPU  (expect ~0 both)\n",
	       (double)root_delta / BW_UNIT,
	       (double)part_delta / BW_UNIT);

	if (root_delta < -BW_TOLERANCE || root_delta > BW_TOLERANCE) {
		printf("  FAIL: root domain total_bw changed by %+ld\n",
		       (long)root_delta);
		failures++;
	} else {
		printf("  PASS: root domain total_bw unchanged\n");
	}

	if (part_delta < -BW_TOLERANCE || part_delta > BW_TOLERANCE) {
		printf("  FAIL: partition total_bw changed by %+ld\n",
		       (long)part_delta);
		failures++;
	} else {
		printf("  PASS: partition total_bw unchanged\n");
	}

	/* Clean up */
	kill(pid, SIGKILL);
	waitpid(pid, NULL, 0);
	usleep(100000);

	cleanup_partition();

	printf("\n");
	if (failures) {
		printf("FAIL: %d test(s) failed\n", failures);
		return 1;
	}

	printf("PASS: all tests passed\n");
	return 0;

fail:
	kill(pid, SIGKILL);
	waitpid(pid, NULL, 0);
	cleanup_partition();
	return 1;
}

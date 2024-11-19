#define _GNU_SOURCE
#include <sched.h>
#include <stdio.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <math.h>
#include <linux/unistd.h>
#include <linux/kernel.h>
#include <linux/types.h>
#include <sys/syscall.h>
#include <pthread.h>

#define gettid() syscall(__NR_gettid)

#define SCHED_DEADLINE       6

/* XXX use the proper syscall numbers */
#ifdef __x86_64__
#define __NR_sched_setattr           314
#define __NR_sched_getattr           315
#endif

#ifdef __i386__
#define __NR_sched_setattr           351
#define __NR_sched_getattr           352
#endif

#ifdef __arm__
#define __NR_sched_setattr           380
#define __NR_sched_getattr           381
#endif

static volatile pid_t thread_tid = -1;
static volatile int done;

struct sched_attr {
	__u32 size;
	
	__u32 sched_policy;
	__u64 sched_flags;
	
	/* SCHED_NORMAL, SCHED_BATCH */
	__s32 sched_nice;
	
	/* SCHED_FIFO, SCHED_RR */
	__u32 sched_priority;
	
	/* SCHED_DEADLINE (nsec) */
	__u64 sched_runtime;
	__u64 sched_deadline;
	__u64 sched_period;
};

int sched_setattr(pid_t pid,
		const struct sched_attr *attr,
		unsigned int flags)
{
	return syscall(__NR_sched_setattr, pid, attr, flags);
}

int sched_getattr(pid_t pid,
		struct sched_attr *attr,
		unsigned int size,
		unsigned int flags)
{
	return syscall(__NR_sched_getattr, pid, attr, size, flags);
}

struct timespec
timespec_add(struct timespec *t1, struct timespec *t2)
{
	struct timespec ts;
	
	ts.tv_sec = t1->tv_sec + t2->tv_sec;
	ts.tv_nsec = t1->tv_nsec + t2->tv_nsec;
	
	while (ts.tv_nsec >= 1E9) {
		ts.tv_nsec -= 1E9;
		ts.tv_sec++;
	}
	
	return ts;
}

struct timespec
usec_to_timespec(unsigned long usec)
{
	struct timespec ts;

	ts.tv_sec = usec / 1000000;
	ts.tv_nsec = (usec % 1000000) * 1000;

	return ts;
}

__u64
timespec_to_nsec(struct timespec *ts)
{
	return round(ts->tv_sec * 1E9 + ts->tv_nsec);
}

unsigned long long
timespec_to_usec_ull(struct timespec *ts)
{
	return llround((ts->tv_sec * 1E9 + ts->tv_nsec) / 1000.0);
}

struct timespec
timespec_sub(struct timespec *t1, struct timespec *t2)
{
	struct timespec ts;

	if (t1->tv_nsec < t2->tv_nsec) {
		ts.tv_sec = t1->tv_sec - t2->tv_sec -1;
		ts.tv_nsec = t1->tv_nsec  + 1000000000 - t2->tv_nsec;
	} else {
		ts.tv_sec = t1->tv_sec - t2->tv_sec;
		ts.tv_nsec = t1->tv_nsec - t2->tv_nsec;
	}
	
	return ts;

}

void *run_deadline(void *data)
{
	struct sched_attr attr;
	int iteration = 0;
	int ret;
	unsigned int flags = 0;
	struct timespec now, next, deadline, wlatency;
	long long deadline_diff;

	thread_tid = gettid();

	printf("deadline thread started [%ld]\n\n", thread_tid);

	attr.size = sizeof(attr);
	attr.sched_flags = 0;
	attr.sched_nice = 0;
	attr.sched_priority = 0;

	/* This creates a 10ms/30ms reservation */
	attr.sched_policy = SCHED_DEADLINE;
	attr.sched_runtime = 10 * 1000 * 1000;
	attr.sched_period = attr.sched_deadline = 30 * 1000 * 1000;

	deadline = usec_to_timespec(attr.sched_deadline / 1000);

	ret = sched_setattr(0, &attr, flags);
	if (ret < 0) {
		done = 0;
		perror("sched_setattr");
		exit(-1);
	}

	if (clock_gettime(CLOCK_MONOTONIC, &now) == -1) {
		perror("clock_gettime");
		exit(EXIT_FAILURE);
	}
	printf("deadline thread iteration=%d now=%llu [%ld]\n", iteration++, timespec_to_nsec(&now), thread_tid);

	next = now;
	
	while (!done) {
		next = timespec_add(&next, &deadline);
		ret = sched_getattr(thread_tid, &attr, sizeof(attr), flags);
		if (ret < 0) {
			done = 0;
			perror("sched_setattr");
			exit(-1);
		}

		deadline_diff = attr.sched_deadline - timespec_to_nsec(&next);
		printf("kruntime=%llu kdeadline=%llu udeadline=%llu diff=%lld [%ld]\n\n", attr.sched_runtime,
				attr.sched_deadline, timespec_to_nsec(&next), deadline_diff, thread_tid);

		if (clock_nanosleep(CLOCK_MONOTONIC, TIMER_ABSTIME, &next, NULL) == -1) {
			perror("clock_nanosleep");
			exit(EXIT_FAILURE);
		}

		if (clock_gettime(CLOCK_MONOTONIC, &now) == -1) {
			perror("clock_gettime");
			exit(EXIT_FAILURE);
		}

		wlatency = timespec_sub(&now, &next);
		printf("deadline thread iteration=%d now=%llu wlat=%llu [%ld]\n", iteration++,
				timespec_to_nsec(&now), timespec_to_nsec(&wlatency), thread_tid);
	}

	if (clock_gettime(CLOCK_MONOTONIC, &now) == -1) {
		perror("clock_gettime");
		exit(EXIT_FAILURE);
	}

	printf("deadline thread dies at %llu [%ld]\n", timespec_to_nsec(&now), thread_tid);

	return NULL;
}

int main (int argc, char *argv[])
{
	pthread_t thread;
	struct sched_attr attr;
	int ret;
	unsigned int flags = 0;
	struct timespec now;

	printf("Calling sched_getparam on a SCHED_DEADLINE task to see what happens!\n\n");

	if (clock_gettime(CLOCK_MONOTONIC, &now) == -1) {
		perror("clock_gettime");
		exit(EXIT_FAILURE);
	}

	printf("main thread at %llu [%ld]\n", timespec_to_nsec(&now), gettid());

	pthread_create(&thread, NULL, run_deadline, NULL);

	while (thread_tid == -1)
		usleep(100);

	sleep(5);

	done = 1;
	pthread_join(thread, NULL);

	if (clock_gettime(CLOCK_MONOTONIC, &now) == -1) {
		perror("clock_gettime");
		exit(EXIT_FAILURE);
	}

	printf("main dies at %llu [%ld]\n", timespec_to_nsec(&now), gettid());

	return 0;
}

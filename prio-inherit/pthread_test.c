#define _GNU_SOURCE
#include <unistd.h>
#include <sys/syscall.h>
#include <stdio.h>
#include <stdlib.h>
#include <signal.h>
#include <string.h>
#include <linux/types.h>
#include <pthread.h>

#define SCHED_DEADLINE	6

/* XXX use the proper syscall numbers */
#ifdef __x86_64__
#define __NR_sched_setattr		314
#define __NR_sched_getattr		315
#endif

#ifdef __i386__
#define __NR_sched_setattr		351
#define __NR_sched_getattr		352
#endif

#ifdef __arm__
#define __NR_sched_setattr		380
#define __NR_sched_getattr		381
#endif

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

pthread_mutex_t mutex;
int terminate;

static int sched_setattr(pid_t pid,
		  const struct sched_attr *attr,
		  unsigned int flags)
{
	return syscall(__NR_sched_setattr, pid, attr, flags);
}

static void handle_err(const char *str)
{
	perror(str);
	exit(EXIT_FAILURE);
}

static void sighandler(int sig)
{
	terminate = 1;
}

static void *worker(void *arg)
{
	struct sched_attr dl;
	pid_t tid;

	tid = syscall(SYS_gettid);

	dl.size = sizeof(struct sched_attr);
	dl.sched_policy = SCHED_DEADLINE;
	dl.sched_flags = 0;
	dl.sched_nice = 0;
	dl.sched_priority = 0;
	dl.sched_runtime =  100 * 1000;
	dl.sched_deadline = 200 * 1000;
	dl.sched_period =   200 * 1000;

	if (sched_setattr(tid, &dl, 0) < 0)
		handle_err("Could not set SCHED_DEADLINE attributes");

	while (!terminate) {
		pthread_mutex_lock(&mutex);
		usleep(100);
		pthread_mutex_unlock(&mutex);
		usleep(10);
	}

	return NULL;
}

static void usage(void)
{
	printf("pthread_test [PROTOCOL]\n");
	printf("  PROTOCOL: none, inherit, protect\n");
	exit(EXIT_SUCCESS);
}

int main(int argc, char *argv[])
{
	pthread_mutexattr_t attr;
	pthread_t thread;
	struct sigaction sa;
	int protocol = PTHREAD_PRIO_NONE;

	if (argc > 1) {
		if (!strcmp(argv[1], "none"))
			protocol = PTHREAD_PRIO_NONE;
		else if (!strcmp(argv[1], "inherit"))
			protocol = PTHREAD_PRIO_INHERIT;
		else if (!strcmp(argv[1], "protect"))
			protocol = PTHREAD_PRIO_PROTECT;
		else
			usage();
	}

	sigemptyset(&sa.sa_mask);
	sa.sa_flags = 0;
	sa.sa_handler = sighandler;
	if (sigaction(SIGINT, &sa, NULL) < 0)
		handle_err("Installing sighandler failed");

	if (pthread_mutexattr_init(&attr) != 0)
		handle_err("phtread_mutexattr_init");

	if (pthread_mutexattr_setprotocol(&attr, protocol) !=0)
		handle_err("pthread_mutexattr_setprotocol");

	if (pthread_mutex_init(&mutex, &attr) != 0)
		handle_err("phtread_mutex_init");

	if (pthread_create(&thread, NULL, worker, NULL) != 0)
		handle_err("pthread_create");

	while(!terminate) {
		pthread_mutex_lock(&mutex);
		usleep(10);
		pthread_mutex_unlock(&mutex);
	}

	pthread_cancel(thread);
	pthread_join(thread, NULL);

	return EXIT_SUCCESS;
}

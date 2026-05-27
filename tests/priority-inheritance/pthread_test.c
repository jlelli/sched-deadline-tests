#define _GNU_SOURCE
#include <unistd.h>
#include <sys/syscall.h>
#include <stdio.h>
#include <stdlib.h>
#include <signal.h>
#include <string.h>
#include <pthread.h>

#include "../../lib/sched_deadline.h"

pthread_mutex_t mutex;
int terminate;

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

/* gcc main.c -lpthread */

/*
 * This program reproduces a kernel bug at line
 * https://elixir.bootlin.com/linux/v4.15/source/kernel/sched/deadline.c#L1405, but not limited
 * to the version v4.15.
 *
 * This is bug is triggered when a non-deadline task that was boosted by a deadline task boosts
 * another non-deadline task.
 *
 * So the execution order of locking steps are the following
 * (N1 and N2 are non-deadline tasks. D1 is a deadline task. M1 and M2 are mutexes that are enabled
 * with priority inheritance.)
 *
 * Time moves forward as this timeline goes down:
 *
 * N1              N2               D1
 * |               |                |
 * |               |                |
 * Lock(M1)        |                |
 * |               |                |
 * |             Lock(M2)           |
 * |               |                |
 * |               |              Lock(M2)
 * |               |                |
 * |             Lock(M1)           |
 * |             (!!bug triggered!) |
 *
 */

#define _GNU_SOURCE
#include <pthread.h>
#include <sched.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/syscall.h>
#include <time.h>
#include <unistd.h>

#include "../../lib/sched_deadline.h"

#define gettid() syscall(__NR_gettid)

static volatile int step;
pthread_mutex_t m1;
pthread_mutex_t m2;

void *run_normal_1(void *data) {
    printf("normal thread N1 started [%ld]\n", gettid());

    // N1 locks M1
    printf("N1 is locking M1\n");
    pthread_mutex_lock(&m1);
    printf("N1 locked M1\n");

    // Notify N2
    step = 1;
    // Wait to be boosted by N2 (on M1)
    printf("N1 sleeps 10\n");
    sleep(10);
    printf("N1 wakes up\n");

    // Won't be able to reach here because of the rt_mutex + sched_deadline bug.
    printf("N1 is unlocking M1\n");
    pthread_mutex_unlock(&m1);
    printf("N1 unlocked M1\n");

    printf("normal thread N1 dies [%ld]\n", gettid());
    return NULL;
}

void *run_normal_2(void *data) {
    printf("normal thread N2 started [%ld]\n", gettid());

    // N2 locks M2
    printf("N2 is locking M2\n");
    pthread_mutex_lock(&m2);
    printf("N2 locked M2\n");

    // Wait until N1 locked M1
    while (step < 1) {
        /* busy wait */
    }

    // Notify D1
    step = 2;
    // Wait to be boosted by D1 (on M2)
    printf("N2 sleeps 5\n");
    sleep(5);
    printf("N2 wakes up\n");

    printf("N2 is locking M1\n");
    // This will boost N1 and trigger the bug.
    pthread_mutex_lock(&m1);
    // Won't reach here because of the bug
    printf("N2 locked M1\n");

    printf("N2 is unlocking M1\n");
    pthread_mutex_unlock(&m1);
    printf("N2 unlocked M1\n");

    printf("N2 is unlocking M2\n");
    pthread_mutex_unlock(&m2);
    printf("N2 unlocked M2\n");

    printf("normal thread N2 dies [%ld]\n", gettid());
    return NULL;
}

void *run_deadline(void *data) {
    struct sched_attr attr;
    int ret = 0;
    unsigned int flags = 0;

    printf("deadline thread D1 started [%ld]\n", gettid());

    attr.size = sizeof(attr);
    attr.sched_flags = 0;
    attr.sched_nice = 0;
    attr.sched_priority = 0;

    /* This creates a 10ms/30ms reservation */
    attr.sched_policy = SCHED_DEADLINE;
    attr.sched_runtime = 10 * 1000 * 1000;
    attr.sched_period = attr.sched_deadline = 30 * 1000 * 1000;

    ret = sched_setattr(0, &attr, flags);
    if (ret < 0) {
        step = 0;
        perror("sched_setattr");
        exit(-1);
    }

    // Wait until N2 locked M2
    while (step < 2) {
        /* busy wait */
    }

    printf("D1 is locking M2\n");
    // This will boost N2
    pthread_mutex_lock(&m2);
    printf("D1 locked M2\n");

    printf("D1 sleeps 10\n");
    sleep(10);
    printf("D1 wakes up\n");
    // Won't reach here because of the bug.

    printf("D1 is unlocking M2\n");
    pthread_mutex_unlock(&m2);
    printf("D1 unlocked M2\n");

    printf("deadline thread dies [%ld]\n", gettid());
    return NULL;
}

int main(int argc, char **argv) {
    pthread_t thread[3];

    printf("main thread [%ld]\n", gettid());

    int rtn;
    pthread_mutexattr_t mutexattr;
    if ((rtn = pthread_mutexattr_init(&mutexattr) != 0)) {
        fprintf(stderr, "pthread_mutexattr_init: %s", strerror(rtn));
        exit(1);
    }
    if ((rtn = pthread_mutexattr_setprotocol(&mutexattr,
                                             PTHREAD_PRIO_INHERIT)) != 0) {
        fprintf(stderr, "pthread_mutexattr_setprotocol: %s", strerror(rtn));
        exit(1);
    }

    if ((rtn = pthread_mutex_init(&m1, &mutexattr)) != 0) {
        fprintf(stderr, "pthread_mutexattr_init: %s", strerror(rtn));
        exit(1);
    }

    if ((rtn = pthread_mutex_init(&m2, &mutexattr)) != 0) {
        fprintf(stderr, "pthread_mutexattr_init: %s", strerror(rtn));
        exit(1);
    }

    // use this volatile variable to coordinate execution order between threads
    step = 0;
    pthread_create(thread, NULL, run_normal_1, NULL);
    pthread_create(thread + 1, NULL, run_normal_2, NULL);
    pthread_create(thread + 2, NULL, run_deadline, NULL);

    pthread_join(thread[0], NULL);
    pthread_join(thread[1], NULL);
    pthread_join(thread[2], NULL);

    printf("main dies [%ld]\n", gettid());
    return 0;
}

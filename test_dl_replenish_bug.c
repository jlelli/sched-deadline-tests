/*
 * Test for DEADLINE ENQUEUE_REPLENISH bug
 *
 * Reproduces the scenario where:
 * 1. Task B (DEADLINE, short deadline) holds a PI mutex
 * 2. Task A (DEADLINE, long deadline) blocks on Task B's mutex
 * 3. Task B doesn't inherit from Task A (B has shorter deadline = higher priority)
 * 4. sched_setscheduler() changes Task B from DEADLINE to IDLE
 * 5. Task B should now inherit DEADLINE from Task A with ENQUEUE_REPLENISH
 *
 * Without the fix, ENQUEUE_REPLENISH flag is missing, causing:
 * "DL de-boosted task PID X: REPLENISH flag missing"
 *
 * Build: gcc -o test_dl_replenish_bug test_dl_replenish_bug.c -lpthread
 * Run:   sudo ./test_dl_replenish_bug
 */

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <pthread.h>
#include <sched.h>
#include <errno.h>
#include <stdint.h>
#include <time.h>
#include <signal.h>

/* Global state */
static pthread_mutex_t pi_mutex;
static pthread_barrier_t barrier;
static volatile int holder_ready = 0;
static volatile int waiter_blocked = 0;
static volatile int test_done = 0;
static volatile int timeout_occurred = 0;
static volatile pid_t holder_tid = 0;
static volatile pid_t waiter_tid = 0;

/* Timeout handler */
static void timeout_handler(int sig)
{
	timeout_occurred = 1;
	test_done = 1;

	printf("\n\n!!! TIMEOUT !!!\n");
	printf("Test appears to have hung - likely due to the bug being triggered!\n");
	printf("This indicates the ENQUEUE_REPLENISH bug corrupted bandwidth accounting.\n");
	printf("\nCheck kernel log:\n");
	printf("  sudo dmesg | tail -50\n");
	printf("\nLook for:\n");
	printf("  'REPLENISH flag missing'\n");
	printf("  'dl_runtime_exceeded' or bandwidth warnings\n");
	printf("\nTest failed - kernel is likely in bad state.\n");
	printf("May need to reboot or wait for scheduler to recover.\n\n");

	exit(1);
}

static void print_sched_info(const char *label, pid_t tid)
{
	struct sched_attr attr = {0};
	attr.size = sizeof(attr);

	if (sched_getattr(tid, &attr, sizeof(attr), 0) == 0) {
		printf("[%s] TID %d: policy=%u prio=%d",
		       label, tid, attr.sched_policy, attr.sched_priority);
		if (attr.sched_policy == SCHED_DEADLINE) {
			printf(" runtime=%llu deadline=%llu period=%llu",
			       (unsigned long long)attr.sched_runtime,
			       (unsigned long long)attr.sched_deadline,
			       (unsigned long long)attr.sched_period);
		}
		printf("\n");
	}
}

static int set_sched_deadline(pid_t tid, uint64_t runtime_ms,
			      uint64_t deadline_ms, uint64_t period_ms)
{
	struct sched_attr attr = {0};

	attr.size = sizeof(attr);
	attr.sched_policy = SCHED_DEADLINE;
	attr.sched_runtime = runtime_ms * 1000000ULL;   /* ms to ns */
	attr.sched_deadline = deadline_ms * 1000000ULL;
	attr.sched_period = period_ms * 1000000ULL;

	return sched_setattr(tid, &attr, 0);
}

static int set_sched_idle(pid_t tid)
{
	struct sched_param param = {0};
	return sched_setscheduler(tid, SCHED_IDLE, &param);
}

/*
 * Thread B: DEADLINE task (SHORT deadline) that holds the PI mutex
 * This will be setscheduled to IDLE, triggering the bug
 */
static void *holder_thread(void *arg)
{
	holder_tid = gettid();

	printf("\n=== HOLDER (Task B) thread started (TID %d) ===\n", holder_tid);

	/* Set to DEADLINE with a SHORT deadline (high priority) */
	if (set_sched_deadline(holder_tid, 5, 30, 60) < 0) {
		perror("holder: sched_setattr");
		return NULL;
	}

	print_sched_info("HOLDER-INIT", holder_tid);

	/* Lock the mutex */
	pthread_mutex_lock(&pi_mutex);
	printf("[HOLDER] TID %d: Locked PI mutex\n", holder_tid);

	/* Signal we're ready */
	holder_ready = 1;

	/* Wait at barrier */
	pthread_barrier_wait(&barrier);

	/* Keep holding the mutex while waiter blocks and gets setscheduled */
	while (!test_done) {
		usleep(10000); /* 10ms */
	}

	printf("[HOLDER] TID %d: Unlocking PI mutex\n", holder_tid);
	pthread_mutex_unlock(&pi_mutex);

	printf("[HOLDER] TID %d: Exiting\n", holder_tid);
	return NULL;
}

/*
 * Thread A: DEADLINE task (LONG deadline) that will block on the mutex
 * This is the pi_task that holder will inherit from after setscheduler
 */
static void *waiter_thread(void *arg)
{
	waiter_tid = gettid();

	printf("\n=== WAITER (Task A) thread started (TID %d) ===\n", waiter_tid);

	/* Set to DEADLINE with a LONG deadline (low priority) */
	if (set_sched_deadline(waiter_tid, 10, 50, 100) < 0) {
		perror("waiter: sched_setattr");
		return NULL;
	}

	print_sched_info("WAITER-INIT", waiter_tid);

	/* Wait for holder to lock the mutex */
	while (!holder_ready) {
		usleep(1000);
	}

	/* Wait at barrier */
	pthread_barrier_wait(&barrier);

	printf("[WAITER] TID %d: Attempting to lock PI mutex (will block)...\n", waiter_tid);

	/* This will block because holder has the lock */
	waiter_blocked = 1;
	pthread_mutex_lock(&pi_mutex);

	/* Eventually we get the lock */
	printf("[WAITER] TID %d: Acquired PI mutex\n", waiter_tid);

	print_sched_info("WAITER-AFTER", waiter_tid);

	pthread_mutex_unlock(&pi_mutex);
	printf("[WAITER] TID %d: Unlocked PI mutex\n", waiter_tid);

	printf("[WAITER] TID %d: Exiting\n", waiter_tid);
	return NULL;
}

int main(int argc, char *argv[])
{
	pthread_t holder, waiter;
	pthread_mutexattr_t attr;
	int iterations = 1;
	int i;

	if (argc > 1) {
		iterations = atoi(argv[1]);
		if (iterations < 1)
			iterations = 1;
	}

	printf("======================================\n");
	printf("DEADLINE ENQUEUE_REPLENISH Bug Test\n");
	printf("======================================\n");
	printf("Iterations: %d\n", iterations);
	printf("Timeout: 5 seconds per iteration\n");
	printf("\nThis test reproduces the scenario where:\n");
	printf("1. Task B (DEADLINE, short deadline) holds a PI mutex\n");
	printf("2. Task A (DEADLINE, long deadline) blocks on Task B's mutex\n");
	printf("3. Task B doesn't inherit from A (B has higher priority)\n");
	printf("4. Task B gets setscheduled to SCHED_IDLE (while A still blocked)\n");
	printf("5. Task B should now inherit from A with ENQUEUE_REPLENISH\n");
	printf("\nWithout fix: Missing ENQUEUE_REPLENISH flag causes WARNING\n");
	printf("\nCheck dmesg for:\n");
	printf("  'DL de-boosted task PID X: REPLENISH flag missing'\n");
	printf("\nNOTE: If test hangs and times out, the bug was triggered!\n");
	printf("======================================\n\n");

	/* Set up timeout handler */
	signal(SIGALRM, timeout_handler);

	/* Initialize PI mutex */
	pthread_mutexattr_init(&attr);
	pthread_mutexattr_setprotocol(&attr, PTHREAD_PRIO_INHERIT);
	pthread_mutex_init(&pi_mutex, &attr);
	pthread_mutexattr_destroy(&attr);

	for (i = 0; i < iterations; i++) {
		if (iterations > 1) {
			printf("\n========== Iteration %d/%d ==========\n",
			       i + 1, iterations);
		}

		/* Reset state */
		holder_ready = 0;
		waiter_blocked = 0;
		test_done = 0;
		timeout_occurred = 0;
		holder_tid = 0;
		waiter_tid = 0;

		/* Set timeout for this iteration (5 seconds) */
		alarm(5);

		/* Initialize barrier for 2 threads */
		pthread_barrier_init(&barrier, NULL, 2);

		/* Create holder thread (will lock mutex) */
		if (pthread_create(&holder, NULL, holder_thread, NULL) != 0) {
			perror("pthread_create holder");
			return 1;
		}

		/* Create waiter thread (will block on mutex) */
		if (pthread_create(&waiter, NULL, waiter_thread, NULL) != 0) {
			perror("pthread_create waiter");
			return 1;
		}

		/* Get waiter's TID */
		sleep(1); /* Give threads time to start */

		/* Wait for waiter to block on the mutex */
		printf("\n[MAIN] Waiting for waiter to block on mutex...\n");
		while (!waiter_blocked) {
			usleep(1000);
		}

		/* Give it a moment to actually block */
		usleep(50000); /* 50ms */

		printf("\n[MAIN] Holder TID: %d\n", holder_tid);
		print_sched_info("HOLDER-HOLDING", holder_tid);

		/*
		 * THE BUG TRIGGER:
		 * Holder (Task B) is DEADLINE with short deadline (high priority).
		 * Waiter (Task A) is DEADLINE with long deadline (low priority), blocked.
		 * Holder didn't inherit from waiter (holder has higher priority).
		 * Now change HOLDER from DEADLINE to SCHED_IDLE.
		 * Holder should inherit DEADLINE from waiter with ENQUEUE_REPLENISH,
		 * but without the fix, it doesn't.
		 */
		printf("\n[MAIN] *** Changing HOLDER (Task B) from SCHED_DEADLINE to SCHED_IDLE ***\n");
		printf("[MAIN] *** This triggers the bug! ***\n");

		if (set_sched_idle(holder_tid) < 0) {
			perror("set_sched_idle");
		} else {
			printf("[MAIN] Successfully changed holder to SCHED_IDLE\n");
			print_sched_info("HOLDER-SETSCHEDULED", holder_tid);
		}

		/* Let the scenario play out */
		usleep(100000); /* 100ms */

		/* Signal threads to finish */
		test_done = 1;

		/* Wait for threads */
		pthread_join(holder, NULL);
		pthread_join(waiter, NULL);

		/* Cancel the alarm - we completed successfully */
		alarm(0);

		pthread_barrier_destroy(&barrier);

		if (timeout_occurred) {
			printf("\n[MAIN] Iteration %d FAILED due to timeout\n", i + 1);
			/* Don't continue if we hit a timeout */
			break;
		}

		printf("\n[MAIN] Iteration %d complete\n", i + 1);

		if (i + 1 < iterations) {
			printf("[MAIN] Sleeping 1s before next iteration...\n");
			sleep(1);
		}
	}

	pthread_mutex_destroy(&pi_mutex);

	printf("\n======================================\n");
	if (timeout_occurred) {
		printf("Test FAILED - Timeout occurred!\n");
		printf("======================================\n");
		printf("\nThe timeout indicates the bug was triggered and the\n");
		printf("scheduler is stuck due to bandwidth accounting corruption.\n");
	} else {
		printf("Test completed successfully!\n");
		printf("======================================\n");
		printf("\nNo timeouts occurred - fix appears to be working.\n");
	}
	printf("\nCheck kernel log:\n");
	printf("  sudo dmesg | tail -50\n");
	printf("\nLook for:\n");
	printf("  'DL de-boosted task PID X: REPLENISH flag missing'\n");
	printf("  'dl_runtime_exceeded' or bandwidth warnings\n");
	printf("\n");

	return timeout_occurred ? 1 : 0;
}

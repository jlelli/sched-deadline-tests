/*
 * test_dl_exit_class_change.c
 *
 * Regression test for the SCHED_DEADLINE this_bw double subtraction bug
 * hit when the scheduling class of a dying task is changed.
 *
 * Bug (fixed by "sched/deadline: Fix this_bw on class change of a dying
 * task", Fixes: 8fd27231c330 "sched/deadline: Track the \"total rq
 * utilization\" too"):
 *
 * When a SCHED_DEADLINE task exits, do_task_dead() first stores TASK_DEAD
 * in p->__state and then calls __schedule(), which dequeues the task with
 * DEQUEUE_SLEEP.  If another CPU changes the class of the still queued,
 * dying task with sched_setscheduler(2) in that window, an unfixed kernel
 * subtracts the task's bandwidth from its runqueue's this_bw twice:
 *
 *   1. the class change dequeues the still queued task with DEQUEUE_SAVE,
 *      and dequeue_dl_entity() subtracts dl_bw from this_bw (and
 *      running_bw);
 *   2. switched_from_dl() then calls task_non_contending(), which sees
 *      p->__state == TASK_DEAD and subtracts dl_bw from this_bw again.
 *
 * __sub_rq_bw() then WARNs about the underflow (or about
 * running_bw > this_bw), and this_bw stays wrong until reboot,
 * miscomputing GRUB reclaim for SCHED_FLAG_RECLAIM tasks on that CPU.
 *
 * Race mechanics (what makes this hard to hit):
 *
 * The losing sched_setscheduler() must take the child's pi_lock after
 * set_special_state(TASK_DEAD) stored TASK_DEAD but before __schedule()
 * acquires the rq lock: a window of only a few dozen guest instructions.
 * Arriving earlier is useless too: __sched_setscheduler holds pi_lock
 * across the whole class change, so the child would then block inside
 * set_special_state() BEFORE storing TASK_DEAD.  Arriving later is also
 * useless: the child's own final __schedule() already dequeued it.  The
 * arrival time is therefore swept across many scales:
 *
 *   - The parent sleeps in sigtimedwait() with SIGCHLD blocked, so it is
 *     woken the moment exit_notify() queues SIGCHLD, which happens right
 *     after exit_state is set and well before do_task_dead().  (A
 *     waitid(WNOHANG) busy poll would only notice the exit at its next
 *     iteration, and under e.g. QEMU one syscall round trip can exceed
 *     the child's whole exit tail, making the parent always too late.)
 *   - A random busy delay, drawn log-uniformly from a wide range of
 *     scales, then shifts the class change across the child's exit tail.
 *
 * The bandwidth corruption is only observable in the kernel log (the
 * per-rq this_bw is not exposed to userspace): the accompanying
 * test_dl_exit_class_change.sh wrapper greps dmesg for the resulting
 * WARNINGs.  This program's own exit status only says whether the race
 * loop ran correctly (every child really entered SCHED_DEADLINE and was
 * class-changed); a clean run does not by itself prove the kernel is
 * fixed, since the race window is narrow (QEMU TCG hits it much more
 * easily than fast bare metal).
 *
 * Usage: test_dl_exit_class_change [iterations]
 *        DL_EXIT_RACE_ITERS=<n> overrides the iteration count.
 *        DL_EXIT_RACE_MAX_SHIFT=<n> overrides the log2 of the maximum
 *        delay (default 15, i.e. delays up to 32767 loop iterations;
 *        raise it if the arrival window cannot be reached).
 *
 * Exit codes: 0 success, 1 failure, 77 skipped (missing prerequisites).
 *
 * Build: gcc -Wall -O2 -o test_dl_exit_class_change test_dl_exit_class_change.c
 * Run:   sudo ./test_dl_exit_class_change
 */

#define _GNU_SOURCE
#include <errno.h>
#include <sched.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#include "../../lib/sched_deadline.h"

#define DEFAULT_ITERS	50000
#define DEFAULT_MAX_SHIFT 15	/* max delay: 2^15 loop iterations */

/* 10% reservation: small enough to always pass admission control. */
#define DL_RUNTIME_NS	(100ULL * 1000 * 1000)
#define DL_DEADLINE_NS	(200ULL * 1000 * 1000)
#define DL_PERIOD_NS	(1000ULL * 1000 * 1000)

/* Give up if a child does not report its exit in time. */
#define EXIT_TIMEOUT_MS	10000

static unsigned int iters = DEFAULT_ITERS;
static unsigned int max_shift = DEFAULT_MAX_SHIFT;
static int cpu_a = -1, cpu_b = -1;	/* two distinct CPUs from the initial mask */
static cpu_set_t orig_mask;	/* affinity mask at startup */
static sigset_t chld_set;	/* { SIGCHLD }, blocked during the race */

static double now_ms(void)
{
	struct timespec ts;

	clock_gettime(CLOCK_MONOTONIC, &ts);
	return ts.tv_sec * 1000.0 + ts.tv_nsec / 1000000.0;
}

/*
 * Pin to @cpu, or restore the affinity the test started with when
 * @cpu < 0.  Restoring the original mask (rather than "all CPUs") keeps
 * the call valid when the test runs inside a cpuset; SCHED_DEADLINE
 * admission control requires the mask to span the whole root domain
 * anyway.
 */
static int pin(int cpu)
{
	cpu_set_t s;

	if (cpu < 0) {
		s = orig_mask;
	} else {
		CPU_ZERO(&s);
		CPU_SET(cpu, &s);
	}
	return sched_setaffinity(0, sizeof(s), &s);
}

/*
 * Random busy-wait that shifts the phase of the race.  The delay is
 * drawn log-uniformly from [0, 2^max_shift): the mapping from delay
 * iterations to position within the child's exit path depends on the
 * machine (emulator speed, kernel config), so the arrival time must be
 * swept over many scales rather than one calibrated range.
 */
static void race_delay(void)
{
	unsigned int scale = 1U << (rand() % (max_shift + 1));

	for (volatile unsigned int k = rand() % scale; k; k--)
		;
}

/*
 * Check that this test can create SCHED_DEADLINE tasks.  Returns 0 if a
 * probe child entered SCHED_DEADLINE, the errno otherwise (-1 for local
 * failures).
 */
static int probe_sched_deadline(void)
{
	struct sched_attr attr = {
		.size = sizeof(attr),
		.sched_policy = SCHED_DEADLINE,
		.sched_runtime = DL_RUNTIME_NS,
		.sched_deadline = DL_DEADLINE_NS,
		.sched_period = DL_PERIOD_NS,
	};
	int p[2], err = 0;
	pid_t pid;

	if (pipe(p) < 0)
		return -1;

	pid = fork();
	if (pid < 0) {
		close(p[0]);
		close(p[1]);
		return -1;
	}

	if (pid == 0) {
		close(p[0]);
		err = sched_setattr(0, &attr, 0) ? errno : 0;
		/* Report the errno through the pipe before exiting. */
		if (write(p[1], &err, sizeof(err)) != sizeof(err))
			_exit(EXIT_FAILURE);
		_exit(err ? EXIT_FAILURE : EXIT_SUCCESS);
	}

	close(p[1]);
	if (read(p[0], &err, sizeof(err)) != sizeof(err))
		err = -1;
	close(p[0]);
	waitpid(pid, NULL, 0);

	return err;
}

int main(int argc, char *argv[])
{
	struct sched_attr attr = {
		.size = sizeof(attr),
		.sched_policy = SCHED_DEADLINE,
		.sched_runtime = DL_RUNTIME_NS,
		.sched_deadline = DL_DEADLINE_NS,
		.sched_period = DL_PERIOD_NS,
	};
	struct sched_param sp = { .sched_priority = 0 };
	double t_start;
	int probe_err, c, ncpus;

	if (argc > 1) {
		iters = atoi(argv[1]);
	} else {
		const char *e = getenv("DL_EXIT_RACE_ITERS");

		if (e)
			iters = atoi(e);
	}
	if (iters == 0)
		iters = DEFAULT_ITERS;
	{
		const char *e = getenv("DL_EXIT_RACE_MAX_SHIFT");

		if (e)
			max_shift = atoi(e);
	}
	if (max_shift > 24)
		max_shift = 24;

	/* Pick two distinct CPUs from the current affinity mask. */
	if (sched_getaffinity(0, sizeof(orig_mask), &orig_mask) < 0) {
		perror("sched_getaffinity");
		return 1;
	}
	ncpus = CPU_COUNT(&orig_mask);
	if (ncpus < 2) {
		printf("TEST_SKIP: need at least 2 CPUs in the affinity mask (have %d)\n",
		       ncpus);
		return 77;
	}
	for (c = 0; c < CPU_SETSIZE && cpu_b < 0; c++) {
		if (!CPU_ISSET(c, &orig_mask))
			continue;
		if (cpu_a < 0)
			cpu_a = c;
		else
			cpu_b = c;
	}
	if (cpu_a < 0 || cpu_b < 0 || cpu_a == cpu_b) {
		printf("TEST_SKIP: could not pick two distinct CPUs (cpu_a=%d cpu_b=%d)\n",
		       cpu_a, cpu_b);
		return 77;
	}

	/*
	 * Check prerequisites before starting: becoming SCHED_DEADLINE
	 * needs root or CAP_SYS_NICE, and admission control requires an
	 * affinity mask spanning the whole root domain.
	 */
	probe_err = probe_sched_deadline();
	if (probe_err == EPERM) {
		printf("TEST_SKIP: cannot create SCHED_DEADLINE tasks (EPERM); run as root or with CAP_SYS_NICE, with an affinity mask spanning the root domain\n");
		return 77;
	}
	if (probe_err == EBUSY) {
		printf("TEST_SKIP: SCHED_DEADLINE admission control refused the test reservation (EBUSY)\n");
		return 77;
	}
	if (probe_err != 0) {
		printf("TEST_FAILED: sched_setattr probe failed: %s\n",
		       probe_err > 0 ? strerror(probe_err) : "pipe/fork failure");
		return 1;
	}

	/*
	 * Block SIGCHLD so that the exit of each race child can be
	 * consumed with sigtimedwait(): the parent then sleeps until
	 * exit_notify() queues SIGCHLD (right after exit_state is set,
	 * before the child's do_task_dead() window) instead of polling
	 * waitid(WNOHANG), whose period can exceed the child's exit tail.
	 */
	sigemptyset(&chld_set);
	sigaddset(&chld_set, SIGCHLD);
	if (sigprocmask(SIG_BLOCK, &chld_set, NULL) < 0) {
		perror("sigprocmask");
		return 1;
	}

	srand(time(NULL) ^ getpid());

	printf("racing %u iterations (max delay 2^%u): parent on CPU%d, child exits on CPU%d\n",
	       iters, max_shift, cpu_b, cpu_a);

	t_start = now_ms();

	for (unsigned int i = 0; i < iters; i++) {
		siginfo_t si;
		int go[2];
		pid_t pid;
		char b = 0;
		double deadline;

		if (pipe(go) < 0) {
			perror("pipe");
			return 1;
		}

		/* Fork while pinned to cpu_a so the child starts there. */
		if (pin(cpu_a) < 0) {
			perror("pin(cpu_a)");
			return 1;
		}

		pid = fork();
		if (pid < 0) {
			perror("fork");
			return 1;
		}

		if (pid == 0) {
			/*
			 * Child: wait until the parent is parked on cpu_b,
			 * then widen the affinity mask (admission control
			 * requires it to span the root domain), become
			 * SCHED_DEADLINE, and die.  The interesting window
			 * is between the TASK_DEAD store in do_task_dead()
			 * and the final __schedule().
			 */
			if (read(go[0], &b, 1) != 1)
				_exit(2);
			close(go[0]);
			if (pin(-1) < 0)
				_exit(3);
			_exit(sched_setattr(0, &attr, 0) ? 1 : 0);
		}

		/* Park on the other CPU before releasing the child. */
		if (pin(cpu_b) < 0) {
			perror("pin(cpu_b)");
			kill(pid, SIGKILL);
			waitpid(pid, NULL, 0);
			return 1;
		}
		if (write(go[1], &b, 1) != 1) {
			perror("write go");
			kill(pid, SIGKILL);
			waitpid(pid, NULL, 0);
			return 1;
		}
		close(go[0]);
		close(go[1]);

		/*
		 * Sleep until the child reports its exit.  exit_notify()
		 * queues SIGCHLD right after setting exit_state, which
		 * wakes us immediately; the child still has its whole
		 * exit tail ahead, including the vulnerable window.
		 */
		deadline = now_ms() + EXIT_TIMEOUT_MS;
		for (;;) {
			struct timespec ts = {
				.tv_sec = 0,
				.tv_nsec = 100 * 1000 * 1000,
			};
			int sig = sigtimedwait(&chld_set, &si, &ts);

			if (sig == SIGCHLD && si.si_pid == pid)
				break;
			if (sig < 0 && errno != EAGAIN && errno != EINTR) {
				printf("TEST_FAILED: sigtimedwait: %s (iteration %u)\n",
				       strerror(errno), i);
				kill(pid, SIGKILL);
				waitpid(pid, NULL, 0);
				return 1;
			}
			if (now_ms() > deadline) {
				printf("TEST_FAILED: child %d did not exit in time (iteration %u)\n",
				       pid, i);
				kill(pid, SIGKILL);
				waitpid(pid, NULL, 0);
				return 1;
			}
		}

		/* The exit status came with the signal. */
		if (si.si_code != CLD_EXITED) {
			printf("TEST_FAILED: child killed by signal %d (iteration %u)\n",
			       si.si_status, i);
			waitpid(pid, NULL, 0);
			return 1;
		}
		switch (si.si_status) {
		case 0:
			break;	/* became SCHED_DEADLINE just fine */
		case 1:
			printf("TEST_FAILED: child could not become SCHED_DEADLINE (iteration %u)\n",
			       i);
			waitpid(pid, NULL, 0);
			return 1;
		default:
			printf("TEST_FAILED: child setup failed (status %d, iteration %u)\n",
			       (int)si.si_status, i);
			waitpid(pid, NULL, 0);
			return 1;
		}

		/*
		 * Random delay: shifts the class change across the
		 * window between "exit reported" and "final dequeue
		 * done", sweeping many time scales.
		 */
		race_delay();

		/*
		 * The trigger: move the dying child out of SCHED_DEADLINE.
		 * If this lands after do_task_dead() stored TASK_DEAD but
		 * before __schedule() dequeued the child, an unfixed kernel
		 * subtracts the child's bandwidth from this_bw twice.
		 */
		if (sched_setscheduler(pid, SCHED_OTHER, &sp) < 0) {
			printf("TEST_FAILED: sched_setscheduler(%d): %s (iteration %u)\n",
			       pid, strerror(errno), i);
			waitpid(pid, NULL, 0);
			return 1;
		}

		if (waitpid(pid, NULL, 0) != pid) {
			perror("waitpid");
			return 1;
		}

		if ((i + 1) % 10000 == 0)
			printf("  %u/%u iterations\n", i + 1, iters);
	}

	printf("completed %u iterations in %.1fs\n",
	       iters, (now_ms() - t_start) / 1000.0);
	/*
	 * Deliberately no TEST_PASSED here: the race loop completing says
	 * nothing about the kernel bug, which is only visible in the kernel
	 * log.  The verdict belongs to the shell wrapper, and run-tests.sh
	 * greps the combined output for TEST_PASSED before TEST_FAILED, so
	 * a TEST_PASSED here would turn the wrapper's failure into a false
	 * pass.
	 */
	printf("race loop completed (kernel log verdict is up to the wrapper)\n");
	return 0;
}

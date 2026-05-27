/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Common definitions for SCHED_DEADLINE tests
 *
 * This header provides backward compatibility for older systems
 * that don't have sched_attr in their headers.
 */

#ifndef _SCHED_DEADLINE_H
#define _SCHED_DEADLINE_H

#include <linux/types.h>
#include <sys/syscall.h>
#include <unistd.h>

/* Check if sched_attr is already defined in system headers */
#ifndef SCHED_ATTR_SIZE_VER0
/* System doesn't have sched_attr, define it ourselves */

#ifndef SCHED_DEADLINE
#define SCHED_DEADLINE 6
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

/* Syscall wrappers */
static inline int sched_setattr(pid_t pid,
				const struct sched_attr *attr,
				unsigned int flags)
{
	return syscall(__NR_sched_setattr, pid, attr, flags);
}

static inline int sched_getattr(pid_t pid,
				struct sched_attr *attr,
				unsigned int size,
				unsigned int flags)
{
	return syscall(__NR_sched_getattr, pid, attr, size, flags);
}

#else
/* System has sched_attr, just include the header */
#include <sched.h>

#ifndef SCHED_DEADLINE
#define SCHED_DEADLINE 6
#endif

#endif /* SCHED_ATTR_SIZE_VER0 */

#endif /* _SCHED_DEADLINE_H */

# Regression Tests Makefile

CC ?= gcc
CFLAGS ?= -Wall -O2
LDFLAGS ?= -lpthread

TARGETS = pi-cfs-bug-repro test_dl_replenish_bug test_dl_total_bw_leak \
	  test_dl_keep_params_underflow test_dl_hotplug_bw \
	  test_dl_zombie_bw_leak test_dl_cpuset_bw_move

.PHONY: all clean

all: $(TARGETS)

pi-cfs-bug-repro: pi-cfs-bug-repro.c
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)

test_dl_replenish_bug: test_dl_replenish_bug.c
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)

test_dl_total_bw_leak: test_dl_total_bw_leak.c
	$(CC) $(CFLAGS) -o $@ $<

test_dl_keep_params_underflow: test_dl_keep_params_underflow.c
	$(CC) $(CFLAGS) -o $@ $<

test_dl_hotplug_bw: test_dl_hotplug_bw.c
	$(CC) $(CFLAGS) -o $@ $<

test_dl_zombie_bw_leak: test_dl_zombie_bw_leak.c
	$(CC) $(CFLAGS) -o $@ $<

test_dl_cpuset_bw_move: test_dl_cpuset_bw_move.c
	$(CC) $(CFLAGS) -o $@ $<

clean:
	rm -f $(TARGETS) *.o

# Regression Tests Makefile

CC ?= gcc
CFLAGS ?= -Wall -O2
LDFLAGS ?= -lpthread

TARGETS = pi-cfs-bug-repro test_dl_replenish_bug test_dl_exit_class_change

.PHONY: all clean

all: $(TARGETS)

pi-cfs-bug-repro: pi-cfs-bug-repro.c
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)

test_dl_replenish_bug: test_dl_replenish_bug.c
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)

test_dl_exit_class_change: test_dl_exit_class_change.c
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)

clean:
	rm -f $(TARGETS) *.o

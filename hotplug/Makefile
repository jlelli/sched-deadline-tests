# To build:
#
# CROSS_COMPILE={arm-linux-gnueabi-,aarch64-linux-gnu-} make
CROSS_COMPILE?=
CC=$(CROSS_COMPILE)gcc

all: cpuhog

cpuhog: cpuhog.c
	$(CC) -o $@ $^ --static

tests:
	./test_hp_migration.sh
	./test_hp_cpuset.sh

tests-trace:
	./test_hp_migration.sh 1
	./test_hp_cpuset.sh 1

clean:
	rm -f cpuhog *.out *.dat

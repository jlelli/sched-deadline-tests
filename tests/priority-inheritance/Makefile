# To build:
#
# CROSS_COMPILE={arm-linux-gnueabi-,aarch64-linux-gnu-} make
CROSS_COMPILE?=
CC=$(CROSS_COMPILE)gcc


all: pthread_test

pthread_test: pthread_test.c
	$(CC) -o $@ $^ -lpthread --static

tests:
	./test_prio_normal.sh
	./test_prio_inherit.sh

tests-trace:
	./test_prio_normal.sh 1
	./test_prio_inherit.sh 1

clean:
	rm -f pthread_test *.out *.dat

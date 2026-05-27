# To build:
#
# CROSS_COMPILE={arm-linux-gnueabi-,aarch64-linux-gnu-} make
CROSS_COMPILE?=
CC=$(CROSS_COMPILE)gcc

all: cpuhog periodic_yield

cpuhog: cpuhog.c
	$(CC) -o $@ $^ --static

periodic_yield: periodic_yield.c
	$(CC) -o $@ $^ -lpthread --static

tests:
	./test_cpuhog_rsv.sh
	./test_cancel_dl_timer.sh
	./test_yield_dl.sh

tests-trace:
	./test_cpuhog_rsv.sh 1
	./test_cancel_dl_timer.sh 1
	./test_yield_dl.sh 1

clean:
	rm -f cpuhog periodic_yield *.out *.dat

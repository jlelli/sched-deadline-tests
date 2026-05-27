# To build:
#
# CROSS_COMPILE={arm-linux-gnueabi-,aarch64-linux-gnu-} make
CROSS_COMPILE?=
CC=$(CROSS_COMPILE)gcc

all: burn

%: %.c
	$(CC) -o $@ $^ --static

tests:
	./test_rsv_cpuset.sh
	./test_3rsv_cpuset.sh
	./test_4rsv_2cpusets.sh

tests-trace:
	./test_rsv_cpuset.sh 1
	./test_3rsv_cpuset.sh 1
	./test_4rsv_2cpusets.sh 1

clean:
	rm -f burn reset *.out *.dat

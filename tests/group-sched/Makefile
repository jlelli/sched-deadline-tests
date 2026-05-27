# To build:
#
# CROSS_COMPILE={arm-linux-gnueabi-,aarch64-linux-gnu-} make
CROSS_COMPILE?=
CC=$(CROSS_COMPILE)gcc

all: burn

%: %.c
	$(CC) -o $@ $^ --static

tests:
	./test_group.sh

tests-trace:
	./test_group.sh 1

clean:
	rm -f burn *.out *.dat

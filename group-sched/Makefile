CC=arm-linux-gnueabi-gcc

all: burn

%: %.c
	$(CC) -o $@ $^ --static

tests:
	./test_group.sh

tests-trace:
	./test_group.sh 1

clean:
	rm -f burn *.out *.dat

CC=arm-linux-gnueabi-gcc

all: pthread_test

pthread_test: pthread_test.c
	$(CC) -o $@ $^ -lpthread

tests:
	./test_prio_normal.sh
	./test_prio_inherit.sh

tests-trace:
	./test_prio_normal.sh 1
	./test_prio_inherit.sh 1

clean:
	rm -f pthread_test *.out *.dat

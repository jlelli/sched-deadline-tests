all: burn tests

%: %.c
	gcc -o $@ $^

tests:
	./test_rsv_cpuset.sh
	./test_4rsv_2cpusets.sh

tests-trace:
	./test_rsv_cpuset.sh 1
	./test_4rsv_2cpusets.sh 1

clean:
	rm -f burn reset *.out *.dat

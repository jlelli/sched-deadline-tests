all: cpuhog

cpuhog: cpuhog.c
	gcc -o $@ $^

tests:
	./test_hp_migration.sh
	./test_hp_cpuset.sh

tests-trace:
	./test_hp_migration.sh 1
	./test_hp_cpuset.sh 1

clean:
	rm -f cpuhog *.out *.dat

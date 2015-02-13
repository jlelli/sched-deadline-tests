all: cpuhog periodic_yield

cpuhog: cpuhog.c
	gcc -o $@ $^

periodic_yield: periodic_yield.c
	gcc -o $@ $^ -lpthread

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

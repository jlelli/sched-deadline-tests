all: cpuhog periodic_yield

cpuhog: cpuhog.c
	gcc -o $@ $^

periodic_yield: periodic_yield.c
	gcc -o $@ $^ -lpthread

clean:
	rm -f cpuhog periodic_yield

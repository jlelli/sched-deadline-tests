all: burn reset sched_setattr

%: %.c
	gcc -o $@ $^

clean:
	rm -f burn reset sched_setattr

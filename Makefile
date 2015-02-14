SUBDIRS = basic prio-inherit sched-domains

all:
	for dir in $(SUBDIRS); do \
		(cd $$dir; ${MAKE} all); \
	done

test:
	for dir in $(SUBDIRS); do \
		(cd $$dir; ${MAKE} tests); \
	done

test-trace:
	for dir in $(SUBDIRS); do \
		(cd $$dir; ${MAKE} tests-trace); \
	done
clean:
	for dir in $(SUBDIRS); do \
		(cd $$dir; ${MAKE} clean); \
	done


SUBDIRS = basic prio-inherit sched-domains
TARGET = debian-kvm

all:
	for dir in $(SUBDIRS); do \
		(scp $(TARGET):/home/juri/tests/$$dir/*.dat .); \
	done

clean:
	rm *.dat

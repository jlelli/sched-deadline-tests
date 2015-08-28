SUBDIRS=basic prio-inherit sched-domains group-sched
WORKDIR=/home/root
PLATFORM=tc2
TARGET=$(shell platip $(PLATFORM))

all:
	for dir in $(SUBDIRS); do \
		(scp $(TARGET):$(WORKDIR)/tests/$$dir/*.dat .); \
	done

clean:
	rm *.dat

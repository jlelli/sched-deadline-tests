SUBDIRS=basic prio-inherit sched-domains hotplug group-sched
WORKDIR=/home/root
PLATFORM=tc2
TARGET=$(shell platip $(PLATFORM))

all:
	for dir in $(SUBDIRS); do \
		(scp root@$(TARGET):$(WORKDIR)/tests/$$dir/*.dat .); \
	done

clean:
	rm *.dat

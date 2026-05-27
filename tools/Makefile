# Tools Makefile

CC ?= gcc
CFLAGS ?= -Wall -O2
LDFLAGS ?= -lpthread

PREFIX ?= /usr/local
BINDIR = $(PREFIX)/bin

TARGETS = dl_getparam

.PHONY: all clean install uninstall

all: $(TARGETS)

dl_getparam: dl_getparam.c
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS) -lm

clean:
	rm -f $(TARGETS) *.o

install: all
	install -d $(BINDIR)
	install -m 755 $(TARGETS) $(BINDIR)/

uninstall:
	rm -f $(addprefix $(BINDIR)/,$(TARGETS))

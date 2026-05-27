# SCHED_DEADLINE Test Suite Makefile

# Compiler settings
CC ?= gcc
CFLAGS ?= -Wall -O2
LDFLAGS ?= -lpthread

# Test categories
TEST_DIRS = tests/basic \
            tests/priority-inheritance \
            tests/sched-domains \
            tests/hotplug \
            tests/group-sched \
            tests/regression

# Tools
TOOL_DIRS = tools

# Installation paths
PREFIX ?= /usr/local
BINDIR = $(PREFIX)/bin
LIBDIR = $(PREFIX)/lib/sched-deadline-tests
TESTDIR = $(PREFIX)/share/sched-deadline-tests

.PHONY: all build test clean install uninstall help

all: build

help:
	@echo "SCHED_DEADLINE Test Suite Build System"
	@echo ""
	@echo "Targets:"
	@echo "  all (default)  - Build all tests and tools"
	@echo "  build          - Build all tests and tools"
	@echo "  test           - Run all tests (requires root)"
	@echo "  clean          - Remove build artifacts"
	@echo "  install        - Install tests and tools to $(PREFIX)"
	@echo "  uninstall      - Remove installed files"
	@echo "  help           - Show this help message"
	@echo ""
	@echo "Test categories:"
	@echo "  make -C tests/basic"
	@echo "  make -C tests/priority-inheritance"
	@echo "  make -C tests/sched-domains"
	@echo "  make -C tests/hotplug"
	@echo "  make -C tests/group-sched"
	@echo ""
	@echo "Variables:"
	@echo "  CC=$(CC)"
	@echo "  CFLAGS=$(CFLAGS)"
	@echo "  PREFIX=$(PREFIX)"

build:
	@echo "Building all test categories..."
	@for dir in $(TEST_DIRS); do \
		if [ -f $$dir/Makefile ]; then \
			echo "  Building $$dir..."; \
			$(MAKE) -C $$dir CC=$(CC) CFLAGS="$(CFLAGS)" LDFLAGS="$(LDFLAGS)" all || exit 1; \
		fi \
	done
	@echo "Building tools..."
	@for dir in $(TOOL_DIRS); do \
		if [ -f $$dir/Makefile ]; then \
			echo "  Building $$dir..."; \
			$(MAKE) -C $$dir CC=$(CC) CFLAGS="$(CFLAGS)" LDFLAGS="$(LDFLAGS)" all || exit 1; \
		fi \
	done
	@echo "Build complete!"

test:
	@if [ $$(id -u) -ne 0 ]; then \
		echo "ERROR: Tests must be run as root"; \
		exit 1; \
	fi
	@./run-tests.sh

clean:
	@echo "Cleaning build artifacts..."
	@for dir in $(TEST_DIRS); do \
		if [ -f $$dir/Makefile ]; then \
			echo "  Cleaning $$dir..."; \
			$(MAKE) -C $$dir clean; \
		fi \
	done
	@for dir in $(TOOL_DIRS); do \
		if [ -f $$dir/Makefile ]; then \
			echo "  Cleaning $$dir..."; \
			$(MAKE) -C $$dir clean; \
		fi \
	done
	@find . -name "*.o" -o -name "*.dat" -o -name "*.out" | xargs rm -f
	@echo "Clean complete!"

install: build
	@echo "Installing to $(PREFIX)..."
	install -d $(BINDIR)
	install -d $(LIBDIR)
	install -d $(TESTDIR)
	# Install test runner
	install -m 755 run-tests.sh $(BINDIR)/sched-deadline-tests
	# Install libraries
	install -m 644 lib/utils.sh $(LIBDIR)/
	install -m 644 lib/test_skeleton.sh $(LIBDIR)/
	# Install tools
	@for dir in $(TOOL_DIRS); do \
		if [ -f $$dir/Makefile ]; then \
			$(MAKE) -C $$dir PREFIX=$(PREFIX) install; \
		fi \
	done
	# Install test directories
	cp -r tests $(TESTDIR)/
	@echo "Installation complete!"
	@echo "Run tests with: sudo $(BINDIR)/sched-deadline-tests"

uninstall:
	@echo "Uninstalling from $(PREFIX)..."
	rm -f $(BINDIR)/sched-deadline-tests
	rm -rf $(LIBDIR)
	rm -rf $(TESTDIR)
	@for dir in $(TOOL_DIRS); do \
		if [ -f $$dir/Makefile ]; then \
			$(MAKE) -C $$dir PREFIX=$(PREFIX) uninstall; \
		fi \
	done
	@echo "Uninstall complete!"

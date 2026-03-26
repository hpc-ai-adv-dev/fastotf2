# Copyright Hewlett Packard Enterprise Development LP.
# This Makefile acts as a proxy for the Parquet library's C++ prereqs.
# Mason doesn't build prereqs for git dependencies, so we do it here
# from the root project's prereqs (which Mason does support).
#
# It delegates to the Parquet package's own prereqs/cpp/Makefile to compile
# the C++ interop code, then emits the right flags via printchplflags.
#
# Mason runs prereqs *before* cloning git dependencies, so the Parquet
# directory may not exist on the first pass.  The guards below make the
# targets succeed silently in that case; Mason will re-run prereqs after
# the clone, at which point the real build happens.

MASON_HOME ?= $(HOME)/.mason
PARQUET_PKG_DIR = $(MASON_HOME)/git/Parquet-HEAD
PARQUET_PREREQS_DIR = $(PARQUET_PKG_DIR)/prereqs/cpp

.PHONY: all clean printchplflags

all:
	@if [ -d "$(PARQUET_PREREQS_DIR)" ]; then \
		$(MAKE) -C $(PARQUET_PREREQS_DIR) all; \
	else \
		echo "parquet-cpp prereqs: Parquet not yet cloned, skipping (will retry after fetch)"; \
	fi

printchplflags:
	@if [ -d "$(PARQUET_PREREQS_DIR)" ]; then \
		$(MAKE) -C $(PARQUET_PREREQS_DIR) --quiet printchplflags; \
	fi

clean:
	@if [ -d "$(PARQUET_PREREQS_DIR)" ]; then \
		$(MAKE) -C $(PARQUET_PREREQS_DIR) clean; \
	fi

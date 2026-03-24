# This Makefile acts as a proxy for the Parquet library's C++ prereqs.
# Mason doesn't build prereqs for git dependencies, so we do it here
# from the root project's prereqs (which Mason does support).
#
# It delegates to the Parquet package's own prereqs/cpp/Makefile to compile
# the C++ interop code, then emits the right flags via printchplflags.

MASON_HOME ?= $(HOME)/.mason
PARQUET_PKG_DIR = $(MASON_HOME)/git/Parquet-write-strings
PARQUET_PREREQS_DIR = $(PARQUET_PKG_DIR)/prereqs/cpp

.PHONY: all clean printchplflags

all:
	$(MAKE) -C $(PARQUET_PREREQS_DIR) all

# Emit the chpl flags that Mason will pick up.
# This delegates to the Parquet Makefile's own printchplflags target
# which knows the correct headers, object files, and paths.
printchplflags:
	@$(MAKE) -C $(PARQUET_PREREQS_DIR) --quiet printchplflags

clean:
	$(MAKE) -C $(PARQUET_PREREQS_DIR) clean

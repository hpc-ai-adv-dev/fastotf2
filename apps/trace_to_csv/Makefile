# Copyright Hewlett Packard Enterprise Development LP.

# Makefile for OTF2 to CSV Chapel Converter
# Description: Compiles trace_to_csv.chpl with additional source files

# Disable all built-in suffix rules
.SUFFIXES:

# Include common variables and rules
include ../../chpl/Makefile.common

# Set the default goal explicitly
.DEFAULT_GOAL := all

# ============================================================================
# Project Configuration
# ============================================================================

# Base name for the project
BASE_NAME = trace_to_csv

# Chapel OTF2 module directory (relative to this Makefile)
CHPL_OTF2_MODULE_DIR = ../../src

# Extra Chapel source files to include in compilation
EXTRA_SOURCES = CallGraph.chpl

# ============================================================================
# Source Files and Targets
# ============================================================================

# Define source files that actually exist
SERIAL_SOURCE = $(BASE_NAME).chpl
PARALLEL_SOURCE = $(BASE_NAME)_parallel.chpl

# Define target executables (only for files that exist)
SERIAL_TARGET = $(BASE_NAME)
PARALLEL_TARGET = $(BASE_NAME)_parallel

# All targets - include both serial and parallel
ALL_TARGETS = $(SERIAL_TARGET) $(PARALLEL_TARGET)

# ============================================================================
# Phony Targets
# ============================================================================

.PHONY: all clean help rebuild serial parallel

# ============================================================================
# Build Targets
# ============================================================================

# Default target - build all available versions
all: $(ALL_TARGETS)

# Prevent Make from using implicit rules to build .chpl files
%.chpl:
	@: # Do nothing - .chpl files are source files, not targets

# Individual build rules for each version (with extra sources)
# Note: EXTRA_SOURCES dependencies are implicit (Chapel compiler will check them)
$(SERIAL_TARGET): $(SERIAL_SOURCE)
	@$(MAKE) build-version \
		SOURCE_FILE=$< \
		TARGET=$@ \
		CHPL_OTF2_MODULE_DIR=$(CHPL_OTF2_MODULE_DIR) \
		EXTRA_SOURCES="$(EXTRA_SOURCES)"

$(PARALLEL_TARGET): $(PARALLEL_SOURCE)
	@$(MAKE) build-version \
		SOURCE_FILE=$< \
		TARGET=$@ \
		CHPL_OTF2_MODULE_DIR=$(CHPL_OTF2_MODULE_DIR) \
		EXTRA_SOURCES="$(EXTRA_SOURCES)"

# Version-specific convenience targets
serial: $(SERIAL_TARGET)

parallel: $(PARALLEL_TARGET)

# ============================================================================
# Clean and Rebuild
# ============================================================================

# Clean build artifacts
clean:
	@$(MAKE) clean-targets TARGETS="$(ALL_TARGETS)"

# Force rebuild
rebuild: clean all

# ============================================================================
# Help
# ============================================================================

help:
	@echo "=========================================================================="
	@echo "  Makefile for OTF2 to CSV Chapel Converter"
	@echo "=========================================================================="
	@echo ""
	@echo "Available targets:"
	@echo "  all          - Compile all available versions (default)"
	@echo "  serial       - Compile serial version"
	@echo "  parallel     - Compile parallel version"
	@echo "  clean        - Remove build artifacts"
	@echo "  rebuild      - Clean and rebuild all"
	@echo "  help         - Show this help message"
	@echo ""
	@echo "Available source files:"
	@echo "  Serial:      $(SERIAL_SOURCE)"
	@echo "  Parallel:    $(PARALLEL_SOURCE)"
	@echo "  Extra:       $(EXTRA_SOURCES)"
	@echo ""
	@echo "Target executables:"
	@echo "  Serial:      $(SERIAL_TARGET)"
	@echo "  Parallel:    $(PARALLEL_TARGET)"
	@echo ""
	@$(MAKE) help-common CHPL_OTF2_MODULE_DIR=$(CHPL_OTF2_MODULE_DIR) EXTRA_SOURCES="$(EXTRA_SOURCES)"
	@echo "=========================================================================="

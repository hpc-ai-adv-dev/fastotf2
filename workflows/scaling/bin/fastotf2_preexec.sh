#!/bin/bash
# Restore LD_LIBRARY_PATH for OTF2 libraries inside the container
export LD_LIBRARY_PATH="/opt/otf2/lib:${LD_LIBRARY_PATH}"
export CHPL_RT_MAX_HEAP_SIZE=70%
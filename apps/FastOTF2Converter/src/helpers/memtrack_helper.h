#ifndef MEMTRACK_HELPER_H
#define MEMTRACK_HELPER_H

#include <sys/resource.h>

static inline long get_peak_rss_kib(void) {
  struct rusage usage;
  if (getrusage(RUSAGE_SELF, &usage) != 0) {
    return -1;  // Error case
  }
#ifdef __APPLE__
  return usage.ru_maxrss / 1024;  // macOS: bytes -> KiB
#else
  return usage.ru_maxrss;         // Linux: already in KiB
#endif
}

#endif

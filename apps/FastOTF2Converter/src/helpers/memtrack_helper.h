#ifndef MEMTRACK_HELPER_H
#define MEMTRACK_HELPER_H

#include <sys/resource.h>

static inline long get_peak_rss_kb(void) {
  struct rusage usage;
  getrusage(RUSAGE_SELF, &usage);
#ifdef __APPLE__
  return usage.ru_maxrss / 1024;  // macOS: bytes -> KB
#else
  return usage.ru_maxrss;         // Linux: already in KB
#endif
}

#endif

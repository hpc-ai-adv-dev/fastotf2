Perf notes from Mon Sep 8
MacBook Pro M2 Max 32GB mem

Here's what we're checking:
Read Events: counts, stores, and calculates stats on events, has potential to write to a file

For each program, we test it on a small trace and a large trace

## Python

Python versions use the Pyton otf2 module

### otf2readevents.py

Simplest implementation, in python
44 lines of code

#### Small trace
```console
❯ python3 comparisons/python/otf2readevents.py
Time taken to open OTF2 archive: 0.01 seconds
Time taken to read and process events: 0.28 seconds
Total time: 0.28 seconds
Total execution time: 0.28 seconds
Event Summary:
Total number of events: 72670
Event types and their counts:
  Unknown: 72590 events
  Enter: 40 events
  Leave: 40 events
Total unique locations: 5
Total unique regions: 19
```
#### Large trace
```console
❯ python3 comparisons/python/otf2readevents.py
Time taken to open OTF2 archive: 0.02 seconds
Time taken to read and process events: 42.18 seconds
Total time: 42.20 seconds
Total execution time: 42.20 seconds

Event Summary:
Total number of events: 16613424
Event types and their counts:
  Unknown: 2633870 events
  Enter: 6989777 events
  Leave: 6989777 events
Total unique locations: 19
Total unique regions: 376
```

## C
C implementaions use the C API for OTF2

### otf2_read_events.c

C implementation needs me to create all the lookup tables and whatnot
380 lines of code

Correctness matches

#### Small trace:
```console
❯ gcc -o otf2_read_events comparisons/c/otf2_read_events.c -I/opt/otf2/include -L/opt/otf2/lib -lotf2 -O3 && ./otf2_read_events
Time taken to open OTF2 archive: 0.00 seconds
Number of locations: 32
Read 368 global definitions
Time taken to read global definitions: 0.00 seconds
Time taken to read local definition files and mark all local event files for reading: 0.01 seconds
Time taken to read events: 0.02 seconds
Total time: 0.03 seconds
```

#### Large trace
```console
❯ gcc -o otf2_read_events comparisons/c/otf2_read_events.c -I/opt/otf2/include -L/opt/otf2/lib -lotf2 -O3 && ./otf2_read_events
Time taken to open OTF2 archive: 0.00 seconds
Number of locations: 201
Read 2606 global definitions
Time taken to read global definitions: 0.00 seconds
Time taken to read local definition files and mark all local event files for reading: 0.03 seconds
Time taken to read events: 3.22 seconds
Total time: 3.25 seconds
```


### otf2_read_events_hash.c

Uses hashtables rather than arrays for definition context for O(1) lookups
456 Lines of code

#### Small trace
```console
❯ gcc -o otf2_read_events_hash comparisons/c/otf2_read_events_hash.c -I/opt/otf2/include -L/opt/otf2/lib -lotf2 -O3 && ./otf2_read_events_hash
Time taken to open OTF2 archive: 0.00 seconds
Number of locations: 32
Read 368 global definitions
Time taken to read global definitions: 0.00 seconds
Time taken to read local definition files and mark all local event files for reading: 0.01 seconds
Time taken to read events: 0.01 seconds
Total time: 0.02 seconds
```

#### Large trace
```console
❯ gcc -o otf2_read_events_hash comparisons/c/otf2_read_events_hash.c -I/opt/otf2/include -L/opt/otf2/lib -lotf2 -O3 && ./otf2_read_events_hash
Time taken to open OTF2 archive: 0.00 seconds
Number of locations: 201
Read 2606 global definitions
Time taken to read global definitions: 0.00 seconds
Time taken to read local definition files and mark all local event files for reading: 0.05 seconds
Time taken to read events: 2.00 seconds
Total time: 2.05 seconds
```


## Chapel

### otf2_read_events.chpl

A chapel version of otf2_read_events_hash.c
218 Lines of code

#### Small trace:
```console
❯ make serial && ./otf2_read_events
Compiling otf2_read_events.chpl...
chpl -M ../_chpl --fast otf2_read_events.chpl -I/opt/otf2/include -L/opt/otf2/lib -lotf2 -o otf2_read_events
Compilation successful!
Time taken to open OTF2 archive: 0.00 seconds
Number of locations: 32
Global definitions read: 368
Time taken to read global definitions: 0.00 seconds
Time taken to read local definition files and mark all local event files for reading: 0.004936 seconds
Time taken to read events: 0.011305 seconds
Total time: 0.016665 seconds
Event Summary:
 Total number of events: 72670
 Event types and their counts:
  Enter: 40 events
  Leave: 40 events
Total Unique Locations: 32
Total Unique Regions: 21
```

#### Large trace:
```console
❯ make serial && ./otf2_read_events
Compiling otf2_read_events.chpl...
chpl -M ../_chpl --fast otf2_read_events.chpl -I/opt/otf2/include -L/opt/otf2/lib -lotf2 -o otf2_read_events
Compilation successful!
Time taken to open OTF2 archive: 0.00 seconds
Number of locations: 201
Global definitions read: 2606
Time taken to read global definitions: 0.00 seconds
Time taken to read local definition files and mark all local event files for reading: 0.079323 seconds
Time taken to read events: 1.91536 seconds
Total time: 1.99742 seconds
Event Summary:
 Total number of events: 16613424
 Event types and their counts:
  Enter: 6989777 events
  Leave: 6989777 events
Total Unique Locations: 201
Total Unique Regions: 677
```

### otf2_read_events_parallel.chpl

A parallel version (using 8 readers in this case) of otf2_read_events.chpl.
There's more optimizations that can be done here, but this is a great proof of concept and correctness
275 Lines of code

#### Small trace:
```console
❯ make parallel && ./otf2_read_events_parallel
Compiling otf2_read_events_parallel.chpl...
chpl -M ../_chpl --fast otf2_read_events_parallel.chpl -I/opt/otf2/include -L/opt/otf2/lib -lotf2 -o otf2_read_events_parallel
Compilation successful!
Time taken to open initial OTF2 archive: 0.00 seconds
Number of locations: 32
Global definitions read: 368
Time taken to read global definitions: 0.00 seconds
Total locations: 32
SANITY CHECK:true
Time taken to convert location IDs to array: 3e-06 seconds
Number of readers: 8
Time taken to mark all local event files for reading: 0.000902 seconds
Time taken to mark all local event files for reading: 0.001 seconds
Time taken to mark all local event files for reading: 0.001052 seconds
Time taken to mark all local event files for reading: 0.001056 seconds
Time taken to mark all local event files for reading: 0.001111 seconds
Time taken to mark all local event files for reading: 0.001261 seconds
Time taken to mark all local event files for reading: 0.001386 seconds
Time taken to mark all local event files for reading: 0.001561 seconds
Time taken to read events (task 2): 0.000444 seconds
Time taken to read events (task 5): 0.000924 seconds
Time taken to read events (task 6): 0.001157 seconds
Time taken to read events (task 4): 0.001344 seconds
Time taken to read events (task 0): 0.001557 seconds
Time taken to read events (task 1): 0.001391 seconds
Time taken to read events (task 3): 0.00119 seconds
Time taken to read events (task 7): 0.001861 seconds
Total time: 0.00421 seconds
Event Summary:
 Total number of events: 72670
 Event types and their counts:
  Aggregated Enter events: 40
  Aggregated Leave events: 40
Total Unique Locations: 32
Total Unique Regions: 21
```

#### Large trace:
```console
❯ make parallel && ./otf2_read_events_parallel
Compiling otf2_read_events_parallel.chpl...
chpl -M ../_chpl --fast otf2_read_events_parallel.chpl -I/opt/otf2/include -L/opt/otf2/lib -lotf2 -o otf2_read_events_parallel
Compilation successful!
Time taken to open initial OTF2 archive: 0.00 seconds
Number of locations: 201
Global definitions read: 2606
Time taken to read global definitions: 0.00 seconds
Total locations: 201
SANITY CHECK:true
Time taken to convert location IDs to array: 1.3e-05 seconds
Number of readers: 8
Time taken to mark all local event files for reading: 0.007492 seconds
Time taken to mark all local event files for reading: 0.007555 seconds
Time taken to mark all local event files for reading: 0.007533 seconds
Time taken to mark all local event files for reading: 0.00817 seconds
Time taken to mark all local event files for reading: 0.008411 seconds
Time taken to mark all local event files for reading: 0.008388 seconds
Time taken to mark all local event files for reading: 0.008688 seconds
Time taken to mark all local event files for reading: 0.008706 seconds
Time taken to read events (task 6): 0.007385 seconds
Time taken to read events (task 7): 0.400417 seconds
Time taken to read events (task 5): 0.421307 seconds
Time taken to read events (task 1): 0.424622 seconds
Time taken to read events (task 4): 0.434175 seconds
Time taken to read events (task 2): 0.443446 seconds
Time taken to read events (task 3): 0.49999 seconds
Time taken to read events (task 0): 0.811525 seconds
Total time: 1.01967 secondsEvent Summary:
 Total number of events: 16613424
 Event types and their counts:
  Aggregated Enter events: 6989777
  Aggregated Leave events: 6989777
Total Unique Locations: 201
Total Unique Regions: 677
```


### otf2_read_events_distributed.chpl

A distributed version of reading otf2 files.
Built chapel with CHPL_COMM=gasnet
I ran it using oversubscription on my mac, so performance numbers mean nothing.

However, the correctness still matches python/C so it means that we have a working
distributed OTF2 reader in Chapel!!

275 Lines of code


#### Small trace:
```console
❯ make distributed && ./otf2_read_events_distributed -nl2
Compiling otf2_read_events_distributed.chpl...
chpl -M ../_chpl --fast otf2_read_events_distributed.chpl -I/opt/otf2/include -L/opt/otf2/lib -lotf2 -o otf2_read_events_distributed
Compilation successful!
Time taken to open initial OTF2 archive: 0.00 seconds
Number of locations: 32
Global definitions read: 368
Time taken to read global definitions: 0.00 seconds
Total locations: 32
SANITY CHECK:true
Time taken to convert location IDs to array: 9e-06 seconds
Number of readers: 2
Time taken to mark all local event files for reading: 0.004858 seconds
Time taken to mark all local event files for reading: 0.006026 seconds
Time taken to read events (task 0): 0.006629 seconds
Time taken to read events (task 1): 0.043379 seconds
Total time: 0.118591 seconds
Event Summary:
 Total number of events: 72670
 Event types and their counts:
  Aggregated Enter events: 40
  Aggregated Leave events: 40
Total Unique Locations: 32
Total Unique Regions: 21
```

#### Large trace:
```console
❯ ./otf2_read_events_distributed -nl2
Time taken to open initial OTF2 archive: 0.00 seconds
Number of locations: 201
Global definitions read: 2606
Time taken to read global definitions: 0.00 seconds
Total locations: 201
SANITY CHECK:true
Time taken to convert location IDs to array: 8e-06 seconds
Number of readers: 2
Time taken to mark all local event files for reading: 0.027561 seconds
Time taken to mark all local event files for reading: 0.027112 seconds
Time taken to read events (task 0): 1.48972 seconds
Time taken to read events (task 1): 3.86742 seconds
Total time: 50.3512 seconds
Event Summary:
 Total number of events: 16613424
 Event types and their counts:
  Aggregated Enter events: 6989777
  Aggregated Leave events: 6989777
Total Unique Locations: 201
Total Unique Regions: 677
```
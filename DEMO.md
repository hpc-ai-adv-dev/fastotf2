# OTF2 in Chapel: A Live Demo

This repo demonstrates the capabilities of the Open Trace Format 2 (OTF2) library within the Chapel programming language. The primary user-facing workflow is the Mason-based trace-to-table converter in `apps/FastOTF2Converter`, backed by the reusable FastOTF2 Chapel library. We will explore the format, compare implementations in Python and C, and showcase the Chapel implementation.

This work is part of a collaboration with Oak Ridge National Laboratory (ORNL) to enable high-performance trace analysis.
The bottleneck in these trace analysis workflows has been converting OTF2 traces into a data format that can be ingested
by data analytics tools like Pandas or Arkouda.
The goals of the analysis to be able to attribute power usage to sections of the code and understand the effects of power capping on the performance. This can help facilitate better efficiency-guided compiler optimizations, for greener HPC systems.

## 1. The OTF2 Format

**Open Trace Format 2 (OTF2)** is a highly scalable event trace data format. It is the default trace format for the Score-P toolkit for collecting traces.

Key characteristics:
- **Scalability**: Designed for massive traces on distributed systems.
- **Structure**:
    - **Anchor File (`.otf2`)**: The main entry point.
    - **Global Definitions**: Metadata about the system (clock properties, strings, regions).
    - **Local Definitions**: Per-process/thread mappings.
    - **Event Files**: The actual trace data (enter/leave regions, MPI sends/recvs).

What does the format look like?

A diagram can be seen in figure 1 of https://apps.fz-juelich.de/jsc-pubsystem/aigaion/attachments/AuthorCopy.pdf-542bcd6a238b2e4948f579f3449bd9bf.pdf


## 2. Showcase Objectives

In this demo, we will:
1.  Understand how to read OTF2 traces using **Python**.
2.  Look at the low-level **C API** required for reading traces.
3.  Introduce the **Chapel API** for OTF2.
4.  Walk through two key examples in Chapel:
    -   **Reading Events**: Basic traversal of a trace.
    -   **OTF2 to Table Output**: Converting binary trace data to tabular outputs such as CSV, with Parquet wiring prepared for later work.


## 3. High-Level Python Implementation

OTF2 has a python module which provides a high-level interface to OTF2, making it easy to prototype and analyze traces. However, for massive traces, performance can be a bottleneck.

The script `comparisons/python/otf2readevents.py` demonstrates how to open a trace and iterate through events.

### Key Concepts:
- `otf2.reader.open(archive_name)`: Opens the trace.
- `trace.events`: An iterator over all events in the trace.
- `otf2.events.Enter`, `otf2.events.Leave`: Event types.


## 4. Understanding the C API

The C API is the foundation of OTF2. It provides maximum performance but requires verbose setup.

To read events in C, you typically need to:
1.  **Create a reader handle**: Initialize the OTF2 reader.
2.  **Define Callbacks**: Write a separate C function for *every* event type you want to process (e.g., `Enter`, `Leave`).
3.  **Register Callbacks**: Manually link these functions to the reader.
4.  **Drive the Reader**: Call `OTF2_Reader_ReadAllGlobalEvents` to start the process.

**The "Rough Edges" of the C API:**
-   **Inversion of Control**: Unlike a simple `for` loop, you don't pull events; the library pushes them to you. This makes the control flow harder to follow.
-   **Manual State Management**: Since you are in a callback, you lose the local context of a loop. You must manually pass state (via `void*` user data) between callbacks to track call stacks or timelines.
-   **Verbosity**: You need to define structs and memory management logic just to store basic data, adding significant boilerplate code.
-   **Completeness Burden**: If you want to handle "all events", you must register a handler for every single event type defined in the spec, or they are silently ignored.

The file `comparisons/c/otf2_read_events.c` shows this approach.


## 5. Exploring the Chapel API

The reusable Chapel modules are located in `src/` and provide a bridge between the raw speed of C and the usability of high-level languages.

**Why Chapel?**
-   **Better Data Structures**: Chapel's rich standard library (Maps, Lists, Records) replaces the manual memory management required in C.
-   **Simplified State**: We can use Chapel classes to encapsulate the state passed to callbacks, making the "user data" handling easier.
-   **C Interoperability**: We still call the optimized C functions directly, but wrap them in a layer that feels like modern code.

Key modules:
-   `OTF2.chpl`: Main entry point.
-   `OTF2_Reader.chpl`: Handles opening and reading archives.
-   `OTF2_Events.chpl`: Event definitions.


## 6. Example: Reading Events

This example demonstrates a simple event reader in Chapel. It mimics the functionality of the C example but with cleaner syntax.

We will compile and run the root Mason example `example/FastOtf2ReadEvents.chpl`.


## 7. Example: OTF2 to Table Conversion

This example is more complex. It reads definitions to understand regions and metrics, and then iterates over events to produce table-oriented output files.

We will compile and run the `FastOTF2Converter` application package through Mason.

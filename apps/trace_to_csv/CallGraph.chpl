// Copyright Hewlett Packard Enterprise Development LP.

module CallGraphModule {
  use List;
  use Sort;
  import Math.inf;

  record interval {
    var start: real;
    var end: real;         // meaningful only if hasEnd == true
    var depth: int;
    var name: string;
    var hasEnd: bool;

    proc init() { // We need this version so our compiler doesn't complain about the comparator
      this.start = 0.0;
      this.end = 0.0;
      this.depth = 0;
      this.name = "";
      this.hasEnd = false;
    }
    proc init(start: real,
              end: real = 0.0,
              depth: int = 0,
              name: string = "",
              hasEnd: bool = false) {
      this.start = start;
      this.end = end;
      this.depth = depth;
      this.name = name;
      this.hasEnd = hasEnd;
    }

    proc isActive(t: real): bool {
      if hasEnd then
        return start <= t && t < end;
      else
        return start <= t;
    }

    proc realEnd(): real {
      return if hasEnd then end else inf;
    }

    proc hasOverlap(other: interval): bool {
      return start < other.realEnd() && other.start < realEnd();
    }

    proc clip(rangeStart: real, rangeEnd: real): interval {
      const rangeIv = new interval(rangeStart, rangeEnd, hasEnd=true);
      if !hasOverlap(rangeIv) then
        halt("Clip range does not overlap interval");
      const newStart = if start > rangeStart then start else rangeStart;
      const newEnd   = if hasEnd then (if end < rangeEnd then end else rangeEnd)
                                else rangeEnd;
      if newStart > newEnd then
        halt("Invalid clipped interval (negative length): start=" + newStart:string + " end=" + newEnd:string + " name=" + name);
      return new interval(newStart, newEnd, depth, name, hasEnd=true);
    }

    proc duration(): real {
      return if hasEnd then end - start else 0.0;
    }
  }

  // Base timeline supporting nested intervals (stack discipline)
  class Timeline {
    var finished: list(interval);
    var live: list(interval);

    proc enter(start: real, name: string) {
      var iv = new interval(start=start,
                            depth=live.size+1,
                            name=name,
                            hasEnd=false);
      live.pushBack(iv);
      return iv;
    }

    proc leave(end: real) {
      if live.isEmpty() then
        halt("No active intervals to leave");
      var iv = live.popBack();
      if iv.hasEnd then
        halt("interval already closed");
      iv.end = end;
      iv.hasEnd = true;
      finished.pushBack(iv);
    }

    proc getIntervalsBetween(rangeStart: real, rangeEnd: real): [] interval {
      if rangeStart > rangeEnd then
        halt("Start greater than end in getIntervalsBetween");

      var tmp: list(interval);

      // Finished intervals
      for iv in finished {
        if iv.hasOverlap(new interval(rangeStart, rangeEnd, hasEnd=true)) {
          tmp.pushBack(iv.clip(rangeStart, rangeEnd));
        }
      }
      // Live intervals (treat as ending at rangeEnd for clipping)
      for iv in live {
        if iv.hasOverlap(new interval(rangeStart, rangeEnd, hasEnd=true)) {
          const clipped =
            if iv.start < rangeStart
              then new interval(rangeStart, rangeEnd, iv.depth, iv.name, hasEnd=true)
              else new interval(iv.start, rangeEnd, iv.depth, iv.name, hasEnd=true);
          tmp.pushBack(clipped);
        }
      }

      // Move into array for sorting
      const n = tmp.size;
      var A: [0..#n] interval;
      var i = 0;
      for v in tmp { A[i] = v; i += 1; }

      // Sort by (start, end, depth)
      sort(A, comparator = new intervalComparator());

      return A;
    }
  }

  record intervalComparator : relativeComparator {}
  proc intervalComparator.compare(x: interval, y: interval): int {
    if x.start < y.start then return -1;
    else if x.start > y.start then return 1;
    else {
      if x.realEnd() < y.realEnd() then return -1;
      else if x.realEnd() > y.realEnd() then return 1;
      else {
        if x.depth < y.depth then return -1;
        else if x.depth > y.depth then return 1;
        else
          return 0;
      }
    }
  }

  // CallGraph extending Timeline
  class CallGraph : Timeline {
    proc depth(): int {
      return live.size;
    }
  }

  // Simple usage example
  // proc main() {
  //   var cg = new CallGraph();
  //   cg.enter(0.0, "A");
  //     cg.enter(1.0, "B");
  //     cg.leave(3.0);   // B
  //   cg.leave(5.0);     // A
  // }
}
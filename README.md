% Performance Profiling v1.0  
% Tamás Dezső  
% Oct 13, 2025  


Abstract
========

`Per4M` is a Makefile based tool that helps creating call graphs and
flamegraphs from so called call-graph records saved by `perf`. To
produce such visualizations it uses the `flamegraph`, `gprof2dot` and
`dot` programs.


Perf
====

Perf is a universal performance measurement tool widely available on
Linux that does not need the code or the build system be modified to
work.

- [Perf Wiki](https://perfwiki.github.io/main/)
- [Brendan Gregg's Perf Examples](https://www.brendangregg.com/perf.html)

Profiling generally requires running the system under a representative
workload for a sufficient period of time to collect meaningful kernel
counters and stack traces. In practice, this means it’s best to create
an automated test that drives the module under test through a realistic
and broad usage scenario, ensuring that the collected performance data
accurately reflects typical behavior.


Statistics
----------

```bash
# Detailed CPU counter statistics (includes extras) for the specified command:
perf stat --detailed command

# CPU counter statistics for the process with the given PID, for 10 seconds:
perf stat -P PID sleep 10
```

E.g.,
```bash
perf stat --detailed sfw_m -c mtest/sm_sip/perf/sfw.sm_sip.cfg -s sch/sfw.sm_sip.cfg.sch
2025-10-03T23:56:43.371 sfw_m.c(685): Termination/interrupt signal received

 Performance counter stats for 'sfw_m -c mtest/sm_sip/perf/sfw.sm_sip.cfg -s sch/sfw.sm_sip.cfg.sch':

         18,892.05 msec task-clock:u              #    0.850 CPUs utilized          
                 0      context-switches:u        #    0.000 /sec                   
                 0      cpu-migrations:u          #    0.000 /sec                   
            77,230      page-faults:u             #    4.088 K/sec                  
    39,176,791,862      cycles:u                  #    2.074 GHz                      (50.02%)
    71,847,258,254      instructions:u            #    1.83  insn per cycle           (62.57%)
    16,428,509,700      branches:u                #  869.599 M/sec                    (62.51%)
        98,922,997      branch-misses:u           #    0.60% of all branches          (62.57%)
    17,082,532,700      L1-dcache-loads:u         #  904.218 M/sec                    (62.52%)
       991,169,722      L1-dcache-load-misses:u   #    5.80% of all L1-dcache accesses  (62.52%)
        10,095,019      LLC-loads:u               #  534.353 K/sec                    (49.96%)
           727,378      LLC-load-misses:u         #    7.21% of all LL-cache accesses  (49.89%)

      22.214520545 seconds time elapsed

      11.389845000 seconds user
       7.444356000 seconds sys
```


Diagnostics Report
------------------

```bash
perf list # shows available CPU performance measurement counters
perf record -e branches,branch-misses,cache-references,cache-misses -b command # writes perf.data
perf report # displays report from perf.data
```

Then the report is browsable and even hot paths can be annotated with
assembly and C source lines.

- `branches` and `branch-misses` measure how often branches occur and how frequently they are mispredicted.
- `cache-references` and `cache-misses` track overall cache accesses and misses across all cache levels.
- `L1-dcache-loads` and `L1-dcache-load-misses` show how often data loads miss in the L1 data cache.


FlameGraph
==========

FlameGraph is a visualization of stack traces of profiled software
so that the most frequent code-paths can be identified quickly and
accurately

- [Brendan Gregg's FlameGraph Page](https://www.brendangregg.com/flamegraphs.html)
- [FlameGraph on GitHub](https://github.com/brendangregg/FlameGraph)

```bash
git clone https://github.com/brendangregg/FlameGraph
FG=${PWD}/FlameGraph

perf record --call-graph lbr command # lbr: Last Branch Record

perf script \
    | ${FG}/stackcollapse-perf.pl \
    | ${FG}/flamegraph.pl \
    > xy_module_flamegraph.svg
```


Call Graph
==========

`gprof2dot` is a Python script to convert the output from many profilers
(e.g., perf) into a dot graph. The call graph is generated from perf and
gprof2dot visualizes how functions in the program call each other and
where the CPU time is spent.

[gprof2dot on GitHub](https://github.com/jrfonseca/gprof2dot)

```bash
git clone https://github.com/jrfonseca/gprof2dot
# gprof2dot/gprof2dot.py

# dot file output to interactively browse with xdot:
perf script \
    | gprof2dot -f perf \
    > callgraph.dot

# pdf output
dot -Tpdf -o callgraph.pdf < callgraph.dot
```


Per4M
=====

Record call graph data of the `command` and generate call graph and
flamegraph via the Makefile. Tune the parameters inside the Makefile if
needed.

```bash
perf record --call-graph lbr command
perf script > perf.script
NAME=my_program SUB=subtitle make
# outputs:
# $(NAME)_callgraph_YYYY-MM-DD.dot
# $(NAME)_callgraph_YYYY-MM-DD.pdf
# $(NAME)_flamegraph_YYYY-MM-DD.svg
```

With the Docker wrapper the `perf script` step is handled for you:

```bash
perf record --call-graph lbr command
per4m.sh all NAME=my_program SUB=subtitle
```

If `per4m`, `flamegraph` and `gprof2dot` are available elsewhere, make
`perf` produce text output from the recorded data, and use it on the
remote to create the graphs, e.g.,

```bash
perf script > perf.script
scp perf.script user@elswhere:path
ssh user@elsewhere
cd git/per4m
make
```


Makefile Targets and Variables
------------------------------

The Makefile expects to find a `perf.script` in the current directory;
it never invokes `perf` itself. Produce it on the machine that recorded
the data (`perf script > perf.script`) — the [`per4m.sh`](per4m.sh)
wrapper does this automatically from `perf.data`. The intermediate
`perf.script.flt` filters out common noise (`@plt` stubs,
`__libc_start_main`, `_start`, `main`).

Targets:

- `all` (default) — build both the call graph and the flamegraph.
- `cg`, `callgraph` — build `$(NAME)_callgraph_YYYY-MM-DD.pdf` (via `.dot`).
- `fg`, `flamegraph` — build `$(NAME)_flamegraph_YYYY-MM-DD.svg`.
- `doc` — render `README.md` to `Per4M_v1.0.pdf` (requires `pandoc` +
  XeLaTeX + the `Ubuntu Mono` font; not installed in the Docker image).
- `clean` — remove generated `*.doc`, `*.flt`, `*.svg`, `*.dot`, `*.pdf`.
- `rebuild` — `clean` followed by `all`.

Variables (override on the `make` command line or via the environment):

| Variable                   | Default                    | Purpose                                                   |
| -------------------------- | -------------------------- | --------------------------------------------------------- |
| `NAME`                     | `perf`                     | Prefix used for the output file names.                    |
| `SUB`                      | *(empty)*                  | Flamegraph subtitle.                                      |
| `FLAMEGRAPH_DIR`           | `$(HOME)/git/FlameGraph`   | Path to a `brendangregg/FlameGraph` checkout.             |
| `CALLGRAPH_NODE_THRES_PCT` | `0.5`                      | `gprof2dot` node prune threshold (percent).               |
| `CALLGRAPH_EDGE_THRES_PCT` | `0.1`                      | `gprof2dot` edge prune threshold (percent).               |
| `CALLGRAPH_THEME_SKEW`     | `0.05`                     | `gprof2dot` color skew (< 1 emphasizes lower percentages).|


Docker Wrapper
==============

For hosts that don't have `gprof2dot`, `graphviz` or FlameGraph
installed — or for reproducibility — the repository ships a
[`Dockerfile`](Dockerfile) and a driver script
[`per4m.sh`](per4m.sh) that bundle everything into a throwaway
container.

The split is deliberate: `perf` runs on the **host**, where the kernel,
the binaries and their debug symbols live; the container only does the
visualization.

What is in the image
--------------------

Based on `debian:bookworm-slim`, the image includes:

- `gprof2dot`, `graphviz` (`dot`), `perl` — turn `perf.script` into
  callgraphs.
- A shallow clone of
  [`brendangregg/FlameGraph`](https://github.com/brendangregg/FlameGraph)
  at `/opt/FlameGraph`.
- The Per4M `Makefile` at `/opt/per4m/Makefile`.
- `make`, `python3`, `git`, `sed`, `grep`, `less`, `bash`.

The `doc` target's dependencies (`pandoc`, `texlive-xetex`,
`fonts-ubuntu`) are intentionally **not** installed to keep the image
small. Add them to the Dockerfile if you need `make doc`.

Requirements on the host
------------------------

- Docker (or a compatible engine exposing the `docker` CLI).
- `perf`, for recording and for converting `perf.data` to `perf.script`.
  It is **not** installed in the image. If you already have a
  `perf.script` (e.g. copied from another machine), `perf` is not needed.

Building the image
------------------

```bash
./per4m.sh build          # explicit build
# or just run any command; the script auto-builds on first use.
```

The tag defaults to `per4m:latest`; override with `PER4M_IMAGE=my/tag`.

Running the pipeline
--------------------

`per4m.sh` first runs `perf script` on the host whenever `perf.data` is
newer than `perf.script`, then mounts the current directory into `/work`
inside a disposable (`--rm`) container and forwards its arguments to
`make` against the baked-in Makefile. Files are written back to the host
under your own UID/GID, so nothing ends up root-owned.

```bash
perf record --call-graph lbr my_program
cd /path/with/perf.data          # or perf.script
/path/to/Per4M/per4m.sh all NAME=my_program SUB="run 1"
/path/to/Per4M/per4m.sh cg  NAME=my_program
/path/to/Per4M/per4m.sh fg  NAME=my_program SUB="hot path"
/path/to/Per4M/per4m.sh clean
```

Any `make` variable can be passed the same way, e.g.
`CALLGRAPH_NODE_THRES_PCT=1.0`. Symlinking `per4m.sh` into a directory
on `PATH` is convenient.

Interactive shell
-----------------

To poke around manually (inspect intermediates, run individual pipeline
stages):

```bash
./per4m.sh shell
# inside the container:
make -f /opt/per4m/Makefile cg NAME=my_program
less perf.script
```

The container is removed as soon as you `exit`.

Script usage
------------

```
Usage: per4m.sh COMMAND [ARGS...]

Commands:
  build              Build the Docker image.
  shell              Interactive bash; CWD mounted at /work.
  <make-target> ...  Run 'make <target> ARGS...' inside the container.

Environment:
  PER4M_IMAGE        Override docker image tag (default: per4m:latest).
  PERF_DATA          Perf recording to convert (default: perf.data).
  PERF_SCRIPT        Text dump handed to the container (default: perf.script).
```


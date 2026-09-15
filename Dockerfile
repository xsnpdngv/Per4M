# Container image with everything the Per4M Makefile needs to turn a
# host-generated perf.script into callgraphs and flamegraphs.
#
# perf itself is deliberately NOT installed: recording and `perf script`
# happen on the host, where the kernel, symbols and debug info live.
#
# Base: debian:bookworm-slim
#   - Small footprint (slim variant strips docs/locales) yet a full apt
#     ecosystem, so we don't have to reach for source builds.
#   - Stable/LTS-ish release cadence keeps rebuilds reproducible.
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        make \
        perl \
        python3 \
        python3-pip \
        graphviz \
        ca-certificates \
        git \
        sed \
        grep \
        less \
        bash \
    && pip3 install --no-cache-dir --break-system-packages gprof2dot \
    && rm -rf /var/lib/apt/lists/*

# FlameGraph is a set of Perl scripts; clone once and bake it in.
RUN git clone --depth 1 https://github.com/brendangregg/FlameGraph.git /opt/FlameGraph

# Ship the Makefile so callers don't need the Per4M checkout mounted.
# The directory is created explicitly first: with BuildKit, COPY --chmod
# applies its mode to auto-created parent directories too, which would
# strip the traversal (x) bit and make /opt/per4m unenterable.
RUN mkdir -p /opt/per4m
COPY --chmod=0644 Makefile /opt/per4m/Makefile

ENV FLAMEGRAPH_DIR=/opt/FlameGraph \
    HOME=/tmp

WORKDIR /work

CMD ["/bin/bash"]

# Container image with everything the Per4M Makefile needs to turn a
# pre-recorded perf.data / perf.script into callgraphs and flamegraphs.
#
# Base: debian:bookworm-slim
#   - Small footprint (slim variant strips docs/locales) yet a full apt
#     ecosystem, so we don't have to reach for source builds.
#   - Ships `linux-perf`, a wrapper that transparently picks a matching
#     perf binary; that's the one non-trivial dependency here and it is
#     awkward to get on Alpine (musl) or on distroless images.
#   - Stable/LTS-ish release cadence keeps rebuilds reproducible.
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        make \
        perl \
        python3 \
        python3-pip \
        graphviz \
        linux-perf \
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

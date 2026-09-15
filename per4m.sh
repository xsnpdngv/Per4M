#!/usr/bin/env bash
# Driver for the Per4M container.
#
# perf runs on the host: this script converts perf.data into perf.script
# locally, then builds the image on demand, mounts the caller's current
# directory into /work inside a throwaway container (--rm) and either runs
# `make` with the Per4M Makefile or drops the user into an interactive shell.

set -euo pipefail

IMAGE_NAME="${PER4M_IMAGE:-per4m:latest}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTAINER_MAKEFILE="/opt/per4m/Makefile"
CONTAINER_FLAMEGRAPH_DIR="/opt/FlameGraph"
PERF_DATA="${PERF_DATA:-perf.data}"
PERF_SCRIPT="${PERF_SCRIPT:-perf.script}"

usage() {
    cat <<EOF
Usage: $(basename "$0") COMMAND [ARGS...]

Record on the host first, then let Per4M do the rest:

  perf record --call-graph lbr <command>
  $(basename "$0") all NAME="<command>"

Commands:
  build              Build the Docker image (${IMAGE_NAME}).
  shell              Interactive bash in the container; CWD mounted at /work.
                     Exit with 'exit'; the container is removed automatically.
  <make-target> ...  Run 'make <target> ...' inside the container against the
                     baked-in Per4M Makefile. Extra ARGS are forwarded verbatim
                     to make (e.g. NAME=... SUB=...).

Common make targets: all, cg (callgraph), fg (flamegraph), clean, rebuild.

Examples:
  $(basename "$0") build
  $(basename "$0") shell
  $(basename "$0") all  NAME=my_program SUB="run 1"
  $(basename "$0") cg   NAME=my_program
  $(basename "$0") fg   NAME=my_program SUB="hot path"
  $(basename "$0") clean

Environment:
  PER4M_IMAGE   Override docker image tag (default: per4m:latest).
  PERF_DATA     Perf recording to convert (default: perf.data).
  PERF_SCRIPT   Text dump handed to the container (default: perf.script).
EOF
}

# perf lives on the host only: turn PERF_DATA into PERF_SCRIPT if needed.
ensure_perf_script() {
    if [[ -f "${PERF_DATA}" ]]; then
        if [[ ! -f "${PERF_SCRIPT}" || "${PERF_DATA}" -nt "${PERF_SCRIPT}" ]]; then
            if ! command -v perf >/dev/null 2>&1; then
                echo "perf not found on the host; cannot convert ${PERF_DATA}." >&2
                exit 1
            fi
            echo "Generating ${PERF_SCRIPT} from ${PERF_DATA}..." >&2
            perf script -i "${PERF_DATA}" > "${PERF_SCRIPT}"
        fi
    elif [[ ! -f "${PERF_SCRIPT}" ]]; then
        echo "Neither ${PERF_DATA} nor ${PERF_SCRIPT} exist." >&2
        echo "Record first:  perf record --call-graph lbr <command>" >&2
        exit 1
    fi
}

image_exists() {
    docker image inspect "${IMAGE_NAME}" >/dev/null 2>&1
}

ensure_image() {
    if ! image_exists; then
        echo "Image '${IMAGE_NAME}' not found; building..." >&2
        do_build
    fi
}

do_build() {
    docker build -t "${IMAGE_NAME}" "${SCRIPT_DIR}"
}

# Assemble docker run flags common to all invocations.
docker_run() {
    local -a tty_flags=()
    if [[ -t 0 && -t 1 ]]; then
        tty_flags=(-it)
    fi

    local -a user_flags=(--user "$(id -u):$(id -g)")

    docker run --rm "${tty_flags[@]}" "${user_flags[@]}" \
        -v "${PWD}:/work" \
        -w /work \
        "${IMAGE_NAME}" \
        "$@"
}

if [[ $# -eq 0 ]]; then
    usage
    exit 0
fi

case "$1" in
    -h|--help|help)
        usage
        ;;
    build)
        shift
        do_build "$@"
        ;;
    shell)
        shift
        ensure_image
        # Interactive shell; user can invoke `make -f $CONTAINER_MAKEFILE ...`
        # manually. FLAMEGRAPH_DIR is already exported in the image.
        docker_run /bin/bash "$@"
        ;;
    clean)
        ensure_image
        docker_run make -f "${CONTAINER_MAKEFILE}" \
            "FLAMEGRAPH_DIR=${CONTAINER_FLAMEGRAPH_DIR}" "$@"
        ;;
    *)
        ensure_perf_script
        ensure_image
        docker_run make -f "${CONTAINER_MAKEFILE}" \
            "FLAMEGRAPH_DIR=${CONTAINER_FLAMEGRAPH_DIR}" "$@"
        ;;
esac

#!/usr/bin/env bash
# Driver for the Per4M container.
#
# Builds the image on demand, mounts the caller's current directory into
# /work inside a throwaway container (--rm) and either runs `make` with
# the Per4M Makefile or drops the user into an interactive shell.

set -euo pipefail

IMAGE_NAME="${PER4M_IMAGE:-per4m:latest}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTAINER_MAKEFILE="/opt/per4m/Makefile"
CONTAINER_FLAMEGRAPH_DIR="/opt/FlameGraph"

usage() {
    cat <<EOF
Usage: $(basename "$0") COMMAND [ARGS...]

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
EOF
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
    *)
        ensure_image
        docker_run make -f "${CONTAINER_MAKEFILE}" \
            "FLAMEGRAPH_DIR=${CONTAINER_FLAMEGRAPH_DIR}" "$@"
        ;;
esac

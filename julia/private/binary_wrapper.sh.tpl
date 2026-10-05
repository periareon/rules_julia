#!/usr/bin/env bash

if [[ -z "${RUNFILES_DIR:-}" && -z "${RUNFILES_MANIFEST_FILE:-}" ]]; then
    if [[ -d "$0.runfiles" ]]; then
        export RUNFILES_DIR="$0.runfiles"
    elif [[ -d "$0.exe.runfiles" ]]; then
        export RUNFILES_DIR="$0.exe.runfiles"
    elif [[ -f "$0.runfiles_manifest" ]]; then
        export RUNFILES_MANIFEST_FILE="$0.runfiles_manifest"
    elif [[ -f "$0.exe.runfiles_manifest" ]]; then
        export RUNFILES_MANIFEST_FILE="$0.exe.runfiles_manifest"
    else
        echo >&2 "ERROR: cannot find runfiles"
        exit 1
    fi
fi

# {RUNFILES_API}

set -euo pipefail

INTERPRETER="$(rlocation "{interpreter}")"
ENTRYPOINT="$(rlocation "{entrypoint}")"
CONFIG="$(rlocation "{config}")"
MAIN="$(rlocation "{main}")"

runfiles_export_envvars

# Remove noisy variables
export -n -f "__runfiles_maybe_grep"
export -n -f "rlocation"
export -n -f "runfiles_current_repository"
export -n -f "runfiles_export_envvars"
export -n -f "runfiles_rlocation_checked"

# Scratch depot for any run-time compilation. Never write into the output tree.
if [ -n "${TEST_TMPDIR:-}" ]; then
    WRITABLE_DEPOT="${TEST_TMPDIR}/rules_julia_depot"
else
    WRITABLE_DEPOT="${TMPDIR:-/tmp}/rules_julia_depot"
fi

# The trailing empty entry expands to Julia's bundled depots (stdlib caches)
# and excludes the user depot (`~/.julia`).
export JULIA_DEPOT_PATH="${WRITABLE_DEPOT}:"

# Only the active project and the stdlib are visible. Library include paths
# are appended by the entrypoint. Nothing from the caller's shell leaks in.
export JULIA_LOAD_PATH="@:@stdlib"
unset JULIA_PROJECT

export JULIA_PKG_PRECOMPILE_AUTO=0

# Check if BAZEL_TEST is set in the environment and if so export JULIA_PKG_OFFLINE=true
if [ -n "${BAZEL_TEST+set}" ]; then
    export JULIA_PKG_OFFLINE=true
fi

# Libraries are precompiled at build time and found via DEPOT_PATH. Tests
# never write caches: anything without a build-time cache is evaluated from
# source. `bazel run` keeps a persistent scratch depot and may compile into it.
# Override with RULES_JULIA_COMPILED_MODULES=yes|no|existing|strict.
if [ -n "${BAZEL_TEST+set}" ]; then
    COMPILED_MODULES="{test_compiled_modules}"
else
    COMPILED_MODULES="yes"
fi
COMPILED_MODULES="${RULES_JULIA_COMPILED_MODULES:-${COMPILED_MODULES}}"

# Optional custom system image.
SYSIMAGE="{sysimage}"
SYSIMAGE_FLAGS=()
if [ -n "${SYSIMAGE}" ]; then
    SYSIMAGE_FLAGS=("--sysimage=$(rlocation "${SYSIMAGE}")")
fi

# Execute Julia with the entrypoint
exec \
    "${INTERPRETER}" \
    ${SYSIMAGE_FLAGS[@]+"${SYSIMAGE_FLAGS[@]}"} \
    --compiled-modules="${COMPILED_MODULES}" \
    "${ENTRYPOINT}" \
    "${CONFIG}" \
    "${MAIN}" \
    -- \
    "$@"

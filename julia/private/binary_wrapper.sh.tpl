#!/usr/bin/env bash

# --- begin runfiles.bash initialization v3 ---
# Copy-pasted from the Bazel Bash runfiles library v3.
set -uo pipefail; set +e; f=bazel_tools/tools/bash/runfiles/runfiles.bash
# shellcheck disable=SC1090
source "${RUNFILES_DIR:-/dev/null}/$f" 2>/dev/null || \
  source "$(grep -sm1 "^$f " "${RUNFILES_MANIFEST_FILE:-/dev/null}" | cut -f2- -d' ')" 2>/dev/null || \
  source "$0.runfiles/$f" 2>/dev/null || \
  source "$(grep -sm1 "^$f " "$0.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null || \
  source "$(grep -sm1 "^$f " "$0.exe.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null || \
  { echo>&2 "ERROR: cannot find $f"; exit 1; }; f=; set -e
# --- end runfiles.bash initialization v3 ---

set -euo pipefail

INTERPRETER="$(rlocation "{interpreter}")"
ENTRYPOINT="$(rlocation "{entrypoint}")"
CONFIG="$(rlocation "{config}")"
MAIN="$(rlocation "{main}")"

RULES_JULIA_EXPERIMENTAL_ENTRYPOINT_INCLUDE="{experimental_entrypoint_use_include}"

runfiles_export_envvars

# Remove noisy variables
export -n -f "__runfiles_maybe_grep"
export -n -f "rlocation"
export -n -f "runfiles_current_repository"
export -n -f "runfiles_export_envvars"
export -n -f "runfiles_rlocation_checked"

# Set up JULIA_DEPOT_PATH
if [ -n "${RUNFILES_DIR:-}" ]; then
    # Get parent directory of RUNFILES_DIR and create .depot next to it
    RUNFILES_PARENT="${RUNFILES_DIR%/*}"
    DEPOT_DIR="${RUNFILES_PARENT}/.depot"
elif [ -n "${RUNFILES_MANIFEST_FILE:-}" ]; then
    # Pure bash implementation to get directory path
    # Remove everything after the last '/' to get the directory, then go up one level
    MANIFEST_DIR="${RUNFILES_MANIFEST_FILE%/*}"
    MANIFEST_PARENT="${MANIFEST_DIR%/*}"
    DEPOT_DIR="${MANIFEST_PARENT}/.depot"
else
    echo>&2 "ERROR: Neither RUNFILES_DIR nor RUNFILES_MANIFEST_FILE is set"
    exit 1
fi

# Ensure depot directory path is absolute
if [ "${DEPOT_DIR#/}" = "${DEPOT_DIR}" ]; then
    # Path doesn't start with /, make it absolute
    DEPOT_DIR="$(pwd)/${DEPOT_DIR}"
fi

export JULIA_DEPOT_PATH="${DEPOT_DIR}"
export RULES_JULIA_DEPOT_PATH="${DEPOT_DIR}"
export JULIA_PKG_PRECOMPILE_AUTO=0

# Check if BAZEL_TEST is set in the environment and if so export JULIA_PKG_OFFLINE=true
# This checks if BAZEL_TEST is set (even to empty string) using parameter expansion
if [ -n "${BAZEL_TEST+set}" ]; then
    export JULIA_PKG_OFFLINE=true
fi


if [[ "${RULES_JULIA_EXPERIMENTAL_ENTRYPOINT_INCLUDE}" == "True" ]]; then
    export RULES_JULIA_EXPERIMENTAL_ENTRYPOINT_INCLUDE
fi

# Execute Julia with the entrypoint
exec \
    "${INTERPRETER}" \
    --compiled-modules=no \
    "${ENTRYPOINT}" \
    "${CONFIG}" \
    "${MAIN}" \
    -- \
    "$@"

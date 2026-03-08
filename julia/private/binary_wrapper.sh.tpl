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

runfiles_export_envvars

# Remove noisy variables
export -n -f "__runfiles_maybe_grep"
export -n -f "rlocation"
export -n -f "runfiles_current_repository"
export -n -f "runfiles_export_envvars"
export -n -f "runfiles_rlocation_checked"

# Create a writable depot for any runtime compilation needs
if [ -n "${RUNFILES_DIR:-}" ]; then
    RUNFILES_PARENT="${RUNFILES_DIR%/*}"
    WRITABLE_DEPOT="${RUNFILES_PARENT}/.depot"
elif [ -n "${RUNFILES_MANIFEST_FILE:-}" ]; then
    MANIFEST_DIR="${RUNFILES_MANIFEST_FILE%/*}"
    MANIFEST_PARENT="${MANIFEST_DIR%/*}"
    WRITABLE_DEPOT="${MANIFEST_PARENT}/.depot"
else
    echo>&2 "ERROR: Neither RUNFILES_DIR nor RUNFILES_MANIFEST_FILE is set"
    exit 1
fi

# Ensure writable depot path is absolute
if [ "${WRITABLE_DEPOT#/}" = "${WRITABLE_DEPOT}" ]; then
    WRITABLE_DEPOT="$(pwd)/${WRITABLE_DEPOT}"
fi

# Trailing colon causes Julia to append its system depot (stdlib compiled caches).
export JULIA_DEPOT_PATH="${WRITABLE_DEPOT}:"

export RULES_JULIA_DEPOT_PATH="${WRITABLE_DEPOT}"
export JULIA_PKG_PRECOMPILE_AUTO=0

# Check if BAZEL_TEST is set in the environment and if so export JULIA_PKG_OFFLINE=true
if [ -n "${BAZEL_TEST+set}" ]; then
    export JULIA_PKG_OFFLINE=true
fi

# Default to no compiled modules. Opt in with RULES_JULIA_COMPILED_MODULES=1.
COMPILED_MODULES="no"
if [ "${RULES_JULIA_COMPILED_MODULES:-}" = "1" ]; then
    COMPILED_MODULES="yes"
fi

# Execute Julia with the entrypoint
exec \
    "${INTERPRETER}" \
    --compiled-modules="${COMPILED_MODULES}" \
    "${ENTRYPOINT}" \
    "${CONFIG}" \
    "${MAIN}" \
    -- \
    "$@"

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

RULES_JULIA_STANDALONE_APP="$(rlocation "{rules_julia_standalone_app}")"

runfiles_export_envvars

export -n -f "__runfiles_maybe_grep"
export -n -f "rlocation"
export -n -f "runfiles_current_repository"
export -n -f "runfiles_export_envvars"
export -n -f "runfiles_rlocation_checked"

# Execute Julia with the entrypoint
exec "${RULES_JULIA_STANDALONE_APP}" $@

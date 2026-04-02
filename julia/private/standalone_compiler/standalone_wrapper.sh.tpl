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

RULES_JULIA_STANDALONE_APP="$(rlocation "{rules_julia_standalone_app}")"

runfiles_export_envvars

export -n -f "__runfiles_maybe_grep"
export -n -f "rlocation"
export -n -f "runfiles_current_repository"
export -n -f "runfiles_export_envvars"
export -n -f "runfiles_rlocation_checked"

# Execute Julia with the entrypoint
exec "${RULES_JULIA_STANDALONE_APP}" $@

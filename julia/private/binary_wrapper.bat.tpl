@ECHO OFF

SETLOCAL ENABLEEXTENSIONS
SETLOCAL ENABLEDELAYEDEXPANSION

@REM Bootstrap runfiles location if not already set
if "%RUNFILES_DIR%"=="" if "%RUNFILES_MANIFEST_FILE%"=="" (
    if exist "%~f0.runfiles\" (
        set "RUNFILES_DIR=%~f0.runfiles"
    ) else if exist "%~f0.exe.runfiles\" (
        set "RUNFILES_DIR=%~f0.exe.runfiles"
    ) else if exist "%~f0.runfiles_manifest" (
        set "RUNFILES_MANIFEST_FILE=%~f0.runfiles_manifest"
    ) else if exist "%~f0.exe.runfiles_manifest" (
        set "RUNFILES_MANIFEST_FILE=%~f0.exe.runfiles_manifest"
    )
)

@REM {RUNFILES_API}

call :runfiles_export_envvars

call :rlocation "{interpreter}" INTERPRETER
call :rlocation "{entrypoint}" ENTRYPOINT
call :rlocation "{config}" CONFIG
call :rlocation "{main}" MAIN

@REM Scratch depot for any run-time compilation. Never write into the output tree.
if defined TEST_TMPDIR (
    set "WRITABLE_DEPOT=%TEST_TMPDIR%\rules_julia_depot"
) else (
    set "WRITABLE_DEPOT=%TEMP%\rules_julia_depot"
)

@REM Unset `RUNFILES_DIR` if the directory does not exist.
if not "%RUNFILES_DIR%"=="" (
    if not exist "%RUNFILES_DIR%" (
        set "RUNFILES_DIR="
    )
)

@REM The trailing empty entry expands to Julia's bundled depots (stdlib caches)
@REM and excludes the user depot.
set "JULIA_DEPOT_PATH=%WRITABLE_DEPOT%;"

@REM Only the active project and the stdlib are visible. Library include paths
@REM are appended by the entrypoint. Nothing from the caller's shell leaks in.
set "JULIA_LOAD_PATH=@;@stdlib"
set "JULIA_PROJECT="

set "JULIA_PKG_PRECOMPILE_AUTO=0"

@REM Check if BAZEL_TEST is set in the environment and if so set JULIA_PKG_OFFLINE=true
if defined BAZEL_TEST (
    set "JULIA_PKG_OFFLINE=true"
)

@REM Libraries are precompiled at build time and found via DEPOT_PATH. Tests
@REM never write caches: anything without a build-time cache is evaluated from
@REM source. `bazel run` keeps a persistent scratch depot and may compile into it.
@REM Override with RULES_JULIA_COMPILED_MODULES=yes|no|existing|strict.
set "COMPILED_MODULES=yes"
if defined BAZEL_TEST set "COMPILED_MODULES={test_compiled_modules}"
if not "%RULES_JULIA_COMPILED_MODULES%"=="" set "COMPILED_MODULES=%RULES_JULIA_COMPILED_MODULES%"

@REM Optional custom system image.
set "SYSIMAGE={sysimage}"
set "SYSIMAGE_FLAGS="
if not "%SYSIMAGE%"=="" (
    call :rlocation "%SYSIMAGE%" SYSIMAGE_PATH
    set "SYSIMAGE_FLAGS=--sysimage=!SYSIMAGE_PATH!"
)

@REM Execute Julia with the entrypoint
"%INTERPRETER%" ^
    %SYSIMAGE_FLAGS% ^
    --compiled-modules=%COMPILED_MODULES% ^
    "%ENTRYPOINT%" ^
    "%CONFIG%" ^
    "%MAIN%" ^
    -- ^
    %*

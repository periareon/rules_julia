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

@REM Create a writable depot for any runtime compilation needs
if not "%RUNFILES_DIR%"=="" (
    for %%F in ("%RUNFILES_DIR%") do set "RUNFILES_PARENT=%%~dpF"
    set "RUNFILES_PARENT=%RUNFILES_PARENT:~0,-1%"
    for %%F in ("%RUNFILES_PARENT%") do set "RUNFILES_PARENT=%%~dpF"
    set "RUNFILES_PARENT=%RUNFILES_PARENT:~0,-1%"
    set "WRITABLE_DEPOT=%RUNFILES_PARENT%\.depot"
) else if not "%RUNFILES_MANIFEST_FILE%"=="" (
    for %%F in ("%RUNFILES_MANIFEST_FILE%") do set "MANIFEST_PARENT=%%~dpF"
    set "MANIFEST_PARENT=%MANIFEST_PARENT:~0,-1%"
    for %%F in ("%MANIFEST_PARENT%") do set "MANIFEST_PARENT=%%~dpF"
    set "MANIFEST_PARENT=%MANIFEST_PARENT:~0,-1%"
    set "WRITABLE_DEPOT=%MANIFEST_PARENT%\.depot"
) else (
    echo>&2 ERROR: Neither RUNFILES_DIR nor RUNFILES_MANIFEST_FILE is set
    exit 1
)

@REM Ensure writable depot path is absolute
if "%WRITABLE_DEPOT:~1,1%" equ ":" goto :writable_path_is_absolute
if "%WRITABLE_DEPOT:~0,2%" equ "\\" goto :writable_path_is_absolute
set "WRITABLE_DEPOT=%CD%\%WRITABLE_DEPOT%"
:writable_path_is_absolute

@REM Unset `RUNFILES_DIR` if the directory does not exist.
if not "%RUNFILES_DIR%"=="" (
    if not exist "%RUNFILES_DIR%" (
        set "RUNFILES_DIR="
    )
)

@REM Trailing semicolon causes Julia to append its system depot (stdlib compiled caches).
set "JULIA_DEPOT_PATH=%WRITABLE_DEPOT%;"

set "RULES_JULIA_DEPOT_PATH=%WRITABLE_DEPOT%"
set "JULIA_PKG_PRECOMPILE_AUTO=0"

@REM Check if BAZEL_TEST is set in the environment and if so set JULIA_PKG_OFFLINE=true
if defined BAZEL_TEST (
    set "JULIA_PKG_OFFLINE=true"
)

@REM Default to no compiled modules. Opt in with RULES_JULIA_COMPILED_MODULES=1.
set "COMPILED_MODULES=no"
if "%RULES_JULIA_COMPILED_MODULES%"=="1" set "COMPILED_MODULES=yes"

@REM Execute Julia with the entrypoint
"%INTERPRETER%" ^
    --compiled-modules=%COMPILED_MODULES% ^
    "%ENTRYPOINT%" ^
    "%CONFIG%" ^
    "%MAIN%" ^
    -- ^
    %*

@ECHO OFF

SETLOCAL ENABLEEXTENSIONS
SETLOCAL ENABLEDELAYEDEXPANSION

@REM Usage of rlocation function:
@REM
@REM        call :rlocation <runfile_path> <abs_path>
@REM
@REM        The rlocation function maps the given <runfile_path> to its absolute
@REM        path and stores the result in a variable named <abs_path>. This
@REM        function fails if the <runfile_path> doesn't exist in mainifest file.
:: Start of rlocation
goto :rlocation_end
:rlocation
if "%~2" equ "" (
    echo>&2 ERROR: Expected two arguments for rlocation function.
    exit 1
)
if exist "%RUNFILES_DIR%" (
    set RUNFILES_MANIFEST_FILE=%RUNFILES_DIR%_manifest
)
if "%RUNFILES_MANIFEST_FILE%" equ "" (
    set RUNFILES_MANIFEST_FILE=%~f0.runfiles\MANIFEST
)
if not exist "%RUNFILES_MANIFEST_FILE%" (
    set RUNFILES_MANIFEST_FILE=%~f0.runfiles_manifest
)
set MF=%RUNFILES_MANIFEST_FILE:/=\%
if not exist "%MF%" (
    echo>&2 ERROR: Manifest file %MF% does not exist.
    exit 1
)
set runfile_path=%~1
set abs_path=
for /F "usebackq tokens=1*" %%a in ("%MF%") do (
    if "%%a" equ "!runfile_path!" (
        set abs_path=%%b
        goto :found_path
    )
)
:found_path
if "!abs_path!" equ "" (
    echo>&2 ERROR: !runfile_path! not found in runfiles manifest
    exit 1
)
set %~2=!abs_path!
exit /b 0
:rlocation_end


@REM Function to replace forward slashes with backslashes.
goto :slocation_end
:slocation
set "input=%~1"
set "varName=%~2"
set "output="

@REM Replace forward slashes with backslashes
set "output=%input:/=\%"

@REM Assign the sanitized path to the specified variable
set "%varName%=%output%"
exit /b 0
:slocation_end

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

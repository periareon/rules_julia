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

@REM Set up JULIA_DEPOT_PATH
if not "%RUNFILES_DIR%"=="" (
    REM Get parent directory of RUNFILES_DIR and create .depot next to it
    for %%F in ("%RUNFILES_DIR%") do set "RUNFILES_PARENT=%%~dpF"
    REM Remove trailing backslash and go up one level
    set "RUNFILES_PARENT=%RUNFILES_PARENT:~0,-1%"
    for %%F in ("%RUNFILES_PARENT%") do set "RUNFILES_PARENT=%%~dpF"
    set "RUNFILES_PARENT=%RUNFILES_PARENT:~0,-1%"
    set "DEPOT_DIR=%RUNFILES_PARENT%\.depot"
) else if not "%RUNFILES_MANIFEST_FILE%"=="" (
    REM Get parent directory of manifest file's directory
    for %%F in ("%RUNFILES_MANIFEST_FILE%") do set "MANIFEST_PARENT=%%~dpF"
    REM Remove trailing backslash and go up one level
    set "MANIFEST_PARENT=%MANIFEST_PARENT:~0,-1%"
    for %%F in ("%MANIFEST_PARENT%") do set "MANIFEST_PARENT=%%~dpF"
    set "MANIFEST_PARENT=%MANIFEST_PARENT:~0,-1%"
    set "DEPOT_DIR=%MANIFEST_PARENT%\.depot"
) else (
    echo>&2 ERROR: Neither RUNFILES_DIR nor RUNFILES_MANIFEST_FILE is set
    exit 1
)

@REM Ensure depot directory path is absolute
@REM Check if path starts with drive letter (e.g., "C:") or UNC path (e.g., "\\")
if "%DEPOT_DIR:~1,1%" equ ":" goto :path_is_absolute
if "%DEPOT_DIR:~0,2%" equ "\\" goto :path_is_absolute
@REM Path is not absolute, make it absolute
set "DEPOT_DIR=%CD%\%DEPOT_DIR%"
:path_is_absolute

@REM Unset `RUNFILES_DIR` if the directory does not exist.
if not "%RUNFILES_DIR%"=="" (
    if not exist "%RUNFILES_DIR%" (
        set "RUNFILES_DIR="
    )
)

set "JULIA_DEPOT_PATH=%DEPOT_DIR%"
set "RULES_JULIA_DEPOT_PATH=%DEPOT_DIR%"
set "JULIA_PKG_PRECOMPILE_AUTO=0"

@REM Check if BAZEL_TEST is set in the environment and if so set JULIA_PKG_OFFLINE=true
@REM Using "if defined" checks if the variable exists regardless of its value
if defined BAZEL_TEST (
    set "JULIA_PKG_OFFLINE=true"
)

@REM Execute Julia with the entrypoint
"%INTERPRETER%" ^
    --compiled-modules=no ^
    "%ENTRYPOINT%" ^
    "%CONFIG%" ^
    "%MAIN%" ^
    -- ^
    %*

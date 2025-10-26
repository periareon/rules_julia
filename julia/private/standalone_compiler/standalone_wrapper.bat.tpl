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

@REM Unset `RUNFILES_DIR` if the directory does not exist.
if not "%RUNFILES_DIR%"=="" (
    if not exist "%RUNFILES_DIR%" (
        set "RUNFILES_DIR="
    )
)

call :rlocation "{rules_julia_standalone_app}" RULES_JULIA_STANDALONE_APP

@REM Execute the standalone app.
"%RULES_JULIA_STANDALONE_APP%" %*

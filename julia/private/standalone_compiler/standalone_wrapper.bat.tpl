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

call :rlocation "{rules_julia_standalone_app}" RULES_JULIA_STANDALONE_APP

@REM Execute the standalone app.
"%RULES_JULIA_STANDALONE_APP%" %*

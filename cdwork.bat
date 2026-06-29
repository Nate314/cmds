@echo off
if exist "%TEMP%\_cdwork_result.txt" del "%TEMP%\_cdwork_result.txt"
pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0_run.ps1" cdwork
if exist "%TEMP%\_cdwork_result.txt" (
    set /p _CDWORK_DIR=<"%TEMP%\_cdwork_result.txt"
    del "%TEMP%\_cdwork_result.txt"
    cd /d "%_CDWORK_DIR%"
)

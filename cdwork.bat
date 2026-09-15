@echo off
setlocal enabledelayedexpansion
if exist "%TEMP%\_cdwork_result.txt" del "%TEMP%\_cdwork_result.txt"
pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0_run.ps1" cdwork
set "_CDWORK_DIR="
if exist "%TEMP%\_cdwork_result.txt" (
    set /p _CDWORK_DIR=<"%TEMP%\_cdwork_result.txt"
    del "%TEMP%\_cdwork_result.txt"
)
rem setlocal also saves/restores the current directory, so it silently undoes any "cd /d"
rem once this script ends. Bake _CDWORK_DIR into a literal value before endlocal wipes it,
rem then cd only after endlocal so the change survives past the script's implicit endlocal.
endlocal & set "_CDWORK_DIR=%_CDWORK_DIR%"
if defined _CDWORK_DIR cd /d "%_CDWORK_DIR%"

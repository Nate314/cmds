@echo off
pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0_run.ps1" utcnow %*

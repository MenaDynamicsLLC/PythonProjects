@echo off
setlocal DisableDelayedExpansion
title CLM Windows Optimizer
if not exist "%~dp0CLM-Windows-Optimizer.ps1" (
    echo Missing CLM-Windows-Optimizer.ps1. Extract all package files together first.
    pause
    exit /b 1
)
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0CLM-Windows-Optimizer.ps1"
if errorlevel 1 (
    echo The utility could not run. See the error above and README.md.
    pause
    exit /b 1
)
endlocal

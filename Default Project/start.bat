@echo off
REM ===========================================================================
REM  Barangay Complaint and Concern Reporting System
REM
REM  Double-click this file to start the server, then use the address it
REM  prints.
REM
REM  IMPORTANT: keep this black window open while you use the system.
REM  Closing it stops the server and the address will stop working.
REM ===========================================================================
title Barangay Complaint and Concern Reporting System - keep this window open

cd /d "%~dp0"

set "PS1=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"

if not exist "%PS1%" (
    echo.
    echo   ERROR: Windows PowerShell was not found on this computer.
    echo          This application needs Windows PowerShell 5.1 or newer.
    echo.
    pause
    exit /b 1
)

"%PS1%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0server.ps1" %*

echo.
echo   ===========================================================
echo    The server has stopped.
echo    http://localhost:8080/ will not work any more.
echo    Double-click start.bat again to start it back up.
echo   ===========================================================
echo.
pause
@echo off
setlocal
title Localhost ^& Port Diagnostic Toolkit

chcp 65001 >nul 2>&1

set "TOOLKIT_DIR=%~dp0"
set "MAIN_SCRIPT=%TOOLKIT_DIR%main.ps1"

REM Verify PowerShell availability
where powershell.exe >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo [ERROR] powershell.exe was not found in your system PATH.
    echo This toolkit requires PowerShell 5.1 or later to operate.
    pause
    exit /b 1
)

REM If a command-line argument was supplied (e.g. launcher.bat 5), run directly
if not "%~1"=="" (
    powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%MAIN_SCRIPT%" -Option "%~1"
    exit /b %ERRORLEVEL%
)

:MENU_LOOP
cls
echo ==============================================================================
echo       LOCAL HOST ^& PORT DIAGNOSTIC TOOLKIT (Windows 10 / 11 / Server)
echo ==============================================================================
echo.
echo   DIAGNOSTIC ^& MANAGEMENT OPTIONS:
echo.
echo    1. Localhost Connectivity Test               9. Firewall Diagnostics
echo    2. TCP Port Scanner - Local Machine         10. IPv4 Diagnostics
echo    3. Port Usage Inspector                     11. IPv6 Diagnostics
echo    4. Process Identification                   12. Port Conflict Resolution
echo    5. HTTP Server Diagnostics                 13. Project Hosting Assistant
echo    6. Python Dev Server Diagnostics           14. Generate Diagnostic Report
echo    7. Node.js / npm Dev Server Diagnostics    15. View Logs
echo    8. LAN Accessibility Test                   16. Exit
echo.
echo   [Tip: Enter a number from 1 to 16 and press Enter. Enter 'Q' to quit.]
echo ==============================================================================
echo.

set "choice="
set /p "choice=Select an option [1-16]: "

if not defined choice goto MENU_LOOP

set "choice=%choice:"=%"

if /i "%choice%"=="16" goto EXIT_TOOLKIT
if /i "%choice%"=="q" goto EXIT_TOOLKIT
if /i "%choice%"=="exit" goto EXIT_TOOLKIT
if /i "%choice%"=="quit" goto EXIT_TOOLKIT

set "valid=0"
for %%i in (1 2 3 4 5 6 7 8 9 10 11 12 13 14 15) do (
    if "%choice%"=="%%i" set "valid=1"
)

if "%valid%"=="0" (
    echo.
    echo [ERROR] Invalid selection "%choice%". Please type a number between 1 and 16.
    timeout /t 2 >nul
    goto MENU_LOOP
)

echo.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%MAIN_SCRIPT%" -Option "%choice%"
goto MENU_LOOP

:EXIT_TOOLKIT
echo.
echo Thank you for using the Localhost ^& Port Diagnostic Toolkit.
exit /b 0

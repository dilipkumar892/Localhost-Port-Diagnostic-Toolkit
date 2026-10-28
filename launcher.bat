@echo off
setlocal
set "TARGET=%~dp0Localhost-Port-Toolkit\launcher.bat"
if exist "%TARGET%" (
    call "%TARGET%" %*
) else (
    echo [ERROR] Could not find Localhost-Port-Toolkit\launcher.bat
    pause
)

@echo off
setlocal
cd /d "%~dp0"
title NitroSense Win10 Installer
echo.
echo NitroSense Win10 Installer
echo ==========================
echo.
echo This installs the generated build from:
echo   "%cd%\output"
echo.
echo Target location:
echo   "C:\Program Files\NitroSense"
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%cd%\internal\scripts\Install-FromOutput.ps1" -OutputDir "%cd%\output" -InstallRoot "%ProgramFiles%\NitroSense"
set EXITCODE=%ERRORLEVEL%
echo.
if not "%EXITCODE%"=="0" (
  echo Install failed with exit code %EXITCODE%.
) else (
  echo Install finished successfully.
)
echo.
pause
exit /b %EXITCODE%

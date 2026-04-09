@echo off
setlocal
cd /d "%~dp0"
title NitroSense Win10 Patcher
echo.
echo NitroSense Win10 Patcher
echo ========================
echo.
echo Put exactly one original Acer NitroSense zip file or one extracted NitroSense folder into:
echo   "%cd%\input"
echo.
echo When patching finishes, open:
echo   "%cd%\output"
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%cd%\internal\scripts\Patch-FromZip.ps1" -InputDir "%cd%\input" -OutputDir "%cd%\output" -WorkDir "%cd%\internal\work\patch-run"
set EXITCODE=%ERRORLEVEL%
echo.
if not "%EXITCODE%"=="0" (
  echo Patch failed with exit code %EXITCODE%.
) else (
  echo Patch finished successfully.
)
echo.
pause
exit /b %EXITCODE%

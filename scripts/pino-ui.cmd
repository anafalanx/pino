@echo off
setlocal

for %%I in ("%~dp0..") do set "PINO_ROOT=%%~fI"
set "PINO_TCLTK=%PINO_ROOT%\tcltk"
set "PINO_RUNTIME_BIN=%PINO_TCLTK%\bin"
set "PINO_WISH=%PINO_RUNTIME_BIN%\wish90.exe"
set "PINO_TCLSH=%PINO_RUNTIME_BIN%\tclsh90.exe"
set "PINO_APP=%PINO_ROOT%\tcl\app.tcl"
if not defined PINO_WORKSPACE set "PINO_WORKSPACE=%CD%"

if not exist "%PINO_WISH%" (
  >&2 echo Pino UI runtime not found: %PINO_WISH%
  exit /b 1
)

if not exist "%PINO_APP%" (
  >&2 echo Pino UI entrypoint not found: %PINO_APP%
  exit /b 1
)

set "PATH=%PINO_RUNTIME_BIN%;%PATH%"
if "%~1"=="--check" (
  "%PINO_TCLSH%" "%PINO_APP%" %*
) else if "%~1"=="--repo-check" (
  "%PINO_TCLSH%" "%PINO_APP%" %*
) else if "%~1"=="--gui-check" (
  "%PINO_TCLSH%" "%PINO_APP%" %*
) else (
  "%PINO_WISH%" "%PINO_APP%" %*
)
exit /b %ERRORLEVEL%
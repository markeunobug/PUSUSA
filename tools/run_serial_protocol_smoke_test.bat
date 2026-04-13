@echo off
setlocal

set PYTHON_EXE=C:\software\python\python.exe
set SCRIPT=%~dp0serial_protocol_smoke_test.py

if "%~1"=="" (
    set PORT=COM12
) else (
    set PORT=%~1
)

"%PYTHON_EXE%" "%SCRIPT%" --port "%PORT%" --mode basic

endlocal

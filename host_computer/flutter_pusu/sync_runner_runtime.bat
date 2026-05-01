@echo off
setlocal

set "PROJECT_DIR=C:\learning\pusu_V2\host_computer\flutter_pusu"
set "RUNNER_DIR=%PROJECT_DIR%\build\windows\x64\runner\Debug"

if not exist "%RUNNER_DIR%\flutter_pusu.exe" (
    echo runner Debug executable is missing. Run flutter build windows --debug first.
    exit /b 1
)

if not exist "%RUNNER_DIR%\data\flutter_assets" (
    echo runner Debug runtime data is missing. Run flutter build windows --debug first.
    exit /b 1
)

if not exist "%RUNNER_DIR%\flutter_windows.dll" (
    echo flutter_windows.dll is missing. Run flutter build windows --debug first.
    exit /b 1
)

echo runner\Debug runtime files are already in place.
exit /b 0

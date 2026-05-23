@echo off
setlocal

set "PROJECT_DIR=C:\learning\pusu_V2\host_computer\flutter_hello"
set "INSTALL_DIR=%PROJECT_DIR%\build\windows\x64\install_bundle"
set "RUNNER_DIR=%PROJECT_DIR%\build\windows\x64\runner\Debug"

if not exist "%INSTALL_DIR%\flutter_hello.exe" (
    echo install_bundle is missing. Run build/install first.
    exit /b 1
)

if not exist "%RUNNER_DIR%" (
    echo runner\\Debug directory is missing. Build the runner first.
    exit /b 1
)

echo Syncing runtime files into runner\Debug...

if exist "%RUNNER_DIR%\data" (
    rmdir /s /q "%RUNNER_DIR%\data"
)

xcopy "%INSTALL_DIR%\data" "%RUNNER_DIR%\data" /E /I /Y >nul
if errorlevel 1 (
    echo Failed to copy data directory.
    exit /b 1
)

copy /Y "%INSTALL_DIR%\flutter_windows.dll" "%RUNNER_DIR%\" >nul
copy /Y "%INSTALL_DIR%\flutter_libserialport_plugin.dll" "%RUNNER_DIR%\" >nul
copy /Y "%INSTALL_DIR%\serialport.dll" "%RUNNER_DIR%\" >nul

echo runner\Debug runtime sync complete.
exit /b 0

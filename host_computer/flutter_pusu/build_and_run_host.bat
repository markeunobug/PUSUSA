@echo off
setlocal

set "PROJECT_DIR=C:\learning\pusu_V2\host_computer\flutter_pusu"
set "FLUTTER_BIN=C:\learning\tools\flutter\bin\flutter.bat"
set "HOST_EXE=%PROJECT_DIR%\build\windows\x64\runner\Debug\flutter_pusu.exe"
set "VSDEV_CMD=C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"
set "WINDOWS_SDK_DIR=C:\Program Files (x86)\Windows Kits\10\"
set "WINDOWS_SDK_VERSION=10.0.18362.0\"

rem Optional proxy for faster Flutter dependency/tool downloads.
set "HTTP_PROXY=http://127.0.0.1:7897"
set "HTTPS_PROXY=http://127.0.0.1:7897"

rem Keep System32 before local tool shims so Flutter's batch file resolves
rem where.exe instead of the local where.cmd shim.
set "PATH=C:\Windows\System32;C:\Windows;C:\Windows\System32\Wbem;C:\Windows\System32\WindowsPowerShell\v1.0;C:\software\git\Git\cmd;C:\learning\tools\flutter\bin;%PATH%"

echo.
echo [1/3] Building Flutter Windows host app...
cd /d "%PROJECT_DIR%"
call "%FLUTTER_BIN%" build windows --debug
if errorlevel 1 (
    echo.
    echo Build failed.
    exit /b 1
)

echo.
echo [1.5/3] Building Windows runner with explicit SDK environment...
call "%VSDEV_CMD%" -host_arch=x64 -arch=x64 >nul
set "WindowsSdkDir=%WINDOWS_SDK_DIR%"
set "WindowsSDKVersion=%WINDOWS_SDK_VERSION%"
cmake --build "%PROJECT_DIR%\build\windows\x64" --config Debug --target flutter_pusu
if errorlevel 1 (
    echo.
    echo Runner build failed.
    exit /b 1
)

echo.
echo [2/3] Stopping old host app if running...
taskkill /F /IM flutter_pusu.exe >nul 2>nul

echo.
echo [3/3] Launching new host app...
start "" "%HOST_EXE%"

echo.
echo Host app rebuilt and launched:
echo %HOST_EXE%
exit /b 0

@echo off
setlocal EnableExtensions

set "ROOT_DIR=%~dp0"
pushd "%ROOT_DIR%" >nul
if errorlevel 1 (
    echo [ERROR] Unable to enter the project directory: %ROOT_DIR%
    exit /b 1
)

for /f "tokens=2" %%V in ('findstr /b /c:"version:" "pubspec.yaml"') do set "FULL_VERSION=%%V"
if not defined FULL_VERSION (
    echo [ERROR] Unable to read the version from pubspec.yaml.
    goto :failed
)

for /f "tokens=1 delims=+" %%V in ("%FULL_VERSION%") do set "APP_VERSION=%%V"
set "RELEASE_DIR=%ROOT_DIR%build\windows\x64\runner\Release"
set "ZIP_PATH=%ROOT_DIR%Inf-Dir-%APP_VERSION%-windows-x64.zip"

echo [1/4] Building viewer plugins...
call "%ROOT_DIR%plugins\build.bat"
if errorlevel 1 goto :failed

echo.
echo [2/4] Resolving Flutter dependencies...
call flutter pub get
if errorlevel 1 goto :failed

echo.
echo [3/4] Building the Windows release...
call flutter build windows --release
if errorlevel 1 goto :failed

if not exist "%RELEASE_DIR%\inf_dir.exe" (
    echo [ERROR] Release executable was not found: %RELEASE_DIR%\inf_dir.exe
    goto :failed
)

echo.
echo [4/4] Creating %ZIP_PATH%...
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command ^
    "$ErrorActionPreference = 'Stop'; Compress-Archive -Path (Join-Path $env:RELEASE_DIR '*') -DestinationPath $env:ZIP_PATH -CompressionLevel Optimal -Force"
if errorlevel 1 goto :failed

echo.
echo [DONE] Windows release: %RELEASE_DIR%
echo [DONE] ZIP package:     %ZIP_PATH%
popd >nul
exit /b 0

:failed
echo.
echo [ERROR] Packaging failed. No successful package was produced.
popd >nul
exit /b 1

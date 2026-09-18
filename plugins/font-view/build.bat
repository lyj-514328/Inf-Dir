@echo off
setlocal EnableExtensions

set "SCRIPT_DIR=%~dp0"
set "OUTPUT_DIR=%SCRIPT_DIR%target\release"

pushd "%SCRIPT_DIR%"
cargo build --release
if errorlevel 1 (
    popd
    exit /b 1
)
popd

if not exist "%OUTPUT_DIR%\font-view.exe" (
    echo [ERROR] font-view.exe was not built.
    exit /b 1
)

echo [DONE] %OUTPUT_DIR%\font-view.exe
endlocal

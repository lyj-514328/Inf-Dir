@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
pushd "%SCRIPT_DIR%pdf-view"
if errorlevel 1 (
    echo [ERROR] plugins/pdf-view directory not found.
    exit /b 1
)

call build.bat
set "BUILD_RESULT=%ERRORLEVEL%"
popd

if not "%BUILD_RESULT%"=="0" (
    echo [ERROR] pdf-view build failed with code %BUILD_RESULT%.
    exit /b %BUILD_RESULT%
)

echo [DONE] pdf-view only.
endlocal

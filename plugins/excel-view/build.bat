@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
set "WEB_DIR=%SCRIPT_DIR%..\excel-view-web"

pushd "%SCRIPT_DIR%"
cargo build --release
if errorlevel 1 (
    echo [ERROR] excel-view Rust build failed.
    popd
    exit /b 1
)
popd

where npm >nul 2>&1
if errorlevel 1 (
    echo [ERROR] npm is required to build excel-view.
    exit /b 1
)

pushd "%SCRIPT_DIR%"
if not exist "node_modules\esbuild\bin\esbuild.exe" (
    call npm ci
    if errorlevel 1 (
        echo [ERROR] excel-view npm install failed.
        popd
        exit /b 1
    )
)
if exist "%WEB_DIR%" rmdir /s /q "%WEB_DIR%"
mkdir "%WEB_DIR%"
call npm run build
if errorlevel 1 (
    echo [ERROR] excel-view web build failed.
    popd
    exit /b 1
)
copy /Y "%SCRIPT_DIR%web\index.html" "%WEB_DIR%\" >nul
copy /Y "%SCRIPT_DIR%web\app.css" "%WEB_DIR%\" >nul
popd

echo.
echo [DONE] target\release\excel-view.exe
echo [DONE] %WEB_DIR%\
endlocal

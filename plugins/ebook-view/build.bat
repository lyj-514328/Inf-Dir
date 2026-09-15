@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
set "OUTPUT_DIR=%SCRIPT_DIR%target\release"

REM foliate-js is used straight from its submodule checkout: it is plain native
REM ES modules, so there is no bundling step and nothing to download.
pushd "%SCRIPT_DIR%.."
set "WEB_DIR=%CD%\ebook-view-web"
popd

if not exist "%WEB_DIR%\reader.html" (
    echo [ERROR] foliate-js assets are missing from "%WEB_DIR%".
    echo         Run: git submodule update --init plugins/ebook-view-web
    exit /b 1
)

pushd "%SCRIPT_DIR%"
cargo build --release
if errorlevel 1 ( popd & exit /b 1 )
popd

REM Junction the foliate-js checkout beside the dev executable so the viewer can
REM be launched from target\release without copying the whole library.
if not exist "%OUTPUT_DIR%\ebook-view-web" (
    mklink /J "%OUTPUT_DIR%\ebook-view-web" "%WEB_DIR%" >nul 2>&1
    if errorlevel 1 echo [WARN] Could not link ebook-view-web beside the dev executable.
)

echo.
echo [DONE] %OUTPUT_DIR%\ebook-view.exe
echo [DONE] %WEB_DIR%\
endlocal

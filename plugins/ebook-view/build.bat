@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
set "OUTPUT_DIR=%SCRIPT_DIR%target\release"

REM foliate-js is used straight from its submodule checkout: it is plain native
REM ES modules, so there is no bundling step and nothing to download.
pushd "%SCRIPT_DIR%.."
set "WEB_DIR=%CD%\ebook-view-web"
popd
set "READER_DIR=%SCRIPT_DIR%web"

if not exist "%WEB_DIR%\reader.html" (
    echo [ERROR] foliate-js assets are missing from "%WEB_DIR%".
    echo         Run: git submodule update --init plugins/ebook-view-web
    exit /b 1
)
if not exist "%READER_DIR%\text.html" (
    echo [ERROR] Inf-Dir reader pages are missing from "%READER_DIR%".
    exit /b 1
)

pushd "%SCRIPT_DIR%"
cargo build --release
if errorlevel 1 ( popd & exit /b 1 )
popd

REM Junction the foliate-js checkout and the reader pages beside the dev
REM executable so the viewer can be launched from target\release without
REM copying the library, and without writing into the submodule.
if not exist "%OUTPUT_DIR%\ebook-view-web" (
    mklink /J "%OUTPUT_DIR%\ebook-view-web" "%WEB_DIR%" >nul 2>&1
    if errorlevel 1 echo [WARN] Could not link ebook-view-web beside the dev executable.
)
if not exist "%OUTPUT_DIR%\ebook-view-reader" (
    mklink /J "%OUTPUT_DIR%\ebook-view-reader" "%READER_DIR%" >nul 2>&1
    if errorlevel 1 echo [WARN] Could not link ebook-view-reader beside the dev executable.
)

echo.
echo [DONE] %OUTPUT_DIR%\ebook-view.exe
echo [DONE] %WEB_DIR%\
echo [DONE] %READER_DIR%\
endlocal

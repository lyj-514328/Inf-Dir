@echo off
setlocal enabledelayedexpansion

REM ============================================================
REM  Inf-Dir plugins one-click build script
REM  Prerequisites: rustup, cargo, 7z (scoop install 7zip)
REM ============================================================

set "SCRIPT_DIR=%~dp0"
set "MPV_DEV_URL=https://github.com/shinchiro/mpv-winbuild-cmake/releases/download/20260610/mpv-dev-x86_64-20260610-git-304426c.7z"
set "MPV_DEV_7Z=%SCRIPT_DIR%video-view\mpv-dev.7z"
set "MPV_DEV_DIR=%SCRIPT_DIR%video-view\mpv-dev"

REM --- Add MinGW-w64 (ucrt64) to PATH for GNU target ---
if exist "C:\msys64\ucrt64\bin" (
    set "PATH=C:\msys64\ucrt64\bin;%PATH%"
) else (
    echo [WARN] C:\msys64\ucrt64\bin not found, video-view (GNU target) may fail.
)

REM --- Ensure rustup target ---
rustup target add x86_64-pc-windows-gnu >nul 2>&1

REM ============================================================
REM  1. Prepare mpv-dev for video-view
REM ============================================================
if not exist "%MPV_DEV_DIR%\libmpv-2.dll" (
    echo [1/5] Downloading mpv-dev...
    if not exist "%MPV_DEV_7Z%" (
        curl -L -o "%MPV_DEV_7Z%" "%MPV_DEV_URL%"
        if errorlevel 1 (
            echo [ERROR] Failed to download mpv-dev.
            exit /b 1
        )
    )
    echo [1/5] Extracting mpv-dev...
    if not exist "%MPV_DEV_DIR%" mkdir "%MPV_DEV_DIR%"
    7z x "%MPV_DEV_7Z%" -o"%MPV_DEV_DIR%" -y >nul
    if errorlevel 1 (
        echo [ERROR] Failed to extract mpv-dev.
        exit /b 1
    )
    del "%MPV_DEV_7Z%" 2>nul
) else (
    echo [1/5] mpv-dev already present, skipping.
)

REM ============================================================
REM  2. Build img-view (MSVC)
REM ============================================================
echo [2/5] Building img-view...
pushd "%SCRIPT_DIR%img-view"
cargo build --release
if errorlevel 1 ( echo [ERROR] img-view build failed. & popd & exit /b 1 )
popd

REM ============================================================
REM  3. Build text-view (MSVC)
REM ============================================================
echo [3/5] Building text-view...
pushd "%SCRIPT_DIR%text-view"
cargo build --release
if errorlevel 1 ( echo [ERROR] text-view build failed. & popd & exit /b 1 )
popd

REM ============================================================
REM  4. Build video-view (GNU / MinGW-w64)
REM ============================================================
echo [4/5] Building video-view...
pushd "%SCRIPT_DIR%video-view"
cargo build --release
if errorlevel 1 ( echo [ERROR] video-view build failed. & popd & exit /b 1 )
popd

REM ============================================================
REM  5. Install artifacts to plugins/
REM ============================================================
echo [5/5] Installing artifacts...
copy /Y "%SCRIPT_DIR%img-view\target\release\img-view.exe" "%SCRIPT_DIR%" >nul
copy /Y "%SCRIPT_DIR%text-view\target\release\text-view.exe" "%SCRIPT_DIR%" >nul
copy /Y "%SCRIPT_DIR%video-view\target\x86_64-pc-windows-gnu\release\video-view.exe" "%SCRIPT_DIR%" >nul
copy /Y "%MPV_DEV_DIR%\libmpv-2.dll" "%SCRIPT_DIR%" >nul

echo.
echo [DONE] All plugins built and installed to: %SCRIPT_DIR%
endlocal

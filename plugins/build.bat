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
set "LIBARCHIVE_URL=https://github.com/li-ruijie/libarchive/releases/download/v3.8.9/libarchive-v3.8.9-windows-msvc-x64-static.zip"
set "LIBARCHIVE_ZIP=%SCRIPT_DIR%archive-view\libarchive.zip"
set "LIBARCHIVE_DEPS=%SCRIPT_DIR%archive-view\libarchive"

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
    echo [1/7] Downloading mpv-dev...
    if not exist "%MPV_DEV_7Z%" (
        curl -L -o "%MPV_DEV_7Z%" "%MPV_DEV_URL%"
        if errorlevel 1 (
            echo [ERROR] Failed to download mpv-dev.
            exit /b 1
        )
    )
    echo [1/7] Extracting mpv-dev...
    if not exist "%MPV_DEV_DIR%" mkdir "%MPV_DEV_DIR%"
    7z x "%MPV_DEV_7Z%" -o"%MPV_DEV_DIR%" -y >nul
    if errorlevel 1 (
        echo [ERROR] Failed to extract mpv-dev.
        exit /b 1
    )
    del "%MPV_DEV_7Z%" 2>nul
) else (
    echo [1/7] mpv-dev already present, skipping.
)

REM ============================================================
REM  2. Prepare libarchive for archive-view
REM ============================================================
if not exist "%LIBARCHIVE_DEPS%\lib\libarchive.lib" (
    echo [2/7] Downloading libarchive...
    if not exist "%LIBARCHIVE_ZIP%" (
        curl -L -o "%LIBARCHIVE_ZIP%" "%LIBARCHIVE_URL%"
        if errorlevel 1 (
            echo [ERROR] Failed to download libarchive.
            exit /b 1
        )
    )
    echo [2/7] Extracting libarchive...
    set "LA_TMP=%SCRIPT_DIR%archive-view\_la_tmp"
    if not exist "!LA_TMP!" mkdir "!LA_TMP!"
    7z x "%LIBARCHIVE_ZIP%" -o"!LA_TMP!" -y >nul
    if errorlevel 1 (
        echo [ERROR] Failed to extract libarchive.
        exit /b 1
    )
    if not exist "%LIBARCHIVE_DEPS%\include" mkdir "%LIBARCHIVE_DEPS%\include"
    if not exist "%LIBARCHIVE_DEPS%\lib" mkdir "%LIBARCHIVE_DEPS%\lib"
    if not exist "%LIBARCHIVE_DEPS%\bin" mkdir "%LIBARCHIVE_DEPS%\bin"
    copy /Y "!LA_TMP!\include\archive.h" "%LIBARCHIVE_DEPS%\include\" >nul
    copy /Y "!LA_TMP!\include\archive_entry.h" "%LIBARCHIVE_DEPS%\include\" >nul
    copy /Y "!LA_TMP!\lib\libarchive.lib" "%LIBARCHIVE_DEPS%\lib\" >nul
    copy /Y "!LA_TMP!\bin\libarchive.dll" "%LIBARCHIVE_DEPS%\bin\archive.dll" >nul
    rmdir /s /q "!LA_TMP!" 2>nul
    del "%LIBARCHIVE_ZIP%" 2>nul
) else (
    echo [2/7] libarchive already present, skipping.
)

REM ============================================================
REM  3. Build img-view (MSVC)
REM ============================================================
echo [3/7] Building img-view...
pushd "%SCRIPT_DIR%img-view"
cargo build --release
if errorlevel 1 ( echo [ERROR] img-view build failed. & popd & exit /b 1 )
popd

REM ============================================================
REM  4. Build text-view (MSVC)
REM ============================================================
echo [4/7] Building text-view...
pushd "%SCRIPT_DIR%text-view"
cargo build --release
if errorlevel 1 ( echo [ERROR] text-view build failed. & popd & exit /b 1 )
popd

REM ============================================================
REM  5. Build archive-view (MSVC)
REM ============================================================
echo [5/7] Building archive-view...
pushd "%SCRIPT_DIR%archive-view"
cargo build --release
if errorlevel 1 ( echo [ERROR] archive-view build failed. & popd & exit /b 1 )
popd

REM ============================================================
REM  6. Build video-view (GNU / MinGW-w64)
REM ============================================================
echo [6/7] Building video-view...
pushd "%SCRIPT_DIR%video-view"
cargo build --release
if errorlevel 1 ( echo [ERROR] video-view build failed. & popd & exit /b 1 )
popd

REM ============================================================
REM  7. Build pdf-view (GNU / MinGW-w64 + PDFium)
REM ============================================================
echo [7/7] Building pdf-view...
pushd "%SCRIPT_DIR%pdf-view"
call build.bat
if errorlevel 1 ( echo [ERROR] pdf-view build failed. & popd & exit /b 1 )
popd

REM ============================================================
REM  Install artifacts to plugins/
REM ============================================================
echo Installing artifacts...
copy /Y "%SCRIPT_DIR%img-view\target\release\img-view.exe" "%SCRIPT_DIR%" >nul
copy /Y "%SCRIPT_DIR%text-view\target\release\text-view.exe" "%SCRIPT_DIR%" >nul
copy /Y "%SCRIPT_DIR%archive-view\target\release\archive-view.exe" "%SCRIPT_DIR%" >nul
copy /Y "%LIBARCHIVE_DEPS%\bin\archive.dll" "%SCRIPT_DIR%" >nul
copy /Y "%SCRIPT_DIR%video-view\target\x86_64-pc-windows-gnu\release\video-view.exe" "%SCRIPT_DIR%" >nul
copy /Y "%MPV_DEV_DIR%\libmpv-2.dll" "%SCRIPT_DIR%" >nul
copy /Y "%SCRIPT_DIR%pdf-view\target\x86_64-pc-windows-gnu\release\pdf-view.exe" "%SCRIPT_DIR%" >nul
copy /Y "%SCRIPT_DIR%pdf-view\target\x86_64-pc-windows-gnu\release\pdfium.dll" "%SCRIPT_DIR%" >nul

echo.
echo [DONE] All plugins built and installed to: %SCRIPT_DIR%
endlocal

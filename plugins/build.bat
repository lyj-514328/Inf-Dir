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
set "OOXML_VERSION=0.75.4"
set "OOXML_URL=https://registry.npmjs.org/@silurus/ooxml/-/ooxml-%OOXML_VERSION%.tgz"
set "OOXML_TGZ=%SCRIPT_DIR%office-view\_ooxml.tgz"
set "OOXML_WEB=%SCRIPT_DIR%office-view-web"

REM --- Add MinGW-w64 (ucrt64) to PATH for GNU target ---
if exist "C:\msys64\ucrt64\bin" (
    set "PATH=C:\msys64\ucrt64\bin;%PATH%"
) else (
    echo [WARN] C:\msys64\ucrt64\bin not found, video-view ^(GNU target^) may fail.
)

REM --- Ensure rustup target ---
rustup target add x86_64-pc-windows-gnu >nul 2>&1

REM ============================================================
REM  1. Prepare mpv-dev for video-view
REM ============================================================
if not exist "%MPV_DEV_DIR%\libmpv-2.dll" (
    echo [1/9] Downloading mpv-dev...
    if not exist "%MPV_DEV_7Z%" (
        curl -L -o "%MPV_DEV_7Z%" "%MPV_DEV_URL%"
        if errorlevel 1 (
            echo [ERROR] Failed to download mpv-dev.
            exit /b 1
        )
    )
    echo [1/9] Extracting mpv-dev...
    if not exist "%MPV_DEV_DIR%" mkdir "%MPV_DEV_DIR%"
    7z x "%MPV_DEV_7Z%" -o"%MPV_DEV_DIR%" -y >nul
    if errorlevel 1 (
        echo [ERROR] Failed to extract mpv-dev.
        exit /b 1
    )
    del "%MPV_DEV_7Z%" 2>nul
) else (
    echo [1/9] mpv-dev already present, skipping.
)

REM ============================================================
REM  2. Prepare libarchive for archive-view
REM ============================================================
if not exist "%LIBARCHIVE_DEPS%\lib\libarchive.lib" (
    echo [2/9] Downloading libarchive...
    if not exist "%LIBARCHIVE_ZIP%" (
        curl -L -o "%LIBARCHIVE_ZIP%" "%LIBARCHIVE_URL%"
        if errorlevel 1 (
            echo [ERROR] Failed to download libarchive.
            exit /b 1
        )
    )
    echo [2/9] Extracting libarchive...
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
    echo [2/9] libarchive already present, skipping.
)

REM ============================================================
REM  3. Prepare @silurus/ooxml web assets for office-view
REM ============================================================
if not exist "%OOXML_WEB%\docx.mjs" (
    echo [3/9] Downloading @silurus/ooxml %OOXML_VERSION%...
    if not exist "%OOXML_TGZ%" (
        curl -L -o "%OOXML_TGZ%" "%OOXML_URL%"
        if errorlevel 1 (
            echo [ERROR] Failed to download @silurus/ooxml.
            exit /b 1
        )
    )
    echo [3/9] Extracting @silurus/ooxml...
    set "OOXML_TMP=%SCRIPT_DIR%office-view\_ooxml_tmp"
    if exist "!OOXML_TMP!" rmdir /s /q "!OOXML_TMP!"
    mkdir "!OOXML_TMP!"
    7z x "%OOXML_TGZ%" -o"!OOXML_TMP!" -y >nul
    if errorlevel 1 (
        echo [ERROR] Failed to extract @silurus/ooxml tarball.
        exit /b 1
    )
    REM 7z extracts _ooxml.tgz to _ooxml.tar (same prefix, .tar extension)
    7z x "!OOXML_TMP!\_ooxml.tar" -o"!OOXML_TMP!\pkg" -y >nul
    if errorlevel 1 (
        echo [ERROR] Failed to extract ooxml tar.
        exit /b 1
    )
    if not exist "%OOXML_WEB%" mkdir "%OOXML_WEB%"
    xcopy /E /I /Y /Q "!OOXML_TMP!\pkg\package\dist" "%OOXML_WEB%" >nul
    copy /Y "%SCRIPT_DIR%office-view\web\index.html" "%OOXML_WEB%\" >nul
    copy /Y "!OOXML_TMP!\pkg\package\LICENSE" "%OOXML_WEB%\" >nul
    copy /Y "!OOXML_TMP!\pkg\package\THIRD_PARTY_NOTICES.md" "%OOXML_WEB%\" >nul
    rmdir /s /q "!OOXML_TMP!" 2>nul
    del "%OOXML_TGZ%" 2>nul
) else (
    echo [3/9] @silurus/ooxml assets already present, skipping.
)

REM ============================================================
REM  4. Build img-view (MSVC)
REM ============================================================
echo [4/9] Building img-view...
pushd "%SCRIPT_DIR%img-view"
cargo build --release
if errorlevel 1 ( echo [ERROR] img-view build failed. & popd & exit /b 1 )
popd

REM ============================================================
REM  5. Build text-view (MSVC)
REM ============================================================
echo [5/9] Building text-view...
pushd "%SCRIPT_DIR%text-view"
cargo build --release
if errorlevel 1 ( echo [ERROR] text-view build failed. & popd & exit /b 1 )
popd

REM ============================================================
REM  6. Build archive-view (MSVC)
REM ============================================================
echo [6/9] Building archive-view...
pushd "%SCRIPT_DIR%archive-view"
cargo build --release
if errorlevel 1 ( echo [ERROR] archive-view build failed. & popd & exit /b 1 )
popd

REM ============================================================
REM  7. Build office-view (MSVC + WebView2)
REM ============================================================
echo [7/9] Building office-view...
pushd "%SCRIPT_DIR%office-view"
cargo build --release
if errorlevel 1 ( echo [ERROR] office-view build failed. & popd & exit /b 1 )
popd

REM ============================================================
REM  8. Build video-view (GNU / MinGW-w64)
REM ============================================================
echo [8/9] Building video-view...
pushd "%SCRIPT_DIR%video-view"
cargo build --release
if errorlevel 1 ( echo [ERROR] video-view build failed. & popd & exit /b 1 )
popd

REM ============================================================
REM  9. Build pdf-view (GNU / MinGW-w64 + PDFium)
REM ============================================================
echo [9/9] Building pdf-view...
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
copy /Y "%SCRIPT_DIR%office-view\target\release\office-view.exe" "%SCRIPT_DIR%" >nul
copy /Y "%SCRIPT_DIR%video-view\target\x86_64-pc-windows-gnu\release\video-view.exe" "%SCRIPT_DIR%" >nul
copy /Y "%MPV_DEV_DIR%\libmpv-2.dll" "%SCRIPT_DIR%" >nul
copy /Y "%SCRIPT_DIR%pdf-view\target\release\pdf-view.exe" "%SCRIPT_DIR%" >nul
copy /Y "%SCRIPT_DIR%pdf-view\target\release\pdfium.dll" "%SCRIPT_DIR%" >nul

echo.
echo [DONE] All plugins built and installed to: %SCRIPT_DIR%
endlocal

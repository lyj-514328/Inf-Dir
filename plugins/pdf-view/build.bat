@echo off
setlocal

set "UCRT64_BIN=C:\msys64\ucrt64\bin"
set "OUTPUT_DIR=target\x86_64-pc-windows-gnu\release"
set "PDFIUM_VERSION=7881"
set "PDFIUM_URL=https://github.com/bblanchon/pdfium-binaries/releases/download/chromium%%2F%PDFIUM_VERSION%/pdfium-win-x64.tgz"
set "PDFIUM_ARCHIVE=target\pdfium-win-x64.tgz"
set "PDFIUM_DIR=target\pdfium-win-x64"

if not exist "%UCRT64_BIN%\gcc.exe" (
    echo [ERROR] UCRT64 GCC not found at %UCRT64_BIN%\gcc.exe
    exit /b 1
)

set "PATH=%UCRT64_BIN%;%PATH%"
rustup target add x86_64-pc-windows-gnu
if errorlevel 1 exit /b 1

cargo build --release --target x86_64-pc-windows-gnu
if errorlevel 1 exit /b 1

if exist "pdfium.dll" (
    copy /Y "pdfium.dll" "%OUTPUT_DIR%\pdfium.dll" >nul
) else (
    where curl.exe >nul 2>&1
    if errorlevel 1 (
        echo [ERROR] curl.exe was not found in PATH.
        exit /b 1
    )
    where tar.exe >nul 2>&1
    if errorlevel 1 (
        echo [ERROR] tar.exe was not found in PATH.
        exit /b 1
    )

    if not exist "%PDFIUM_DIR%\bin\pdfium.dll" (
        if not exist "target" mkdir "target"
        echo [INFO] Downloading PDFium %PDFIUM_VERSION% x64...
        curl.exe -fL -C - --retry 5 --retry-delay 3 --retry-all-errors --connect-timeout 20 --speed-limit 1024 --speed-time 60 -o "%PDFIUM_ARCHIVE%" "%PDFIUM_URL%"
        if errorlevel 1 (
            echo [ERROR] Failed to download PDFium.
            echo         Re-run build.bat to resume the download.
            exit /b 1
        )

        if not exist "%PDFIUM_DIR%" mkdir "%PDFIUM_DIR%"
        echo [INFO] Extracting PDFium...
        tar.exe -xf "%PDFIUM_ARCHIVE%" -C "%PDFIUM_DIR%"
        if errorlevel 1 (
            echo [ERROR] Failed to extract PDFium archive.
            exit /b 1
        )
    )

    copy /Y "%PDFIUM_DIR%\bin\pdfium.dll" "%OUTPUT_DIR%\pdfium.dll" >nul
    if errorlevel 1 (
        echo [ERROR] Failed to install pdfium.dll.
        exit /b 1
    )
)

echo.
echo [DONE] %OUTPUT_DIR%\pdf-view.exe
echo [DONE] %OUTPUT_DIR%\pdfium.dll
endlocal

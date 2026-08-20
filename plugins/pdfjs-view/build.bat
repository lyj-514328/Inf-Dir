@echo off
setlocal

set "OUTPUT_DIR=target\release"
set "PDFJS_VERSION=6.2.108"
set "PDFJS_URL=https://github.com/mozilla/pdf.js/releases/download/v%PDFJS_VERSION%/pdfjs-%PDFJS_VERSION%-dist.zip"
set "PDFJS_ZIP=target\pdfjs-dist.zip"
set "PDFJS_TMP=target\pdfjs-dist"
set "WEB_DIR=..\pdfjs-view-web"

cargo build --release
if errorlevel 1 exit /b 1

REM Download and extract pdf.js dist assets if not already present.
if exist "%WEB_DIR%\web\viewer.html" if exist "%WEB_DIR%\build\pdf.mjs" (
    echo [INFO] pdf.js %PDFJS_VERSION% assets already present, skipping.
    goto :done
)

where curl.exe >nul 2>&1
if errorlevel 1 (
    echo [ERROR] curl.exe was not found in PATH.
    exit /b 1
)
where 7z.exe >nul 2>&1
if errorlevel 1 (
    echo [ERROR] 7z.exe was not found in PATH.
    exit /b 1
)

if not exist "target" mkdir "target"
if not exist "%PDFJS_ZIP%" (
    echo [INFO] Downloading pdf.js %PDFJS_VERSION% dist...
    curl.exe -fL -C - --retry 5 --retry-delay 3 --retry-all-errors --connect-timeout 20 --speed-limit 1024 --speed-time 60 -o "%PDFJS_ZIP%" "%PDFJS_URL%"
    if errorlevel 1 (
        echo [ERROR] Failed to download pdf.js.
        echo         Re-run build.bat to resume the download.
        exit /b 1
    )
)

if exist "%PDFJS_TMP%" rmdir /s /q "%PDFJS_TMP%"
mkdir "%PDFJS_TMP%"
echo [INFO] Extracting pdf.js...
7z x "%PDFJS_ZIP%" -o"%PDFJS_TMP%" -y >nul
if errorlevel 1 (
    echo [ERROR] Failed to extract pdf.js archive.
    exit /b 1
)

if not exist "%WEB_DIR%" mkdir "%WEB_DIR%"
if exist "%WEB_DIR%\build" rmdir /s /q "%WEB_DIR%\build"
if exist "%WEB_DIR%\web" rmdir /s /q "%WEB_DIR%\web"
xcopy /E /I /Y /Q "%PDFJS_TMP%\build" "%WEB_DIR%\build" >nul
if errorlevel 1 (
    echo [ERROR] Failed to install pdf.js build assets.
    exit /b 1
)
xcopy /E /I /Y /Q "%PDFJS_TMP%\web" "%WEB_DIR%\web" >nul
if errorlevel 1 (
    echo [ERROR] Failed to install pdf.js web assets.
    exit /b 1
)

del "%PDFJS_ZIP%" 2>nul

:done
echo.
echo [DONE] %OUTPUT_DIR%\pdfjs-view.exe
echo [DONE] %WEB_DIR%\
endlocal

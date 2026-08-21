@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
set "WEB_DIR=%SCRIPT_DIR%..\onlyoffice-view-web"
set "PDFJS_WEB=%SCRIPT_DIR%..\pdfjs-view-web"

if not exist "%PDFJS_WEB%\web\viewer.html" (
    echo [ERROR] pdf.js assets are missing. Build pdfjs-view first.
    exit /b 1
)

pushd "%SCRIPT_DIR%"
cargo build --release
if errorlevel 1 exit /b 1
popd

if exist "%WEB_DIR%" rmdir /s /q "%WEB_DIR%"
mkdir "%WEB_DIR%"
xcopy /E /I /Y /Q "%PDFJS_WEB%\build" "%WEB_DIR%\build" >nul
xcopy /E /I /Y /Q "%PDFJS_WEB%\web" "%WEB_DIR%\web" >nul
if errorlevel 1 (
    echo [ERROR] Failed to copy pdf.js assets.
    exit /b 1
)

echo.
echo [DONE] target\release\onlyoffice-view.exe
echo [DONE] %WEB_DIR%\
echo [INFO] Set ONLYOFFICE_X2T_DIR when packaging the x2t runtime.
endlocal

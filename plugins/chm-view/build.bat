@echo off
setlocal EnableExtensions

set "SCRIPT_DIR=%~dp0"
set "CHMATE_DIR=%SCRIPT_DIR%..\..\ai_refs\CHMate"
set "WEB_DIR=%SCRIPT_DIR%chm-view-web"
set "OUTPUT_DIR=%SCRIPT_DIR%target\release"

if not exist "%CHMATE_DIR%\src\chm\chm-reader.js" (
    echo [ERROR] CHMate submodule is missing. Run: git submodule update --init --recursive
    exit /b 1
)

pushd "%SCRIPT_DIR%"
cargo build --release
if errorlevel 1 (
    popd
    exit /b 1
)
popd

if exist "%WEB_DIR%" rmdir /s /q "%WEB_DIR%"
mkdir "%WEB_DIR%"
xcopy /E /I /Y /Q "%SCRIPT_DIR%web\*" "%WEB_DIR%\" >nul
if errorlevel 1 exit /b 1
copy /Y "%CHMATE_DIR%\LICENSE" "%WEB_DIR%\CHMATE-LICENSE.txt" >nul
copy /Y "%CHMATE_DIR%\CREDITS.md" "%WEB_DIR%\CHMATE-CREDITS.md" >nul

if not exist "%OUTPUT_DIR%\chm-view.exe" (
    echo [ERROR] chm-view.exe was not built.
    exit /b 1
)
if not exist "%WEB_DIR%\index.html" (
    echo [ERROR] chm-view-web assets were not prepared.
    exit /b 1
)

echo [DONE] %OUTPUT_DIR%\chm-view.exe
echo [DONE] %WEB_DIR%\
endlocal

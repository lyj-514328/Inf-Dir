@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
set "HOST_DIR=%SCRIPT_DIR%host"
set "WEB_DIR=%SCRIPT_DIR%web"
set "WEB_OUTPUT=%SCRIPT_DIR%..\project-view-web"
set "PUBLISH_DIR=%SCRIPT_DIR%bin\Release\project-view"

echo [project-view] Building native mpxj-rs host...
cargo build --release --manifest-path "%HOST_DIR%\Cargo.toml"
if errorlevel 1 ( echo [ERROR] Rust host build failed. & exit /b 1 )

echo [project-view] Running parser tests...
cargo test --release --quiet --manifest-path "%HOST_DIR%\Cargo.toml"
if errorlevel 1 ( echo [ERROR] Rust parser tests failed. & exit /b 1 )

where npm >nul 2>&1
if errorlevel 1 ( echo [ERROR] npm is required to package dhtmlxGantt. & exit /b 1 )
if not exist "%WEB_DIR%\node_modules\dhtmlx-gantt\codebase\dhtmlxgantt.js" (
  pushd "%WEB_DIR%"
  call npm install --ignore-scripts --no-package-lock --no-save dhtmlx-gantt@10.0.2
  if errorlevel 1 ( popd & echo [ERROR] dhtmlxGantt install failed. & exit /b 1 )
  popd
)

if exist "%WEB_OUTPUT%" rmdir /s /q "%WEB_OUTPUT%"
mkdir "%WEB_OUTPUT%"
copy /Y "%WEB_DIR%\index.html" "%WEB_OUTPUT%\" >nul
copy /Y "%WEB_DIR%\app.js" "%WEB_OUTPUT%\" >nul
copy /Y "%WEB_DIR%\app.css" "%WEB_OUTPUT%\" >nul
copy /Y "%WEB_DIR%\node_modules\dhtmlx-gantt\codebase\dhtmlxgantt.js" "%WEB_OUTPUT%\" >nul
copy /Y "%WEB_DIR%\node_modules\dhtmlx-gantt\codebase\dhtmlxgantt.css" "%WEB_OUTPUT%\" >nul

if exist "%PUBLISH_DIR%" rmdir /s /q "%PUBLISH_DIR%"
mkdir "%PUBLISH_DIR%"
copy /Y "%HOST_DIR%\target\release\project-view.exe" "%PUBLISH_DIR%\" >nul
xcopy /E /I /Y /Q "%WEB_OUTPUT%" "%PUBLISH_DIR%\project-view-web" >nul
copy /Y "%SCRIPT_DIR%plugin.json" "%PUBLISH_DIR%\" >nul
copy /Y "%SCRIPT_DIR%THIRD_PARTY_NOTICES.txt" "%PUBLISH_DIR%\" >nul

echo [DONE] %PUBLISH_DIR%
endlocal

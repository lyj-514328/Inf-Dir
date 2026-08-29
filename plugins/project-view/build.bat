@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
set "BACKEND_DIR=%SCRIPT_DIR%backend"
set "HOST_DIR=%SCRIPT_DIR%host"
set "WEB_DIR=%SCRIPT_DIR%web"
set "WEB_OUTPUT=%SCRIPT_DIR%..\project-view-web"
set "PARSER_IMAGE=%BACKEND_DIR%\target\image"
set "PUBLISH_DIR=%SCRIPT_DIR%bin\Release\project-view"
set "MAVEN_VERSION=3.9.11"
set "MAVEN_HOME=%BACKEND_DIR%\.maven\apache-maven-%MAVEN_VERSION%"
set "MAVEN_ZIP=%BACKEND_DIR%\.maven\apache-maven-%MAVEN_VERSION%-bin.zip"

if not exist "%BACKEND_DIR%\.maven" mkdir "%BACKEND_DIR%\.maven"
where mvn.cmd >nul 2>&1
if errorlevel 1 (
  if not exist "%MAVEN_HOME%\bin\mvn.cmd" (
    echo [project-view] Downloading Apache Maven %MAVEN_VERSION%...
    if exist "%MAVEN_ZIP%" del /q "%MAVEN_ZIP%"
    curl -L --fail --retry 3 --retry-all-errors --connect-timeout 15 --max-time 180 -o "%MAVEN_ZIP%" "https://archive.apache.org/dist/maven/maven-3/%MAVEN_VERSION%/binaries/apache-maven-%MAVEN_VERSION%-bin.zip"
    if errorlevel 1 ( echo [ERROR] Failed to download Maven. & exit /b 1 )
    powershell -NoProfile -Command "Expand-Archive -LiteralPath '%MAVEN_ZIP%' -DestinationPath '%BACKEND_DIR%\.maven' -Force"
    if errorlevel 1 ( echo [ERROR] Failed to extract Maven. & exit /b 1 )
    del /q "%MAVEN_ZIP%" 2>nul
  )
  set "MAVEN_CMD=%MAVEN_HOME%\bin\mvn.cmd"
) else (
  set "MAVEN_CMD=mvn.cmd"
)

echo [project-view] Building Java MPXJ parser...
call "%MAVEN_CMD%" -q -f "%BACKEND_DIR%\pom.xml" clean package
if errorlevel 1 ( echo [ERROR] Java parser build failed. & exit /b 1 )

echo [project-view] Building WebView2 host...
cargo build --release --manifest-path "%HOST_DIR%\Cargo.toml"
if errorlevel 1 ( echo [ERROR] Rust host build failed. & exit /b 1 )

where npm >nul 2>&1
if errorlevel 1 ( echo [ERROR] npm is required to package ECharts. & exit /b 1 )
if not exist "%WEB_DIR%\node_modules\echarts\dist\echarts.min.js" (
  pushd "%WEB_DIR%"
  call npm install --ignore-scripts --no-package-lock --no-save echarts@6.0.0
  if errorlevel 1 ( popd & echo [ERROR] ECharts install failed. & exit /b 1 )
  popd
)
if exist "%WEB_OUTPUT%" rmdir /s /q "%WEB_OUTPUT%"
mkdir "%WEB_OUTPUT%"
copy /Y "%WEB_DIR%\index.html" "%WEB_OUTPUT%\" >nul
copy /Y "%WEB_DIR%\app.js" "%WEB_OUTPUT%\" >nul
copy /Y "%WEB_DIR%\app.css" "%WEB_OUTPUT%\" >nul
copy /Y "%WEB_DIR%\node_modules\echarts\dist\echarts.min.js" "%WEB_OUTPUT%\" >nul

echo [project-view] Packaging Java parser runtime...
if exist "%PARSER_IMAGE%" rmdir /s /q "%PARSER_IMAGE%"
mkdir "%PARSER_IMAGE%"
jpackage --type app-image --name project-parser --input "%BACKEND_DIR%\target" --main-jar project-parser-0.1.0.jar --main-class infdir.projectview.ProjectParser --dest "%PARSER_IMAGE%" --app-version 0.1.0 --vendor Inf-Dir --java-options "-Dfile.encoding=UTF-8"
if errorlevel 1 ( echo [ERROR] Java parser packaging failed. & exit /b 1 )

if exist "%PUBLISH_DIR%" rmdir /s /q "%PUBLISH_DIR%"
mkdir "%PUBLISH_DIR%"
copy /Y "%HOST_DIR%\target\release\project-view.exe" "%PUBLISH_DIR%\" >nul
xcopy /E /I /Y /Q "%WEB_OUTPUT%" "%PUBLISH_DIR%\project-view-web" >nul
xcopy /E /I /Y /Q "%PARSER_IMAGE%\project-parser" "%PUBLISH_DIR%\project-parser" >nul
copy /Y "%SCRIPT_DIR%plugin.json" "%PUBLISH_DIR%\" >nul
copy /Y "%SCRIPT_DIR%THIRD_PARTY_NOTICES.txt" "%PUBLISH_DIR%\" >nul

echo [project-view] Running parser self-test...
start "" /wait "%PUBLISH_DIR%\project-parser\project-parser.exe" --self-test
if errorlevel 1 ( echo [ERROR] Java parser self-test failed. & exit /b 1 )
echo [DONE] %PUBLISH_DIR%
endlocal

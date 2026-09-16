@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM Prepare the runtimes used by mupdf-view only. DjVuLibre, GhostXPS and
REM LibreOffice are shared with other viewers and are prepared by
REM plugins\runtime\build.bat, which the root plugins\build.bat installs as
REM plugins\dist\inf-dir.runtime\.
set "SCRIPT_DIR=%~dp0"
set "CACHE_DIR=%SCRIPT_DIR%_cache"
set "TEMP_DIR=%SCRIPT_DIR%_runtime_tmp"
set "DWG_DIR=%SCRIPT_DIR%libredwg"
set "DWG_ARCHIVE=%CACHE_DIR%\libredwg-0.14-win64.zip"
set "DWG_URL=https://github.com/LibreDWG/libredwg/releases/download/0.14/libredwg-0.14-win64.zip"
set "DWG_SHA=1ad7e15344d20b3426c3435b078d82fb84b35062815946b2cca9c5fc9810fea8"

if not exist "%CACHE_DIR%" mkdir "%CACHE_DIR%"
call :prepare_dwg
if errorlevel 1 exit /b 1
echo [DOC] LibreDWG runtime ready.
exit /b 0

:prepare_dwg
if exist "%DWG_DIR%\dwg2SVG.exe" exit /b 0
if not exist "%DWG_ARCHIVE%" (
    echo [DOC] Downloading LibreDWG...
    curl.exe --fail --location --retry 3 --retry-delay 2 -o "%DWG_ARCHIVE%" "%DWG_URL%"
    if errorlevel 1 exit /b 1
)
call :verify "%DWG_ARCHIVE%" "%DWG_SHA%"
if errorlevel 1 exit /b 1
if exist "%TEMP_DIR%" rmdir /s /q "%TEMP_DIR%"
mkdir "%TEMP_DIR%"
7z x "%DWG_ARCHIVE%" -o"%TEMP_DIR%" -y >nul
if errorlevel 1 exit /b 1
if exist "%DWG_DIR%" rmdir /s /q "%DWG_DIR%"
mkdir "%DWG_DIR%"
for %%F in (dwg2SVG.exe dxf2dwg.exe libiconv-2.dll libpcre2-16-0.dll libpcre2-8-0.dll libredwg-0.dll README.txt) do if exist "%TEMP_DIR%\%%F" copy /Y "%TEMP_DIR%\%%F" "%DWG_DIR%\" >nul
rmdir /s /q "%TEMP_DIR%"
if not exist "%DWG_DIR%\dwg2SVG.exe" exit /b 1
exit /b 0

:verify
set "HASH_FILE=%~1"
set "EXPECTED=%~2"
set "ACTUAL="
for /f "usebackq delims=" %%H in (`powershell -NoProfile -Command "(Get-FileHash -LiteralPath '%HASH_FILE%' -Algorithm SHA256).Hash.ToLowerInvariant()"`) do set "ACTUAL=%%H"
if /I not "!ACTUAL!"=="%EXPECTED%" (
    echo [ERROR] Runtime archive SHA-256 mismatch: %HASH_FILE%
    exit /b 1
)
exit /b 0

@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM Build the bundled 7-Zip archive-operation plugin from the official release.
REM Usage: build.bat [dist-directory]

set "SCRIPT_DIR=%~dp0"
if "%~1"=="" (
    for %%I in ("%SCRIPT_DIR%..\dist") do set "DIST_DIR=%%~fI"
) else (
    set "DIST_DIR=%~f1"
)

set "SEVENZIP_VERSION=26.02"
set "SEVENZIP_ARCHIVE=7z2602-extra.7z"
set "SEVENZIP_URL=https://github.com/ip7z/7zip/releases/download/26.02/7z2602-extra.7z"
set "SEVENZIP_SHA256=081df9e9311dfd9c9e0e98c1c80180b99bb51e4cb24156b5f3057fe3c259d70a"

set "CACHE_DIR=%SCRIPT_DIR%_cache"
set "TEMP_DIR=%SCRIPT_DIR%_tmp"
set "SEVENZIP_ARCHIVE_PATH=%CACHE_DIR%\%SEVENZIP_ARCHIVE%"
set "SEVENZIP_DIST=%DIST_DIR%\inf-dir.7z-archive"

if not exist "%CACHE_DIR%" mkdir "%CACHE_DIR%"
if not exist "%DIST_DIR%" mkdir "%DIST_DIR%"

echo [ARCHIVE] Preparing 7-Zip %SEVENZIP_VERSION%...
call :download_and_verify "%SEVENZIP_URL%" "%SEVENZIP_ARCHIVE_PATH%" "%SEVENZIP_SHA256%"
if errorlevel 1 exit /b 1

if exist "%TEMP_DIR%" rmdir /s /q "%TEMP_DIR%"
mkdir "%TEMP_DIR%"
7z x "%SEVENZIP_ARCHIVE_PATH%" -o"%TEMP_DIR%" -y >nul
if errorlevel 1 (
    echo [ERROR] Failed to extract %SEVENZIP_ARCHIVE%.
    exit /b 1
)

set "SEVENZIP_EXE=%TEMP_DIR%\x64\7za.exe"
if not exist "%SEVENZIP_EXE%" set "SEVENZIP_EXE="
for /r "%TEMP_DIR%" %%F in (7za.exe) do if not defined SEVENZIP_EXE set "SEVENZIP_EXE=%%~fF"
if not defined SEVENZIP_EXE (
    echo [ERROR] 7za.exe is missing from %SEVENZIP_ARCHIVE%.
    exit /b 1
)

if exist "%SEVENZIP_DIST%" rmdir /s /q "%SEVENZIP_DIST%"
mkdir "%SEVENZIP_DIST%"
copy /Y "%SCRIPT_DIR%7zip\plugin.json" "%SEVENZIP_DIST%\" >nul
copy /Y "%SCRIPT_DIR%7zip\THIRD_PARTY_NOTICES.txt" "%SEVENZIP_DIST%\" >nul
copy /Y "%SEVENZIP_EXE%" "%SEVENZIP_DIST%\7za.exe" >nul

for /r "%TEMP_DIR%" %%F in (License.txt) do if exist "%%~fF" copy /Y "%%~fF" "%SEVENZIP_DIST%\License.txt" >nul
for /r "%TEMP_DIR%" %%F in (license.txt) do if exist "%%~fF" copy /Y "%%~fF" "%SEVENZIP_DIST%\License.txt" >nul

if not exist "%SEVENZIP_DIST%\7za.exe" (
    echo [ERROR] Failed to install the 7-Zip archive plugin.
    exit /b 1
)

rmdir /s /q "%TEMP_DIR%"
echo [ARCHIVE] Installed 7-Zip archive plugin to: %SEVENZIP_DIST%
exit /b 0

:download_and_verify
set "DOWNLOAD_URL=%~1"
set "DOWNLOAD_FILE=%~2"
set "EXPECTED_SHA=%~3"

if exist "%DOWNLOAD_FILE%" (
    call :verify_sha256 "%DOWNLOAD_FILE%" "%EXPECTED_SHA%"
    if not errorlevel 1 exit /b 0
    echo [WARN] Cached 7-Zip archive failed verification; downloading again.
    del /q "%DOWNLOAD_FILE%"
)

curl.exe --fail --location --silent --show-error --retry 3 --retry-delay 2 -o "%DOWNLOAD_FILE%" "%DOWNLOAD_URL%"
if errorlevel 1 (
    del /q "%DOWNLOAD_FILE%" 2>nul
    echo [ERROR] Failed to download 7-Zip.
    exit /b 1
)

call :verify_sha256 "%DOWNLOAD_FILE%" "%EXPECTED_SHA%"
if errorlevel 1 (
    del /q "%DOWNLOAD_FILE%" 2>nul
    echo [ERROR] SHA-256 verification failed for 7-Zip.
    exit /b 1
)
exit /b 0

:verify_sha256
set "INF_DIR_ARCHIVE_HASH_FILE=%~1"
set "ACTUAL_SHA="
for /f "usebackq delims=" %%H in (`powershell -NoProfile -Command "(Get-FileHash -LiteralPath $env:INF_DIR_ARCHIVE_HASH_FILE -Algorithm SHA256).Hash.ToLowerInvariant()"`) do set "ACTUAL_SHA=%%H"
if not defined ACTUAL_SHA exit /b 1
if /I not "!ACTUAL_SHA!"=="%~2" exit /b 1
exit /b 0

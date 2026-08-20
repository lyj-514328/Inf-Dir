@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM Build the bundled search-provider plugins from pinned official releases.
REM Usage: build.bat [dist-directory]

set "SCRIPT_DIR=%~dp0"
if "%~1"=="" (
    for %%I in ("%SCRIPT_DIR%..\dist") do set "DIST_DIR=%%~fI"
) else (
    set "DIST_DIR=%~f1"
)

set "FD_VERSION=10.4.2"
set "FD_ARCHIVE=fd-v%FD_VERSION%-x86_64-pc-windows-msvc.zip"
set "FD_URL=https://github.com/sharkdp/fd/releases/download/v%FD_VERSION%/%FD_ARCHIVE%"
set "FD_SHA256=b2816e506390a89941c63c9187d58a3cc10e9a55f2ef0685f9ea0eccaf7c98c8"

set "RG_VERSION=15.2.0"
set "RG_ARCHIVE=ripgrep-%RG_VERSION%-x86_64-pc-windows-msvc.zip"
set "RG_URL=https://github.com/BurntSushi/ripgrep/releases/download/%RG_VERSION%/%RG_ARCHIVE%"
set "RG_SHA256=71b2fef860abe467217a538ff31de02f5258807c0129f771846f87bd029aafc5"

set "CACHE_DIR=%SCRIPT_DIR%_cache"
set "TEMP_DIR=%SCRIPT_DIR%_tmp"
set "FD_ZIP=%CACHE_DIR%\%FD_ARCHIVE%"
set "RG_ZIP=%CACHE_DIR%\%RG_ARCHIVE%"
set "FD_TEMP=%TEMP_DIR%\fd"
set "RG_TEMP=%TEMP_DIR%\ripgrep"
set "FD_ROOT=%FD_TEMP%\fd-v%FD_VERSION%-x86_64-pc-windows-msvc"
set "RG_ROOT=%RG_TEMP%\ripgrep-%RG_VERSION%-x86_64-pc-windows-msvc"
set "FD_DIST=%DIST_DIR%\inf-dir.fd-search"
set "RG_DIST=%DIST_DIR%\inf-dir.ripgrep-search"

if not exist "%CACHE_DIR%" mkdir "%CACHE_DIR%"
if not exist "%DIST_DIR%" mkdir "%DIST_DIR%"

echo [SEARCH] Preparing fd %FD_VERSION%...
call :download_and_verify "%FD_URL%" "%FD_ZIP%" "%FD_SHA256%" "fd"
if errorlevel 1 exit /b 1

echo [SEARCH] Preparing ripgrep %RG_VERSION%...
call :download_and_verify "%RG_URL%" "%RG_ZIP%" "%RG_SHA256%" "ripgrep"
if errorlevel 1 exit /b 1

if exist "%TEMP_DIR%" rmdir /s /q "%TEMP_DIR%"
mkdir "%FD_TEMP%"
mkdir "%RG_TEMP%"

7z x "%FD_ZIP%" -o"%FD_TEMP%" -y >nul
if errorlevel 1 (
    echo [ERROR] Failed to extract %FD_ARCHIVE%.
    exit /b 1
)

7z x "%RG_ZIP%" -o"%RG_TEMP%" -y >nul
if errorlevel 1 (
    echo [ERROR] Failed to extract %RG_ARCHIVE%.
    exit /b 1
)

set "FD_EXE=%FD_ROOT%\fd.exe"
if not exist "%FD_EXE%" (
    set "FD_EXE="
    for /r "%FD_TEMP%" %%F in (fd.exe) do if not defined FD_EXE set "FD_EXE=%%~fF"
)
if not defined FD_EXE (
    echo [ERROR] fd.exe is missing from %FD_ARCHIVE%.
    exit /b 1
)
for %%D in ("%FD_EXE%") do set "FD_SRC=%%~dpD"

set "RG_EXE=%RG_ROOT%\rg.exe"
if not exist "%RG_EXE%" (
    set "RG_EXE="
    for /r "%RG_TEMP%" %%F in (rg.exe) do if not defined RG_EXE set "RG_EXE=%%~fF"
)
if not defined RG_EXE (
    echo [ERROR] rg.exe is missing from %RG_ARCHIVE%.
    exit /b 1
)
for %%D in ("%RG_EXE%") do set "RG_SRC=%%~dpD"

if exist "%FD_DIST%" rmdir /s /q "%FD_DIST%"
if exist "%RG_DIST%" rmdir /s /q "%RG_DIST%"
mkdir "%FD_DIST%"
mkdir "%RG_DIST%"

copy /Y "%SCRIPT_DIR%fd\plugin.json" "%FD_DIST%\" >nul
copy /Y "%SCRIPT_DIR%fd\THIRD_PARTY_NOTICES.txt" "%FD_DIST%\" >nul
copy /Y "%FD_EXE%" "%FD_DIST%\" >nul
for %%F in (LICENSE-APACHE LICENSE-MIT) do if exist "%FD_SRC%%%F" copy /Y "%FD_SRC%%%F" "%FD_DIST%\" >nul

copy /Y "%SCRIPT_DIR%ripgrep\plugin.json" "%RG_DIST%\" >nul
copy /Y "%SCRIPT_DIR%ripgrep\THIRD_PARTY_NOTICES.txt" "%RG_DIST%\" >nul
copy /Y "%RG_EXE%" "%RG_DIST%\" >nul
for %%F in (COPYING LICENSE-MIT UNLICENSE) do if exist "%RG_SRC%%%F" copy /Y "%RG_SRC%%%F" "%RG_DIST%\" >nul

if not exist "%FD_DIST%\fd.exe" (
    echo [ERROR] Failed to install the fd search plugin.
    exit /b 1
)
if not exist "%RG_DIST%\rg.exe" (
    echo [ERROR] Failed to install the ripgrep search plugin.
    exit /b 1
)

rmdir /s /q "%TEMP_DIR%"
echo [SEARCH] Installed search plugins to: %DIST_DIR%
exit /b 0

:download_and_verify
set "DOWNLOAD_URL=%~1"
set "DOWNLOAD_FILE=%~2"
set "EXPECTED_SHA=%~3"
set "DISPLAY_NAME=%~4"

if exist "!DOWNLOAD_FILE!" (
    call :verify_sha256 "!DOWNLOAD_FILE!" "!EXPECTED_SHA!"
    if not errorlevel 1 exit /b 0
    echo [WARN] Cached !DISPLAY_NAME! archive failed verification; downloading again.
    del /q "!DOWNLOAD_FILE!"
)

curl.exe --fail --location --silent --show-error --retry 3 --retry-delay 2 -o "!DOWNLOAD_FILE!" "!DOWNLOAD_URL!"
if errorlevel 1 (
    del /q "!DOWNLOAD_FILE!" 2>nul
    echo [ERROR] Failed to download !DISPLAY_NAME!.
    exit /b 1
)

call :verify_sha256 "!DOWNLOAD_FILE!" "!EXPECTED_SHA!"
if errorlevel 1 (
    del /q "!DOWNLOAD_FILE!" 2>nul
    echo [ERROR] SHA-256 verification failed for !DISPLAY_NAME!.
    exit /b 1
)
exit /b 0

:verify_sha256
set "INF_DIR_SEARCH_HASH_FILE=%~1"
set "ACTUAL_SHA="
for /f "usebackq delims=" %%H in (`powershell -NoProfile -Command "(Get-FileHash -LiteralPath $env:INF_DIR_SEARCH_HASH_FILE -Algorithm SHA256).Hash.ToLowerInvariant()"`) do set "ACTUAL_SHA=%%H"
if not defined ACTUAL_SHA exit /b 1
if /I not "!ACTUAL_SHA!"=="%~2" exit /b 1
exit /b 0

@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM ============================================================
REM  Shared viewer runtimes
REM
REM  Prepares the tools used by more than one viewer. The root plugins\build.bat
REM  installs this directory as plugins\dist\inf-dir.runtime\, and each viewer
REM  resolves the tools from there (see docs\viewer-technology-stack.md 4.4).
REM
REM    djvulibre\ddjvu.exe            DjVu -> PDF                (ebook-view)
REM    gxps\gxpswin64.exe             XPS/OXPS -> PDF            (pdfjs-view)
REM    libreoffice\program\soffice.exe Office/ODF/CAD -> PDF,     (pdfjs-view)
REM                                   legacy spreadsheets -> xlsx (excel-view),
REM                                   Visio -> SVG                (web-view)
REM ============================================================

set "SCRIPT_DIR=%~dp0"
set "CACHE_DIR=%SCRIPT_DIR%_cache"
set "TEMP_DIR=%SCRIPT_DIR%_runtime_tmp"
set "DJVU_DIR=%SCRIPT_DIR%djvulibre"
set "GXPS_DIR=%SCRIPT_DIR%gxps"
set "LO_DIR=%SCRIPT_DIR%libreoffice"

set "DJVU_ARCHIVE=%CACHE_DIR%\DjVuLibre-3.5.29_DjView-4.12_Setup.exe"
set "DJVU_URL=https://sourceforge.net/projects/djvu/files/DjVuLibre_Windows/3.5.29%%2B4.12/DjVuLibre-3.5.29_DjView-4.12_Setup.exe/download"
set "DJVU_SHA=92233fbf891c63f3fb7a0b5e1ce108baa4c29a40c89a442d1313f883aae84670"

REM GhostXPS is the XPS/OpenXPS interpreter of the GhostPDL family. Artifex
REM attaches the ghostxps asset to the matching Ghostscript release tag (gs10080
REM for version 10.08.0), which keeps the download URL stable and versioned.
set "GXPS_VERSION=10.08.0"
set "GXPS_TAG=gs10080"
set "GXPS_ARCHIVE=%CACHE_DIR%\ghostxps-%GXPS_VERSION%-win64.zip"
set "GXPS_URL=https://github.com/ArtifexSoftware/ghostpdl-downloads/releases/download/%GXPS_TAG%/ghostxps-%GXPS_VERSION%-win64.zip"
set "GXPS_SHA=b842043d43b61c1bfacb294537ee4916a3c5d765828bf17ccffe08d85b99d282"
set "GXPS_EXTRACT_DIR=ghostxps-%GXPS_VERSION%-win64"

REM LibreOffice headless converts documents Office viewers cannot open natively.
REM The archive is NOT an upstream LibreOffice release: the Windows upstream
REM package is an .msi without the flat "instdir" tree this viewer starts. It is
REM pinned by SHA-256 so a changed artifact fails the build instead of shipping.
set "LO_VERSION=26.2.5"
set "LO_ARCHIVE=%CACHE_DIR%\instdir.7z"
set "LO_URL=https://github.com/lyj-514328/core/releases/download/windows-build/instdir.7z"
set "LO_SHA=17047c570c52d97379f82dd5adfb1fe351a225800150d1b1b653536415be1768"

if not exist "%CACHE_DIR%" mkdir "%CACHE_DIR%"

call :prepare_djvu
if errorlevel 1 exit /b 1
call :prepare_gxps
if errorlevel 1 exit /b 1
call :prepare_libreoffice
if errorlevel 1 exit /b 1

echo [DOC] Shared runtimes ready: djvulibre, gxps, libreoffice.
exit /b 0

:prepare_djvu
if exist "%DJVU_DIR%\ddjvu.exe" exit /b 0
if not exist "%DJVU_ARCHIVE%" (
    echo [DOC] Downloading DjVuLibre...
    curl.exe --fail --location --retry 3 --retry-delay 2 -o "%DJVU_ARCHIVE%" "%DJVU_URL%"
    if errorlevel 1 exit /b 1
)
call :verify "%DJVU_ARCHIVE%" "%DJVU_SHA%"
if errorlevel 1 exit /b 1
if exist "%TEMP_DIR%" rmdir /s /q "%TEMP_DIR%"
mkdir "%TEMP_DIR%"
7z x "%DJVU_ARCHIVE%" -o"%TEMP_DIR%" -y >nul
if errorlevel 1 exit /b 1
if exist "%DJVU_DIR%" rmdir /s /q "%DJVU_DIR%"
mkdir "%DJVU_DIR%"
for %%F in (ddjvu.exe libdjvulibre.dll libjpeg.dll libtiff.dll libz.dll COPYING.txt) do if exist "%TEMP_DIR%\%%F" copy /Y "%TEMP_DIR%\%%F" "%DJVU_DIR%\" >nul
rmdir /s /q "%TEMP_DIR%"
if not exist "%DJVU_DIR%\ddjvu.exe" exit /b 1
exit /b 0

:prepare_gxps
if exist "%GXPS_DIR%\gxpswin64.exe" exit /b 0
if not exist "%GXPS_ARCHIVE%" (
    echo [DOC] Downloading GhostXPS %GXPS_VERSION%...
    curl.exe --fail --location --retry 3 --retry-delay 2 -o "%GXPS_ARCHIVE%" "%GXPS_URL%"
    if errorlevel 1 exit /b 1
)
call :verify "%GXPS_ARCHIVE%" "%GXPS_SHA%"
if errorlevel 1 exit /b 1
if exist "%TEMP_DIR%" rmdir /s /q "%TEMP_DIR%"
mkdir "%TEMP_DIR%"
7z x "%GXPS_ARCHIVE%" -o"%TEMP_DIR%" -y >nul
if errorlevel 1 exit /b 1
if exist "%GXPS_DIR%" rmdir /s /q "%GXPS_DIR%"
mkdir "%GXPS_DIR%"
REM Ship the interpreter, the command line driver and every license file from
REM the archive; only the two bundled sample .xps files are left out.
for %%F in (gxpswin64.exe gxpsdll64.dll COPYING COPYING.AFPL LICENSE README.txt) do if exist "%TEMP_DIR%\%GXPS_EXTRACT_DIR%\%%F" copy /Y "%TEMP_DIR%\%GXPS_EXTRACT_DIR%\%%F" "%GXPS_DIR%\" >nul
rmdir /s /q "%TEMP_DIR%"
if not exist "%GXPS_DIR%\gxpswin64.exe" exit /b 1
if not exist "%GXPS_DIR%\gxpsdll64.dll" exit /b 1
exit /b 0

:prepare_libreoffice
REM The completeness markers must be files this pinned archive really contains.
REM A previous check required help\idxcaption.xsl, which is not part of the
REM instdir tree, so every build deleted the 472 MB runtime and extracted it
REM again.
if exist "%LO_DIR%\program\soffice.exe" if exist "%LO_DIR%\program\soffice.bin" if exist "%LO_DIR%\program\version.ini" (
    del /q "%LO_DIR%\*.msi" 2>nul
    exit /b 0
)
if not exist "%LO_ARCHIVE%" (
    echo [DOC] Downloading LibreOffice %LO_VERSION%...
    curl.exe --fail --location --retry 3 --retry-delay 2 -o "%LO_ARCHIVE%" "%LO_URL%"
    if errorlevel 1 exit /b 1
)
call :verify "%LO_ARCHIVE%" "%LO_SHA%"
if errorlevel 1 exit /b 1
if exist "%TEMP_DIR%" rmdir /s /q "%TEMP_DIR%"
mkdir "%TEMP_DIR%"
echo [DOC] Extracting the LibreOffice runtime archive...
7z x "%LO_ARCHIVE%" -o"%TEMP_DIR%" -y >nul
if errorlevel 1 exit /b 1
REM The archive wraps everything in instdir\; flatten it so the runtime root
REM holds program\, share\ and friends directly.
if exist "%TEMP_DIR%\instdir\program\soffice.exe" (
    xcopy /E /I /Y /Q "%TEMP_DIR%\instdir\*" "%TEMP_DIR%\" >nul
    rmdir /s /q "%TEMP_DIR%\instdir"
)
if not exist "%TEMP_DIR%\program\soffice.exe" (
    echo [ERROR] LibreOffice extraction did not contain soffice.exe.
    exit /b 1
)
if exist "%LO_DIR%" rmdir /s /q "%LO_DIR%"
mkdir "%LO_DIR%"
xcopy /E /I /Y /Q "%TEMP_DIR%\*" "%LO_DIR%\" >nul
if errorlevel 1 (
    echo [ERROR] Failed to copy the LibreOffice runtime.
    exit /b 1
)
del /q "%LO_DIR%\*.msi" 2>nul
rmdir /s /q "%TEMP_DIR%"
if not exist "%LO_DIR%\program\soffice.exe" exit /b 1
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

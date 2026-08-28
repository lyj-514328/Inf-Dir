@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM Prepare the portable ImageMagick runtime used for extended image/RAW/font decoding.
set "SCRIPT_DIR=%~dp0"
set "CACHE_DIR=%SCRIPT_DIR%_cache"
set "TEMP_DIR=%SCRIPT_DIR%_magick_tmp"
set "RUNTIME_DIR=%SCRIPT_DIR%magick"
set "COMPFACE_DIR=%SCRIPT_DIR%compface"
set "COMPFACE_ARCHIVE=%CACHE_DIR%\compface-1.5.2-bin.zip"
set "COMPFACE_URL=https://downloads.sourceforge.net/gnuwin32/compface-1.5.2-bin.zip"
set "COMPFACE_SHA=ea9ae88a6380d7b0f8398ce12d6e0f35003b6b141f768c7a74dd7fe90dc50e34"
set "LIBRAW_DIR=%SCRIPT_DIR%libraw-decoder"
set "LIBRAW_ARCHIVE=%CACHE_DIR%\LibRaw-0.22.2-Win64.zip"
set "LIBRAW_URL=https://www.libraw.org/data/LibRaw-0.22.2-Win64.zip"
set "LIBRAW_SHA=ac64fa12bb00a7581332d4c6ab918c0533fb3f119d6b668d47a6875410dca948"
set "LIBRAW_BUILD_DIR=%TEMP_DIR%\libraw-build"
set "ARCHIVE=%CACHE_DIR%\ImageMagick-LibRaw-x64.zip"
set "URL=https://github.com/lyj-514328/ImageMagick/releases/download/7.1.2-30/ImageMagick-LibRaw-x64.zip"
set "SHA=e7ddd77c100560e92379dc0a8d3135f46c09cf6296cbe85e83ba733991bdaeb8"

if not exist "%CACHE_DIR%" mkdir "%CACHE_DIR%"
if not exist "%RUNTIME_DIR%\magick.exe" (
    call :prepare_magick
) else if not exist "%RUNTIME_DIR%\CORE_RL_raw_.dll" (
    call :prepare_magick
) else if not exist "%RUNTIME_DIR%\IM_MOD_RL_dng_.dll" (
    call :prepare_magick
)
if errorlevel 1 exit /b 1
if not exist "%COMPFACE_DIR%\uncompface.exe" call :prepare_compface
if errorlevel 1 exit /b 1
if not exist "%LIBRAW_DIR%\libraw-decoder.exe" (
    call :prepare_libraw
) else if not exist "%LIBRAW_DIR%\libraw.dll" (
    call :prepare_libraw
)
if errorlevel 1 exit /b 1
goto :done

:prepare_magick

if not exist "%ARCHIVE%" (
    echo [IMG] Downloading ImageMagick...
    curl.exe --fail --location --retry 3 --retry-delay 2 -o "%ARCHIVE%" "%URL%"
    if errorlevel 1 exit /b 1
)
for /f "usebackq delims=" %%H in (`powershell -NoProfile -Command "(Get-FileHash -LiteralPath '%ARCHIVE%' -Algorithm SHA256).Hash.ToLowerInvariant()"`) do set "ACTUAL_SHA=%%H"
if /I not "!ACTUAL_SHA!"=="%SHA%" (
    echo [ERROR] ImageMagick archive SHA-256 mismatch.
    exit /b 1
)

if exist "%TEMP_DIR%" rmdir /s /q "%TEMP_DIR%"
mkdir "%TEMP_DIR%"
7z x "%ARCHIVE%" -o"%TEMP_DIR%" -y >nul
if errorlevel 1 exit /b 1
if not exist "%TEMP_DIR%\Artifacts\bin\magick.exe" (
    echo [ERROR] ImageMagick archive layout unexpected.
    exit /b 1
)
if exist "%RUNTIME_DIR%" rmdir /s /q "%RUNTIME_DIR%"
mkdir "%RUNTIME_DIR%"
robocopy "%TEMP_DIR%\Artifacts\bin" "%RUNTIME_DIR%" /E /XF *.pdb /NFL /NDL /NJH /NJS /NP >nul
if errorlevel 8 exit /b 1
rmdir /s /q "%TEMP_DIR%"
exit /b 0

:prepare_compface
if not exist "%COMPFACE_ARCHIVE%" (
    echo [IMG] Downloading Compface...
    curl.exe --fail --location --retry 3 --retry-delay 2 -o "%COMPFACE_ARCHIVE%" "%COMPFACE_URL%"
    if errorlevel 1 exit /b 1
)
for /f "usebackq delims=" %%H in (`powershell -NoProfile -Command "(Get-FileHash -LiteralPath '%COMPFACE_ARCHIVE%' -Algorithm SHA256).Hash.ToLowerInvariant()"`) do set "ACTUAL_SHA=%%H"
if /I not "!ACTUAL_SHA!"=="%COMPFACE_SHA%" (
    echo [ERROR] Compface archive SHA-256 mismatch.
    exit /b 1
)
if exist "%TEMP_DIR%" rmdir /s /q "%TEMP_DIR%"
mkdir "%TEMP_DIR%"
7z x "%COMPFACE_ARCHIVE%" -o"%TEMP_DIR%" -y >nul
if errorlevel 1 exit /b 1
if exist "%COMPFACE_DIR%" rmdir /s /q "%COMPFACE_DIR%"
mkdir "%COMPFACE_DIR%"
copy /Y "%TEMP_DIR%\bin\uncompface.exe" "%COMPFACE_DIR%\" >nul
copy /Y "%TEMP_DIR%\bin\compface1.dll" "%COMPFACE_DIR%\" >nul
copy /Y "%TEMP_DIR%\contrib\compface\1.5.2\compface-1.5.2-src\README" "%COMPFACE_DIR%\" >nul
rmdir /s /q "%TEMP_DIR%"
if not exist "%COMPFACE_DIR%\uncompface.exe" exit /b 1
exit /b 0

:prepare_libraw

if not exist "%LIBRAW_ARCHIVE%" (
    echo [IMG] Downloading LibRaw Win64...
    curl.exe --fail --location --retry 3 --retry-delay 2 -o "%LIBRAW_ARCHIVE%" "%LIBRAW_URL%"
    if errorlevel 1 exit /b 1
)
for /f "usebackq delims=" %%H in (`powershell -NoProfile -Command "(Get-FileHash -LiteralPath '%LIBRAW_ARCHIVE%' -Algorithm SHA256).Hash.ToLowerInvariant()"`) do set "ACTUAL_SHA=%%H"
if /I not "!ACTUAL_SHA!"=="%LIBRAW_SHA%" (
    echo [ERROR] LibRaw archive SHA-256 mismatch.
    exit /b 1
)

if exist "%TEMP_DIR%" rmdir /s /q "%TEMP_DIR%"
mkdir "%TEMP_DIR%"
7z x "%LIBRAW_ARCHIVE%" -o"%TEMP_DIR%" -y >nul
if errorlevel 1 exit /b 1
set "LIBRAW_ROOT=%TEMP_DIR%\LibRaw-0.22.2"
if not exist "%LIBRAW_ROOT%\bin\libraw.dll" (
    echo [ERROR] LibRaw archive layout unexpected.
    exit /b 1
)
if exist "%LIBRAW_BUILD_DIR%" rmdir /s /q "%LIBRAW_BUILD_DIR%"
cmake -S "%SCRIPT_DIR%libraw-decoder" -B "%LIBRAW_BUILD_DIR%" -DLIBRAW_ROOT="%LIBRAW_ROOT%" -DLIBRAW_LIB="%LIBRAW_ROOT%\lib\libraw.lib"
if errorlevel 1 exit /b 1
cmake --build "%LIBRAW_BUILD_DIR%" --config Release --target libraw-decoder
if errorlevel 1 exit /b 1
if not exist "%LIBRAW_BUILD_DIR%\out\libraw-decoder.exe" (
    echo [ERROR] CMake did not produce libraw-decoder.exe.
    exit /b 1
)
if not exist "%LIBRAW_DIR%" mkdir "%LIBRAW_DIR%"
copy /Y "%LIBRAW_BUILD_DIR%\out\libraw-decoder.exe" "%LIBRAW_DIR%\" >nul
copy /Y "%LIBRAW_ROOT%\bin\libraw.dll" "%LIBRAW_DIR%\" >nul
rmdir /s /q "%TEMP_DIR%"
if not exist "%LIBRAW_DIR%\libraw-decoder.exe" exit /b 1
if not exist "%LIBRAW_DIR%\libraw.dll" exit /b 1
exit /b 0

:done
if not exist "%RUNTIME_DIR%\magick.exe" (
    echo [ERROR] ImageMagick runtime is incomplete.
    exit /b 1
)
if not exist "%RUNTIME_DIR%\CORE_RL_raw_.dll" (
    echo [ERROR] ImageMagick RAW delegate is missing.
    exit /b 1
)
if not exist "%RUNTIME_DIR%\IM_MOD_RL_dng_.dll" (
    echo [ERROR] ImageMagick DNG coder module is missing.
    exit /b 1
)
if not exist "%LIBRAW_DIR%\libraw-decoder.exe" (
    echo [ERROR] LibRaw decoder runtime is incomplete.
    exit /b 1
)
if not exist "%LIBRAW_DIR%\libraw.dll" (
    echo [ERROR] LibRaw DLL runtime is incomplete.
    exit /b 1
)
echo [IMG] ImageMagick runtime ready.
endlocal

@echo off
setlocal

REM Prerequisites: .NET SDK (>= 8), NuGet access (MuPDF.NET + native assets are
REM pulled from nuget.org on first publish).

set "OUTPUT_DIR=bin\Release\net10.0-windows\win-x64\publish"

REM Prefer the scoop-installed SDK, fall back to PATH.
set "DOTNET=%USERPROFILE%\scoop\apps\dotnet-sdk\current\dotnet.exe"
if not exist "%DOTNET%" set "DOTNET=dotnet"

"%DOTNET%" publish -c Release -r win-x64 --self-contained true -p:PublishSingleFile=false -p:PublishReadyToRun=false -p:DebugType=None -p:DebugSymbols=false
if errorlevel 1 (
    echo [ERROR] mupdf-view publish failed.
    exit /b 1
)

REM MuPDF.Fonts.dll is only used by the TextWriter API (not by the viewer);
REM drop it to keep the package smaller.
if exist "%OUTPUT_DIR%\MuPDF.Fonts.dll" del /q "%OUTPUT_DIR%\MuPDF.Fonts.dll"
REM Third-party packages may ship their own PDB files.
del /q "%OUTPUT_DIR%\*.pdb" 2>nul

echo.
echo [DONE] %OUTPUT_DIR%\mupdf-view.exe
endlocal

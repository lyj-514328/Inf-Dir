@echo off
setlocal EnableExtensions

set "SCRIPT_DIR=%~dp0"
set "OUTPUT_DIR=%SCRIPT_DIR%target\release"
set "PARSER_PUBLISH=%SCRIPT_DIR%parser\bin\Release\net8.0\win-x64\publish"

if exist "%USERPROFILE%\scoop\apps\dotnet-sdk\current\dotnet.exe" (
    set "DOTNET_EXE=%USERPROFILE%\scoop\apps\dotnet-sdk\current\dotnet.exe"
) else (
    set "DOTNET_EXE=dotnet"
)

pushd "%SCRIPT_DIR%parser"
"%DOTNET_EXE%" publish EmailParse.csproj -c Release
if errorlevel 1 ( popd & exit /b 1 )
popd

"%PARSER_PUBLISH%\email-parse.exe" --self-test
if errorlevel 1 exit /b 1

pushd "%SCRIPT_DIR%"
cargo build --release
if errorlevel 1 (
    popd
    exit /b 1
)
popd

if not exist "%OUTPUT_DIR%\email-view.exe" (
    echo [ERROR] email-view.exe was not built.
    exit /b 1
)

echo [DONE] %OUTPUT_DIR%\email-view.exe
endlocal

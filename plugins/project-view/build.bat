@echo off
setlocal
set "OUTPUT_DIR=%~dp0bin\Release\net10.0-windows\win-x64\publish"
set "DOTNET=%USERPROFILE%\scoop\apps\dotnet-sdk\current\dotnet.exe"
if not exist "%DOTNET%" set "DOTNET=dotnet"
pushd "%~dp0"
"%DOTNET%" publish project-view.csproj -c Release -r win-x64 --self-contained true -o "%OUTPUT_DIR%" -p:PublishReadyToRun=false -p:DebugType=None -p:DebugSymbols=false
if errorlevel 1 ( popd & exit /b 1 )
del /q "%OUTPUT_DIR%\*.pdb" 2>nul
start "" /wait "%OUTPUT_DIR%\project-view.exe" --self-test
if errorlevel 1 ( popd & exit /b 1 )
popd
echo [DONE] %OUTPUT_DIR%\project-view.exe
endlocal

@echo off
setlocal enabledelayedexpansion

REM ============================================================
REM  Inf-Dir plugins one-click build script
REM  Prerequisites: rustup, cargo, Node.js/npm, .NET SDK, curl, PowerShell, 7z, JDK 17+ (project-view)
REM ============================================================

set "SCRIPT_DIR=%~dp0"
set "DIST_DIR=%SCRIPT_DIR%dist"
set "MPV_DEV_URL=https://github.com/shinchiro/mpv-winbuild-cmake/releases/download/20260610/mpv-dev-x86_64-20260610-git-304426c.7z"
set "MPV_DEV_7Z=%SCRIPT_DIR%video-view\mpv-dev.7z"
set "MPV_DEV_DIR=%SCRIPT_DIR%video-view\mpv-dev"
set "LIBARCHIVE_URL=https://github.com/li-ruijie/libarchive/releases/download/v3.8.9/libarchive-v3.8.9-windows-msvc-x64-static.zip"
set "LIBARCHIVE_ZIP=%SCRIPT_DIR%archive-view\libarchive.zip"
set "LIBARCHIVE_DEPS=%SCRIPT_DIR%archive-view\libarchive"
set "OOXML_VERSION=0.75.4"
set "OOXML_URL=https://registry.npmjs.org/@silurus/ooxml/-/ooxml-%OOXML_VERSION%.tgz"
set "OOXML_TGZ=%SCRIPT_DIR%office-view\_ooxml.tgz"
set "OOXML_WEB=%SCRIPT_DIR%office-view-web"
set "MDIT_VERSION=14.1.0"
set "KATEX_VERSION=0.16.11"
set "HLJS_VERSION=11.10.0"
set "GHCSS_VERSION=5.7.0"
set "MERMAID_VERSION=11.4.1"
set "MD_WEB=%SCRIPT_DIR%markdown-view-web"
set "CODE_WEB=%SCRIPT_DIR%code-view-web"
set "EMAIL_WEB=%SCRIPT_DIR%email-view-web"
set "EMAIL_PUBLISH=%SCRIPT_DIR%email-view\publish"
set "FONT_PUBLISH=%SCRIPT_DIR%font-view\bin\Release\net8.0-windows\win-x64\publish"
set "PROJECT_PUBLISH=%SCRIPT_DIR%project-view\bin\Release\project-view"
set "ONLYOFFICE_RUNTIME_URL=https://github.com/ONLYOFFICE/DocumentBuilder/releases/download/v9.4.0/onlyoffice-documentbuilder-windows-x64.zip"
set "ONLYOFFICE_RUNTIME_ZIP=%SCRIPT_DIR%onlyoffice-view\_documentbuilder-v9.4.0-windows-x64.zip"
set "ONLYOFFICE_RUNTIME_DIR=%SCRIPT_DIR%onlyoffice-view\_documentbuilder-runtime-v9.4.0"

REM Prefer the Scoop SDK because a machine-wide dotnet host may have no SDK.
if exist "%USERPROFILE%\scoop\apps\dotnet-sdk\current\dotnet.exe" (
    set "DOTNET_EXE=%USERPROFILE%\scoop\apps\dotnet-sdk\current\dotnet.exe"
) else (
    set "DOTNET_EXE=dotnet"
)

REM --- Download and package pinned search-provider plugins ---
call "%SCRIPT_DIR%search\build.bat" "%DIST_DIR%"
if errorlevel 1 (
    echo [ERROR] Search plugin build failed.
    exit /b 1
)

REM --- Download and package the bundled 7-Zip archive-operation plugin ---
call "%SCRIPT_DIR%archive\build.bat" "%DIST_DIR%"
if errorlevel 1 (
    echo [ERROR] Archive plugin build failed.
    exit /b 1
)

REM --- Prepare extended image and document runtimes ---
call "%SCRIPT_DIR%img-view\build.bat"
if errorlevel 1 (
    echo [ERROR] ImageMagick runtime preparation failed.
    exit /b 1
)
call "%SCRIPT_DIR%mupdf-view\build-runtime.bat"
if errorlevel 1 (
    echo [ERROR] Document conversion runtime preparation failed.
    exit /b 1
)

REM --- Add MinGW-w64 (ucrt64) to PATH for GNU target ---
if exist "C:\msys64\ucrt64\bin" (
    set "PATH=C:\msys64\ucrt64\bin;%PATH%"
) else (
    echo [WARN] C:\msys64\ucrt64\bin not found, video-view ^(GNU target^) may fail.
)

REM ============================================================
REM  0. Prepare the official ONLYOFFICE Document Builder runtime
REM ============================================================
if not exist "%ONLYOFFICE_RUNTIME_DIR%\docbuilder.exe" (
    echo [0/19] Downloading the official ONLYOFFICE Document Builder runtime v9.4.0...
    if not exist "%ONLYOFFICE_RUNTIME_ZIP%" (
        curl -L --fail -o "%ONLYOFFICE_RUNTIME_ZIP%" "%ONLYOFFICE_RUNTIME_URL%"
        if errorlevel 1 (
            echo [ERROR] Failed to download the ONLYOFFICE Document Builder runtime.
            exit /b 1
        )
    )
    if exist "%ONLYOFFICE_RUNTIME_DIR%" rmdir /s /q "%ONLYOFFICE_RUNTIME_DIR%"
    mkdir "%ONLYOFFICE_RUNTIME_DIR%"
    7z x "%ONLYOFFICE_RUNTIME_ZIP%" -o"%ONLYOFFICE_RUNTIME_DIR%" -y >nul
    if errorlevel 1 (
        echo [ERROR] Failed to extract the ONLYOFFICE Document Builder runtime.
        exit /b 1
    )
    if not exist "%ONLYOFFICE_RUNTIME_DIR%\docbuilder.exe" (
        echo [ERROR] The downloaded runtime does not contain docbuilder.exe.
        exit /b 1
    )
    del "%ONLYOFFICE_RUNTIME_ZIP%" 2>nul
) else (
    echo [0/19] ONLYOFFICE runtime v9.4.0 already present, skipping download.
)
if not exist "%ONLYOFFICE_RUNTIME_DIR%\docbuilder.exe" (
    echo [ERROR] The ONLYOFFICE runtime does not contain docbuilder.exe.
    exit /b 1
)
if not exist "%ONLYOFFICE_RUNTIME_DIR%\x2t.exe" (
    echo [ERROR] The ONLYOFFICE runtime does not contain x2t.exe.
    exit /b 1
)

REM --- Ensure rustup target ---
rustup target add x86_64-pc-windows-gnu >nul 2>&1

REM ============================================================
REM  1. Prepare mpv-dev for video-view
REM ============================================================
if not exist "%MPV_DEV_DIR%\libmpv-2.dll" (
    echo [1/14] Downloading mpv-dev...
    if not exist "%MPV_DEV_7Z%" (
        curl -L -o "%MPV_DEV_7Z%" "%MPV_DEV_URL%"
        if errorlevel 1 (
            echo [ERROR] Failed to download mpv-dev.
            exit /b 1
        )
    )
    echo [1/14] Extracting mpv-dev...
    if not exist "%MPV_DEV_DIR%" mkdir "%MPV_DEV_DIR%"
    7z x "%MPV_DEV_7Z%" -o"%MPV_DEV_DIR%" -y >nul
    if errorlevel 1 (
        echo [ERROR] Failed to extract mpv-dev.
        exit /b 1
    )
    del "%MPV_DEV_7Z%" 2>nul
) else (
    echo [1/14] mpv-dev already present, skipping.
)

REM ============================================================
REM  2. Prepare libarchive for archive-view
REM ============================================================
if not exist "%LIBARCHIVE_DEPS%\lib\libarchive.lib" (
    echo [2/14] Downloading libarchive...
    if not exist "%LIBARCHIVE_ZIP%" (
        curl -L -o "%LIBARCHIVE_ZIP%" "%LIBARCHIVE_URL%"
        if errorlevel 1 (
            echo [ERROR] Failed to download libarchive.
            exit /b 1
        )
    )
    echo [2/14] Extracting libarchive...
    set "LA_TMP=%SCRIPT_DIR%archive-view\_la_tmp"
    if not exist "!LA_TMP!" mkdir "!LA_TMP!"
    7z x "%LIBARCHIVE_ZIP%" -o"!LA_TMP!" -y >nul
    if errorlevel 1 (
        echo [ERROR] Failed to extract libarchive.
        exit /b 1
    )
    if not exist "%LIBARCHIVE_DEPS%\include" mkdir "%LIBARCHIVE_DEPS%\include"
    if not exist "%LIBARCHIVE_DEPS%\lib" mkdir "%LIBARCHIVE_DEPS%\lib"
    if not exist "%LIBARCHIVE_DEPS%\bin" mkdir "%LIBARCHIVE_DEPS%\bin"
    copy /Y "!LA_TMP!\include\archive.h" "%LIBARCHIVE_DEPS%\include\" >nul
    copy /Y "!LA_TMP!\include\archive_entry.h" "%LIBARCHIVE_DEPS%\include\" >nul
    copy /Y "!LA_TMP!\lib\libarchive.lib" "%LIBARCHIVE_DEPS%\lib\" >nul
    copy /Y "!LA_TMP!\bin\libarchive.dll" "%LIBARCHIVE_DEPS%\bin\archive.dll" >nul
    rmdir /s /q "!LA_TMP!" 2>nul
    del "%LIBARCHIVE_ZIP%" 2>nul
) else (
    echo [2/14] libarchive already present, skipping.
)

REM ============================================================
REM  3. Prepare @silurus/ooxml web assets for office-view
REM ============================================================
if not exist "%OOXML_WEB%\docx.mjs" (
    echo [3/14] Downloading @silurus/ooxml %OOXML_VERSION%...
    if not exist "%OOXML_TGZ%" (
        curl -L -o "%OOXML_TGZ%" "%OOXML_URL%"
        if errorlevel 1 (
            echo [ERROR] Failed to download @silurus/ooxml.
            exit /b 1
        )
    )
    echo [3/14] Extracting @silurus/ooxml...
    set "OOXML_TMP=%SCRIPT_DIR%office-view\_ooxml_tmp"
    if exist "!OOXML_TMP!" rmdir /s /q "!OOXML_TMP!"
    mkdir "!OOXML_TMP!"
    7z x "%OOXML_TGZ%" -o"!OOXML_TMP!" -y >nul
    if errorlevel 1 (
        echo [ERROR] Failed to extract @silurus/ooxml tarball.
        exit /b 1
    )
    REM 7z extracts _ooxml.tgz to _ooxml.tar (same prefix, .tar extension)
    7z x "!OOXML_TMP!\_ooxml.tar" -o"!OOXML_TMP!\pkg" -y >nul
    if errorlevel 1 (
        echo [ERROR] Failed to extract ooxml tar.
        exit /b 1
    )
    if not exist "%OOXML_WEB%" mkdir "%OOXML_WEB%"
    xcopy /E /I /Y /Q "!OOXML_TMP!\pkg\package\dist" "%OOXML_WEB%" >nul
    copy /Y "%SCRIPT_DIR%office-view\web\index.html" "%OOXML_WEB%\" >nul
    copy /Y "!OOXML_TMP!\pkg\package\LICENSE" "%OOXML_WEB%\" >nul
    copy /Y "!OOXML_TMP!\pkg\package\THIRD_PARTY_NOTICES.md" "%OOXML_WEB%\" >nul
    rmdir /s /q "!OOXML_TMP!" 2>nul
    del "%OOXML_TGZ%" 2>nul
) else (
    echo [3/14] @silurus/ooxml assets already present, skipping.
)

REM ============================================================
REM  4. Prepare markdown-view web assets (markdown-it / KaTeX /
REM     highlight.js / github-markdown-css / mermaid)
REM ============================================================
if not exist "%MD_WEB%\markdown-it.min.js" (
    echo [4/14] Downloading markdown-view web assets...
    set "MD_TMP=%SCRIPT_DIR%markdown-view\_web_tmp"
    if exist "!MD_TMP!" rmdir /s /q "!MD_TMP!"
    mkdir "!MD_TMP!"
    if not exist "%MD_WEB%" mkdir "%MD_WEB%"

    curl -L -o "!MD_TMP!\markdown-it.tgz" "https://registry.npmjs.org/markdown-it/-/markdown-it-%MDIT_VERSION%.tgz"
    if errorlevel 1 (
        echo [ERROR] Failed to download markdown-it.
        exit /b 1
    )
    curl -L -o "!MD_TMP!\katex.tgz" "https://registry.npmjs.org/katex/-/katex-%KATEX_VERSION%.tgz"
    if errorlevel 1 (
        echo [ERROR] Failed to download katex.
        exit /b 1
    )
    curl -L -o "!MD_TMP!\hljs.tgz" "https://registry.npmjs.org/@highlightjs/cdn-assets/-/cdn-assets-%HLJS_VERSION%.tgz"
    if errorlevel 1 (
        echo [ERROR] Failed to download highlight.js.
        exit /b 1
    )
    curl -L -o "!MD_TMP!\ghcss.tgz" "https://registry.npmjs.org/github-markdown-css/-/github-markdown-css-%GHCSS_VERSION%.tgz"
    if errorlevel 1 (
        echo [ERROR] Failed to download github-markdown-css.
        exit /b 1
    )
    curl -L -o "!MD_TMP!\mermaid.tgz" "https://registry.npmjs.org/mermaid/-/mermaid-%MERMAID_VERSION%.tgz"
    if errorlevel 1 (
        echo [ERROR] Failed to download mermaid.
        exit /b 1
    )

    echo [4/14] Extracting markdown-view web assets...
    7z x "!MD_TMP!\markdown-it.tgz" -o"!MD_TMP!\p-mdit" -y >nul
    if errorlevel 1 (
        echo [ERROR] Failed to extract markdown-it.
        exit /b 1
    )
    7z x "!MD_TMP!\p-mdit\markdown-it.tar" -o"!MD_TMP!\p-mdit\pkg" -y >nul
    if errorlevel 1 (
        echo [ERROR] Failed to extract markdown-it tar.
        exit /b 1
    )
    copy /Y "!MD_TMP!\p-mdit\pkg\package\dist\markdown-it.min.js" "%MD_WEB%\" >nul

    7z x "!MD_TMP!\katex.tgz" -o"!MD_TMP!\p-katex" -y >nul
    if errorlevel 1 (
        echo [ERROR] Failed to extract katex.
        exit /b 1
    )
    7z x "!MD_TMP!\p-katex\katex.tar" -o"!MD_TMP!\p-katex\pkg" -y >nul
    if errorlevel 1 (
        echo [ERROR] Failed to extract katex tar.
        exit /b 1
    )
    copy /Y "!MD_TMP!\p-katex\pkg\package\dist\katex.min.css" "%MD_WEB%\" >nul
    copy /Y "!MD_TMP!\p-katex\pkg\package\dist\katex.min.js" "%MD_WEB%\" >nul
    copy /Y "!MD_TMP!\p-katex\pkg\package\dist\contrib\auto-render.min.js" "%MD_WEB%\katex-auto-render.min.js" >nul
    xcopy /E /I /Y /Q "!MD_TMP!\p-katex\pkg\package\dist\fonts" "%MD_WEB%\fonts" >nul

    7z x "!MD_TMP!\hljs.tgz" -o"!MD_TMP!\p-hljs" -y >nul
    if errorlevel 1 (
        echo [ERROR] Failed to extract highlight.js.
        exit /b 1
    )
    7z x "!MD_TMP!\p-hljs\hljs.tar" -o"!MD_TMP!\p-hljs\pkg" -y >nul
    if errorlevel 1 (
        echo [ERROR] Failed to extract highlight.js tar.
        exit /b 1
    )
    copy /Y "!MD_TMP!\p-hljs\pkg\package\highlight.min.js" "%MD_WEB%\" >nul
    copy /Y "!MD_TMP!\p-hljs\pkg\package\styles\github.min.css" "%MD_WEB%\hljs-github.min.css" >nul
    copy /Y "!MD_TMP!\p-hljs\pkg\package\styles\github-dark.min.css" "%MD_WEB%\hljs-github-dark.min.css" >nul

    7z x "!MD_TMP!\ghcss.tgz" -o"!MD_TMP!\p-ghcss" -y >nul
    if errorlevel 1 (
        echo [ERROR] Failed to extract github-markdown-css.
        exit /b 1
    )
    7z x "!MD_TMP!\p-ghcss\ghcss.tar" -o"!MD_TMP!\p-ghcss\pkg" -y >nul
    if errorlevel 1 (
        echo [ERROR] Failed to extract github-markdown-css tar.
        exit /b 1
    )
    copy /Y "!MD_TMP!\p-ghcss\pkg\package\github-markdown.css" "%MD_WEB%\" >nul

    7z x "!MD_TMP!\mermaid.tgz" -o"!MD_TMP!\p-mermaid" -y >nul
    if errorlevel 1 (
        echo [ERROR] Failed to extract mermaid.
        exit /b 1
    )
    7z x "!MD_TMP!\p-mermaid\mermaid.tar" -o"!MD_TMP!\p-mermaid\pkg" -y >nul
    if errorlevel 1 (
        echo [ERROR] Failed to extract mermaid tar.
        exit /b 1
    )
    copy /Y "!MD_TMP!\p-mermaid\pkg\package\dist\mermaid.min.js" "%MD_WEB%\" >nul

    rmdir /s /q "!MD_TMP!" 2>nul
) else (
    echo [4/14] markdown-view web assets already present, skipping.
)

REM Glue files are always refreshed so edits take effect without re-downloading.
copy /Y "%SCRIPT_DIR%markdown-view\web\index.html" "%MD_WEB%\" >nul
copy /Y "%SCRIPT_DIR%markdown-view\web\app.js" "%MD_WEB%\" >nul
copy /Y "%SCRIPT_DIR%markdown-view\web\app.css" "%MD_WEB%\" >nul

REM ============================================================
REM  5. Build code-view web assets (CodeMirror + Lucide)
REM ============================================================
echo [5/14] Building code-view web assets...
where npm >nul 2>&1
if errorlevel 1 (
    echo [ERROR] npm is required to build code-view.
    exit /b 1
)
pushd "%SCRIPT_DIR%code-view"
if not exist "node_modules\esbuild\bin\esbuild" (
    call npm ci
    if errorlevel 1 ( echo [ERROR] code-view npm install failed. & popd & exit /b 1 )
)
call npm run build
if errorlevel 1 ( echo [ERROR] code-view web build failed. & popd & exit /b 1 )
popd
if not exist "%CODE_WEB%" mkdir "%CODE_WEB%"
copy /Y "%SCRIPT_DIR%code-view\web\index.html" "%CODE_WEB%\" >nul
copy /Y "%SCRIPT_DIR%code-view\web\app.css" "%CODE_WEB%\" >nul
copy /Y "%SCRIPT_DIR%code-view\THIRD_PARTY_NOTICES.txt" "%CODE_WEB%\" >nul

REM ============================================================
REM  6. Build email-view web assets (DOMPurify + Lucide)
REM ============================================================
echo [6/14] Building email-view web assets...
pushd "%SCRIPT_DIR%email-view"
if not exist "node_modules\esbuild\bin\esbuild" (
    call npm ci
    if errorlevel 1 ( echo [ERROR] email-view npm install failed. & popd & exit /b 1 )
)
call npm run build
if errorlevel 1 ( echo [ERROR] email-view web build failed. & popd & exit /b 1 )
popd
if not exist "%EMAIL_WEB%" mkdir "%EMAIL_WEB%"
copy /Y "%SCRIPT_DIR%email-view\web\index.html" "%EMAIL_WEB%\" >nul
copy /Y "%SCRIPT_DIR%email-view\web\app.css" "%EMAIL_WEB%\" >nul
copy /Y "%SCRIPT_DIR%email-view\THIRD_PARTY_NOTICES.txt" "%EMAIL_WEB%\" >nul

REM ============================================================
REM  7. Build img-view (MSVC)
REM ============================================================
echo [7/14] Building img-view...
pushd "%SCRIPT_DIR%img-view"
cargo build --release
if errorlevel 1 ( echo [ERROR] img-view build failed. & popd & exit /b 1 )
popd

REM ============================================================
REM  8. Build code-view (MSVC + WebView2)
REM ============================================================
echo [8/14] Building code-view...
pushd "%SCRIPT_DIR%code-view"
cargo build --release
if errorlevel 1 ( echo [ERROR] code-view build failed. & popd & exit /b 1 )
popd

REM ============================================================
REM  9. Build archive-view (MSVC)
REM ============================================================
echo [9/14] Building archive-view...
pushd "%SCRIPT_DIR%archive-view"
cargo build --release
if errorlevel 1 ( echo [ERROR] archive-view build failed. & popd & exit /b 1 )
popd

REM ============================================================
REM  9a. Build web-view (MSVC + WebView2)
REM ============================================================
echo [9a/20] Building web-view...
pushd "%SCRIPT_DIR%web-view"
cargo build --release
if errorlevel 1 ( echo [ERROR] web-view build failed. & popd & exit /b 1 )
popd

REM ============================================================
REM  10. Build office-view (MSVC + WebView2)
REM ============================================================
echo [10/14] Building office-view...
pushd "%SCRIPT_DIR%office-view"
cargo build --release
if errorlevel 1 ( echo [ERROR] office-view build failed. & popd & exit /b 1 )
popd

REM ============================================================
REM  12. Build markdown-view (MSVC + WebView2)
REM ============================================================
echo [12/20] Building markdown-view...
pushd "%SCRIPT_DIR%markdown-view"
cargo build --release
if errorlevel 1 ( echo [ERROR] markdown-view build failed. & popd & exit /b 1 )
popd

REM ============================================================
REM  12. Build email-view (.NET 8 self-contained + WebView2)
REM ============================================================
echo [12/14] Building email-view...
"%DOTNET_EXE%" --list-sdks | findstr /r "." >nul
if errorlevel 1 (
    echo [ERROR] A .NET SDK is required to build email-view.
    exit /b 1
)
if exist "%EMAIL_PUBLISH%" rmdir /s /q "%EMAIL_PUBLISH%"
pushd "%SCRIPT_DIR%email-view"
"%DOTNET_EXE%" publish EmailView.csproj -c Release -r win-x64 --self-contained true -o "%EMAIL_PUBLISH%"
if errorlevel 1 ( echo [ERROR] email-view publish failed. & popd & exit /b 1 )
start "" /wait "%EMAIL_PUBLISH%\email-view.exe" --self-test
if errorlevel 1 ( echo [ERROR] email-view self-test failed. & popd & exit /b 1 )
popd

REM ============================================================
REM  13. Build video-view (GNU / MinGW-w64)
REM ============================================================
echo [13/14] Building video-view...
pushd "%SCRIPT_DIR%video-view"
cargo build --release
if errorlevel 1 ( echo [ERROR] video-view build failed. & popd & exit /b 1 )
popd

REM ============================================================
REM  14. Build pdf-view (GNU / MinGW-w64 + PDFium)
REM ============================================================
echo [14/19] Building pdf-view...
pushd "%SCRIPT_DIR%pdf-view"
call build.bat
if errorlevel 1 ( echo [ERROR] pdf-view build failed. & popd & exit /b 1 )
popd

REM ============================================================
REM  15. Build pdfjs-view (MSVC + WebView2 + pdf.js)
REM ============================================================
echo [15/19] Building pdfjs-view...
pushd "%SCRIPT_DIR%pdfjs-view"
call build.bat
if errorlevel 1 ( echo [ERROR] pdfjs-view build failed. & popd & exit /b 1 )
popd

REM ============================================================
REM  16. Build onlyoffice-view (MSVC + WebView2 + ONLYOFFICE Document Builder)
REM ============================================================
echo [16/19] Building onlyoffice-view...
pushd "%SCRIPT_DIR%onlyoffice-view"
call build.bat
if errorlevel 1 ( echo [ERROR] onlyoffice-view build failed. & popd & exit /b 1 )
popd

REM ============================================================
REM  17. Build mupdf-view (.NET self-contained + MuPDF.NET)
REM ============================================================
echo [17/19] Building mupdf-view...
pushd "%SCRIPT_DIR%mupdf-view"
call build.bat
if errorlevel 1 ( echo [ERROR] mupdf-view build failed. & popd & exit /b 1 )
popd

REM ============================================================
REM  18. Build font-view (.NET self-contained + WebView2)
REM ============================================================
echo [18/19] Building font-view...
pushd "%SCRIPT_DIR%font-view"
call build.bat
if errorlevel 1 ( echo [ERROR] font-view build failed. & popd & exit /b 1 )
popd

REM ============================================================
REM  19. Build project-view (Rust/WebView2 + Java MPXJ)
REM ============================================================
echo [19/19] Building project-view...
pushd "%SCRIPT_DIR%project-view"
call build.bat
if errorlevel 1 ( echo [ERROR] project-view build failed. & popd & exit /b 1 )
popd

REM ============================================================
REM  19. Build chm-view (MSVC + WebView2 + CHMate)
REM ============================================================
echo [19/19] Building chm-view...
pushd "%SCRIPT_DIR%chm-view"
call build.bat
if errorlevel 1 ( echo [ERROR] chm-view build failed. & popd & exit /b 1 )
popd

REM ============================================================
REM  Install artifacts to plugins/
REM ============================================================
echo Installing artifacts...
if not exist "%DIST_DIR%" mkdir "%DIST_DIR%"

for %%D in (
    inf-dir.image-view
    inf-dir.code-view
    inf-dir.archive-view
    inf-dir.web-view
    inf-dir.office-view
    inf-dir.markdown-view
    inf-dir.email-view
    inf-dir.video-view
    inf-dir.pdf-view
    inf-dir.pdfjs-view
    inf-dir.onlyoffice-view
    inf-dir.mupdf-view
    inf-dir.chm-view
    inf-dir.font-view
    inf-dir.project-view
    inf-dir.vscode-open
    inf-dir.windows-terminal
) do if not exist "%DIST_DIR%\%%D" mkdir "%DIST_DIR%\%%D"

copy /Y "%SCRIPT_DIR%img-view\plugin.json" "%DIST_DIR%\inf-dir.image-view\" >nul
copy /Y "%SCRIPT_DIR%img-view\target\release\img-view.exe" "%DIST_DIR%\inf-dir.image-view\" >nul
copy /Y "%SCRIPT_DIR%img-view\THIRD_PARTY_NOTICES.txt" "%DIST_DIR%\inf-dir.image-view\" >nul
if exist "%DIST_DIR%\inf-dir.image-view\magick" rmdir /s /q "%DIST_DIR%\inf-dir.image-view\magick"
xcopy /E /I /Y /Q "%SCRIPT_DIR%img-view\magick" "%DIST_DIR%\inf-dir.image-view\magick" >nul
if exist "%DIST_DIR%\inf-dir.image-view\compface" rmdir /s /q "%DIST_DIR%\inf-dir.image-view\compface"
xcopy /E /I /Y /Q "%SCRIPT_DIR%img-view\compface" "%DIST_DIR%\inf-dir.image-view\compface" >nul
if exist "%DIST_DIR%\inf-dir.image-view\libraw-decoder" rmdir /s /q "%DIST_DIR%\inf-dir.image-view\libraw-decoder"
if not exist "%SCRIPT_DIR%img-view\libraw-decoder\libraw-decoder.exe" (
    echo [ERROR] LibRaw decoder executable is missing from the image-view build output.
    exit /b 1
)
if not exist "%SCRIPT_DIR%img-view\libraw-decoder\libraw.dll" (
    echo [ERROR] LibRaw DLL is missing from the image-view build output.
    exit /b 1
)
mkdir "%DIST_DIR%\inf-dir.image-view\libraw-decoder"
copy /Y "%SCRIPT_DIR%img-view\libraw-decoder\libraw-decoder.exe" "%DIST_DIR%\inf-dir.image-view\libraw-decoder\" >nul
if errorlevel 1 (
    echo [ERROR] Failed to install libraw-decoder.exe.
    exit /b 1
)
copy /Y "%SCRIPT_DIR%img-view\libraw-decoder\libraw.dll" "%DIST_DIR%\inf-dir.image-view\libraw-decoder\" >nul
if errorlevel 1 (
    echo [ERROR] Failed to install libraw.dll.
    exit /b 1
)
if not exist "%DIST_DIR%\inf-dir.image-view\libraw-decoder\libraw-decoder.exe" (
    echo [ERROR] Installed image-view package is missing libraw-decoder.exe.
    exit /b 1
)
if not exist "%DIST_DIR%\inf-dir.image-view\libraw-decoder\libraw.dll" (
    echo [ERROR] Installed image-view package is missing libraw.dll.
    exit /b 1
)
if exist "%DIST_DIR%\inf-dir.image-view\wic-decoder" rmdir /s /q "%DIST_DIR%\inf-dir.image-view\wic-decoder"
if not exist "%SCRIPT_DIR%img-view\wic-decoder\wic-decoder.exe" (
    echo [ERROR] WIC decoder executable is missing from the image-view build output.
    exit /b 1
)
mkdir "%DIST_DIR%\inf-dir.image-view\wic-decoder"
copy /Y "%SCRIPT_DIR%img-view\wic-decoder\wic-decoder.exe" "%DIST_DIR%\inf-dir.image-view\wic-decoder\" >nul
if errorlevel 1 (
    echo [ERROR] Failed to install wic-decoder.exe.
    exit /b 1
)
if not exist "%DIST_DIR%\inf-dir.image-view\wic-decoder\wic-decoder.exe" (
    echo [ERROR] Installed image-view package is missing wic-decoder.exe.
    exit /b 1
)
copy /Y "%SCRIPT_DIR%code-view\plugin.json" "%DIST_DIR%\inf-dir.code-view\" >nul
copy /Y "%SCRIPT_DIR%code-view\target\release\code-view.exe" "%DIST_DIR%\inf-dir.code-view\" >nul
if exist "%DIST_DIR%\inf-dir.code-view\code-view.exe.WebView2" rmdir /s /q "%DIST_DIR%\inf-dir.code-view\code-view.exe.WebView2"
if exist "%DIST_DIR%\inf-dir.code-view\code-view-web" rmdir /s /q "%DIST_DIR%\inf-dir.code-view\code-view-web"
xcopy /E /I /Y /Q "%CODE_WEB%" "%DIST_DIR%\inf-dir.code-view\code-view-web" >nul

copy /Y "%SCRIPT_DIR%web-view\plugin.json" "%DIST_DIR%\inf-dir.web-view\" >nul
copy /Y "%SCRIPT_DIR%web-view\target\release\web-view.exe" "%DIST_DIR%\inf-dir.web-view\" >nul
if exist "%DIST_DIR%\inf-dir.web-view\web-view-web" rmdir /s /q "%DIST_DIR%\inf-dir.web-view\web-view-web"
xcopy /E /I /Y /Q "%SCRIPT_DIR%web-view\web" "%DIST_DIR%\inf-dir.web-view\web-view-web" >nul

copy /Y "%SCRIPT_DIR%archive-view\plugin.json" "%DIST_DIR%\inf-dir.archive-view\" >nul
copy /Y "%SCRIPT_DIR%archive-view\target\release\archive-view.exe" "%DIST_DIR%\inf-dir.archive-view\" >nul
copy /Y "%LIBARCHIVE_DEPS%\bin\archive.dll" "%DIST_DIR%\inf-dir.archive-view\" >nul

copy /Y "%SCRIPT_DIR%office-view\plugin.json" "%DIST_DIR%\inf-dir.office-view\" >nul
copy /Y "%SCRIPT_DIR%office-view\target\release\office-view.exe" "%DIST_DIR%\inf-dir.office-view\" >nul
if exist "%DIST_DIR%\inf-dir.office-view\office-view-web" rmdir /s /q "%DIST_DIR%\inf-dir.office-view\office-view-web"
xcopy /E /I /Y /Q "%OOXML_WEB%" "%DIST_DIR%\inf-dir.office-view\office-view-web" >nul

copy /Y "%SCRIPT_DIR%markdown-view\plugin.json" "%DIST_DIR%\inf-dir.markdown-view\" >nul
copy /Y "%SCRIPT_DIR%markdown-view\target\release\markdown-view.exe" "%DIST_DIR%\inf-dir.markdown-view\" >nul
if exist "%DIST_DIR%\inf-dir.markdown-view\markdown-view-web" rmdir /s /q "%DIST_DIR%\inf-dir.markdown-view\markdown-view-web"
xcopy /E /I /Y /Q "%MD_WEB%" "%DIST_DIR%\inf-dir.markdown-view\markdown-view-web" >nul

copy /Y "%SCRIPT_DIR%chm-view\plugin.json" "%DIST_DIR%\inf-dir.chm-view\" >nul
copy /Y "%SCRIPT_DIR%chm-view\target\release\chm-view.exe" "%DIST_DIR%\inf-dir.chm-view\" >nul
copy /Y "%SCRIPT_DIR%chm-view\THIRD_PARTY_NOTICES.txt" "%DIST_DIR%\inf-dir.chm-view\" >nul
if exist "%DIST_DIR%\inf-dir.chm-view\chm-view-web" rmdir /s /q "%DIST_DIR%\inf-dir.chm-view\chm-view-web"
xcopy /E /I /Y /Q "%SCRIPT_DIR%chm-view\chm-view-web" "%DIST_DIR%\inf-dir.chm-view\chm-view-web" >nul

if exist "%DIST_DIR%\inf-dir.email-view" rmdir /s /q "%DIST_DIR%\inf-dir.email-view"
mkdir "%DIST_DIR%\inf-dir.email-view"
xcopy /E /I /Y /Q "%EMAIL_PUBLISH%\*" "%DIST_DIR%\inf-dir.email-view\" >nul
copy /Y "%SCRIPT_DIR%email-view\plugin.json" "%DIST_DIR%\inf-dir.email-view\" >nul
xcopy /E /I /Y /Q "%EMAIL_WEB%" "%DIST_DIR%\inf-dir.email-view\email-view-web" >nul

copy /Y "%SCRIPT_DIR%video-view\plugin.json" "%DIST_DIR%\inf-dir.video-view\" >nul
copy /Y "%SCRIPT_DIR%video-view\target\x86_64-pc-windows-gnu\release\video-view.exe" "%DIST_DIR%\inf-dir.video-view\" >nul
copy /Y "%MPV_DEV_DIR%\libmpv-2.dll" "%DIST_DIR%\inf-dir.video-view\" >nul

copy /Y "%SCRIPT_DIR%pdf-view\plugin.json" "%DIST_DIR%\inf-dir.pdf-view\" >nul
copy /Y "%SCRIPT_DIR%pdf-view\target\release\pdf-view.exe" "%DIST_DIR%\inf-dir.pdf-view\" >nul
copy /Y "%SCRIPT_DIR%pdf-view\target\release\pdfium.dll" "%DIST_DIR%\inf-dir.pdf-view\" >nul

copy /Y "%SCRIPT_DIR%pdfjs-view\plugin.json" "%DIST_DIR%\inf-dir.pdfjs-view\" >nul
copy /Y "%SCRIPT_DIR%pdfjs-view\target\release\pdfjs-view.exe" "%DIST_DIR%\inf-dir.pdfjs-view\" >nul
if exist "%DIST_DIR%\inf-dir.pdfjs-view\pdfjs-view.exe.WebView2" rmdir /s /q "%DIST_DIR%\inf-dir.pdfjs-view\pdfjs-view.exe.WebView2"
if exist "%DIST_DIR%\inf-dir.pdfjs-view\pdfjs-view-web" rmdir /s /q "%DIST_DIR%\inf-dir.pdfjs-view\pdfjs-view-web"
xcopy /E /I /Y /Q "%SCRIPT_DIR%pdfjs-view-web" "%DIST_DIR%\inf-dir.pdfjs-view\pdfjs-view-web" >nul

copy /Y "%SCRIPT_DIR%onlyoffice-view\plugin.json" "%DIST_DIR%\inf-dir.onlyoffice-view\" >nul
copy /Y "%SCRIPT_DIR%onlyoffice-view\target\release\onlyoffice-view.exe" "%DIST_DIR%\inf-dir.onlyoffice-view\" >nul
if exist "%DIST_DIR%\inf-dir.onlyoffice-view\onlyoffice-view-web" rmdir /s /q "%DIST_DIR%\inf-dir.onlyoffice-view\onlyoffice-view-web"
xcopy /E /I /Y /Q "%SCRIPT_DIR%onlyoffice-view-web" "%DIST_DIR%\inf-dir.onlyoffice-view\onlyoffice-view-web" >nul
if exist "%DIST_DIR%\inf-dir.onlyoffice-view\onlyoffice" rmdir /s /q "%DIST_DIR%\inf-dir.onlyoffice-view\onlyoffice"
xcopy /E /I /Y /Q "%ONLYOFFICE_RUNTIME_DIR%" "%DIST_DIR%\inf-dir.onlyoffice-view\onlyoffice" >nul
if errorlevel 1 (
    echo [ERROR] Failed to package the ONLYOFFICE runtime.
    exit /b 1
)

copy /Y "%SCRIPT_DIR%mupdf-view\plugin.json" "%DIST_DIR%\inf-dir.mupdf-view\" >nul
if exist "%DIST_DIR%\inf-dir.mupdf-view\publish" rmdir /s /q "%DIST_DIR%\inf-dir.mupdf-view\publish"
xcopy /E /I /Y /Q "%SCRIPT_DIR%mupdf-view\bin\Release\net10.0-windows\win-x64\publish" "%DIST_DIR%\inf-dir.mupdf-view" >nul
if exist "%DIST_DIR%\inf-dir.mupdf-view\djvulibre" rmdir /s /q "%DIST_DIR%\inf-dir.mupdf-view\djvulibre"
if exist "%DIST_DIR%\inf-dir.mupdf-view\libredwg" rmdir /s /q "%DIST_DIR%\inf-dir.mupdf-view\libredwg"
xcopy /E /I /Y /Q "%SCRIPT_DIR%mupdf-view\djvulibre" "%DIST_DIR%\inf-dir.mupdf-view\djvulibre" >nul
xcopy /E /I /Y /Q "%SCRIPT_DIR%mupdf-view\libredwg" "%DIST_DIR%\inf-dir.mupdf-view\libredwg" >nul
copy /Y "%SCRIPT_DIR%mupdf-view\THIRD_PARTY_NOTICES.txt" "%DIST_DIR%\inf-dir.mupdf-view\" >nul

copy /Y "%SCRIPT_DIR%font-view\plugin.json" "%DIST_DIR%\inf-dir.font-view\" >nul
xcopy /E /I /Y /Q "%FONT_PUBLISH%\*" "%DIST_DIR%\inf-dir.font-view\" >nul
copy /Y "%SCRIPT_DIR%font-view\THIRD_PARTY_NOTICES.txt" "%DIST_DIR%\inf-dir.font-view\" >nul

copy /Y "%SCRIPT_DIR%project-view\plugin.json" "%DIST_DIR%\inf-dir.project-view\" >nul
xcopy /E /I /Y /Q "%PROJECT_PUBLISH%\*" "%DIST_DIR%\inf-dir.project-view\" >nul
copy /Y "%SCRIPT_DIR%project-view\THIRD_PARTY_NOTICES.txt" "%DIST_DIR%\inf-dir.project-view\" >nul

copy /Y "%SCRIPT_DIR%vscode-open\plugin.json" "%DIST_DIR%\inf-dir.vscode-open\" >nul

copy /Y "%SCRIPT_DIR%terminal\plugin.json" "%DIST_DIR%\inf-dir.windows-terminal\" >nul

rem Quick View default associations (schema v3, manually maintained tree).
copy /Y "%SCRIPT_DIR%quick-view.default.json" "%DIST_DIR%\" >nul

echo.
echo [DONE] All plugins built and installed to: %DIST_DIR%
endlocal

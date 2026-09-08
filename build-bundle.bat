@echo off
setlocal EnableExtensions EnableDelayedExpansion
title Hermes - build the offline bundle

REM ===========================================================
REM  STEP 1 OF 2 - run this on the FAST machine.
REM
REM  Produces ONE self-contained archive, hermes-bundle.zip:
REM
REM    install.bat   the installer
REM    src\          trimmed source tree, ~60 MB, with the built
REM                  TUI and dashboard already inside hermes_cli\
REM    desktop\      the packed Electron app, ~250 MB
REM    node\         node.exe, ~80 MB - the TUI is a Node program
REM                  and the restricted machine has no Node
REM
REM  Carry that single zip to the restricted machine, unpack it
REM  anywhere and run install.bat. Nothing else has to travel with
REM  it, and npm / Electron / Node never run over there.
REM
REM  The source tree stays in the bundle on purpose. Hermes blocks
REM  wheel builds (setup.py) precisely because a wheel drops the
REM  bundled assets - skills, locales, optional-mcps, plugin
REM  manifests - which are resolved from the checkout layout.
REM  Shipping the tree costs ~60 MB against a ~310 MB bundle and
REM  keeps every asset resolving the way upstream expects.
REM
REM  Put this file in the Hermes source root (next to
REM  pyproject.toml) and run it.
REM
REM  Optional overrides:
REM    set ELECTRON_MIRROR=https://npmmirror.com/mirrors/electron/
REM    set HTTPS_PROXY=http://proxy.corp:3128
REM    set BUNDLE_OUT=D:\somewhere\hermes-bundle.zip
REM ===========================================================

set "SRC=%~dp0"
if "%SRC:~-1%"=="\" set "SRC=%SRC:~0,-1%"
set "NODEROOT=%LOCALAPPDATA%\hermes\node"
set "NODETMP=%LOCALAPPDATA%\hermes\node-download"
set "STAGE=%SRC%\.bundle-stage"
if not defined BUNDLE_OUT set "BUNDLE_OUT=%SRC%\hermes-bundle.zip"

if not exist "%SRC%\pyproject.toml" (
    echo [ERROR] pyproject.toml not found next to this script.
    echo         Place this file in the Hermes source root.
    goto :fail
)
if not exist "%SRC%\apps\desktop\package.json" (
    echo [ERROR] apps\desktop not present in this checkout.
    goto :fail
)
if not exist "%SRC%\install.bat" (
    echo [ERROR] install.bat not found next to this script.
    echo         Both scripts must sit in the source root.
    goto :fail
)

echo.
echo   source : %SRC%
echo   output : %BUNDLE_OUT%
echo.

REM ---------- 1/6  Node.js -----------------------------------
REM Root package.json engines: node ">=22.22.0". Hermes pins the
REM 22.x line (hermes_constants.py: _HERMES_NODE_TARGET_MAJOR = 22).
echo [!TIME:~0,8!] [1/6] Resolving Node.js ...
if exist "%NODEROOT%\node.exe" (
    set "PATH=%NODEROOT%;%PATH%"
    echo        using the portable Node at %NODEROOT%
)
set "NODE_OK="
where node >nul 2>&1 && (
    node -e "const v=process.versions.node.split('.').map(Number);process.exit((v[0]>22||(v[0]===22&&v[1]>=22))?0:1)" >nul 2>&1 && set "NODE_OK=1"
)
if defined NODE_OK (
    for /f "delims=" %%N in ('node -v') do echo        Node %%N - OK
) else (
    call :install_node
    if not defined NODE_OK (
        echo [ERROR] Could not provide Node.js - cannot build.
        goto :fail
    )
)

REM Node has to travel too. The restricted machine has no Node at
REM all, and install.bat sets HERMES_SKIP_NODE_BOOTSTRAP=1 so Hermes
REM is not allowed to fetch one either - which makes the staged TUI
REM bundle dead weight without it, since _node_bin("node") exits with
REM "node not found - install Node.js to use the TUI".
REM Resolved here, ahead of the slow stages, so a build that cannot
REM produce a complete bundle fails in seconds instead of minutes.
REM :install_node prepends %NODEROOT% to PATH, so `where` already
REM reports the portable copy first when this script installed one.
set "NODE_EXE="
for /f "delims=" %%N in ('where node.exe 2^>nul') do if not defined NODE_EXE set "NODE_EXE=%%N"
if not defined NODE_EXE if exist "%NODEROOT%\node.exe" set "NODE_EXE=%NODEROOT%\node.exe"
if not defined NODE_EXE (
    echo [ERROR] Node answered on PATH but no real node.exe could be
    echo         resolved, so none can be put in the bundle. A shim-only
    echo         install ^(nvm, a .cmd wrapper^) cannot be bundled.
    echo         Install Node 22.x from nodejs.org, or delete
    echo         %NODEROOT% and re-run to let this script fetch a
    echo         portable copy.
    goto :fail
)
echo        node.exe for the bundle: !NODE_EXE!

REM ---------- 2/6  workspace ---------------------------------
REM 1364 packages across 5 workspaces. Resolution is ~1s; the time
REM goes into download and extraction, so the flags below target
REM concurrency and cache reuse, not the resolver.
echo [!TIME:~0,8!] [2/6] npm ci - 1364 packages, several minutes ...
pushd "%SRC%"
call npm ci --no-audit --no-fund --maxsockets 32 --prefer-offline
if errorlevel 1 (
    echo        npm ci failed - retrying with npm install ...
    call npm install --no-audit --no-fund --maxsockets 32 --prefer-offline
    if errorlevel 1 (
        popd
        echo [ERROR] Workspace install failed.
        goto :fail
    )
)
popd

REM ---------- 3/6  TUI + dashboard ---------------------------
REM The dashboard lands inside hermes_cli\ by itself - web/
REM vite.config.ts sets outDir to ../hermes_cli/web_dist - so it
REM travels with the trimmed tree for free.
REM
REM The TUI does NOT. ui-tui/scripts/build.mjs writes
REM ui-tui\dist\entry.js, and ui-tui\ is excluded from the staging
REM robocopy below, so the built bundle has to be copied into
REM hermes_cli\tui_dist\ by hand - that is the path
REM _find_bundled_tui() probes (hermes_cli/main.py). The bundle is
REM self-contained ("no runtime node_modules needed"), so that single
REM entry.js is all that has to move.
REM
REM Without the copy the restricted machine has no TUI at all, and it
REM does not degrade gracefully: `hermes --tui` AND the dashboard /
REM desktop Chat tab (which spawns the same binary behind a PTY) both
REM hard-exit, because ui-tui\ and .git are equally absent so the
REM built-in `git restore` recovery cannot run either.
echo [!TIME:~0,8!] [3/6] Building the TUI and dashboard ...
pushd "%SRC%"
call npm run build --workspace ui-tui
if errorlevel 1 echo        [WARN] TUI build failed
call npm run build --workspace web
if errorlevel 1 echo        [WARN] dashboard build failed - "hermes dashboard" will be unavailable
popd

set "TUI_OK="
if exist "%SRC%\ui-tui\dist\entry.js" (
    if not exist "%SRC%\hermes_cli\tui_dist" mkdir "%SRC%\hermes_cli\tui_dist" 2>nul
    copy /y "%SRC%\ui-tui\dist\entry.js" "%SRC%\hermes_cli\tui_dist\entry.js" >nul
    if errorlevel 1 (
        echo        [WARN] could not copy the TUI bundle into hermes_cli\tui_dist
    ) else (
        set "TUI_OK=1"
        echo        TUI bundle staged into hermes_cli\tui_dist
    )
) else (
    echo        [WARN] ui-tui\dist\entry.js not found after the build
)
if not defined TUI_OK (
    echo        [WARN] this bundle will ship WITHOUT a TUI - "hermes --tui"
    echo               and the desktop Chat tab will not work on the target
)

REM ---------- 4/6  Electron app ------------------------------
echo [!TIME:~0,8!] [4/6] npm run pack - downloads Electron 40.x, about 150 MB ...
if defined ELECTRON_MIRROR echo        ELECTRON_MIRROR=%ELECTRON_MIRROR%
pushd "%SRC%\apps\desktop"
call npm run pack
set "PACKRC=!errorlevel!"
popd
if not "!PACKRC!"=="0" (
    echo [ERROR] Desktop build failed - see the output above.
    goto :fail
)

set "RELDIR="
for %%C in (win-unpacked win-arm64-unpacked) do (
    if not defined RELDIR if exist "%SRC%\apps\desktop\release\%%C\Hermes.exe" set "RELDIR=%%C"
)
if not defined RELDIR (
    echo [ERROR] Built Hermes.exe not found under apps\desktop\release\
    goto :fail
)

REM ---------- 5/6  stage ------------------------------------
echo [!TIME:~0,8!] [5/6] Staging the bundle ...
if exist "%STAGE%" rmdir /s /q "%STAGE%"
mkdir "%STAGE%" 2>nul

REM Trimmed copy of the checkout. Everything excluded here is either
REM a build input we already consumed (node_modules, apps, ui-tui,
REM web), or not used at runtime (tests, docs, website, evals).
REM hermes_cli\tui_dist and hermes_cli\web_dist ARE inside the copy.
echo        copying the source tree ...
robocopy "%SRC%" "%STAGE%\src" /E /NFL /NDL /NJH /NJS /NP ^
    /XD ".git" "node_modules" "__pycache__" ".idea" ".bundle-stage" "tests" "tests-js" "evals" "website" "docs" "apps" "ui-tui" "web" "mcp-research-data" "contributors" "target" ^
    /XF "*.pyc" "hermes-bundle.zip" >nul
if errorlevel 8 (
    echo [ERROR] robocopy failed while staging the source.
    goto :fail
)

echo        copying the desktop app ...
robocopy "%SRC%\apps\desktop\release\!RELDIR!" "%STAGE%\desktop" /E /NFL /NDL /NJH /NJS /NP >nul
if errorlevel 8 (
    echo [ERROR] robocopy failed while staging the desktop app.
    goto :fail
)

echo        copying the node runtime ...
if not exist "%STAGE%\node" mkdir "%STAGE%\node" 2>nul
copy /y "!NODE_EXE!" "%STAGE%\node\node.exe" >nul
if errorlevel 1 (
    echo [ERROR] Could not copy node.exe into the bundle.
    goto :fail
)

copy /y "%SRC%\install.bat" "%STAGE%\install.bat" >nul

REM ---------- 6/6  pack -------------------------------------
echo [!TIME:~0,8!] [6/6] Packing ...
REM tar.exe from System32 is bsdtar: -a picks the format from the
REM .zip extension. Paths are stored relative to the stage root.
if exist "%BUNDLE_OUT%" del "%BUNDLE_OUT%"
pushd "%STAGE%"
tar.exe -a -c -f "%BUNDLE_OUT%" install.bat src desktop node
set "TARRC=!errorlevel!"
popd
if not "!TARRC!"=="0" (
    echo [ERROR] Could not create the zip.
    goto :fail
)
rmdir /s /q "%STAGE%"

for %%F in ("%BUNDLE_OUT%") do set "BSIZE=%%~zF"
set /a BMB=!BSIZE!/1048576

echo.
echo ===========================================================
echo   Bundle ready - !BMB! MB
echo ===========================================================
echo.
echo   %BUNDLE_OUT%
echo.
echo   On the restricted machine:
echo     1. unpack this zip anywhere
echo     2. run install.bat from the unpacked folder
echo.
echo   Nothing else needs to travel with it.
echo.
if defined TUI_OK (
    echo   TUI: bundled - "hermes --tui" and the Chat tab will work.
) else (
    echo   TUI: MISSING from this bundle - see the warnings above.
)
echo.
pause
exit /b 0


:fail
echo.
echo ===========================================================
echo   Build aborted.
echo ===========================================================
echo.
pause
exit /b 1


:install_node
REM Portable Node into %LOCALAPPDATA%\hermes\node - the same place the
REM desktop app prepends to its backend PATH (apps/desktop/electron/
REM backend-env.ts: "node.exe at the root, no bin\"). curl.exe and
REM tar.exe ship in System32 and are real PE binaries, so neither is
REM affected by PowerShell script blocking; curl uses Schannel, i.e.
REM the Windows certificate store, which works behind a TLS-inspecting
REM corporate proxy.
echo        Node.js missing or too old - installing a portable copy ...
set "NARCH=x64"
if /i "%PROCESSOR_ARCHITECTURE%"=="ARM64" set "NARCH=arm64"
set "NIDX=https://nodejs.org/dist/latest-v22.x/"

if not exist "%NODETMP%" mkdir "%NODETMP%" 2>nul
set "IDXFILE=%NODETMP%\index.html"

curl -fsS --max-time 60 -o "%IDXFILE%" "%NIDX%"
if errorlevel 1 (
    echo        could not reach nodejs.org - check HTTPS_PROXY
    goto :eof
)

set "NODEZIP="
for /f "tokens=2 delims=<>" %%A in ('findstr /i /c:"-win-!NARCH!.zip" "%IDXFILE%"') do (
    if not defined NODEZIP set "NODEZIP=%%A"
)
if not defined NODEZIP (
    echo        could not find a win-!NARCH! build in the nodejs.org index
    goto :eof
)
echo        downloading !NODEZIP! - about 35 MB ...
curl -fL --retry 2 --max-time 900 -o "%NODETMP%\!NODEZIP!" "%NIDX%!NODEZIP!"
if errorlevel 1 (
    echo        download failed
    goto :eof
)

echo        extracting ...
tar -xf "%NODETMP%\!NODEZIP!" -C "%NODETMP%"
if errorlevel 1 (
    echo        extraction failed
    goto :eof
)

set "NODESRC="
for /d %%D in ("%NODETMP%\node-v22*-win-!NARCH!") do set "NODESRC=%%~fD"
if not defined NODESRC (
    echo        extracted tree not found
    goto :eof
)

if exist "%NODEROOT%" rmdir /s /q "%NODEROOT%"
move "!NODESRC!" "%NODEROOT%" >nul
if errorlevel 1 (
    echo        could not move the tree into place
    goto :eof
)
del "%NODETMP%\!NODEZIP!" 2>nul
del "%IDXFILE%" 2>nul

REM Session-scoped only: no setx, no system PATH surgery.
set "PATH=%NODEROOT%;%PATH%"
if exist "%NODEROOT%\node.exe" (
    for /f "delims=" %%N in ('node -v') do echo        installed Node %%N at %NODEROOT%
    set "NODE_OK=1"
)
goto :eof

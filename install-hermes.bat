@echo off
setlocal EnableExtensions EnableDelayedExpansion
title Hermes Agent - install

REM ===========================================================
REM  STEP 2 OF 2 - run this on the RESTRICTED machine.
REM
REM  Installs Hermes (CLI + desktop app) without install.ps1 and
REM  without Hermes-Setup.exe: on hosts where EDR/AppLocker blocks
REM  PowerShell scripts those fail with ACCESS_DENIED before
REM  anything runs.
REM
REM  If hermes-desktop-bundle.zip (built by build-bundle.bat on a
REM  fast machine) sits next to this file, the prebuilt desktop app
REM  is unpacked from it and npm / Electron / Node are skipped
REM  entirely. Otherwise the app is built here, which is slow.
REM
REM  Put this file in the Hermes source root (next to
REM  pyproject.toml) and run it.
REM
REM  Optional overrides, set before running:
REM    set HERMES_HOME=D:\somewhere\hermes-data
REM    set HTTPS_PROXY=http://proxy.corp:3128
REM    set PIP_INDEX_URL=https://nexus.corp/repository/pypi/simple
REM    set SKIP_DESKTOP=1        CLI only
REM ===========================================================

set "SRC=%~dp0"
if "%SRC:~-1%"=="\" set "SRC=%SRC:~0,-1%"

if not exist "%SRC%\pyproject.toml" (
    echo [ERROR] pyproject.toml not found next to this script.
    echo         Place this file in the Hermes source root.
    goto :fail
)

REM The venv MUST live at <src>\venv. The desktop app resolves its
REM Python backend by probing <root>\.venv and <root>\venv only
REM (apps/desktop/electron/main.ts, findPythonForRoot) and spawns it
REM from <root>\venv (createPythonBackend). A venv anywhere else makes
REM Desktop fall through to its own bootstrap installer - the exact
REM PowerShell path that is blocked on this class of machine.
set "HERMES_VENV=%SRC%\venv"
if not defined HERMES_HOME set "HERMES_HOME=%LOCALAPPDATA%\hermes"
if not exist "%HERMES_HOME%" mkdir "%HERMES_HOME%" 2>nul
set "PIPLOG=%HERMES_HOME%\install-pip.log"
set "NODEROOT=%HERMES_HOME%\node"
set "NODETMP=%HERMES_HOME%\node-download"
set "BUNDLE=%SRC%\hermes-desktop-bundle.zip"
set "DESKTOP_BUILT="
set "LAUNCHER="
set "LMMODEL="

echo.
echo   source  : %SRC%
echo   venv    : %HERMES_VENV%
echo   data    : %HERMES_HOME%
if exist "%BUNDLE%" (
    echo   bundle  : found - the desktop app will be unpacked, not built
) else (
    echo   bundle  : none - the desktop app would have to be built here
)
echo.

REM ---------- 1/9  locate a supported Python -----------------
REM pyproject requires-python is ">=3.11,<3.14".
echo [!TIME:~0,8!] [1/9] Looking for Python 3.11 - 3.13 ...
set "PY_CMD="

REM The py launcher first: it never triggers the Microsoft Store stub.
for %%V in (3.11 3.12 3.13) do (
    if not defined PY_CMD (
        py -%%V -c "import sys" >nul 2>&1 && set "PY_CMD=py -%%V"
    )
)

REM Fall back to python.exe on PATH, but skip the WindowsApps alias:
REM that stub opens the Microsoft Store and blocks forever when the
REM script runs with its output redirected.
if not defined PY_CMD (
    for /f "delims=" %%P in ('where python 2^>nul') do (
        if not defined PY_CMD (
            echo %%P | find /i "WindowsApps" >nul
            if errorlevel 1 (
                "%%P" -c "import sys;sys.exit(0 if sys.version_info[:2] in ((3,11),(3,12),(3,13)) else 1)" >nul 2>&1 && set "PY_CMD=%%P"
            ) else (
                echo        skipping Microsoft Store stub: %%P
            )
        )
    )
)

if not defined PY_CMD (
    echo [ERROR] No usable Python 3.11 - 3.13 found.
    echo         Install one from python.org - tick "Add python.exe to PATH".
    echo         Do NOT use the Microsoft Store build.
    goto :fail
)
for /f "delims=" %%P in ('!PY_CMD! -c "import sys;print(sys.version.split()[0])"') do set "PY_VER=%%P"
echo        Python !PY_VER! via "!PY_CMD!"

REM ---------- 2/9  virtual environment -----------------------
if exist "%HERMES_VENV%\Scripts\python.exe" (
    echo [!TIME:~0,8!] [2/9] Reusing existing venv
) else (
    echo [!TIME:~0,8!] [2/9] Creating venv ...
    !PY_CMD! -m venv "%HERMES_VENV%"
    if errorlevel 1 (
        echo [ERROR] venv creation failed.
        goto :fail
    )
)
set "VPY=%HERMES_VENV%\Scripts\python.exe"
if not exist "%VPY%" (
    echo [ERROR] venv python missing at %VPY%
    goto :fail
)

REM ---------- 3/9  network preflight -------------------------
REM Fail in 10 seconds with a clear message instead of stalling
REM for many minutes inside pip's own retry loop.
echo [!TIME:~0,8!] [3/9] Checking package index reachability ...
if defined PIP_INDEX_URL (
    echo        PIP_INDEX_URL is set - trusting it, skipping the probe
) else (
    "%VPY%" -c "import urllib.request as u;u.urlopen('https://pypi.org/simple/',timeout=10);print('       pypi.org reachable')" 2>nul
    if errorlevel 1 (
        echo.
        echo [ERROR] pypi.org is NOT reachable from this machine.
        echo         Nothing was installed. Set one of these and re-run:
        echo             set HTTPS_PROXY=http://proxy.corp:3128
        echo             set PIP_INDEX_URL=https://nexus.corp/repository/pypi/simple
        goto :fail
    )
)

REM ---------- 4/9  python dependencies -----------------------
set "INSTALLER=pip"
where uv >nul 2>&1 && set "INSTALLER=uv"

REM Bounded network behaviour: without these pip can sit for many
REM minutes in silent retries on a filtered corporate link.
set "PIPOPTS=--disable-pip-version-check --no-input --timeout 20 --retries 2 --progress-bar on --log "%PIPLOG%""

echo [!TIME:~0,8!] [4/9] Installing python dependencies with !INSTALLER! ...
echo        around 150 packages - expect several minutes
if "!INSTALLER!"=="pip" (
    echo        detailed log: %PIPLOG%
) else (
    echo        uv prints its own progress below
)
echo.

pushd "%SRC%"
if "!INSTALLER!"=="uv" (
    uv pip install --python "%VPY%" -e ".[all]"
) else (
    "%VPY%" -m pip install --upgrade pip setuptools !PIPOPTS!
    "%VPY%" -m pip install -e ".[all]" !PIPOPTS!
)

if errorlevel 1 (
    echo.
    echo [WARN] Install of the "all" extra failed - retrying with the base package only.
    echo.
    if "!INSTALLER!"=="uv" (
        uv pip install --python "%VPY%" -e .
    ) else (
        "%VPY%" -m pip install -e . !PIPOPTS!
    )
    if errorlevel 1 (
        popd
        echo.
        echo [ERROR] Dependency installation failed. Full detail in:
        echo             %PIPLOG%
        goto :fail
    )
)
popd

REM ---------- 5/9  data directory and config -----------------
echo.
echo [!TIME:~0,8!] [5/9] Preparing %HERMES_HOME% ...
if not exist "%HERMES_HOME%\.env" type nul > "%HERMES_HOME%\.env"

set "CFG=%HERMES_HOME%\config.yaml"
if exist "%CFG%" (
    echo        config.yaml already exists - left untouched
) else (
    call :write_config
)

REM ---------- 6/9  launchers and environment -----------------
REM PATH is deliberately NOT modified: "setx PATH %PATH%" is a known
REM way to corrupt a user PATH by folding the system half into it.
set "SHIM=%HERMES_HOME%\hermes.cmd"
> "%SHIM%" echo @echo off
>> "%SHIM%" echo "%HERMES_VENV%\Scripts\hermes.exe" %%*
echo [!TIME:~0,8!] [6/9] CLI launcher: %SHIM%

REM Point Desktop at this checkout. Without it Desktop looks only at
REM %LOCALAPPDATA%\hermes\hermes-agent, finds nothing usable, and runs
REM its own PowerShell bootstrap - which is blocked here.
setx HERMES_DESKTOP_HERMES_ROOT "%SRC%" >nul 2>&1
set "HERMES_DESKTOP_HERMES_ROOT=%SRC%"
echo        HERMES_DESKTOP_HERMES_ROOT=%SRC%

REM Keep Hermes' own node bootstrap from reaching out to nodejs.org.
setx HERMES_SKIP_NODE_BOOTSTRAP 1 >nul 2>&1

REM ---------- 7/9  verify the CLI ----------------------------
echo [!TIME:~0,8!] [7/9] Verifying CLI ...
"%HERMES_VENV%\Scripts\hermes.exe" --version
if errorlevel 1 (
    echo [ERROR] hermes did not start. See the output above.
    goto :fail
)

if defined SKIP_DESKTOP (
    echo.
    echo        SKIP_DESKTOP is set - stopping before the desktop app.
    goto :success
)

REM ---------- 8/9  desktop app -------------------------------
if exist "%BUNDLE%" (
    echo [!TIME:~0,8!] [8/9] Unpacking the prebuilt desktop app ...
    tar -xf "%BUNDLE%" -C "%SRC%"
    if errorlevel 1 (
        echo [WARN] Could not unpack %BUNDLE% - desktop app skipped.
        goto :shortcut
    )
    echo        unpacked - npm, Electron and Node were not needed
    goto :shortcut
)

echo [!TIME:~0,8!] [8/9] No bundle found - building the desktop app here.
echo        This needs Node plus 1364 npm packages plus Electron ^(150 MB^).
echo        Ten to twenty minutes on a filtered link is normal. To avoid it,
echo        run build-bundle.bat on a fast machine and bring the zip over.
echo.

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
        echo [WARN] Could not provide Node.js - skipping the desktop app.
        echo        The CLI is installed and fully usable.
        goto :success
    )
)

pushd "%SRC%"
echo        npm ci ...
call npm ci --no-audit --no-fund --maxsockets 32 --prefer-offline
if errorlevel 1 (
    echo        npm ci failed - retrying with npm install ...
    call npm install --no-audit --no-fund --maxsockets 32 --prefer-offline
    if errorlevel 1 (
        popd
        echo [WARN] Workspace install failed - desktop app skipped, CLI is fine.
        goto :success
    )
)
popd

pushd "%SRC%\apps\desktop"
echo        npm run pack ...
call npm run pack
set "PACKRC=!errorlevel!"
popd
if not "!PACKRC!"=="0" (
    echo [WARN] Desktop build failed - CLI is still fully usable.
    goto :success
)

:shortcut
REM ---------- 9/9  desktop shortcut --------------------------
echo [!TIME:~0,8!] [9/9] Creating the desktop shortcut ...
set "EXE="
for %%C in (
    "%SRC%\apps\desktop\release\win-unpacked\Hermes.exe"
    "%SRC%\apps\desktop\release\win-arm64-unpacked\Hermes.exe"
) do (
    if not defined EXE if exist %%C set "EXE=%%~fC"
)
if not defined EXE (
    echo [WARN] Hermes.exe not found under apps\desktop\release\
    goto :success
)
echo        exe: !EXE!
set "DESKTOP_BUILT=1"

REM Resolve the REAL desktop folder from the registry: on machines with
REM OneDrive folder redirection %USERPROFILE%\Desktop is the wrong path.
set "DESKTOPDIR="
for /f "tokens=2,*" %%A in ('reg query "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders" /v Desktop 2^>nul') do set "DESKTOPDIR=%%B"
if not defined DESKTOPDIR set "DESKTOPDIR=%USERPROFILE%\Desktop"
if not exist "!DESKTOPDIR!" set "DESKTOPDIR=%USERPROFILE%\Desktop"

for %%I in ("!EXE!") do set "EXEDIR=%%~dpI"
set "LNK=!DESKTOPDIR!\Hermes.lnk"
set "CMDLNK=!DESKTOPDIR!\Hermes.cmd"

REM Preferred: a real .lnk. Uses PowerShell, which may be blocked on
REM this host - hence the .cmd fallback right below, which always works.
powershell -NoProfile -ExecutionPolicy Bypass -Command "$s=(New-Object -ComObject WScript.Shell).CreateShortcut('!LNK!');$s.TargetPath='!EXE!';$s.WorkingDirectory='!EXEDIR!';$s.Save()" >nul 2>&1

if exist "!LNK!" (
    echo        shortcut: !LNK!
    set "LAUNCHER=!LNK!"
) else (
    > "!CMDLNK!" echo @echo off
    >> "!CMDLNK!" echo start "" "!EXE!"
    echo        .lnk could not be created - wrote a .cmd launcher instead
    echo        launcher: !CMDLNK!
    set "LAUNCHER=!CMDLNK!"
)
goto :success


:success
echo.
echo ===========================================================
echo   Done.
echo ===========================================================
echo.
echo   CLI:           "%SHIM%"
echo   Health check:  "%SHIM%" doctor
if defined DESKTOP_BUILT (
    echo   Desktop app:   !LAUNCHER!
) else (
    echo   Desktop app:   not installed - see the warnings above
)
echo.
if defined LMMODEL (
    echo   LM Studio model written to config: !LMMODEL!
) else (
    echo   NOTE: no LM Studio model id was written. Start the LM Studio
    echo         server, load a model, then either edit model.default in
    echo             %CFG%
    echo         or run:  "%SHIM%" model
)
echo.
pause
exit /b 0


:fail
echo.
echo ===========================================================
echo   Installation aborted.
echo ===========================================================
echo.
pause
exit /b 1


REM ===========================================================
REM  Subroutines
REM ===========================================================

:install_node
REM Portable Node into HERMES_HOME\node - the same place the desktop
REM app prepends to its backend PATH (apps/desktop/electron/
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


:write_config
echo        writing a minimal config.yaml
REM Only overrides belong here. Every other key comes from
REM DEFAULT_CONFIG in hermes_cli/config_defaults.py and is merged
REM in at load time, so this file stays short on purpose.
REM
REM The model id is probed from a running LM Studio server. Output is
REM captured through a temp file rather than `for /f ... in (`cmd`)`:
REM with a quoted interpreter path that form breaks cmd's parser and
REM silently yields nothing.
set "LMMODEL="
set "LMTMP=%HERMES_HOME%\lmprobe.txt"
"%VPY%" -c "import urllib.request,json;print(json.load(urllib.request.urlopen('http://127.0.0.1:1234/v1/models',timeout=3))['data'][0]['id'])" > "%LMTMP%" 2>nul
if exist "%LMTMP%" set /p LMMODEL=<"%LMTMP%"
del "%LMTMP%" 2>nul

> "%CFG%" echo # Hermes Agent - minimal configuration.
>> "%CFG%" echo # Only overrides live here; every other key comes from the
>> "%CFG%" echo # built-in defaults and is merged in at load time.
>> "%CFG%" echo.
>> "%CFG%" echo model:
>> "%CFG%" echo    provider: "lmstudio"
>> "%CFG%" echo    base_url: "http://127.0.0.1:1234/v1"
if defined LMMODEL (
    >> "%CFG%" echo    default: "!LMMODEL!"
) else (
    >> "%CFG%" echo    # default: "put-your-lm-studio-model-id-here"
)
>> "%CFG%" echo.
>> "%CFG%" echo # ---- network isolation ------------------------------------
>> "%CFG%" echo # Goal: the only outbound traffic the app starts on its own
>> "%CFG%" echo # is the update check against github.com.
>> "%CFG%" echo.
>> "%CFG%" echo security:
>> "%CFG%" echo    # do not download the tirith binary from GitHub releases
>> "%CFG%" echo    tirith_enabled: false
>> "%CFG%" echo    # do not install optional backends from PyPI on the fly
>> "%CFG%" echo    allow_lazy_installs: false
>> "%CFG%" echo.
>> "%CFG%" echo model_catalog:
>> "%CFG%" echo    # do not fetch the hosted model catalog
>> "%CFG%" echo    enabled: false
>> "%CFG%" echo.
>> "%CFG%" echo models_dev:
>> "%CFG%" echo    # models.dev has no off switch - an unroutable URL makes
>> "%CFG%" echo    # the background refresh fail instantly and serve the cache
>> "%CFG%" echo    url: "http://127.0.0.1:9/api.json"
goto :eof

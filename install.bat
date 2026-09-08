@echo off
setlocal EnableExtensions EnableDelayedExpansion
title Hermes Agent - install

REM ===========================================================
REM  STEP 2 OF 2 - run this on the RESTRICTED machine.
REM
REM  Unpack hermes-bundle.zip anywhere and run this file from the
REM  unpacked folder. It installs Hermes into the canonical
REM  location and never runs npm, Electron or Node.
REM
REM  Deliberately avoids install.ps1 and Hermes-Setup.exe: on hosts
REM  where EDR/AppLocker blocks PowerShell scripts those fail with
REM  ACCESS_DENIED before anything runs.
REM
REM  Also works when placed directly in a source checkout (next to
REM  pyproject.toml); it then installs that tree in place and skips
REM  the desktop app.
REM
REM  Optional overrides, set before running:
REM    set HERMES_HOME=D:\somewhere\hermes-data
REM    set HTTPS_PROXY=http://proxy.corp:3128
REM    set PIP_INDEX_URL=https://nexus.corp/repository/pypi/simple
REM ===========================================================

set "HERE=%~dp0"
if "%HERE:~-1%"=="\" set "HERE=%HERE:~0,-1%"

if not defined HERMES_HOME set "HERMES_HOME=%LOCALAPPDATA%\hermes"

REM Bundle layout or bare checkout?
set "MODE="
if exist "%HERE%\src\pyproject.toml" set "MODE=bundle"
if not defined MODE if exist "%HERE%\pyproject.toml" set "MODE=checkout"
if not defined MODE (
    echo [ERROR] Neither src\pyproject.toml nor pyproject.toml found here.
    echo         Run this from an unpacked hermes-bundle, or from a
    echo         Hermes source root.
    goto :fail
)

REM ACTIVE_HERMES_ROOT is what the desktop app probes by default
REM (apps/desktop/electron/main.ts, step 3 of resolveHermesBackend):
REM %LOCALAPPDATA%\hermes\hermes-agent with its venv inside. Installing
REM there means Desktop finds the backend with no overrides and never
REM reaches for its own PowerShell bootstrap.
if "%MODE%"=="bundle" (
    set "ROOT=%HERMES_HOME%\hermes-agent"
) else (
    set "ROOT=%HERE%"
)
set "VENV=!ROOT!\venv"
set "APPDIR=%HERMES_HOME%\desktop"
set "PIPLOG=%HERMES_HOME%\install-pip.log"
set "LMMODEL="
set "LAUNCHER="
set "DESKTOP_OK="
set "TUI_READY="

if not exist "%HERMES_HOME%" mkdir "%HERMES_HOME%" 2>nul

echo.
echo   mode    : %MODE%
echo   root    : !ROOT!
echo   venv    : !VENV!
echo   data    : %HERMES_HOME%
echo.

REM ---------- 1/7  locate a supported Python -----------------
REM pyproject requires-python is ">=3.11,<3.14".
echo [!TIME:~0,8!] [1/7] Looking for Python 3.11 - 3.13 ...
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

REM ---------- 2/7  place the files ---------------------------
if "%MODE%"=="bundle" (
    echo [!TIME:~0,8!] [2/7] Installing files into !ROOT! ...
    robocopy "%HERE%\src" "!ROOT!" /E /NFL /NDL /NJH /NJS /NP /XD "venv" >nul
    if errorlevel 8 (
        echo [ERROR] Could not copy the source tree.
        goto :fail
    )
    if exist "%HERE%\desktop\Hermes.exe" (
        echo        installing the desktop app into %APPDIR% ...
        robocopy "%HERE%\desktop" "%APPDIR%" /E /NFL /NDL /NJH /NJS /NP >nul
        if errorlevel 8 (
            echo [WARN] Could not copy the desktop app - CLI will still work.
        ) else (
            set "DESKTOP_OK=1"
        )
    ) else (
        echo        no desktop\Hermes.exe in this bundle - CLI only
    )
    call :place_node
) else (
    echo [!TIME:~0,8!] [2/7] Checkout mode - using the tree in place
)

REM ---------- 3/7  virtual environment -----------------------
REM The venv MUST sit at <root>\venv: the desktop app probes only
REM <root>\.venv and <root>\venv (findPythonForRoot) and spawns the
REM backend from <root>\venv (createPythonBackend).
if exist "!VENV!\Scripts\python.exe" (
    echo [!TIME:~0,8!] [3/7] Reusing existing venv
) else (
    echo [!TIME:~0,8!] [3/7] Creating venv ...
    !PY_CMD! -m venv "!VENV!"
    if errorlevel 1 (
        echo [ERROR] venv creation failed.
        goto :fail
    )
)
set "VPY=!VENV!\Scripts\python.exe"
if not exist "!VPY!" (
    echo [ERROR] venv python missing at !VPY!
    goto :fail
)

REM ---------- 4/7  python dependencies -----------------------
echo [!TIME:~0,8!] [4/7] Checking package index reachability ...
if defined PIP_INDEX_URL (
    echo        PIP_INDEX_URL is set - trusting it, skipping the probe
) else (
    "!VPY!" -c "import urllib.request as u;u.urlopen('https://pypi.org/simple/',timeout=10);print('       pypi.org reachable')" 2>nul
    if errorlevel 1 (
        echo.
        echo [ERROR] pypi.org is NOT reachable from this machine.
        echo         Nothing was installed. Set one of these and re-run:
        echo             set HTTPS_PROXY=http://proxy.corp:3128
        echo             set PIP_INDEX_URL=https://nexus.corp/repository/pypi/simple
        goto :fail
    )
)

set "INSTALLER=pip"
where uv >nul 2>&1 && set "INSTALLER=uv"

REM Bounded network behaviour: without these pip can sit for many
REM minutes in silent retries on a filtered corporate link.
set "PIPOPTS=--disable-pip-version-check --no-input --timeout 20 --retries 2 --progress-bar on --log "%PIPLOG%""

echo        installing python dependencies with !INSTALLER! - several minutes
if "!INSTALLER!"=="pip" echo        detailed log: %PIPLOG%
echo.

pushd "!ROOT!"
if "!INSTALLER!"=="uv" (
    uv pip install --python "!VPY!" -e ".[all]"
) else (
    "!VPY!" -m pip install --upgrade pip setuptools !PIPOPTS!
    "!VPY!" -m pip install -e ".[all]" !PIPOPTS!
)
if errorlevel 1 (
    echo.
    echo [WARN] Install of the "all" extra failed - retrying with the base package only.
    echo.
    if "!INSTALLER!"=="uv" (
        uv pip install --python "!VPY!" -e .
    ) else (
        "!VPY!" -m pip install -e . !PIPOPTS!
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

REM ---------- 5/7  config ------------------------------------
echo.
echo [!TIME:~0,8!] [5/7] Preparing %HERMES_HOME% ...
if not exist "%HERMES_HOME%\.env" type nul > "%HERMES_HOME%\.env"

set "CFG=%HERMES_HOME%\config.yaml"
if exist "%CFG%" (
    echo        config.yaml already exists - left untouched
) else (
    call :write_config
)

REM ---------- 6/7  launchers and environment -----------------
REM PATH is deliberately NOT modified: "setx PATH %PATH%" is a known
REM way to corrupt a user PATH by folding the system half into it.
set "SHIM=%HERMES_HOME%\hermes.cmd"
> "%SHIM%" echo @echo off
>> "%SHIM%" echo "!VENV!\Scripts\hermes.exe" %%*
echo [!TIME:~0,8!] [6/7] CLI launcher: %SHIM%

REM HERMES_DESKTOP_HERMES is the explicit deployment override the Nix
REM wrapper uses (main.ts, step 4 of resolveHermesBackend). It is
REM trusted without a probe and never falls through to the bootstrap
REM installer, which is the PowerShell path blocked on this machine.
setx HERMES_DESKTOP_HERMES "!VENV!\Scripts\hermes.exe" >nul 2>&1
setx HERMES_DESKTOP_HERMES_ROOT "!ROOT!" >nul 2>&1
REM Keep Hermes' own node bootstrap from reaching out to nodejs.org.
setx HERMES_SKIP_NODE_BOOTSTRAP 1 >nul 2>&1
echo        desktop backend pinned to !VENV!\Scripts\hermes.exe

REM ---------- 7/7  verify + shortcut -------------------------
echo [!TIME:~0,8!] [7/7] Verifying ...
"!VENV!\Scripts\hermes.exe" --version
if errorlevel 1 (
    echo [ERROR] hermes did not start. See the output above.
    goto :fail
)

REM The TUI is not optional dressing: the dashboard and desktop Chat
REM tab spawn the very same `hermes --tui` binary behind a PTY
REM (web_server.py /api/pty), so a missing half breaks the desktop
REM app's main screen, not just the terminal flag. Both halves are
REM reported here so that shows up now rather than on first launch.
set "TUI_ENTRY=!ROOT!\hermes_cli\tui_dist\entry.js"
if exist "!TUI_ENTRY!" (
    if exist "%HERMES_HOME%\node\node.exe" set "TUI_READY=1"
)
if defined TUI_READY (
    echo        TUI: ready
) else (
    if not exist "!TUI_ENTRY!" echo        TUI: missing hermes_cli\tui_dist\entry.js
    if not exist "%HERMES_HOME%\node\node.exe" echo        TUI: missing %HERMES_HOME%\node\node.exe
    echo        TUI: unavailable - the CLI and the rest of the dashboard still work
)

if not defined DESKTOP_OK goto :success
set "EXE=%APPDIR%\Hermes.exe"
if not exist "!EXE!" goto :success

REM Resolve the REAL desktop folder from the registry: on machines with
REM OneDrive folder redirection %USERPROFILE%\Desktop is the wrong path.
set "DESKTOPDIR="
for /f "tokens=2,*" %%A in ('reg query "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders" /v Desktop 2^>nul') do set "DESKTOPDIR=%%B"
if not defined DESKTOPDIR set "DESKTOPDIR=%USERPROFILE%\Desktop"
if not exist "!DESKTOPDIR!" set "DESKTOPDIR=%USERPROFILE%\Desktop"

set "LNK=!DESKTOPDIR!\Hermes.lnk"
set "CMDLNK=!DESKTOPDIR!\Hermes.cmd"

REM Preferred: a real .lnk. Uses PowerShell, which may be blocked on
REM this host - hence the .cmd fallback right below, which always works.
powershell -NoProfile -ExecutionPolicy Bypass -Command "$s=(New-Object -ComObject WScript.Shell).CreateShortcut('!LNK!');$s.TargetPath='!EXE!';$s.WorkingDirectory='%APPDIR%';$s.Save()" >nul 2>&1

if exist "!LNK!" (
    echo        shortcut: !LNK!
    set "LAUNCHER=!LNK!"
) else (
    > "!CMDLNK!" echo @echo off
    >> "!CMDLNK!" echo start "" "!EXE!"
    echo        .lnk could not be created - wrote a .cmd launcher instead
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
if defined LAUNCHER (
    echo   Desktop app:   !LAUNCHER!
) else (
    echo   Desktop app:   not installed
)
if defined TUI_READY (
    echo   TUI / Chat:    ready
) else (
    echo   TUI / Chat:    unavailable - rebuild the bundle to get it
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


:place_node
REM Hermes resolves its own Node before anything on PATH:
REM iter_hermes_node_dirs() in hermes_constants.py probes
REM %HERMES_HOME%\node first on Windows, then %HERMES_HOME%\node\bin.
REM Dropping node.exe at the first of those is exactly the layout the
REM upstream install.ps1 produces, so find_node_executable("node")
REM picks it up with no PATH surgery and no env var.
REM
REM This is what makes the bundled TUI actually runnable: the TUI is a
REM Node program, this machine has no Node, and step 6/7 sets
REM HERMES_SKIP_NODE_BOOTSTRAP=1 so Hermes may not fetch one itself.
if not exist "%HERE%\node\node.exe" (
    echo        no node\node.exe in this bundle - TUI will be unavailable
    goto :eof
)
if exist "%HERMES_HOME%\node\node.exe" (
    echo        node runtime already present - left untouched
    goto :eof
)
if not exist "%HERMES_HOME%\node" mkdir "%HERMES_HOME%\node" 2>nul
copy /y "%HERE%\node\node.exe" "%HERMES_HOME%\node\node.exe" >nul
if errorlevel 1 (
    echo        [WARN] could not place node.exe - TUI will be unavailable
    goto :eof
)
echo        node runtime installed into %HERMES_HOME%\node
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
"!VPY!" -c "import urllib.request,json;print(json.load(urllib.request.urlopen('http://127.0.0.1:1234/v1/models',timeout=3))['data'][0]['id'])" > "%LMTMP%" 2>nul
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

@echo off
setlocal EnableExtensions EnableDelayedExpansion
title COWebs.lb Master Developer Environment Setup v5.0.0
color 0B
for /f "tokens=2 delims=:" %%C in ('chcp') do set "ORIGINAL_CODE_PAGE=%%C"
chcp 65001 >nul

set "VERSION=5.0.0"
set "REPOSITORY=cowebsLB/cowebs-developer-setup"
set "ASSET_NAME=cowebs-developer-setup-v5.0.0.zip"
set "DOWNLOAD_URL=https://github.com/%REPOSITORY%/releases/download/v%VERSION%/%ASSET_NAME%"
set "EXPECTED_SHA256=6489CE3E0901643AE20E6C704CEDAAF0FA8B43F73BCE174E91629495D6E71DFB"
if defined COWEBS_SETUP_BUNDLE_PATH if defined COWEBS_SETUP_BUNDLE_SHA256 set "EXPECTED_SHA256=%COWEBS_SETUP_BUNDLE_SHA256%"
set "PROFILE="
set "DRY_RUN=0"
set "NO_CONFIG=0"
set "NO_RESTART=0"
set "KEEP_TEMP=0"

call :ParseArguments %*
set "PARSE_EXIT=!errorlevel!"
if not "!PARSE_EXIT!"=="0" goto ExitWithParseError

call :ShowHeader
if "!SHOW_HELP!"=="1" (
    call :ShowUsage
    goto ExitSuccess
)
if "!SHOW_VERSION!"=="1" (
    echo !VERSION!
    goto ExitSuccess
)

where powershell.exe >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Windows PowerShell is required but was not found.
    set "FINAL_EXIT=3"
    goto CleanupAndExit
)

set "TEMP_ROOT=%TEMP%\COWebs.lb"
set "SESSION_DIR=!TEMP_ROOT!\setup-%RANDOM%-%RANDOM%"
set "ARCHIVE_PATH=!SESSION_DIR!\!ASSET_NAME!"
set "EXTRACT_PATH=!SESSION_DIR!\payload"
mkdir "!EXTRACT_PATH!" >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Could not create the temporary setup directory.
    set "FINAL_EXIT=4"
    goto CleanupAndExit
)

set "COWEBS_BOOTSTRAP_URL=!DOWNLOAD_URL!"
set "COWEBS_BOOTSTRAP_ARCHIVE=!ARCHIVE_PATH!"
set "COWEBS_BOOTSTRAP_EXTRACT=!EXTRACT_PATH!"
set "COWEBS_BOOTSTRAP_SHA256=!EXPECTED_SHA256!"

echo [INFO] Preparing verified COWebs.lb setup payload v!VERSION!...
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='Stop';" ^
  "$archive=$env:COWEBS_BOOTSTRAP_ARCHIVE;" ^
  "if ($env:COWEBS_SETUP_BUNDLE_PATH) { Copy-Item -LiteralPath $env:COWEBS_SETUP_BUNDLE_PATH -Destination $archive -Force } else { Invoke-WebRequest -UseBasicParsing -Uri $env:COWEBS_BOOTSTRAP_URL -OutFile $archive };" ^
  "$actual=(Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash;" ^
  "if ($actual -ne $env:COWEBS_BOOTSTRAP_SHA256) { throw ('Release checksum mismatch. Expected ' + $env:COWEBS_BOOTSTRAP_SHA256 + ', received ' + $actual) };" ^
  "Expand-Archive -LiteralPath $archive -DestinationPath $env:COWEBS_BOOTSTRAP_EXTRACT -Force"
if errorlevel 1 (
    echo [ERROR] The setup payload could not be downloaded, verified, or extracted.
    set "FINAL_EXIT=5"
    goto CleanupAndExit
)

set "ENGINE_PATH=!EXTRACT_PATH!\src\windows\setup.ps1"
if not exist "!ENGINE_PATH!" (
    echo [ERROR] The verified payload does not contain the Windows setup engine.
    set "FINAL_EXIT=6"
    goto CleanupAndExit
)

set "ENGINE_ARGUMENTS="
if defined PROFILE set "ENGINE_ARGUMENTS=!ENGINE_ARGUMENTS! -Profile !PROFILE!"
if "!DRY_RUN!"=="1" set "ENGINE_ARGUMENTS=!ENGINE_ARGUMENTS! -DryRun"
if "!NO_CONFIG!"=="1" set "ENGINE_ARGUMENTS=!ENGINE_ARGUMENTS! -NoConfig"
if "!NO_RESTART!"=="1" set "ENGINE_ARGUMENTS=!ENGINE_ARGUMENTS! -NoRestart"

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "!ENGINE_PATH!" !ENGINE_ARGUMENTS!
set "FINAL_EXIT=!errorlevel!"

:CleanupAndExit
if not defined FINAL_EXIT set "FINAL_EXIT=0"
if "!KEEP_TEMP!"=="1" (
    if defined SESSION_DIR echo [INFO] Temporary payload retained at: !SESSION_DIR!
) else (
    if defined SESSION_DIR if exist "!SESSION_DIR!" (
        echo [INFO] Cleaning up the temporary setup payload...
        rmdir /s /q "!SESSION_DIR!"
    )
)
chcp !ORIGINAL_CODE_PAGE! >nul
endlocal & exit /b %FINAL_EXIT%

:ExitWithParseError
set "FINAL_EXIT=!PARSE_EXIT!"
goto CleanupAndExit

:ExitSuccess
set "FINAL_EXIT=0"
goto CleanupAndExit

:ParseArguments
set "SHOW_HELP=0"
set "SHOW_VERSION=0"
:ParseNextArgument
if "%~1"=="" exit /b 0
if /I "%~1"=="--profile" (
    if "%~2"=="" (
        echo [ERROR] --profile requires a profile name.
        exit /b 2
    )
    call :ValidateProfile "%~2"
    if errorlevel 1 exit /b 2
    set "PROFILE=%~2"
    shift
    shift
    goto ParseNextArgument
)
if /I "%~1"=="--dry-run" (
    set "DRY_RUN=1"
    set "NO_CONFIG=1"
    set "NO_RESTART=1"
    shift
    goto ParseNextArgument
)
if /I "%~1"=="--no-config" (
    set "NO_CONFIG=1"
    shift
    goto ParseNextArgument
)
if /I "%~1"=="--no-restart" (
    set "NO_RESTART=1"
    shift
    goto ParseNextArgument
)
if /I "%~1"=="--keep-temp" (
    set "KEEP_TEMP=1"
    shift
    goto ParseNextArgument
)
if /I "%~1"=="--help" (
    set "SHOW_HELP=1"
    shift
    goto ParseNextArgument
)
if /I "%~1"=="-h" (
    set "SHOW_HELP=1"
    shift
    goto ParseNextArgument
)
if /I "%~1"=="--version" (
    set "SHOW_VERSION=1"
    shift
    goto ParseNextArgument
)
echo [ERROR] Unknown argument: %~1
exit /b 2

:ValidateProfile
for %%P in (backend frontend android devops ai cyber game fullstack everything) do (
    if /I "%~1"=="%%P" exit /b 0
)
echo [ERROR] Unknown profile: %~1
exit /b 1

:ShowUsage
echo Usage:
echo   master-setup.bat
echo   master-setup.bat --profile PROFILE [options]
echo.
echo Profiles:
echo   backend, frontend, android, devops, ai, cyber, game, fullstack, everything
echo.
echo Options:
echo   --dry-run      Preview without installing, configuring, creating folders, or restarting.
echo   --no-config    Skip optional post-install configuration.
echo   --no-restart   Suppress the Windows restart prompt.
echo   --keep-temp    Retain the verified temporary payload for debugging.
echo   --version      Print the bootstrap version.
echo   --help, -h     Show this help without downloading the payload.
exit /b 0

:ShowHeader
cls
echo.
:: Banner artwork spells COWEBS.LB.
echo ================================================================================================
echo    ██████╗ ██████╗ ██╗    ██╗███████╗██████╗ ███████╗    ██╗     ██████╗
echo   ██╔════╝██╔═══██╗██║    ██║██╔════╝██╔══██╗██╔════╝    ██║     ██╔══██╗
echo   ██║     ██║   ██║██║ █╗ ██║█████╗  ██████╔╝███████╗    ██║     ██████╔╝
echo   ██║     ██║   ██║██║███╗██║██╔══╝  ██╔══██╗╚════██║    ██║     ██╔══██╗
echo   ╚██████╗╚██████╔╝╚███╔███╔╝███████╗██████╔╝███████║██╗ ███████╗██████╔╝
echo    ╚═════╝ ╚═════╝  ╚══╝╚══╝ ╚══════╝╚═════╝ ╚══════╝╚═╝ ╚══════╝╚═════╝
echo.
echo                           Master Developer Environment Setup v%VERSION%
echo                                  https://cowebslb.com
echo ================================================================================================
echo.
exit /b 0

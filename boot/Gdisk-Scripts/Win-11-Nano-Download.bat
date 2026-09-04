@echo off
setlocal enabledelayedexpansion

REM Clear the screen
cls

REM Display GDISK ASCII art banner
echo.
echo  _____ ________  _________ _   __
echo /  __ \|  _  \   ^|  _  ^| \ ^| ^|/ /
echo ^| /  \/^| ^| ^| ^|   ^| ^| ^| ^|  \  /
echo ^| ^|    ^| ^| ^| ^|   ^| ^| ^| ^| ^|\ ^|
echo ^| \__/\^| ^|_^| ^|___^| ^|_^| ^| ^| \  \
echo  \____/\___/\___/\___/\_^| \_/
echo.
echo Grub2 - Device - Image - System - Kit
echo.

REM Set download URL and filename
set "URL=https://glitchlinux.wtf/FILES/Windows-Installers/Win-11-Nano-Installer-v8.iso"
set "FILENAME=Win-11-Nano-Installer-v8.iso"
set "FILEPATH=%cd%\%FILENAME%"

REM Check if file exists and delete it
if exist "%FILEPATH%" (
    echo Removing existing %FILENAME%...
    del "%FILEPATH%"
    echo.
)

REM Download the ISO file using PowerShell
echo Downloading Win-11-Nano-Installer-v8.iso
echo.

powershell -NoProfile -Command "& {
    try {
        $ProgressPreference = 'Continue'
        Invoke-WebRequest -Uri '%URL%' -OutFile '%FILEPATH%' -UseBasicParsing
    } catch {
        Write-Host 'Error: Failed to download file' -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        pause
        exit 1
    }
}"

if errorlevel 1 (
    echo Download failed!
    pause
    exit /b 1
)

REM Clear screen and display success message
cls
echo Win-11-Nano-Installer-v8.iso Downloaded successfully!
echo.
pause

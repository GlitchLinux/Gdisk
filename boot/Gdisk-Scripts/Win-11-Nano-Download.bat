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

REM Download the ISO file using wget
echo Downloading Win-11-Nano-Installer-v8.iso
echo.

wget -q --show-progress "%URL%"

if errorlevel 1 (
    echo.
    echo Download failed!
    pause
    exit /b 1
)

REM Clear screen and display success message
cls
echo Win-11-Nano-Installer-v8.iso Downloaded successfully!
echo.
pause

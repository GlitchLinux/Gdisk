@echo off
title Gdisk WinPE Downloader
color 0A
mode con cols=80 lines=8
cd ..
copy boot\Gdisk-Installer\wget.exe Gdisk\
cd Gdisk
del EaseUS_Partition_Pro.vtoy >NUL
del Diskgenius-Pro-v6.vtoy >NUL
del NanoTech-11-x64-v1.8-25-July-2026.wim >NUL 
del NanoTech-11-x64-v1.8.wim >NUL
cls
echo.
echo -----= By : GLITCH LINUX 
echo -----= Site : https://GITHUB.COM/GLITCHLINUX 
echo -----= Downloading WinPE Vtoy - EaseUS_Partition_Pro 
echo.
wget.exe -q --show-progress "https://glitchlinux.wtf/FILES/Windows-PE/WinPE-Vtoy/EaseUS_Partition_Pro.vtoy" --no-check-certificate
cls
echo.
echo -----= By : GLITCH LINUX 
echo -----= Site : https://GITHUB.COM/GLITCHLINUX 
echo -----= Downloading WinPE Vtoy - Diskgenius-Pro-v6
echo.
wget.exe -q --show-progress "https://glitchlinux.wtf/FILES/Windows-PE/WinPE-Vtoy/Diskgenius-Pro-v6.vtoy" --no-check-certificate
cls
echo.
echo -----= By : GLITCH LINUX 
echo -----= Site : https://GITHUB.COM/GLITCHLINUX 
echo -----= Downloading WinPE Wim - NanoTech-11-x64-v1.8
echo.
wget.exe -q --show-progress "https://glitchlinux.wtf/FILES/Windows-PE/NanoTech-11-x64/NanoTech-11-x64-v1.8-25-July-2026.wim" --no-check-certificate
copy NanoTech-11-x64-v1.8-25-July-2026.wim NanoTech-11-x64-v1.8.wim
del NanoTech-11-x64-v1.8-25-July-2026.wim
del wget.exe
cls
echo.
echo -----= WinPE Downloading Finished 
echo
pause

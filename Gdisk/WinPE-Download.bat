@echo off
cd ..
copy boot/Gdisk-Installer/wget.exe Gdisk
echo Downloading WinPE Vtoy - EaseUS_Partition_Pro
wget.exe -q --show-progress "https://glitchlinux.wtf/FILES/Windows-PE/WinPE-Vtoy/EaseUS_Partition_Pro.vtoy" --no-check-certificate
cls
echo Downloading WinPE Vtoy - Diskgenius-Pro-v6
echo.
wget.exe -q --show-progress "https://glitchlinux.wtf/FILES/Windows-PE/WinPE-Vtoy/Diskgenius-Pro-v6.vtoy" --no-check-certificate
cls
echo Downloading WinPE Wim - NanoTech-11-x64-v1.8
echo.
wget.exe -q --show-progress "https://glitchlinux.wtf/FILES/Windows-PE/NanoTech-11-x64/NanoTech-11-x64-v1.8-25-July-2026.wim" --no-check-certificate
copy NanoTech-11-x64-v1.8-25-July-2026.wim NanoTech-11-x64-v1.8.wim
del NanoTech-11-x64-v1.8-25-July-2026.wim
del wget.exe
cls

@echo off
title Gdisk WinPE Downloader
color 0A
mode con cols=80 lines=12
cd ..
copy boot\Gdisk-Installer\wget.exe Gdisk\
cd Gdisk
del EaseUS_Partition_Pro.vtoy >NUL
del Diskgenius-Pro-v6.vtoy >NUL
del NanoTech-11-x64-v1.8-25-July-2026.wim >NUL 
del NanoTech-11-x64-v1.8.wim >NUL
cls
cls
echo.
echo      .aMMMMP   dMMMMb    dMP   .dMMMb    dMP dMP
echo     dMP'      dMP VMP   amr   dMP' VP   dMP dMP
echo    dMP MMP'  dMP dMP   dMP    VMMMb    dMMMM'
echo   dMP.dMP   dMP.aMP   dMP   dP .dMP   dMP'AMF 
echo   VMMMP'   dMMMMP'   dMP    VMMMP'   dMP dMP 
echo.
echo -----= Downloading WinPE Wim - NanoTech-11-x64-v1.8
echo.
wget.exe -q --show-progress "https://glitchlinux.wtf/FILES/Windows-PE/NanoTech-11-x64/NanoTech-11-x64-v1.8-25-July-2026.wim" --no-check-certificate
copy NanoTech-11-x64-v1.8-25-July-2026.wim NanoTech-11-x64-v1.8.wim
del NanoTech-11-x64-v1.8-25-July-2026.wim
del wget.exe
cls
echo.
echo      .aMMMMP   dMMMMb    dMP   .dMMMb    dMP dMP
echo     dMP'      dMP VMP   amr   dMP' VP   dMP dMP
echo    dMP MMP'  dMP dMP   dMP    VMMMb    dMMMM'
echo   dMP.dMP   dMP.aMP   dMP   dP .dMP   dMP'AMF 
echo   VMMMP'   dMMMMP'   dMP    VMMMP'   dMP dMP 
echo.
echo -----= WinPE Downloading Finished 
echo.
pause

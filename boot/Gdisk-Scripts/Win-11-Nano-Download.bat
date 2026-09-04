@echo off
title Gdisk Win-11-Nano Downloader
color 0A
mode con cols=80 lines=12
cd ..
cd ..
copy boot\Gdisk-Installer\wget.exe Gdisk\
cd Gdisk
del Win-11-Nano-Installer-v8.iso >NUL 2>NUL
cls
echo.
echo      .aMMMMP   dMMMMb    dMP   .dMMMb    dMP dMP
echo     dMP'      dMP VMP   amr   dMP' VP   dMP dMP
echo    dMP MMP'  dMP dMP   dMP    VMMMb    dMMMM'
echo   dMP.dMP   dMP.aMP   dMP   dP .dMP   dMP'AMF 
echo   VMMMP'   dMMMMP'   dMP    VMMMP'   dMP dMP 
echo.
echo -----= Downloading Win-11-Nano-Installer-v8.iso
echo.
wget.exe -q --show-progress "https://glitchlinux.wtf/FILES/Windows-Installers/Win-11-Nano-Installer-v8.iso" --no-check-certificate
del wget.exe
cls
echo.
echo      .aMMMMP   dMMMMb    dMP   .dMMMb    dMP dMP
echo     dMP'      dMP VMP   amr   dMP' VP   dMP dMP
echo    dMP MMP'  dMP dMP   dMP    VMMMb    dMMMM'
echo   dMP.dMP   dMP.aMP   dMP   dP .dMP   dMP'AMF 
echo   VMMMP'   dMMMMP'   dMP    VMMMP'   dMP dMP 
echo.
echo -----= Win-11-Nano-Installer-v8.iso Downloaded Successfully!
echo.
pause

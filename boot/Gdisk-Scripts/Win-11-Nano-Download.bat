@echo off
title Gdisk Win-11-Nano Downloader
color 0A
mode con cols=80 lines=12
cd ..
cd ..
copy boot\Gdisk-Installer\wget.exe Gdisk\
cd Gdisk
del WinPE-Teal-Installer-v1.4.iso >NUL 2>NUL
cls
echo.
echo      .aMMMMP   dMMMMb    dMP   .dMMMb    dMP dMP
echo     dMP'      dMP VMP   amr   dMP' VP   dMP dMP
echo    dMP MMP'  dMP dMP   dMP    VMMMb    dMMMM'
echo   dMP.dMP   dMP.aMP   dMP   dP .dMP   dMP'AMF 
echo   VMMMP'   dMMMMP'   dMP    VMMMP'   dMP dMP 
echo.
echo -----= Downloading WinPE-Teal-Installer-v1.4.iso
echo.
wget.exe -q --show-progress "https://glitchlinux.wtf/FILES/Windows-Installers/WinPE-Teal-Installer-v1.4.iso" --no-check-certificate
del wget.exe
cls
echo.
echo      .aMMMMP   dMMMMb    dMP   .dMMMb    dMP dMP
echo     dMP'      dMP VMP   amr   dMP' VP   dMP dMP
echo    dMP MMP'  dMP dMP   dMP    VMMMb    dMMMM'
echo   dMP.dMP   dMP.aMP   dMP   dP .dMP   dMP'AMF 
echo   VMMMP'   dMMMMP'   dMP    VMMMP'   dMP dMP 
echo.
echo -----= WinPE-Teal-Installer-v1.4.iso Downloaded Successfully!
echo.
pause

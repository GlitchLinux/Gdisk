@echo off
title Gdisk WinPE Downloader
color 0A
mode con cols=80 lines=12
cd ..
cd ..
copy boot\Gdisk-Installer\wget.exe Gdisk\
cd Gdisk
del MultiTech-11-X64-v2.6.wim >NUL
cls
cls
echo.
echo      .aMMMMP   dMMMMb    dMP   .dMMMb    dMP dMP
echo     dMP'      dMP VMP   amr   dMP' VP   dMP dMP
echo    dMP MMP'  dMP dMP   dMP    VMMMb    dMMMM'
echo   dMP.dMP   dMP.aMP   dMP   dP .dMP   dMP'AMF 
echo   VMMMP'   dMMMMP'   dMP    VMMMP'   dMP dMP 
echo.
echo -----= Downloading WinPE Wim - MultiTech-11-X64-v2.6
echo.
wget.exe -q --show-progress "https://glitchlinux.wtf/FILES/Windows-PE/MultiTech-11-x64/MultiTech-11-X64-v2.6.wim" --no-check-certificate
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

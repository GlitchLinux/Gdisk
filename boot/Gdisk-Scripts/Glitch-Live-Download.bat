@echo off 
title Glitch-Linux LIVE Download
color 0A
mode con cols=80 lines=12

cd ..

mkdir glitch-live

cd glitch-live

del initrd.img >NUL
del vmlinuz >NUL
del filesystem.squashfs >NUL
cls
echo.
echo      .aMMMMP   dMMMMb    dMP   .dMMMb    dMP dMP
echo     dMP'      dMP VMP   amr   dMP' VP   dMP dMP
echo    dMP MMP'  dMP dMP   dMP    VMMMb    dMMMM'
echo   dMP.dMP   dMP.aMP   dMP   dP .dMP   dMP'AMF 
echo   VMMMP'   dMMMMP'   dMP    VMMMP'   dMP dMP 
echo.
echo -----= Downloading Glitch-Linux Live v39 - initrd.img
echo. 
wget.exe -q --show-progress "https://glitchlinux.wtf/ipxe/Glitch-Linux-v39/live/initrd.img" --no-check-certificate
cls
echo.
echo      .aMMMMP   dMMMMb    dMP   .dMMMb    dMP dMP
echo     dMP'      dMP VMP   amr   dMP' VP   dMP dMP
echo    dMP MMP'  dMP dMP   dMP    VMMMb    dMMMM'
echo   dMP.dMP   dMP.aMP   dMP   dP .dMP   dMP'AMF 
echo   VMMMP'   dMMMMP'   dMP    VMMMP'   dMP dMP 
echo. 
echo -----= Downloading Glitch-Linux Live v39 - vmlinuz
echo.
wget.exe -q --show-progress "https://glitchlinux.wtf/ipxe/Glitch-Linux-v39/live/vmlinuz" --no-check-certificate
cls
echo.
echo      .aMMMMP   dMMMMb    dMP   .dMMMb    dMP dMP
echo     dMP'      dMP VMP   amr   dMP' VP   dMP dMP
echo    dMP MMP'  dMP dMP   dMP    VMMMb    dMMMM'
echo   dMP.dMP   dMP.aMP   dMP   dP .dMP   dMP'AMF 
echo   VMMMP'   dMMMMP'   dMP    VMMMP'   dMP dMP 
echo.
echo -----= Downloading Glitch-Linux Live v39 - filesystem.squashfs
echo.
wget.exe -q --show-progress "https://glitchlinux.wtf/ipxe/Glitch-Linux-v39/live/filesystem.squashfs" --no-check-certificate

del wget.exe

cls
echo.
echo      .aMMMMP   dMMMMb    dMP   .dMMMb    dMP dMP
echo     dMP'      dMP VMP   amr   dMP' VP   dMP dMP
echo    dMP MMP'  dMP dMP   dMP    VMMMb    dMMMM'
echo   dMP.dMP   dMP.aMP   dMP   dP .dMP   dMP'AMF 
echo   VMMMP'   dMMMMP'   dMP    VMMMP'   dMP dMP 
echo.
echo -----= Glitch Linux Live Sucessfully Downloaded!
echo.
pause

@echo off 
title Glitch-Linux LIVE Download
color 0A
mode con cols=80 lines=8

cd ..

mkdir glitch-live

copy boot\Gdisk-Installer\wget.exe glitch-live\

cd glitch-live

del initrd.img >NUL
del vmlinuz >NUL
del filesystem.squashfs >NUL
cls
echo.
echo -----= By : GLITCH LINUX 
echo -----= Site : https://GITHUB.COM/GLITCHLINUX 
echo -----= Downloading Glitch-Linux Live v39 - initrd.img
echo.
wget.exe -q --show-progress "https://glitchlinux.wtf/ipxe/Glitch-Linux-v39/live/initrd.img" --no-check-certificate
cls
echo.
echo -----= By : GLITCH LINUX 
echo -----= Site : https://GITHUB.COM/GLITCHLINUX 
echo -----= Downloading Glitch-Linux Live v39 - vmlinuz
echo.
wget.exe -q --show-progress "https://glitchlinux.wtf/ipxe/Glitch-Linux-v39/live/vmlinuz" --no-check-certificate
cls
echo.
echo -----= By : GLITCH LINUX 
echo -----= Site : https://GITHUB.COM/GLITCHLINUX 
echo -----= Downloading Glitch-Linux Live v39 - filesystem.squashfs
echo.
wget.exe -q --show-progress "https://glitchlinux.wtf/ipxe/Glitch-Linux-v39/live/filesystem.squashfs" --no-check-certificate

del wget.exe

cls
echo.
echo -----= Glitch Linux Live Sucessfully Downloaded!
echo.
pause

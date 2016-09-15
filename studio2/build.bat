@echo off
cd ..\Generate
call build.bat
cd ..\studio2
mingw32-make
copy /Y studio2.exe ..\bin


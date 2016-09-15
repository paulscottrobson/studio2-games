@echo off
python process.py
python binaryconv.py
copy /Y *.h ..\Studio2

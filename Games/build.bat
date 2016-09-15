@echo off
..\..\bin\asmx -s9 -l -ew -C 1802 %APP%.asm 
python ..\s9tobinary.py %APP%.asm.s9
python ..\makest2.py
..\..\bin\studio2 %APP%.asm.bin

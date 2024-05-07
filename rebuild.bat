echo on

if exist obj rd /s /q obj
if exist gamehunt2025.nes del /s /q /f gamehunt2025.nes
mkdir obj
ca65 gamehunt2025.s -o obj\gamehunt2025.o
ld65 -C nrom.cfg obj\gamehunt2025.o -o gamehunt2025.nes
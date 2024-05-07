#!/bin/bash
set -x

rm -fr obj gamehunt2025.nes
mkdir -p obj
ca65 gamehunt2025.s -o obj/gamehunt2025.o
ld65 -C nrom.cfg obj/gamehunt2025.o -o gamehunt2025.nes
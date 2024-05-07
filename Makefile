AS = ca65
LD = ld65
AS_FLAGS =
LD_FLAGS = -C nrom.cfg
OBJ = obj

PROJECT = gamehunt2025
DEPS = data.inc system.inc patterntable.chr nametable1.nam nametable2.nam nrom.cfg

$(PROJECT).nes: $(OBJ) $(OBJ)/$(PROJECT).o
	$(LD) $(LD_FLAGS) $(OBJ)/$(PROJECT).o -o $(PROJECT).nes

$(OBJ):
ifeq ($(OS), Windows_NT)
	mkdir $(OBJ)
else
	mkdir -p $(OBJ)
endif

$(OBJ)/$(PROJECT).o: $(PROJECT).s $(DEPS)
	$(AS) $(AS_FLAGS) $(PROJECT).s -o $(OBJ)/$(PROJECT).o

.PHONY: clean
clean:
ifeq ($(OS), Windows_NT)
	if exist $(OBJ) rd /s /q $(OBJ)
	if exist $(PROJECT).nes del /s /q /f $(PROJECT).nes
else
	rm -fr $(OBJ) $(PROJECT).nes
endif
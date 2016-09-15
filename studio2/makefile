#OBJS specifies which files to compile as part of the project
OBJS = cpu.c debug.c debugscreen.c hardware.c main.c system.c
#CC specifies which compiler we're using
CC = gcc

#INCLUDE_PATHS specifies the additional include paths we'll need
INCLUDE_PATHS = -IC:\mingw\sdl\include\SDL2 -Iframework -I.

#LIBRARY_PATHS specifies the additional library paths we'll need
LIBRARY_PATHS = -LC:\mingw\sdl\lib

#COMPILER_FLAGS specifies the additional compilation options we're using
# -w suppresses all warnings
# -Wl,-subsystem,windows gets rid of the console window
COMPILER_FLAGS = -Wall -DINCLUDE_DEBUGGING_SUPPORT -DWINDOWS -DSOUND

#LINKER_FLAGS specifies the libraries we're linking against
LINKER_FLAGS = -lmingw32 -lSDL2main -lSDL2 -static-libgcc -static-libstdc++

#OBJ_NAME specifies the name of our exectuable
OBJ_NAME = studio2

#This is the target that compiles our executable
all : $(OBJS)
	$(CC) $(OBJS) $(INCLUDE_PATHS) $(LIBRARY_PATHS) $(COMPILER_FLAGS) $(LINKER_FLAGS) -o $(OBJ_NAME)

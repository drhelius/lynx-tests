# Alpine Games Copy Protection Test for Atari Lynx
# Tests off-screen sprite rendering with overlapping buffers

# cc65 toolchain settings
CC = cl65
AS = ca65
LD = ld65
SYS = lynx

# Compiler and linker flags
CFLAGS = -t $(SYS) -O
ASFLAGS = -t $(SYS)
LDFLAGS = -t $(SYS)

# Output files
TARGET = sprite-test.lnx
SYMBOLS = sprite-test.sym

# Object files
OBJECTS = tests.o main.o

# Default target
all: $(TARGET)

# Link the final ROM
$(TARGET): $(OBJECTS)
	$(CC) -Ln $(SYMBOLS) -t $(SYS) -o $@ $(OBJECTS) lynx.lib

# Compile C files
main.o: main.c
	$(CC) $(CFLAGS) -c -o $@ $<

# Assemble assembly files
tests.o: tests.s
	$(AS) $(ASFLAGS) -o $@ $<

# Clean up
clean:
	rm -f $(OBJECTS) $(TARGET) $(SYMBOLS)

.PHONY: all clean

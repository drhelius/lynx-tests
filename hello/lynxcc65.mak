CC65=$(CC65_HOME)
CC65_BIN=$(CC65)/bin
CC65_INC=$(CC65)/include
CC65_ASMINC=$(CC65)/asminc
CC65_TOOLS=$(CC65)/wbin

BUILDDIR=$(MAKEDIR)/$(BUILD)
ODIR=$(MAKEDIR)/obj

.SUFFIXES : .c .s .o .asm .bmp .pal .spr

OBJ=debug

# We are compiling for Atari Lynx
SYS=lynx

# These are the names of the tools we use
CO=co65
CC=cc65
AS=ca65
AR=ar65
CL=cl65
SPRPCK=sprpck
CP=cp
RM=rm
ECHO=echo
TOUCH=touch

CODE_SEGMENT=CODE
DATA_SEGMENT=DATA
RODATA_SEGMENT=RODATA
BSS_SEGMENT=BSS

SEGMENTS=--code-name $(CODE_SEGMENT) \
				--rodata-name $(RODATA_SEGMENT) \
				--bss-name $(BSS_SEGMENT) \
				--data-name $(DATA_SEGMENT)

# The flag for adding stuff to a library
ARFLAGS=a

# The flags for compiling C-code
CFLAGS=-I . -t $(SYS) --add-source -O -Or -Cl -Os

# Rule for making a *.o file out of a *.s file
# TODO: Find out if this works {}.s{$(ODIR)}.o:
.s.o:
	$(AS) -t $(SYS) -I $(CC65_ASMINC) -o $@ $(AFLAGS) $<

# Rule for making a *.o file out of a *.c file
#{}.c{$(ODIR)}.o:

.c.o:
	$(CC) $(SEGMENTS) $(CFLAGS) $<
	$(AS) -o $@ $(AFLAGS) $(*).s
#	$(RM) $*.s

# lynx-stdjoy.o:
# 	$(CP) $(CC65_INC)/../joy/$*.joy .
# 	$(CO) --code-label _lynxjoy $*.joy
# 	$(AS) -t lynx -o $@ $(AFLAGS) $*.s
# 	$(RM) $*.joy
# 	$(RM) $*.s

# lynx-160-102-16.o:
# 	$(CP) $(CC65_INC)/../tgi/$*.tgi .
# 	$(CO) --code-label _lynxtgi $*.tgi
# 	$(AS) -t lynx -o $@ $(AFLAGS) $*.s
# 	$(RM) $*.tgi
# 	$(RM) $*.s

# Rule for making a *.o file out of a *.bmp file
.bmp.o:
	$(SPRPCK) -t6 -p2 $<
	$(ECHO) .global _$(*B) > $*.s
	$(ECHO) .segment "$(RODATA_SEGMENT)" >> $*.s
	$(ECHO) _$(*B): .incbin "$*.spr" >> $*.s
	$(AS) -t lynx -o $@ $(AFLAGS) $*.s
	$(RM) $*.s
	$(RM) $*.pal
	$(RM) $*.spr


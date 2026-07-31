include ../shared/lynxcc65.mak

CFLAGS += -I../shared
AFLAGS += -I../shared

target = sprites1.lnx
symbols = sprites1.sym
objects = tests.o main.o

all: $(target)

$(target) : $(objects)
	$(CL) -Ln $(symbols) -t $(SYS) -o $@ $(objects) lynx.lib

clean:
	$(RM) -f $(objects) $(target)

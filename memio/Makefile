include ../shared/lynxcc65.mak

CFLAGS += -I../shared

target = memio.lnx
objects = tests.o main.o

all: $(target)

$(target) : $(objects)
	$(CL) -t $(SYS) -o $@ $(objects) lynx.lib 
	
clean:
	$(RM) -f $(objects) $(target)
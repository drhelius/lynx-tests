include ../shared/lynxcc65.mak

CFLAGS += -I../shared

target = timers.lnx
symbols = timers.sym
objects = tests.o main.o

all: $(target)

$(target) : $(objects)
	$(CL) -Ln $(symbols) -t $(SYS) -o $@ $(objects) lynx.lib 
	
clean:
	$(RM) -f $(objects) $(target)
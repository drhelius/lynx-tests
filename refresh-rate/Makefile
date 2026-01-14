	include ../shared/lynxcc65.mak

CFLAGS += -I../shared

target = refresh-rate.lnx
symbols = refresh-rate.sym
objects = isr.o main.o

all: $(target)

$(target) : $(objects)
	$(CL) -Ln $(symbols) -t $(SYS) -o $@ $(objects) lynx.lib 
	
clean:
	$(RM) -f $(objects) $(target)

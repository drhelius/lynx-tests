include ../shared/lynxcc65.mak

CFLAGS += -I../shared

target = uart2.lnx
symbols = uart2.sym
objects = tests.o main.o

all: $(target)

$(target) : $(objects)
	$(CL) -Ln $(symbols) -t $(SYS) -o $@ $(objects) lynx.lib 
	
clean:
	$(RM) -f $(objects) $(target)
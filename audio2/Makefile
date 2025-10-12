include ../shared/lynxcc65.mak

CFLAGS += -I../shared

target = audio2.lnx
symbols = audio2.sym
objects = tests.o main.o

all: $(target)

$(target) : $(objects)
	$(CL) -Ln $(symbols) -t $(SYS) -o $@ $(objects) lynx.lib 
	
clean:
	$(RM) -f $(objects) $(target)
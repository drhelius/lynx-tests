include lynxcc65.mak

target = timers.lnx
objects = tests.o main.o 

all: $(target)

$(target) : $(objects)
	$(CL) -t $(SYS) -o $@ $(objects) lynx.lib 
	
clean:
	$(RM) -f $(objects) $(target)
include lynxcc65.mak

target = hello.lnx
objects = hello.o

all: $(target)

$(target) : $(objects)
	$(CL) -t $(SYS) -o $@ $(objects) lynx.lib 
	
clean:

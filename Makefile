PROG = qp
SRC  = src/*.swift

# Default target builds the optimized version
default: release

# Target for the optimized version
release: SWIFTC_FLAGS = -DRELEASE -O
release: $(PROG)

# Target for the debuggable version.  This version prints verbose output
# and is not suitable for normal use.  It is only useful for debugging and
# observing the inner workings of the program.
debug: SWIFTC_FLAGS = -DDEBUG -g
debug: $(PROG)

# Target for the actual build
$(PROG): $(SRC)
	swiftc $(SWIFTC_FLAGS) -o $@ $^
	cp $(PROG) bin

# Clean
clean:
	rm -rf $(PROG) $(PROG).dSYM

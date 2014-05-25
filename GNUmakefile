########################################
# Find which compilers are installed.
#

VOLT ?= $(shell which volt)


########################################
# Basic settings.
#

VFLAGS ?=
LDFLAGS ?=
TARGET ?= volta


########################################
# Setting up the source.
#

SRC = \
	src/main.volt \
	src/volt/*.volt \
	src/volt/ir/*.volt \
	src/volt/token/*.volt \
	src/volt/parser/*.volt \
	src/volt/util/string.volt
#	src/volt/util/*.volt
#	src/volt/visitor/*.volt
#	src/volt/semantic/*.volt

ALL_SRC = $(shell find src -name "*.volt")


########################################
# Targets.
#

all: run

$(TARGET): $(SRC) GNUmakefile
	@echo "  VOLT   $(TARGET)"
	@$(VOLT) -I src $(VFLAGS) $(LDFLAGS) -o $(TARGET) $(SRC)

run: $(TARGET)
	@echo "  RUN    $(TARGET)"
	@./$(TARGET) $(ALL_SRC)

debug: $(TARGET)
	@echo "  DBG    $(TARGET)"
	@gdb --args ./$(TARGET) test/simple.volt

clean:
	@rm -rf $(TARGET) .obj

.PHONY: all run debug clean

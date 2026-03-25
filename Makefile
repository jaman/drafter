CFLAGS ?= -fPIC -O2
LDFLAGS ?=

UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
	LDFLAGS += -dynamiclib -undefined dynamic_lookup
else
	LDFLAGS += -shared
endif

ERTS_INCLUDE_DIR ?= $(shell erl -noshell -eval 'io:format("~s/include", [code:root_dir() ++ "/erts-" ++ erlang:system_info(version)])' -s init stop)

PRIV_DIR = priv
NIF_SO = $(PRIV_DIR)/termios_nif.so
NIF_SRC = c_src/termios_nif.c

all: $(NIF_SO)

$(PRIV_DIR):
	mkdir -p $(PRIV_DIR)

$(NIF_SO): $(NIF_SRC) | $(PRIV_DIR)
	$(CC) $(CFLAGS) -I$(ERTS_INCLUDE_DIR) -o $@ $< $(LDFLAGS)

clean:
	rm -f $(NIF_SO)

.PHONY: all clean

comma := ,

CROSS_TARGET := $(shell printf '%s' '$(CC)' | sed -n 's/.*-target \([^ ]*\).*/\1/p')

ifneq ($(CROSS_TARGET),)
TARGET_CPU := $(firstword $(subst -, ,$(CROSS_TARGET)))
TARGET_SYSTEM := $(word 2,$(subst -, ,$(CROSS_TARGET)))
else
TARGET_CPU := $(shell uname -m)
TARGET_SYSTEM := $(shell uname -s)
endif

ifneq ($(findstring macos,$(TARGET_SYSTEM))$(findstring Darwin,$(TARGET_SYSTEM)),)
TARGET_OS := darwin
else ifneq ($(findstring linux,$(TARGET_SYSTEM))$(findstring Linux,$(TARGET_SYSTEM)),)
TARGET_OS := linux
else
TARGET_OS := windows
endif

ifneq ($(findstring arm64,$(TARGET_CPU))$(findstring aarch64,$(TARGET_CPU)),)
NATIVE_CPU := aarch64
else
NATIVE_CPU := x86_64
endif

ifneq ($(CROSS_TARGET),)
PRIV_ROOT := $(MIX_APP_PATH)/priv
else
PRIV_ROOT := priv
endif

PRIV_DIR := $(PRIV_ROOT)/native/$(TARGET_OS)-$(NATIVE_CPU)

CFLAGS ?= -fPIC -O2
LDFLAGS ?=

ifeq ($(TARGET_OS),darwin)
	LDFLAGS += -dynamiclib -undefined dynamic_lookup
else
	LDFLAGS += -shared -lutil
endif

PROGRAM_CC := $(filter-out -shared -dynamic -Wl$(comma)-undefined=dynamic_lookup,$(CC))

ERTS_INCLUDE_DIR ?= $(shell erl -noshell -eval 'io:format("~s/include", [code:root_dir() ++ "/erts-" ++ erlang:system_info(version)])' -s init stop)

NIF_SO = $(PRIV_DIR)/termios_nif.so
NIF_SRC = c_src/termios_nif.c
PTY_SPAWN = $(PRIV_DIR)/pty_spawn
PTY_SPAWN_SRC = c_src/pty_spawn.c

ifeq ($(TARGET_OS),windows)
all:
else
all: $(NIF_SO) $(PTY_SPAWN)
endif

$(PRIV_DIR):
	mkdir -p $(PRIV_DIR)

$(NIF_SO): $(NIF_SRC) | $(PRIV_DIR)
	$(CC) $(CFLAGS) -I$(ERTS_INCLUDE_DIR) -o $@.tmp $< $(LDFLAGS) && mv -f $@.tmp $@ && rm -rf $@.tmp.dSYM

$(PTY_SPAWN): $(PTY_SPAWN_SRC) | $(PRIV_DIR)
	$(PROGRAM_CC) -O2 -o $@.tmp $< && mv -f $@.tmp $@

clean:
ifneq ($(MIX_APP_PATH),)
	rm -f $(NIF_SO) $(PTY_SPAWN) $(PRIV_DIR)/*.tmp
	rm -rf $(PRIV_DIR)/*.tmp.dSYM
endif

.PHONY: all clean

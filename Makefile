VUSTED_USE_LOCAL ?= 1
VUSTED ?= vusted
STYLUA ?= stylua
LUACHECK ?= luacheck

_LUAROCKS_BIN := $(shell luarocks --local config deploy_bin_dir 2>/dev/null)

# When the binary is not on PATH, fall back to the luarocks deploy bin dir,
# which is where `luarocks install <pkg>` places executables in CI and local dev.
_HAS_VUSTED := $(shell command -v $(VUSTED) 2>/dev/null)
_HAS_LUACHECK := $(shell command -v $(LUACHECK) 2>/dev/null)

ifeq ($(_HAS_VUSTED),)
ifneq ($(_LUAROCKS_BIN),)
VUSTED := $(_LUAROCKS_BIN)/vusted
endif
endif

ifeq ($(_HAS_LUACHECK),)
ifneq ($(_LUAROCKS_BIN),)
LUACHECK := $(_LUAROCKS_BIN)/luacheck
endif
endif

test:
	VUSTED_USE_LOCAL=$(VUSTED_USE_LOCAL) $(VUSTED) ./tests

stylua:
	$(STYLUA) --check .

luacheck:
	@set +e; $(LUACHECK) .; exit_code=$$?; if [ $$exit_code -gt 1 ]; then exit $$exit_code; fi

.PHONY: test stylua luacheck

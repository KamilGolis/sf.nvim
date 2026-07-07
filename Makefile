VUSTED_USE_LOCAL ?= 1
VUSTED ?= vusted

_LUAROCKS_BIN := $(shell luarocks --local config deploy_bin_dir 2>/dev/null)
_HAS_VUSTED := $(shell which $(VUSTED) 2>/dev/null)

ifeq ($(_HAS_VUSTED),)
  ifneq ($(_LUAROCKS_BIN),)
    VUSTED := $(_LUAROCKS_BIN)/vusted
  endif
endif

test:
	VUSTED_USE_LOCAL=$(VUSTED_USE_LOCAL) $(VUSTED) ./tests

stylua:
	stylua --check .

luacheck:
	luacheck .

.PHONY: test stylua luacheck

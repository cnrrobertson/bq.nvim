help:
	@sed -ne '/@sed/!s/## //p' $(MAKEFILE_LIST)

## ----------------------------------------------
##    Documentation
##    -------------
docs: ##  -- Compile documentation from source files
	nvim --headless --noplugin -u ./scripts/minimal_init.lua \
        -c "lua MiniDoc.generate({ \
        'lua/bq.lua', \
        'lua/bq/config.lua' \
        })" \
        -c "quit"

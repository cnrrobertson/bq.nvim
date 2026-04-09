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

## ----------------------------------------------
##    Tests
##    -----
test: ##  -- Run all tests
	nvim --headless --noplugin -u ./scripts/minimal_init.lua \
        -c "lua MiniTest.run()" -c "quit"

test_file: ##  -- Run a single test file  (FILE=tests/test_foo.lua)
	nvim --headless --noplugin -u ./scripts/minimal_init.lua \
        -c "lua MiniTest.run_file('$(FILE)')" -c "quit"

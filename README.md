# lua-minifier
A self-contained Lua module for minifying, packing, and compiling Lua code.

## Adding this module to your project

Since all the logic is contained in a single file with no dependencies, you can simply copy and paste the file or its contents into your project.

## Installing the module as a binary

If you want to use Lumin as a command-line script, just run `./install.sh`.
You should then be able to run `lumin -h` to see available options.

### Example Usage

```lua
local lumin = require 'lumin'

--Arbitrary Lua code to minify. Can read this from a file or hard-code it in the variable.
local lua_code = io.open('some_file'):read('*a')

--To minify Lua code (remove comments and excess whitespace)
local minified_code = lumin:minify(lua_code)
```

Note that by default, this does NOT follow require statements and pack them all into a single Lua source.
However there is an option to enable this feature.

## Details

```
minify = function(
    text: string                   | The Lua code to minify.
    standalone: boolean?           | Whether to pack any required files into the resultant source.
    remove_delete_blocks: boolean? | Whether to remove blocks of code that are wrapped in `--[[minify-delete]]` ... `--[[/minify-delete]]` comments.
    print_progress: boolean?       | Whether to print progress messages (useful when minifying very large Lua projects)
) -> string | The minified Lua code.
```

So, if you also want to pack everything into a single Lua file as well, pass `true` as the second parameter:
```lua
local packed_minified_code = lumin:minify(lua_code, true)
```

If you only want to pack the code into a single file, but don't want to minify, just call `lumin:pack()`
```
pack = function(
    text: string                   | The Lua code to pack.
    remove_delete_blocks: boolean? | Whether to remove blocks of code that are wrapped in `--[[minify-delete]]` ... `--[[/minify-delete]]` comments.
    print_progress: boolean?       | Whether to print progress messages.
) -> string | The packed Lua code.
```
```lua
local packed_code = lumin:pack(lua_code)
```

Lastly, Lumin allows compiling a string of Lua code into bytecode.
This does not include packing require statements, into a single file, as sometimes you want to keep those statements!

```
compile = function(
    text: string | The Lua code to compile.
) -> string? | The compiled Lua bytecode, or nil if compilation failed.
  2. string? | The error message if compilation failed, or nil if compilation succeeded.
```
```lua
local bytecode = lumin:compile(lua_code)
```

## Special Comment Blocks

Lumin recognizes a few special comment markers that can change how it handles certain blocks of code.

- `--[[no-install]] ... --[[/no-install]]`
  - Anything inside these markers will always be removed, regardless of any flags passed to `lumin:minify()`.
- `--[[minify-delete]] ... --[[/minify-delete]]`
  - Anything inside these markers will be removed if the second argument to `lumin:minify()` is `true`.
- `--[[build-replace=FILE_NAME]] ... --[[/build-replace]]`
  - Anything inside these markers will be replaced with the contents of the file at `FILE_NAME` as a string.
  - The string will of course be escaped properly so that the Lua code stays valid.

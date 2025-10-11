#!/usr/bin/env bash

# A simple installer script for lumin.

# Generate the Lua program that takes a file as input and runs lumin on it.
tmpfile='.lumin_temp_install.lua'
cat >"$tmpfile" <<EOF
local function print_usage()
    io.stderr:write([[
Lumin - Minify, pack, and compile Lua code.
Usage: lumin [options] [input_file]

Input:
  input_file                The Lua source file to minify (default: stdin)

Options:
  -o --output output_file   Specify the output file (default: stdout)
  -c --compile              Compile to Lua bytecode
  -r --recursive            Recursively pack all require calls (default: false)
  -d --delete               Remove \`--[[minify-delete]]..']]'..[[\` blocks
  -m --minify               Minify the Lua code (default: false)
  -p --progress             Print progress to stderr
  -h --help                 Show this help message
]])
end

local input_file = nil
local output_file = nil
local compile = false
local recursive = false
local delete_blocks = false
local minify = false
local print_progress = false

for i = 1, #arg do
    local a = arg[i]
    if a == '-o' then
        i = i + 1
        output_file = arg[i]
    elseif a == '-c' or a == '--compile' then
        compile = true
    elseif a == '-r' or a == '--recursive' then
        recursive = true
    elseif a == '-d' or a == '--delete' then
        delete_blocks = true
    elseif a == '-m' or a == '--minify' then
        minify = true
    elseif a == '-p' or a == '--progress' then
        print_progress = true
    elseif a == '-h' or a == '--help' then
        print_usage()
        os.exit(0)
    elseif not input_file then
        input_file = a
    else
        io.stderr:write('Unknown argument: ' .. a .. '\n')
        print_usage()
        os.exit(1)
    end
end

local f_input = io.stdin
if input_file and input_file ~= '-' then
    local f, err = io.open(input_file, 'r')
    if not f then
        io.stderr:write('Error opening input file: ' .. err .. '\n')
        os.exit(1)
    end
    f_input = f
end

local f_output = io.stdout
if output_file and output_file ~= '-' then
    local f, err = io.open(output_file, 'w')
    if not f then
        io.stderr:write('Error opening output file: ' .. err .. '\n')
        os.exit(1)
    end
    f_output = f
end

local lumin = require 'lumin'

local text = f_input:read('*a')
if f_input ~= io.stdin then
    f_input:close()
end

local new_text = nil
if minify then
    new_text = lumin:minify(text, recursive, delete_blocks, print_progress)
else
    new_text = lumin:pack(text, delete_blocks, print_progress)
end
if compile then
    local bytecode, err = lumin:compile(new_text)
    if not bytecode then
        io.stderr:write(err .. '\n')
        io.stderr:write('Error: Failed to compile Lua code into bytecode.\n')
        os.exit(1)
    end
    new_text = bytecode
end

f_output:write(new_text)
if f_output ~= io.stdout then
    f_output:close()
end

EOF

# Pack the lumin.lua file into the temp file.
lua "$tmpfile" "$tmpfile" > "$tmpfile.2"
mv "$tmpfile.2" "$tmpfile"

# Copy the temp file to user's local bin directory.
if [ -d "$HOME/.local/bin" ]; then
    install_dir="$HOME/.local/bin"
elif [ -d "/usr/local/bin" ]; then
    install_dir="/usr/local/bin"
else
    echo "Error: Could not find a suitable installation directory." >&2
    exit 1
fi
install_path="$install_dir/lumin"
echo "#!/usr/bin/env lua" > "$install_path"
cat "$tmpfile" >> "$install_path"
chmod +x "$install_path"
echo "Installed lumin to $install_path"

rm -f "$tmpfile"

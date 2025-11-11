--[[
	Lumin - A self-contained Lua module for minifying, gluing, and compiling Lua code.
	Copyright (C) 2025 Zachary Westerman

	This program is free software: you can redistribute it and/or modify
	it under the terms of the GNU General Public License as published by
	the Free Software Foundation, either version 3 of the License, or
	(at your option) any later version.

	This program is distributed in the hope that it will be useful,
	but WITHOUT ANY WARRANTY; without even the implied warranty of
	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
	GNU General Public License for more details.

	You should have received a copy of the GNU General Public License
	along with this program.  If not, see <https://www.gnu.org/licenses/>.
--]]

return {
	---@class (exact) lumin.Token
	---@field text string
	---@field type string

	--- Tokenize a string of Lua code.
	--- @param text string
	--- @return lumin.Token[]
	tokenize = function(text)
		local tokens = {}

		local patterns = {
			{ '^%s+',            'space' }, -- Whitespace
			{ '^#!.-\n',         'comment' }, -- Shebang
			{ '^%-%-%[%[.-%]%]', 'comment' }, -- Multiline Comments
			{ '^%-%-.-\n',       'comment' }, -- Comments
			{ '^%[%[.-%]%]',     'string' }, -- Multiline strings
			{ '^%"',             'string' }, -- Strings
			{ '^\'',             'string' }, -- Strings
			{ '^[%w_]+',         'word' }, -- Words
			{ '^%(',             'lparen' }, -- Left Parentheses
			{ '^%)',             'rparen' }, -- Right Parentheses
			{ '^[%p]',           'symbol' }, -- Punctuation
		}

		while #text > 0 do
			local found = false
			for _, pattern in ipairs(patterns) do
				local token = text:match(pattern[1])
				if token then
					if token == '"' or token == '\'' then
						local i = 1
						while true do
							local ix = text:find(token, i + 1, true)
							if not ix then
								error('ERROR When parsing Lua code: Unclosed string.')
							end

							i = ix
							--Ignore escaped quotes with an odd number of backslashes
							local backslashes = 0
							local b = i
							while text:sub(b - 1, b - 1) == '\\' do
								backslashes = backslashes + 1
								b = b - 1
							end

							if backslashes % 2 == 0 then
								break
							end
						end
						token = text:sub(1, i)
					end

					table.insert(tokens, {
						text = token,
						type = pattern[2]
					})
					text = text:sub(#token + 1)
					found = true
					break
				end
			end

			if not found then
				error('ERROR When parsing Lua code: Unexpected character: `' .. text:sub(1, 1) .. '`.')
			end
		end

		return tokens
	end,

	--- Minify a string of Lua code.
	--- @param text string The Lua code.
	--- @param standalone boolean? Whether to resolve require statements.
	--- @param remove_delete_blocks boolean? Whether to remove blocks of code that are wrapped in `--[[minify-delete]]` ... `--[[/minify-delete]]` comments.
	--- @param print_progress boolean? Whether to print progress messages.
	--- @return string new_code The minified Lua code.
	minify = function(self, text, standalone, remove_delete_blocks, print_progress)
		local tokens = self.tokenize(text)

		if remove_delete_blocks then
			tokens = self.tokens.remove_delete_blocks(tokens)
		end

		if standalone then
			tokens = self.tokens.replace_requires(self, tokens, print_progress, remove_delete_blocks)
		end

		tokens = self.tokens.remove_noinstall_blocks(tokens)

		if print_progress then io.stderr:write('\nInserting helper files...') end
		tokens = self.tokens.replace_build_replace_blocks(self, tokens, print_progress)

		tokens = self.tokens.strip(tokens)

		if print_progress then io.stderr:write('\n') end
		local result = self.tokens.join(tokens, print_progress)
		if print_progress then io.stderr:write('\n') end

		return result
	end,

	--- Resolve all require statements in a string of Lua code, and replace special comment blocks.
	--- @param text string The Lua code.
	--- @param remove_delete_blocks boolean? Whether to remove blocks of code that are wrapped in `--[[minify-delete]]` ... `--[[/minify-delete]]` comments.
	--- @param print_progress boolean? Whether to print progress messages.
	--- @return string new_code The resolved Lua code.
	pack = function(self, text, remove_delete_blocks, print_progress)
		local tokens = self.tokenize(text)

		tokens = self.tokens.replace_requires(self, tokens, print_progress)

		if remove_delete_blocks then
			tokens = self.tokens.remove_delete_blocks(tokens)
		end

		tokens = self.tokens.remove_noinstall_blocks(tokens)

		if print_progress then io.stderr:write('\nInserting helper files...') end
		tokens = self.tokens.replace_build_replace_blocks(self, tokens, print_progress)

		if print_progress then io.stderr:write('\n') end
		local result = self.tokens.join(tokens, print_progress)
		if print_progress then io.stderr:write('\n') end

		return result
	end,

	--- Compile a string of Lua code into Lua bytecode.
	--- @param text string The Lua code.
	--- @return string? bytecode The Lua bytecode, or nil if compilation failed.
	--- @return string? error_message The error message, or nil if compilation succeeded.
	compile = function(self, text)
		local switch = false
		local function loadfn()
			if switch then return nil end
			switch = true
			return text
		end

		local fn, err = load(loadfn)
		if not fn then
			return nil, err
		end

		return string.dump(fn), nil
	end,

	tokens = {
		--- Print a table of tokens.
		--- @param tokens lumin.Token[] The tokens to print.
		--- @return nil
		print = function(tokens)
			for _, token in ipairs(tokens) do
				print(token.type, ' = ', token.text)
			end
		end,

		--- Remove whitespace and comments from a table of tokens.
		--- @param tokens lumin.Token[] The tokens to process.
		--- @return lumin.Token[] stripped The processed tokens.
		strip = function(tokens)
			local stripped = {}
			for i, token in ipairs(tokens) do
				if token.type ~= 'space' and token.type ~= 'comment' then
					table.insert(stripped, token)
				end
			end
			return stripped
		end,

		--- Join a table of tokens into a string.
		--- @param tokens lumin.Token[] The tokens to join.
		--- @param print_progress boolean? Whether to print progress messages.
		--- @return string text The joined text.
		join = function(tokens, print_progress)
			local text = ''
			local prev = {
				type = 'space',
				text = '',
			}
			local buffer = ''

			for i, token in ipairs(tokens) do
				if prev.type == 'word' and token.type == 'word' then
					buffer = buffer .. ' '
				end
				buffer = buffer .. token.text
				prev = token

				if print_progress and i % 100 == 0 then
					io.stderr:write('\rGenerating text... ' .. math.floor(i / #tokens * 100) .. '%')
				end

				if #buffer > 4096 then
					text = text .. buffer
					buffer = ''
				end
			end
			text = text .. buffer

			if print_progress then
				io.stderr:write('\rGenerating text... 100%\n')
			end
			return text
		end,

		_requires_cache = {},
		_rqid = 0,

		--- Recursively parse require statements and split into a function call and the rest of the program.
		--- @param tokens lumin.Token[] The tokens to process.
		--- @param print_progress boolean? Whether to print progress messages.
		--- @param remove_delete_blocks boolean? Whether to remove blocks of code that are wrapped in `--[[minify-delete]]` ... `--[[/minify-delete]]` comments.
		--- @return lumin.Token[] new_tokens The processed tokens.
		_extract_requires = function(self, tokens, print_progress, remove_delete_blocks)
			if print_progress then
				io.stderr:write('.')
			end

			local function match_types(tokens, i, group)
				for j = 1, #group do
					-- Ignore whitespace and comments
					while tokens[i].type == 'space' or tokens[i].type == 'comment' do
						i = i + 1
					end

					if tokens[i + j - 1].type ~= group[j] then
						return false
					end
				end
				return true
			end

			local function get_next_value(tokens, i, token_type)
				while tokens[i].type ~= token_type do
					i = i + 1
				end
				return tokens[i].text
			end

			local function get_next_index(tokens, i, token_type)
				while tokens[i].type ~= token_type do
					i = i + 1
				end
				return i
			end

			local new_tokens = {}
			local i = 1
			while i <= #tokens do
				if tokens[i].text == 'require' and match_types(tokens, i + 1, { 'string' }) then
					local file = get_next_value(tokens, i, 'string'):sub(2, -2):gsub('%.', '/') .. '.lua'
					local fp = io.open(file)
					if not fp then
						io.stderr:write('WARNING: File not found: `' .. file ..'`. Skipping require statement.\n')
						table.insert(new_tokens, tokens[i])
					else
						if not self.tokens._requires_cache[file] then
							local t = self.tokenize(fp:read('*a'))
							if remove_delete_blocks then
								t = self.tokens.remove_delete_blocks(t)
							end
							self.tokens._requires_cache[file] = {}
							self.tokens._requires_cache[file] = {
								tokens = self.tokens._extract_requires(self, t, print_progress, remove_delete_blocks),
								id = 'RQ' .. self.tokens._rqid,
							}
							self.tokens._rqid = self.tokens._rqid + 1
						end

						table.insert(new_tokens, { text = self.tokens._requires_cache[file].id, type = 'word' })
						table.insert(new_tokens, { text = '(', type = 'lparen' })
						table.insert(new_tokens, { text = ')', type = 'rparen' })

						i = get_next_index(tokens, i, 'string')
						fp:close()
					end
				else
					table.insert(new_tokens, tokens[i])
				end
				i = i + 1
			end

			return new_tokens
		end,

		--- Replace all require calls with the appropriate file contents.
		--- @param tokens lumin.Token[] The tokens to process.
		--- @param print_progress boolean? Whether to print progress messages.
		--- @param remove_delete_blocks boolean? Whether to remove blocks of code that are wrapped in `--[[minify-delete]]` ... `--[[/minify-delete]]` comments.
		--- @return lumin.Token[] new_tokens The processed tokens.
		replace_requires = function(self, tokens, print_progress, remove_delete_blocks)
			self.tokens._requires_cache = {}

			local t = tokens
			if remove_delete_blocks then
				t = self.tokens.remove_delete_blocks(t)
			end

			local program = self.tokens._extract_requires(self, t, print_progress, remove_delete_blocks)

			local result = {}
			for _, token_list in pairs(self.tokens._requires_cache) do
				--Cache for require calls.
				table.insert(result, { text = 'C' .. token_list.id, type = 'word' })
				table.insert(result, { text = '={nil,false}', type = 'lparen' })

				--Function begin
				table.insert(result, { text = 'function ' .. token_list.id, type = 'word' })
				table.insert(result, { text = '()', type = 'lparen' })

				--Function body (called with `require`).
				table.insert(result, { text = 'local fn=function', type = 'word' })
				table.insert(result, { text = '()', type = 'lparen' })
				for _, token in ipairs(token_list.tokens) do
					table.insert(result, token)
				end
				table.insert(result, { text = 'end', type = 'word' })

				--If function hasn't been called yet, call it and cache the result.
				table.insert(result, {
					text = 'if not C' .. token_list.id .. '[2] then C' .. token_list.id .. '={fn(),true} end',
					type = 'word'
				})
				table.insert(result, { text = 'return C' .. token_list.id, type = 'word' })
				table.insert(result, { text = '[1]', type = 'lparen' })

				--Function end
				table.insert(result, { text = 'end', type = 'word' })
			end

			for _, token in ipairs(program) do
				table.insert(result, token)
			end

			return result
		end,

		--- Remove any blocks of code that are wrapped in `--[[minify-delete]]` ... `--[[/minify-delete]]` comments.
		--- @param tokens lumin.Token[] The tokens to process.
		--- @return lumin.Token[] new_tokens The processed tokens.
		remove_delete_blocks = function(tokens)
			local new_tokens = {}
			local i = 1
			while i <= #tokens do
				if tokens[i].type == 'comment' and tokens[i].text == '--[[minify-delete]]' then
					local beg = i
					while tokens[i].type ~= 'comment' or tokens[i].text ~= '--[[/minify-delete]]' do
						i = i + 1
						--Check for minification errors
						if tokens[i].type == 'comment' and tokens[i].text == '--[[minify-delete]]' then
							local msg = 'ERROR: Unexpected `--[[minify-delete]]` inside a `--[[minify-delete]]` block.'
							msg = msg .. '\nCONTEXT:\n'
							for j = beg - 1, i do
								if tokens[j] then
									msg = msg .. tokens[j].text
								end
							end
							io.stderr:write(msg .. '\n')
							os.exit(1)
						end
					end
				else
					table.insert(new_tokens, tokens[i])
				end
				i = i + 1
			end
			return new_tokens
		end,

		--- Remove any blocks of code that are wrapped in `--[[no-=install]]` ... `--[[/no-install]]` comments.
		--- @param tokens lumin.Token[] The tokens to process.
		--- @return lumin.Token[] new_tokens The processed tokens.
		remove_noinstall_blocks = function(tokens)
			local new_tokens = {}
			local i = 1
			while i <= #tokens do
				if tokens[i].type == 'comment' and tokens[i].text == '--[[no-install]]' then
					while tokens[i].type ~= 'comment' or tokens[i].text ~= '--[[/no-install]]' do
						i = i + 1
					end
				else
					table.insert(new_tokens, tokens[i])
				end
				i = i + 1
			end
			return new_tokens
		end,


		--- Replace all blocks of code that are wrapped in `--[[build-replace=...]]` ... `--[[/build-replace]]` comments with the specified file contents.
		--- @param tokens lumin.Token[] The tokens to process.
		--- @param print_progress boolean? Whether to print progress messages.
		--- @return lumin.Token[] new_tokens The processed tokens.
		replace_build_replace_blocks = function(self, tokens, print_progress)
			local new_tokens = {}
			local i = 1
			while i <= #tokens do
				if tokens[i].type == 'comment' and tokens[i].text:match('^%-%-%[%[build%-replace=(.-)%]%]') then
					local file = tokens[i].text:match('^%-%-%[%[build%-replace=(.-)%]%]')
					local fp = io.open(file)
					if not fp then
						error('ERROR in `build-replace=' .. file .. '` block: File not found.')
					end
					local text = fp:read('*a')
					fp:close()

					--Minify any Lua code
					if file:match('%.lua$') then
						text = self:minify(text, true, _G['SANDBOX'] or false)
					end

					--Escape the text so it can be used in a Lua string
					text = text:gsub('\\', '\\\\'):gsub('\n', '\\n'):gsub('"', '\\"')

					--Append the text to the new tokens
					table.insert(new_tokens, { text = '"' .. text .. '"', type = 'string' })

					--Skip to the end of the block
					while tokens[i].type ~= 'comment' or tokens[i].text ~= '--[[/build-replace]]' do
						i = i + 1
					end

					if print_progress then io.stderr:write('.') end
				else
					table.insert(new_tokens, tokens[i])
				end
				i = i + 1
			end
			return new_tokens
		end,
	},
}

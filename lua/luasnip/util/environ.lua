local util = require("luasnip.util.util")

local Environ = {}

local eager = {}
local lazy = {}
local table_env = {}

function Environ.new(pos)
	local self = setmetatable({}, { __index = Environ })
	self:fill_eagers(pos)
	return self
end

function Environ:fill_eagers(pos)
	for name, func in pairs(eager) do
		self[name] = func(pos)
	end
end

function Environ:call(key, ctx)
	if self[key] then
		return self[key]
	end
	return lazy[key](ctx)
end

function Environ.register(name, func, is_eager, is_table)
	if is_eager then
		eager[name] = func
	else
		lazy[name] = func
	end
    if is_table then
        table_env[name] = true
    end
end

function Environ.is_table(key)
    return table_env[key]
end

Environ.register("TM_CURRENT_LINE", function(pos)
	return vim.api.nvim_buf_get_lines(0, pos[1], pos[1] + 1, false)[1]
end, true)

Environ.register("TM_CURRENT_WORD", function(pos)
	return util.word_under_cursor(
		pos,
		vim.api.nvim_buf_get_lines(0, pos[1], pos[1] + 1, false)[1]
	)
end, true)

Environ.register("TM_LINE_INDEX", function(pos)
	return tostring(pos[1])
end, true)

Environ.register("TM_LINE_NUMBER", function(pos)
	return tostring(pos[1] + 1)
end, true)

Environ.register("SELECT_RAW", function()
	local ret = util.get_selection()
	return ret
end, true, true)

Environ.register("SELECT_DEDENT", function()
	local _, ret = util.get_selection()
	return ret
end, true, true)

Environ.register("TM_SELECTED_TEXT", function()
	local _, _, ret = util.get_selection()
	return ret
end, true, true)

Environ.register("TM_FILENAME", function()
	return vim.fn.expand("%:t")
end)

Environ.register("TM_FILENAME_BASE", function()
	return vim.fn.expand("%:t:r")
end)

Environ.register("TM_DIRECTORY", function()
	return vim.fn.expand("%:p:h")
end)

Environ.register("TM_FILEPATH", function()
	return vim.fn.expand("%:p")
end)

local function part_ws()
	local LSP_WORSKPACE_PARTS = "LSP_WORSKPACE_PARTS" -- cache
	local ok, ws_parts = pcall(vim.api.nvim_buf_get_var, 0, LSP_WORSKPACE_PARTS)
	if not ok then
		local file_path = vim.fn.expand("%:p")
		for _, ws in pairs(vim.lsp.buf.list_workspace_folders()) do
			if vim.startswith(file_path, ws) then
				ws_parts = { ws, file_path:sub(#ws + 2) }
				break
			end
		end
		if not ws_parts then
			ws_parts = { vim.fn.expand("%:p:h"), vim.fn.expand("%:p:t") }
		end
		vim.api.nvim_buf_set_var(0, LSP_WORSKPACE_PARTS, ws_parts)
	end
	return ws_parts
end

Environ.register("WORKSPACE_FOLDER", function()
	return part_ws()[1]
end)

Environ.register("WORKSPACE_NAME", function()
	return vim.fn.fnamemodify(part_ws()[1], ":t")
end)

Environ.register("RELATIVE_FILEPATH", function()
	return part_ws()[2]
end)

Environ.register("CLIPBOARD", function()
	return vim.fn.getreg('"', 1, true)
end)

Environ.register("CURRENT_YEAR", function()
	return os.date("%Y")
end)

Environ.register("CURRENT_YEAR_SHORT", function()
	return os.date("%y")
end)

Environ.register("CURRENT_MONTH", function()
	return os.date("%m")
end)

Environ.register("CURRENT_MONTH_NAME", function()
	return os.date("%B")
end)

Environ.register("CURRENT_MONTH_NAME_SHORT", function()
	return os.date("%b")
end)

Environ.register("CURRENT_DATE", function()
	return os.date("%d")
end)

Environ.register("CURRENT_DAY_NAME", function()
	return os.date("%A")
end)

Environ.register("CURRENT_DAY_NAME_SHORT", function()
	return os.date("%a")
end)

Environ.register("CURRENT_HOUR", function()
	return os.date("%H")
end)

Environ.register("CURRENT_MINUTE", function()
	return os.date("%M")
end)

Environ.register("CURRENT_SECOND", function()
	return os.date("%S")
end)

Environ.register("CURRENT_SECONDS_UNIX", function()
	return tostring(os.time())
end)

math.randomseed(os.time())

Environ.register("RANDOM", function()
	return string.format("%06d", math.random(999999)) -- 10^6-1
end)

Environ.register("RANDOM", function()
	return string.format("%06d", math.random(16777215)) -- 16^6-1
end)

Environ.register("UUID", function()
	local uuid = string.gsub(
		"xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx",
		"[xy]",
		function(c)
			local v = c == "x" and math.random(0, 15) or math.random(8, 11)
			return string.format("%x", v)
		end
	)
	return uuid
end)

Environ.register("LINE_COMMENT", function ()
    return util.buffer_comment_chars()[1]
end)

Environ.register("BLOCK_COMMENT_START", function ()
    return util.buffer_comment_chars()[2]
end)

Environ.register("BLOCK_COMMENT_END", function ()
    return util.buffer_comment_chars()[3]
end)

return Environ

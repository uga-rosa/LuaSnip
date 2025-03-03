-- Check if treesitter is available
local ok_parsers, ts_parsers = pcall(require, "nvim-treesitter.parsers")
if not ok_parsers then
	ts_parsers = nil
end

local ok_utils, ts_utils = pcall(require, "nvim-treesitter.ts_utils")
if not ok_utils then
	ts_utils = nil
end

local function from_cursor_pos()
	if not ts_parsers or not ts_utils then
		return {}
	end

	local parser = ts_parsers.get_parser()
	local current_node = ts_utils.get_node_at_cursor()

	if current_node then
		return { parser:language_for_range({ current_node:range() }):lang() }
	else
		return {}
	end
end

local function from_filetype()
	return vim.split(vim.bo.filetype, ".", true)
end

local function from_pos_or_filetype()
	local from_cursor = from_cursor_pos()
	if not vim.tbl_isempty(from_cursor) then
		return from_cursor
	else
		return from_filetype()
	end
end

return {
	from_filetype = from_filetype,
	from_cursor_pos = from_cursor_pos,
	from_pos_or_filetype = from_pos_or_filetype,
}

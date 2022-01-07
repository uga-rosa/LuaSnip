local parser = require("vim.lsp._snippet")

local util = require("luasnip.util.util")
local util_fn = require("luasnip.util.functions")

util.exist_nest = function(...)
	local args = { ... }
	local t = args[1]
	for i = 2, #args do
		if t[args[i]] ~= nil then
			t = t[args[i]]
		else
			return nil
		end
	end
	return t
end

local text_node = require("luasnip.nodes.textNode").T
local insert_node = require("luasnip.nodes.insertNode").I
local choice_node = require("luasnip.nodes.choiceNode").C
local function_node = require("luasnip.nodes.functionNode").F
local snippet_node = require("luasnip.nodes.snippet").SN
local snippet = require("luasnip.nodes.snippet").S
local ai = require("luasnip.nodes.absolute_indexer")

local M = {}

-- Type = {
--         SNIPPET = 0,
--         TABSTOP = 1,
--         PLACEHOLDER = 2,
--         VARIABLE = 3
--         CHOICE = 4,
--         TRANSFORM = 5,
--         FORMAT = 6,
--         TEXT = 7,
--       },

function M.parse(context, body)
	vim.tbl_extend("keep", context, { docstring = body })

	local ast = parser.parse(body).children
	M.check_copy(ast)
    ---@diagnostic disable-next-line: undefined-global
	dump(ast)

	local snip = vim.tbl_map(M._parse, ast)

	return snippet(context, snip)
end

---shallow copy
---@param src table
---@return table
local function tbl_copy(src)
	vim.validate({ src = { src, "t" } })
	local dst = {}
	for key, value in pairs(src) do
		dst[key] = value
	end
	return dst
end

local function get_blank(tbl)
    for i = 1, #tbl do
        if tbl[i] == nil then
            return i
        end
    end
    return #tbl + 1
end

function M.check_copy(ast)
	local tabstops = {}
	local function _normalize(_ast, up_index)
		for _, node in ipairs(_ast) do
			if
				vim.tbl_contains({ 1, 2, 4 }, node.tabstop)
				and not node.transform
			then
				local index = tbl_copy(up_index or {})
				table.insert(index, node.tabstop)
				node.index = index

				local ts = tabstops[node.tabstop]
				if ts then
					if node.type == 1 then -- TABSTOP
						node.is_copy = true
						node.see = ts.index
						if ts.incomplete then
							table.insert(ts.copies, node)
						end
					else -- PLACEHOLDER or CHOICE
						if ts.incomplete then
							ts.is_copy = true
							ts.see = index
							for _, n in ipairs(ts.copies) do
								n.see = index
							end
							tabstops[node.tabstop] = node
						else
							-- Multiple placeholders/choices on the same tabstop.
							-- Make all but the first one a copy of the first one.
							node.is_copy = true
							node.see = ts.index
						end
					end
				else
					tabstops[node.tabstop] = node
					if node.type == 1 then
						node.incomplete = true
						node.copies = {}
					end
				end
			end

			if node.children then
				if node.type == 3 then
					local index = tbl_copy(up_index or {})
					table.insert(index, get_blank(tabstops))
					node.index = index
				end
				_normalize(node.children, node.index)
			end
		end
	end
	_normalize(ast)
end

function M._parse(node, is_not_top)
	if node.is_copy then
		return function_node(util_fn.copy, ai(node.index))
	elseif node.type == 1 then
		if node.transform then
			return function_node(M._transform(node.transform), ai(node.index))
		else
			return insert_node(node.tabstop)
		end
	elseif node.type == 2 then
		if M._all_same_type(node.children, 7) then
			local text = {}
			for _, n in ipairs(node.children) do
				table.insert(text, n.esc)
			end
			return insert_node(node.tabstop, table.concat(text, ""))
		end
	elseif node.type == 3 then
	elseif node.type == 4 then
		return choice_node(
			node.tabstop,
			vim.tbl_map(function(s)
				return text_node(s)
			end, node.items)
		)
	elseif node.type == 7 then
		return text_node(node.esc)
	end
end

function M._all_same_type(children, type)
	for _, node in ipairs(children) do
		if node.type ~= type then
			return false
		end
	end
	return true
end

function M._transform(node)
	if node.pattern == "(.*)" then
		-- TODO: full js-regex parse
		local fns = {}
		for _, f in ipairs(node.format) do
			if f.type == 7 then
				table.insert(fns, M._text(f.esc))
			elseif f.type == 6 and f.capture_index == 1 then
				if f.modifier then
					table.insert(fns, M._modifier(f.modifier))
				elseif f.if_text or f.else_text then
					table.insert(fns, function(capture)
						if capture ~= "" then
							return f.if_text or ""
						end
						return f.else_text or ""
					end)
				else
					table.insert(fns, M._text())
				end
			end
		end
		return function(args)
			local capture = args[1][1]
			return table.concat(
				vim.tbl_map(function(fn)
					return fn(capture)
				end, fns),
				""
			)
		end
	else
		-- use vim regex
		local format = {}
		for _, n in ipairs(node.format) do
			if n.type == 7 then
				table.insert(format, n.esc)
			end
		end
		format = table.concat(format)

		return function(args)
			local capture = args[1][1]
			return vim.fn.substitute(capture, node.pattern, format, node.option)
		end
	end
end

function M._text(text)
	if text then
		return function()
			return text
		end
	end
	return function(c)
		return c
	end
end

function M._modifier(mod)
	if mod == "upcase" then
		return string.upper
	elseif mod == "downcase" then
		return string.lower
	elseif mod == "capitalize" then
		return function(text)
			return text:sub(1, 1):upper() .. text:sub(2)
		end
	elseif mod == "camelcase" then
		return M._camelcase()
	elseif mod == "pascalcase" then
		return M._camelcase(true)
	end
end

function M._camelcase(is_upper)
	return function(ctx)
		local ret = {}
		local is_first = true
		for c in vim.gsplit(ctx, "[-_]") do
			if is_first and not is_upper then
				table.insert(ret, c)
			else
				table.insert(ret, c:sub(1, 1):upper())
				table.insert(ret, c:sub(2))
			end
			is_first = false
		end
		return table.concat(ret, "")
	end
end

require("luasnip").snippets.all = {
	M.parse(
		{ trig = "hoge" },
		"$1${1/hoge/foo/g}${2:${1:hi}}$2$3${2:hoge}${4|hoge,foo,hey|}"
	),
}

return M

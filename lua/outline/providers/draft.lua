local M = {
	name = "draft",
}

local CONTEXT = 2
local SUB_CONTEXT = 13

function M.supports_buffer(bufnr, config)
	local ft = vim.bo[bufnr].filetype
	if config and config.filetypes then
		for _, ft_check in ipairs(config.filetypes) do
			if ft_check == ft then
				return true
			end
		end
	end
	return ft == "draft"
end

function M.request_symbols(on_symbols, opts)
	local bufnr = vim.api.nvim_get_current_buf()
	local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "draft")
	if not ok or not parser then
		return on_symbols({}, opts)
	end

	local tree = parser:parse()[1]
	if not tree then
		return on_symbols({}, opts)
	end

	local success, query = pcall(vim.treesitter.query.get, "draft", "outline")
	if not success or not query then
		return on_symbols({}, opts)
	end

	local items = {}

	for id, node in query:iter_captures(tree:root(), bufnr, 0, -1) do
		local capture_name = query.captures[id]
		local start_row = node:range()
		local text = vim.treesitter.get_node_text(node, bufnr)

		if capture_name == "context" then
			table.insert(items, {
				row = start_row,
				symbol = {
					kind = CONTEXT,
					name = text,
					selectionRange = {
						start = { character = 0, line = start_row },
						["end"] = { character = 0, line = start_row },
					},
					range = {
						start = { character = 0, line = start_row },
						["end"] = { character = 0, line = start_row },
					},
					children = {},
				},
			})
		elseif capture_name == "sub_context" then
			table.insert(items, {
				row = start_row,
				symbol = {
					kind = SUB_CONTEXT,
					name = text,
					selectionRange = {
						start = { character = 0, line = start_row },
						["end"] = { character = 0, line = start_row },
					},
					range = {
						start = { character = 0, line = start_row },
						["end"] = { character = 0, line = start_row },
					},
				},
			})
		end
	end

	table.sort(items, function(a, b)
		return a.row < b.row
	end)

	local symbols = {}
	local current_ctx = nil

	for _, item in ipairs(items) do
		if item.symbol.kind == CONTEXT then
			current_ctx = item.symbol
			table.insert(symbols, current_ctx)
		elseif item.symbol.kind == SUB_CONTEXT and current_ctx then
			table.insert(current_ctx.children, item.symbol)
		else
			table.insert(symbols, item.symbol)
		end
	end

	on_symbols(symbols, opts)
end

return M

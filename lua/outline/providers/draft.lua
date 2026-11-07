local M = {
	name = "draft",
}

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

	local symbols = {}
	for _, node in query:iter_captures(tree:root(), bufnr, 0, -1) do
		local start_row, _, _, _ = node:range()
		local section_name = vim.treesitter.get_node_text(node, bufnr)

		table.insert(symbols, {
			kind = 14,
			name = section_name,
			selectionRange = {
				start = { character = 0, line = start_row },
				["end"] = { character = 0, line = start_row },
			},
			range = {
				start = { character = 0, line = start_row },
				["end"] = { character = 0, line = start_row },
			},
		})
	end

	on_symbols(symbols, opts)
end

return M

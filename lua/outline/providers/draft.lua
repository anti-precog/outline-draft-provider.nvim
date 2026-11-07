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
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	local symbols = {}

	for i, line in ipairs(lines) do
		-- Dopasuj swój wzorzec linii (np. kluczowe słowa, zmienne, funkcje)
		local symbol_type, title = string.match(line, "^%s*([#<>])%s+(.+)$")

		if title then
			table.insert(symbols, {
				kind = 13, -- variable
				name = title,
				selectionRange = {
					start = { character = 1, line = i - 1 },
					["end"] = { character = 1, line = i - 1 },
				},
				range = {
					start = { character = 1, line = i - 1 },
					["end"] = { character = 1, line = i - 1 },
				},
			})
		end
	end

	on_symbols(symbols, opts)
end

return M

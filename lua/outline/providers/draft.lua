local M = {}

M.name = "draft"

-- Sprawdza, czy provider ma działać dla danego bufora
function M.supports_buffer(bufnr)
	return vim.bo[bufnr].filetype == "draft"
end

-- Opcjonalne: Status wyświetlany w :OutlineStatus
function M.get_status()
	return { "Draft Treesitter Provider Active" }
end

-- Główna funkcja zbierająca symbole
function M.request_symbols(callback, opts)
	opts = opts or {}
	local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()

	local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "draft")
	if not ok or not parser then
		callback({}, opts)
		return
	end

	local tree = parser:parse()[1]
	if not tree then
		callback({}, opts)
		return
	end

	local root = tree:root()

	local query_ok, query = pcall(vim.treesitter.query.get, "draft", "outline")
	if not query_ok or not query then
		callback({}, opts)
		return
	end

	local raw_symbols = {}

	-- Wykonaj zapytanie na drzewie AST
	for _, match, metadata in query:iter_matches(root, bufnr, 0, -1) do
		local name, range, is_group

		for id, nodes in pairs(match) do
			local capture_name = query.captures[id]
			if capture_name == "name" then
				local node = type(nodes) == "table" and nodes[1] or nodes
				name = vim.treesitter.get_node_text(node, bufnr)
			elseif capture_name == "definition.section" then
				local def_node = type(nodes) == "table" and nodes[1] or nodes
				local start_row, start_col, end_row, end_col = def_node:range()
				range = {
					start = { line = start_row, character = start_col },
					["end"] = { line = end_row, character = end_col },
				}
				is_group = false
			elseif capture_name == "definition.group" then
				local def_node = type(nodes) == "table" and nodes[1] or nodes
				local start_row, start_col, end_row, end_col = def_node:range()
				range = {
					start = { line = start_row, character = start_col },
					["end"] = { line = end_row, character = end_col },
				}
				is_group = true
			end
		end

		if name and range then
			table.insert(raw_symbols, {
				name = name,
				kind = is_group and 12 or 18, -- 18 = Section, 12 = Group
				selectionRange = range,
				range = range,
				children = {},
				is_group = is_group,
			})
		end
	end

	-- Funkcja pomocnicza: czy zakres sekcji zawiera zakres grupy
	local function contains(parent, child)
		local p_start = parent.range.start
		local p_end = parent.range["end"]
		local c_start = child.range.start
		local c_end = child.range["end"]

		local start_after = (c_start.line > p_start.line)
			or (c_start.line == p_start.line and c_start.character >= p_start.character)
		local end_before = (c_end.line < p_end.line)
			or (c_end.line == p_end.line and c_end.character <= p_end.character)

		return start_after and end_before
	end

	-- Budowanie hierarchii drzewa
	local tree_symbols = {}
	local sections = {}

	-- Krok 1: Wrzucamy najpierw wszystkie sekcje na najwyższy poziom
	for _, sym in ipairs(raw_symbols) do
		if not sym.is_group then
			table.insert(sections, sym)
			table.insert(tree_symbols, sym)
		end
	end

	-- Krok 2: Rozdzielamy grupy (do sekcji lub na główny poziom)
	for _, sym in ipairs(raw_symbols) do
		if sym.is_group then
			local placed = false
			for _, sec in ipairs(sections) do
				if contains(sec, sym) then
					table.insert(sec.children, sym)
					placed = true
					break
				end
			end
			-- Jeśli grupa nie znajduje się w żadnej sekcji, ląduje na samej górze drzewa
			if not placed then
				table.insert(tree_symbols, sym)
			end
		end
	end

	callback(tree_symbols, opts)
end

return M

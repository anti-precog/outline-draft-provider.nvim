local M = {}

M.name = "draft"

-- ============================================================================
-- 1. SPRAWDZANIE BUFORA (Supports Buffer)
-- ============================================================================

--- Sprawdza, czy dany bufor obsługuje ten provider.
---@param bufnr integer Numer bufora
---@return boolean, table?
function M.supports_buffer(bufnr)
	bufnr = bufnr ~= 0 and bufnr or vim.api.nvim_get_current_buf()

	local ft = vim.api.nvim_get_option_value("filetype", { buf = bufnr })
	if ft ~= "draft" then
		return false
	end

	local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "draft")
	if not ok or not parser then
		return false
	end

	return true, { parser = parser, ft = ft, buf = bufnr, lang = "draft" }
end

-- ============================================================================
-- 2. STATUS WTYCZKI (OutlineStatus)
-- ============================================================================

--- Zwraca informacje diagnostyczne dla `:OutlineStatus`.
---@param bufnr integer|table? Numer bufora
---@return string[]
function M.get_status(bufnr)
	if type(bufnr) ~= "number" or bufnr <= 0 then
		bufnr = vim.api.nvim_get_current_buf()
	end

	local ft = vim.api.nvim_get_option_value("filetype", { buf = bufnr })
	local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "draft")

	return {
		string.format("Draft Treesitter Provider Active (ft: %s)", ft),
		string.format("Treesitter Parser Loaded: %s", ok and "Yes (Ready)" or "No (Missing)"),
	}
end

-- ============================================================================
-- 3. FUNKCJE POMOCNICZE
-- ============================================================================

--- Sprawdza, czy zakres rodzica w pełni zawiera zakres dziecka.
local function contains(parent, child)
	local p_start = parent.range.start
	local p_end = parent.range["end"]
	local c_start = child.range.start
	local c_end = child.range["end"]

	-- Ignorujemy sytuację, gdy węzeł zawiera sam siebie
	if
		p_start.line == c_start.line
		and p_start.character == c_start.character
		and p_end.line == c_end.line
		and p_end.character == c_end.character
	then
		return false
	end

	local start_after = (c_start.line > p_start.line)
		or (c_start.line == p_start.line and c_start.character >= p_start.character)
	local end_before = (c_end.line < p_end.line) or (c_end.line == p_end.line and c_end.character <= p_end.character)

	return start_after and end_before
end

--- Formatuje tekst węzła do wyświetlenia w outline (np. przycina do 1 linii i max 50 znaków)
local function format_node_text(node, bufnr)
	local text = vim.treesitter.get_node_text(node, bufnr) or ""
	-- Bierzemy tylko pierwszą linię tekstu
	text = text:match("([^\r\n]*)") or text
	text = vim.trim(text)
	if #text > 50 then
		text = text:sub(1, 47) .. "..."
	end
	if text == "" then
		text = "[elem]"
	end
	return text
end

-- ============================================================================
-- 4. GŁÓWNA FUNKCJA ZBIERAJĄCA SYMBOLE
-- ============================================================================

--- Zbiera symbole i buduje z nich hierarchiczne drzewo.
---@param callback function
---@param opts table
---@param info table?
function M.request_symbols(callback, opts, info)
	opts = opts or {}
	info = info or {}
	local bufnr = opts.bufnr or info.buf or vim.api.nvim_get_current_buf()

	local parser = info.parser or opts.parser
	if not parser then
		local ok, p = pcall(vim.treesitter.get_parser, bufnr, "draft")
		if not ok or not p then
			callback({}, opts)
			return
		end
		parser = p
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

	-- Iteracja po dopasowaniach zapytania Treesittera
	for _, match, _ in query:iter_matches(root, bufnr, 0, -1) do
		local name, range, kind, is_container = nil, nil, 13, false

		for id, nodes in pairs(match) do
			local capture_name = query.captures[id]
			local node = type(nodes) == "table" and nodes[1] or nodes

			local start_row, start_col, end_row, end_col = node:range()
			range = {
				start = { line = start_row, character = start_col },
				["end"] = { line = end_row, character = end_col },
			}

			if capture_name == "definition.section" then
				kind = 18 -- 18 = Section
				is_container = true
			elseif capture_name == "definition.group" then
				kind = 12 -- 12 = Group/Folder
				is_container = true
			elseif capture_name == "definition.narration" then
				kind = 13 -- Variable / Narration
				name = format_node_text(node, bufnr)
			elseif capture_name == "definition.quotation" then
				kind = 15 -- String / Quotation
				name = format_node_text(node, bufnr)
			elseif capture_name == "definition.dialog" then
				kind = 1 -- Text / Dialog
				name = format_node_text(node, bufnr)
			elseif capture_name == "definition.comment" then
				kind = 1 -- Comment
				name = format_node_text(node, bufnr)
			elseif capture_name == "definition.header" then
				kind = 12 -- Header w grupie
				name = "Header: " .. format_node_text(node, bufnr)
			elseif capture_name == "definition.footer" then
				kind = 12 -- Footer w grupie
				name = "Footer: " .. format_node_text(node, bufnr)
			elseif capture_name == "name" then
				-- Dla sekcji lub grupy pobieramy tekst tytułu/nagłówka
				name = format_node_text(node, bufnr)
			end
		end

		if name and range then
			table.insert(raw_symbols, {
				name = name,
				kind = kind,
				selectionRange = range,
				range = range,
				children = {},
				is_container = is_container,
			})
		end
	end

	-- Sortujemy symbole od największych do najmniejszych zakresów,
	-- dzięki czemu kontenery (sekcje/grupy) procesujemy przed ich dziećmi.
	table.sort(raw_symbols, function(a, b)
		local span_a = (a.range["end"].line - a.range.start.line) * 1000
			+ (a.range["end"].character - a.range.start.character)
		local span_b = (b.range["end"].line - b.range.start.line) * 1000
			+ (b.range["end"].character - b.range.start.character)
		return span_a > span_b
	end)

	-- Automatyczne budowanie hierarchii drzewa na podstawie zakresów
	local tree_symbols = {}
	for _, sym in ipairs(raw_symbols) do
		local function insert_into(list)
			for _, parent in ipairs(list) do
				if parent.is_container and contains(parent, sym) then
					if #parent.children > 0 then
						if insert_into(parent.children) then
							return true
						end
					end
					table.insert(parent.children, sym)
					return true
				end
			end
			return false
		end

		if not insert_into(tree_symbols) then
			table.insert(tree_symbols, sym)
		end
	end

	-- Czyszczenie flag wewnętrznych przed zwrotem danych
	local function cleanup(nodes)
		for _, n in ipairs(nodes) do
			n.is_container = nil
			if #n.children > 0 then
				cleanup(n.children)
			end
		end
	end
	cleanup(tree_symbols)

	callback(tree_symbols, opts)
end

return M

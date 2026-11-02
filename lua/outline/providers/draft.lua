local M = {}

M.name = "draft"

-- ============================================================================
-- 1. SPRAWDZANIE BUFORA (Supports Buffer)
-- ============================================================================

--- Sprawdza, czy dany bufor obsługuje ten provider.
--- Jeśli tak, zwraca `true` oraz wstępnie przygotowany kontekst (parser, ft, buf).
---@param bufnr integer Numer bufora
---@return boolean, table?
function M.supports_buffer(bufnr)
	bufnr = bufnr ~= 0 and bufnr or vim.api.nvim_get_current_buf()

	-- Sprawdzamy, czy typ pliku (filetype) to faktycznie "draft"
	local ft = vim.api.nvim_get_option_value("filetype", { buf = bufnr })
	if ft ~= "draft" then
		return false
	end

	-- Próbujemy pobrać parser Treesittera dla języka "draft"
	local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "draft")
	if not ok or not parser then
		return false
	end

	-- Zwracamy sukces oraz cache'ujemy parser w kontekście,
	-- aby uniknąć ponownego wyszukiwania go w `request_symbols`.
	return true, { parser = parser, ft = ft, buf = bufnr, lang = "draft" }
end

-- ============================================================================
-- 2. STATUS WTYCZKI (OutlineStatus)
-- ============================================================================

--- Zwraca informacje diagnostyczne wyświetlane pod poleceniem `:OutlineStatus`.
---@param bufnr integer|table? Numer bufora lub tabela przekazana przez wtyczkę
---@return string[]
function M.get_status(bufnr)
	-- Jeśli bufnr jest tabelą (np. Neovim przekazał coś innego) lub jest nil/0, bierzemy aktualny bufor
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
-- 3. FUNKCJA POMOCNICZA: SPRAWDZANIE ZAGNIĘŻENIA
-- ============================================================================

--- Sprawdza, czy zakres rodzica (sekcji) w pełni zawiera zakres dziecka (grupy).
---@param parent table Obiekt symbolu nadrzędnego
---@param child table Obiekt symbolu podrzędnego
---@return boolean
local function contains(parent, child)
	local p_start = parent.range.start
	local p_end = parent.range["end"]
	local c_start = child.range.start
	local c_end = child.range["end"]

	-- Określenie, czy początek dziecka wypada po lub w tym samym miejscu co początek rodzica
	local start_after = (c_start.line > p_start.line)
		or (c_start.line == p_start.line and c_start.character >= p_start.character)

	-- Określenie, czy koniec dziecka wypada przed lub w tym samym miejscu co koniec rodzica
	local end_before = (c_end.line < p_end.line) or (c_end.line == p_end.line and c_end.character <= p_end.character)

	return start_after and end_before
end

-- ============================================================================
-- 4. GŁÓWNA FUNKCJA ZBIERAJĄCA SYMBOLE
-- ============================================================================

--- Główna funkcja parsująca drzewo AST i budująca hierarchię konspektu.
---@param callback function Funkcja zwrotna przyjmująca gotową listę symboli i opcje
---@param opts table Tabela opcji
---@param info table? Kontekst przekazany opcjonalnie z `supports_buffer`
function M.request_symbols(callback, opts, info)
	opts = opts or {}
	info = info or {}
	local bufnr = opts.bufnr or info.buf or vim.api.nvim_get_current_buf()

	-- KROK 4.1: Pobranie parsera (z cache'a przekazanego przez info/opts lub jako fallback)
	local parser = info.parser or opts.parser
	if not parser then
		local ok, p = pcall(vim.treesitter.get_parser, bufnr, "draft")
		if not ok or not p then
			callback({}, opts)
			return
		end
		parser = p
	end

	-- KROK 4.2: Parsowanie drzewa składniowego (AST)
	local tree = parser:parse()[1]
	if not tree then
		callback({}, opts)
		return
	end
	local root = tree:root()

	-- KROK 4.3: Pobranie zapytania Treesittera (.scm query o nazwie "outline")
	local query_ok, query = pcall(vim.treesitter.query.get, "draft", "outline")
	if not query_ok or not query then
		callback({}, opts)
		return
	end

	local raw_symbols = {}

	-- KROK 4.4: Iteracja po dopasowaniach zapytania Treesittera w dokumencie
	for _, match, _ in query:iter_matches(root, bufnr, 0, -1) do
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

		-- Jeśli zebraliśmy nazwę oraz zakres, dodajemy symbol do płaskiej listy
		if name and range then
			table.insert(raw_symbols, {
				name = name,
				kind = is_group and 12 or 18, -- 18 = Section (LSP), 12 = Group/Folder (LSP)
				selectionRange = range,
				range = range,
				children = {},
				is_group = is_group, -- Flaga pomocnicza do budowania drzewa
			})
		end
	end

	-- KROK 4.5: Budowanie hierarchicznej struktury drzewa (rodzic -> dziecko)
	local tree_symbols = {}
	local sections = {}

	-- Faza 1: Umieszczamy wszystkie sekcje na najwyższym poziomie drzewa
	for _, sym in ipairs(raw_symbols) do
		if not sym.is_group then
			table.insert(sections, sym)
			table.insert(tree_symbols, sym)
		end
	end

	-- Faza 2: Rozdzielamy grupy – dopasowujemy je do sekcji lub wyrzucamy na główny poziom
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
			-- Jeśli grupa nie mieści się w żadnej sekcji, ląduje bezpośrednio w korzeniu
			if not placed then
				table.insert(tree_symbols, sym)
			end
		end
	end

	-- Faza 3: Czyszczenie flag wewnętrznych przed zwrotem danych (opcjonalnie, dla porządku)
	for _, sym in ipairs(tree_symbols) do
		sym.is_group = nil
		for _, child in ipairs(sym.children) do
			child.is_group = nil
		end
	end

	-- KROK 4.6: Zwrócenie gotowego drzewa symboli przez funkcję zwrotną
	callback(tree_symbols, opts)
end

return M

-- The menu. Everything the desktop can be asked to do, one keystroke in.
--
--   type        search every row, wherever it sits
--   Up/Down     move
--   Return      open a submenu, or do the thing
--   Left/Esc    back a level, and close at the top
--
-- Two lists behind one window: the rows of wherever you are while the query
-- is empty, and every row there is once it is not. That is what lib/picker.lua
-- calls a source, and the whole difference between this and a dmenu.
--
-- The tree is lists/menu.lua, and a person is meant to edit it.
-- Nothing here knows what a row means: it runs the command the row names, or
-- sends the word the row names up the kippsrv socket.

local picker  = require("lib.picker")
local kipp    = require("lib.kipp")
local palette = require("lib.palette")
local config  = require("lib.settings")

local HOME = os.getenv("HOME") or ""
local TREE = HOME .. "/.config/tildesh-shell/lists/menu.lua"

local COLS, ROWS = 46, 12

local function load_tree()
	local chunk, why = loadfile(TREE)
	local ok, t = pcall(chunk or function() return nil end)

	-- A tree that will not load is a menu with nothing in it, which looks
	-- exactly like a menu nobody wrote. Say which it is.
	if not chunk then
		io.stderr:write("menu: ", tostring(why), "\n")
	elseif not ok then
		io.stderr:write("menu: ", TREE, ": ", tostring(t), "\n")
	end
	return (ok and type(t) == "table") and t or {}
end

local tree = load_tree()

-- Every `when` and `checked` in one shell rather than one each. A menu that
-- forks twenty times before it draws is a menu you watch open.
local function guards()
	local out, asked = {}, {}

	for _, row in ipairs(tree) do
		for _, kind in ipairs({"when", "checked"}) do
			if row[kind] then
				asked[#asked + 1] =
					("printf '%s\\t%s\\t'; { %s ; } >/dev/null 2>&1 && echo 1 || echo 0")
					:format(kind, row.id, row[kind])
			end
		end
	end
	if #asked == 0 then return out end

	for line in Surface.sh(table.concat(asked, "\n"), 5000):gmatch("[^\n]+") do
		local kind, id, yes = line:match("^(%a+)\t(%S+)\t([01])$")
		if kind then out[kind .. " " .. id] = yes == "1" end
	end
	return out
end

local told = guards()

local function shown(row)
	return row.when == nil or told["when " .. row.id] == true
end

local function ticked(row)
	return row.checked ~= nil and told["checked " .. row.id] == true
end

local function parent_of(id)
	return id:match("^(.*)%.[^.]+$") or ""
end

local label_of = {}
for _, row in ipairs(tree) do label_of[row.id] = row.label end

-- Style › Theme, for a row found by searching rather than by walking to it.
local function trail(id)
	local out, at = {}, parent_of(id)
	while at ~= "" do
		table.insert(out, 1, label_of[at] or at)
		at = parent_of(at)
	end
	return table.concat(out, " › ")
end

local function has_children(id)
	for _, row in ipairs(tree) do
		if parent_of(row.id) == id then return true end
	end
	return false
end

local menu = {at = ""}          -- which submenu is open, "" for the root

local function draw_row(row, note)
	return {
		text  = ("%s  %s"):format(row.icon or " ", row.label),
		note  = note,
		value = row,
	}
end

-- What is in front of you.
local function here()
	local out = {}
	for _, row in ipairs(tree) do
		if parent_of(row.id) == menu.at and shown(row) then
			out[#out + 1] = draw_row(row, ticked(row) and "✓"
			                              or (has_children(row.id) and "›" or ""))
		end
	end
	return out
end

-- Everything that does something, wherever it sits. A submenu is not here:
-- searching for a place to go is walking, and walking is what the other list
-- is for.
local function every()
	local out = {}
	for _, row in ipairs(tree) do
		if shown(row) and not has_children(row.id) then
			out[#out + 1] = draw_row(row, trail(row.id))
		end
	end
	return out
end

local list = picker.new{
	prompt  = "Menu",
	rows    = ROWS,
	sources = {
		{name = "here",   live = function(q) return q == "" end, rows = here},
		{name = "search", live = function(q) return q ~= "" end, rows = every},
	},

	pick = function(row, self)
		local it = row.value

		if has_children(it.id) then
			menu.at = it.id
			self.prompt = it.label
			self.sel, self.top = 1, 1
			self:refresh()
			return
		end

		if it.kipp then
			kipp.send(it.kipp)
		elseif it.action then
			Surface.spawn(it.action)
		end
		Surface.close(0)
	end,

	key = function(k, self)
		if k ~= "Escape" and k ~= "Left" then return false end

		-- Escape gives back the query first, then the level, then the window.
		if self.query ~= "" then
			self:clear()
		elseif menu.at ~= "" then
			menu.at = parent_of(menu.at)
			self.prompt = menu.at == "" and "Menu" or (label_of[menu.at] or "Menu")
			self.sel, self.top = 1, 1
			self:refresh()
		else
			Surface.close(1)
		end
		return true
	end,
}
list.empty = "Nothing here"

local cfg = config.load()
Surface.font(cfg.font, cfg.size)
Surface.border("round", list.style.title)
Surface.layer("overlay")
Surface.anchor("center")
Surface.window(COLS, ROWS + 1)
Surface.listen("theme")
Surface.run(list)

-- Templates.
--
-- A template is a config file for some application with `{{ token }}` where a
-- colour goes. The token forms are omarchy's, so its templates render here
-- unchanged, which is the whole point of keeping them.
--
--   {{ accent }}                     a key from the palette
--   {{ accent_strip }}               without the leading #
--   {{ accent_rgb }}                 30,30,46
--   {{ mix background accent 30 }}   and _strip and _rgb
--   {{ hypr_gradient border accent }}   a wlroots border, one colour or many
--   {{ shell_gradient border accent }}  the same, space separated
--   {{ gradient_start border accent }}  its first colour
--
-- A token naming something the palette does not hold is left alone. A raw
-- {{ }} in a rendered file says which key is missing and where.

local colors  = require("lib.theme.colors")

local M = {}

local function decorate(value, how)
	if how == "strip" then return (value:gsub("^#", "")) end
	if how == "rgb" then return colors.rgb(value) end
	return value
end

-- A reference is a palette key, or a fallback key, or the fallback itself.
local function ref(t, name, fallback)
	if t[name] then return t[name] end
	if fallback then return t[fallback] or fallback end
	return name
end

-- "#1e1e2e", "rgba(1e1e2eff)", "rgb(30,30,46)" and "0xff1e1e2e" all mean one
-- colour. Anything that draws wants the same six digits.
local function as_hex(c)
	local six = c:match("^#(%x%x%x%x%x%x)%x?%x?$")
	          or c:match("^[Rr][Gg][Bb][Aa]?%((%x%x%x%x%x%x)%x?%x?%)$")
	if six then return "#" .. six end

	local r, g, b = c:match("^[Rr][Gg][Bb][Aa]?%((%d+),(%d+),(%d+),?[%d.]*%)$")
	if r then
		return ("#%02x%02x%02x"):format(math.min(255, r), math.min(255, g),
		                                math.min(255, b))
	end

	local argb = c:match("^0x%x%x(%x%x%x%x%x%x)$")
	return argb and "#" .. argb or c
end

-- A gradient is colours and an optional angle, in any order.
local function gradient(t, spec)
	local list, angle = {}, nil
	for word in spec:gmatch("%S+") do
		if word:match("^%-?%d+%.?%d*deg$") then
			angle = word:gsub("deg$", "")
		else
			list[#list + 1] = t[word] or word
		end
	end
	return list, angle
end

local function hypr_gradient(t, spec)
	local list, angle = gradient(t, spec)
	if #list < 2 then return ('"%s"'):format(list[1] or spec) end

	local out = "{ colors = {"
	for i, c in ipairs(list) do
		out = out .. (i > 1 and "," or "") .. (' "%s"'):format(c)
	end
	out = out .. " }"
	if angle then out = out .. (", angle = %s"):format(angle) end
	return out .. " }"
end

local function shell_gradient(t, spec)
	local list, angle = gradient(t, spec)
	if #list == 0 then return spec end
	local out = table.concat(list, " ")
	return angle and out .. " " .. angle .. "deg" or out
end

-- One token, or nil to leave it as it was written.
local function value(t, token)
	local word = {}
	for w in token:gmatch("%S+") do word[#word + 1] = w end
	local head = word[1]
	if not head then return nil end

	if #word == 1 then
		if t[head] then return t[head] end
		local base, how = head:match("^(.+)_(strip)$")
		if not base then base, how = head:match("^(.+)_(rgb)$") end
		return t[base] and decorate(t[base], how) or nil
	end

	local fn, how = head:match("^(mix)_(strip)$")
	if not fn then fn, how = head:match("^(mix)_(rgb)$") end
	if head == "mix" or fn then
		local from, to = t[word[2]], t[word[3]]
		if not from or not to then return nil end
		return decorate(colors.mix(from, to, word[4]), how)
	end

	local spec = ref(t, word[2], word[3])
	if head == "hypr_gradient"  then return hypr_gradient(t, spec) end
	if head == "shell_gradient" then return shell_gradient(t, spec) end
	if head == "gradient_start" then
		local list = gradient(t, spec)
		return as_hex(list[1] or spec)
	end
	return nil
end

function M.text(t, template)
	return (template:gsub("{{%s*(.-)%s*}}", function(token)
		return value(t, token)
	end))
end

function M.file(t, from, to)
	local src = io.open(from)
	if not src then return false end
	local body = src:read("a")
	src:close()

	local dst = io.open(to, "w")
	if not dst then return false end
	dst:write(M.text(t, body))
	dst:close()
	return true
end

return M

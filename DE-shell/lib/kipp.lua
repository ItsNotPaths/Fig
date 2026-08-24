-- Facts off the kippsrv socket.
--
-- A consumer connects, is sent every fact that is currently true, then one
-- `sync state` line, then every change for as long as it stays connected. So
-- a surface needs somewhere to keep what it has been told, and that is the
-- same job in every surface. It lives here once.
--
--   local kipp = require("lib.kipp")
--   local facts = kipp.store()
--   Surface.listen(kipp.socket)
--   -- onMessage(line): facts:feed(line)
--
-- Nothing here knows what a tag or a battery is. A surface asks for the kinds
-- it draws and skips the rest, which is why a new fact costs no consumer
-- anything.

local M = {}

M.socket = (os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/kippsrv.sock"

-- Field one is the kind. The fields after it are subject until one holds an
-- '=', and everything from there is an attribute. SPEC.md, and no more.
function M.parse(line)
	local kind, subj, attr, in_attr = nil, {}, {}, false

	for field in line:gmatch("[^\t]+") do
		if not kind then
			if field:sub(1, 1) ~= "@" then kind = field end
		else
			local key, value = field:match("^([^=]+)=(.*)$")
			if key then
				in_attr = true
				attr[key] = value
			elseif not in_attr then
				subj[#subj + 1] = field
			end
		end
	end

	if not kind then return nil end
	return kind, subj, attr
end

local Store = {}
Store.__index = Store

local function key_of(kind, subj)
	return kind .. "\t" .. table.concat(subj, "\t")
end

-- Kinds that are about the connection rather than the desktop. A surface
-- never sees them.
local PROTOCOL = {version = true, sync = true, error = true}

-- One line in. Returns the kind it changed, so a surface can decide whether
-- the line was worth a redraw, or nil for a line it does not have to care
-- about.
function Store:feed(line)
	local kind, subj, attr = M.parse(line)
	if not kind then return nil end

	if kind == "sync" then
		self.synced = true
		return nil
	end
	if PROTOCOL[kind] then return nil end

	-- Retraction and doubt are not the same thing. A dropped fact is gone; a
	-- stale one is the last thing anybody knew, and a surface may want to
	-- show it greyed rather than pretend it never existed.
	if kind == "drop" or kind == "stale" then
		local of = table.remove(subj, 1)
		if not of then return nil end
		local key = key_of(of, subj)
		if kind == "drop" then
			self.facts[key] = nil
		elseif self.facts[key] then
			self.facts[key].stale = true
		end
		return of
	end

	local key = key_of(kind, subj)
	if not self.facts[key] then
		self.order[#self.order + 1] = key
	end
	self.facts[key] = {kind = kind, subj = subj, attr = attr, stale = false}
	return kind
end

-- Every fact of a kind, in the order they were first seen, which is the order
-- the publisher sent them and so the order worth drawing them in.
function Store:each(kind)
	local i = 0
	return function()
		while true do
			i = i + 1
			local key = self.order[i]
			if not key then return nil end
			local fact = self.facts[key]
			if fact and fact.kind == kind then return fact end
		end
	end
end

-- One fact by its subject: facts:get("tags", "eDP-1")
function Store:get(kind, ...)
	return self.facts[key_of(kind, {...})]
end

function M.store()
	return setmetatable({facts = {}, order = {}, synced = false}, Store)
end

-- A command back, which is uppercase and goes up the same socket. Lua has no
-- sockets and wweft's listen only reads, so this is the one place that shells
-- out. A publisher whose channel is a FIFO can be written with io.open
-- instead, and should be.
function M.send(command)
	local cmd = ("printf '%s\\n' | socat -t0 - UNIX-CONNECT:%s 2>/dev/null &")
	            :format(command:gsub("'", ""), M.socket)
	if Surface and Surface.spawn then Surface.spawn(cmd) else os.execute(cmd) end
end

return M

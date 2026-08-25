-- weather-fetch prints kipp already, so this file splits a line and hands the
-- fields to k.emit. It exists because kippsrv wants an adapter for each
-- source, not because the format needs one. The same is true of wm/hedl.lua,
-- and for the same reason: the source got the format right.
--
-- It lives beside kippsrv.lua rather than in /usr/share/kippsrv/lua, because
-- the weather is ours and that directory is kippsrv's.
return {
	feed = function(line)
		local f = {}
		for field in line:gmatch("[^\t]+") do f[#f + 1] = field end
		if #f < 2 then return end
		k.emit(table.remove(f, 1), table.unpack(f))
	end,
}

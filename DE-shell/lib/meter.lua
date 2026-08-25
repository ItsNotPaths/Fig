-- A bar for a share of something, drawn in eighths.
--
-- One cell is eight steps rather than one, so a ten cell bar answers a key
-- press instead of looking broken until the fourth.

local M = {}

local PARTS = {"▏", "▎", "▍", "▌", "▋", "▊", "▉"}
local SOLID = "█"

-- share is 0 to 1.
function M.draw(g, x, y, w, share, trough, fill)
	g.fill(x, y, w, 1, trough)
	local units = math.round(math.max(0, math.min(1, share)) * w * 8)
	for i = 0, w - 1 do
		local take = math.max(0, math.min(8, units - i * 8))
		if take == 8 then
			g.text(x + i, y, SOLID, fill)
		elseif take > 0 then
			g.text(x + i, y, PARTS[take], fill)
		end
	end
end

return M

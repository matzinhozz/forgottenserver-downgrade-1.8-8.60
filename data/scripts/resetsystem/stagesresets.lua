ResetStages = {}
ResetStages._stages = {}

local function loadStagesResets()
	local filePath = CORE_DIRECTORY .. "/XML/stagesresets.xml"
	local f = io.open(filePath, "r")
	if not f then
		print("[ResetStages] WARNING: stagesresets.xml not found at " .. filePath)
		return
	end

	local content = f:read("*all")
	f:close()

	for attrs in content:gmatch("<stage%s+(.-)%s*/>") do
		local minreset  = tonumber(attrs:match('minreset%s*=%s*"(%d+)"'))
		local maxreset  = tonumber(attrs:match('maxreset%s*=%s*"(%d+)"'))
		local mult      = tonumber(attrs:match('multiplier%s*=%s*"([%d%.]+)"'))

		if minreset and maxreset ~= nil and mult then
			table.insert(ResetStages._stages, {
				minReset   = minreset,
				maxReset   = maxreset,
				multiplier = mult,
			})
		end
	end

	if #ResetStages._stages == 0 then
		print("[ResetStages] WARNING: No stages loaded from stagesresets.xml.")
	else
		print("[ResetStages] " .. #ResetStages._stages .. " reset stage(s) loaded.")
	end
end

function ResetStages.getMultiplier(resetCount)
	for _, stage in ipairs(ResetStages._stages) do
		if resetCount >= stage.minReset and (stage.maxReset == 0 or resetCount <= stage.maxReset) then
			return stage.multiplier
		end
	end
	return 1.0
end

loadStagesResets()

ResetLevelTable = {
	useFormula = true,

	formula = {
		baseLevel     = 65000,
		levelPerReset = 5000,
	},

	table = {
		{ minReset =   0, maxReset =   4, levelVIP =  9428, levelFree = 10000 },
		{ minReset =   5, maxReset =   9, levelVIP =  9714, levelFree = 10142 },
		{ minReset =  10, maxReset =  14, levelVIP = 10142, levelFree = 10285 },
		{ minReset =  15, maxReset =  19, levelVIP = 10285, levelFree = 10428 },
		{ minReset =  20, maxReset =  24, levelVIP = 10571, levelFree = 10857 },
		{ minReset =  25, maxReset =  29, levelVIP = 10857, levelFree = 11142 },
		{ minReset =  30, maxReset =  34, levelVIP = 11428, levelFree = 11714 },
		{ minReset =  35, maxReset =  39, levelVIP = 12000, levelFree = 12285 },
		{ minReset =  40, maxReset =  44, levelVIP = 12571, levelFree = 12857 },
		{ minReset =  45, maxReset =  49, levelVIP = 13428, levelFree = 13714 },
		{ minReset =  50, maxReset =  54, levelVIP = 14285, levelFree = 14571 },
		{ minReset =  55, maxReset =  59, levelVIP = 15428, levelFree = 15714 },
		{ minReset =  60, maxReset =  64, levelVIP = 16571, levelFree = 16857 },
		{ minReset =  65, maxReset =  69, levelVIP = 17714, levelFree = 18000 },
		{ minReset =  70, maxReset =  74, levelVIP = 19142, levelFree = 19428 },
		{ minReset =  75, maxReset =  79, levelVIP = 20571, levelFree = 20857 },
		{ minReset =  80, maxReset =  84, levelVIP = 22000, levelFree = 22285 },
		{ minReset =  85, maxReset =  89, levelVIP = 24000, levelFree = 24571 },
		{ minReset =  90, maxReset =  94, levelVIP = 26000, levelFree = 26571 },
		{ minReset =  95, maxReset =  99, levelVIP = 28285, levelFree = 28857 },
		{ minReset = 100, maxReset = 104, levelVIP = 31142, levelFree = 32285 },
		{ minReset = 105, maxReset = 109, levelVIP = 34000, levelFree = 35142 },
		{ minReset = 110, maxReset = 114, levelVIP = 36857, levelFree = 38000 },
		{ minReset = 115, maxReset = 119, levelVIP = 42571, levelFree = 43714 },
		{ minReset = 120, maxReset = 129, levelVIP = 48285, levelFree = 49428 },
		{ minReset = 130, maxReset = 139, levelVIP = 54000, levelFree = 56857 },
		{ minReset = 140, maxReset = 149, levelVIP = 60000, levelFree = 62857 },
		{ minReset = 150, maxReset = 160, levelVIP = 65000, levelFree = 70000 },
		{ minReset = 161, maxReset = 165, levelVIP = 70428, levelFree = 77142 },
		{ minReset = 166, maxReset = 175, levelVIP = 76428, levelFree = 80000 },
		{ minReset = 176, maxReset = 185, levelVIP = 82428, levelFree = 84285 },
		{ minReset = 186, maxReset = 190, levelVIP = 84285, levelFree = 85714 },
		{ minReset = 191, maxReset = 210, levelVIP = 85742, levelFree = 85742 },
		{ minReset = 211, maxReset = 220, levelVIP = 88571, levelFree = 90000 },
		{ minReset = 221, maxReset = 999, levelVIP = 90000, levelFree = 92857 },
	},
}

function ResetLevelTable.getRequiredLevel(currentResets, isVip)
	if ResetLevelTable.useFormula then
		return ResetLevelTable.formula.baseLevel + (ResetLevelTable.formula.levelPerReset * currentResets)
	end

	for _, entry in ipairs(ResetLevelTable.table) do
		if currentResets >= entry.minReset and currentResets <= entry.maxReset then
			return isVip and entry.levelVIP or entry.levelFree
		end
	end
	local last = ResetLevelTable.table[#ResetLevelTable.table]
	return isVip and last.levelVIP or last.levelFree
end

local proficiency = TalkAction("!proficiency")

function proficiency.onSay(player, words, param)
	if not configManager.getBoolean(configKeys.WEAPON_PROFICIENCY_ENABLED) then
		player:sendCancelMessage("Weapon Proficiency system is disabled.")
		return false
	end

	local info = Proficiency.getDisplayInfo(player)
	if not info then return false end

	param = param:trim():lower()
	local unlocked = Proficiency.getUnlockedLevelCount(info.item, info.experience)
	local maxLevel = #(info.profile.Levels or {})
	local itemName = info.item:getName()
	local currentLevel = Proficiency.getCurrentLevelByExp(info.item, info.experience)
	local nextLevelExp = Proficiency.getNextLevelExperience(info.experience, info.item)
	local isMastered = info.experience >= Proficiency.getMaxExperience(info.profile, info.item)

	if param == "info" or param == "" then
		local msg = string.format("Weapon: %s\n", itemName)
		msg = msg .. string.format("Experience: %d\n", info.experience)

		if isMastered then
			msg = msg .. "Status: Mastery achieved!\n"
		else
			local remaining = nextLevelExp - info.experience
			msg = msg .. string.format("Next level XP: %d (remaining: %d)\n", nextLevelExp, remaining)
			msg = msg .. string.format("Level: %d/%d\n", currentLevel, maxLevel)
		end

		msg = msg .. "\nApplied Perks:\n"
		local hasPerks = false
		for i = 0, maxLevel - 1 do
			local perkIndex = info.perks[i + 1]
			if perkIndex ~= nil then
				hasPerks = true
				local perkData = Proficiency.getPerkInfo(info.profile, i, perkIndex)
				if perkData then
					msg = msg .. string.format("  * Slot %d: %s (%s: %.2f)\n",
						i, Proficiency.getPerkName(perkData),
						perkData.Type ~= nil and type(perkData.Value) == "number" and "value" or "val",
						perkData.Value or 0)
				else
					msg = msg .. string.format("  * Slot %d: Unknown (index %d)\n", i, perkIndex)
				end
			end
		end
		if not hasPerks then
			msg = msg .. "  (no perks applied)\n"
		end
		player:popupFYI(msg)

	elseif param == "slot" then
		local msg = string.format("Weapon: %s\n\n", itemName)
		if isMastered then
			msg = msg .. "Mastery: ACHIEVED\n\n"
		else
			if nextLevelExp > 0 then
				msg = msg .. string.format("Progress: %d XP to next perk\n\n", nextLevelExp - info.experience)
			end
		end

		for i = 0, maxLevel - 1 do
			local levelData = info.profile.Levels[i + 1]
			local isUnlocked = i < unlocked
			local selectedIndex = info.perks[i + 1]
			local status = isUnlocked and "[UNLOCKED]" or "[LOCKED]"
			msg = msg .. string.format("Slot %d: %s\n", i, status)

			if levelData and levelData.Perks then
				for j, perk in ipairs(levelData.Perks) do
					local isSelected = isUnlocked and ((j - 1) == selectedIndex)
					local marker = isSelected and " *" or ""
					local lockInfo = not isUnlocked and " [LOCKED]" or ""
					msg = msg .. string.format("  - %s%s%s\n",
						Proficiency.getPerkName(perk), marker, lockInfo)
				end
			else
				msg = msg .. "  (no perks available)\n"
			end
			msg = msg .. "\n"
		end
		player:popupFYI(msg)

	else
		player:sendCancelMessage("Usage: !proficiency info or !proficiency slot")
	end
	return false
end

proficiency:separator(" ")
proficiency:register()

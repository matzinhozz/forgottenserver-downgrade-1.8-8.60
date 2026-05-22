-- Weapon Proficiency System Library
Proficiency = Proficiency or {}

-- Network send helpers (use NetworkMessage + sendToPlayer)
local function sendWeaponProficiency(player, itemId, experience, perkLevels)
	local msg = NetworkMessage()
	msg:addByte(0xE8)
	msg:addU16(itemId)
	msg:addU32(experience)
	msg:addByte(#perkLevels)
	for _, level in ipairs(perkLevels) do
		msg:addByte(level)
	end
	msg:sendToPlayer(player)
end

local function sendProficiencyNotification(player, itemId, experience, hasUnnusedPerk)
	local msg = NetworkMessage()
	msg:addByte(0xE9)
	msg:addU16(itemId)
	msg:addU32(experience)
	msg:addByte(hasUnnusedPerk and 1 or 0)
	msg:sendToPlayer(player)
end

Proficiency.ExperienceTable = {
	{ regular = 600,    knight = 600,    crossbow = 600 },
	{ regular = 8000,   knight = 8000,   crossbow = 8000 },
	{ regular = 30000,  knight = 30000,  crossbow = 30000 },
	{ regular = 150000, knight = 150000, crossbow = 150000 },
	{ regular = 650000, knight = 650000, crossbow = 650000 },
}

Proficiency.Profiles = {}
Proficiency.WeaponTypeToProfile = {
	[WEAPON_SWORD] = 1,
	[WEAPON_AXE] = 2,
	[WEAPON_CLUB] = 3,
	[WEAPON_DISTANCE] = 4,
	[WEAPON_WAND] = 5,
}

Proficiency.PerkNames = {
	[0]  = "Attack Damage",
	[1]  = "Defense Bonus",
	[3]  = "Skill Bonus",
	[4]  = "Specialized Magic",
	[5]  = "Spell Augment",
	[7]  = "Powerful Foe Bonus",
	[8]  = "Critical Hit Chance",
	[12] = "Critical Extra Damage",
	[13] = "Elemental Critical Damage",
	[16] = "Mana Leech",
	[17] = "Life Leech",
	[18] = "Mana Gain on Hit",
	[19] = "Life Gain on Hit",
	[20] = "Mana Gain on Kill",
	[21] = "Life Gain on Kill",
	[22] = "Perfect Shot Damage",
	[25] = "Skill Percent Auto Attack",
	[26] = "Skill Percent Spell Damage",
	[27] = "Skill Percent Spell Healing",
}

function Proficiency.loadJson()
	local file = io.open("data/items/proficiencies.json", "r")
	if not file then
		print("[Warning - Proficiency] Could not load proficiencies.json")
		return
	end
	local content = file:read("*a")
	file:close()

	local status, result = pcall(function() return json.decode(content) end)
	if not status then
		print("[Error - Proficiency] Failed to parse proficiencies.json: " .. result)
		return
	end

	Proficiency.Profiles = {}
	for _, data in ipairs(result) do
		Proficiency.Profiles[data.ProficiencyId] = data
	end
	print("[Proficiency] Loaded " .. #result .. " weapon proficiency profiles.")
end

function Proficiency.getProfile(id)
	return Proficiency.Profiles[id] or Proficiency.Profiles[Proficiency.WeaponTypeToProfile[id]] or nil
end

function Proficiency.getProfileForItem(item)
	if not item then return nil end
	local itemType = ItemType(item:getId())
	local profId = itemType:getProficiencyId()
	if profId and profId > 0 then
		return Proficiency.Profiles[profId]
	end
	-- fallback: map by weapon type
	local weaponType = itemType:getWeaponType()
	local defaultId = Proficiency.WeaponTypeToProfile[weaponType]
	return defaultId and Proficiency.Profiles[defaultId] or nil
end

function Proficiency.getWeaponProfessionType(item)
	if not item then return "regular" end
	local itemType = ItemType(item:getId())
	local weaponType = itemType:getWeaponType()
	if weaponType == WEAPON_DISTANCE then
		local ammoType = itemType:getAmmoType()
		if ammoType == AMMO_BOLT then
			return "crossbow"
		end
		return "regular"
	elseif weaponType == WEAPON_SWORD or weaponType == WEAPON_AXE or weaponType == WEAPON_CLUB then
		return "regular"
	end
	return "regular"
end

function Proficiency.getMaxExperience(profile, item)
	if not profile then return 0 end
	local vocationType = Proficiency.getWeaponProfessionType(item)
	local levels = #(profile.Levels or {})
	if levels == 0 then return 0 end
	local lastStage = Proficiency.ExperienceTable[levels + 2] or Proficiency.ExperienceTable[#Proficiency.ExperienceTable]
	return lastStage[vocationType] or 0
end

function Proficiency.getMaxExperienceByLevel(level, item)
	local vocationType = Proficiency.getWeaponProfessionType(item)
	local stage = Proficiency.ExperienceTable[level]
	return stage and stage[vocationType] or 0
end

function Proficiency.getCurrentLevelByExp(item, currentExperience)
	local vocationType = Proficiency.getWeaponProfessionType(item)
	local currentLevel = 0
	for level, data in ipairs(Proficiency.ExperienceTable) do
		if currentExperience >= (data[vocationType] or 0) then
			currentLevel = level
		end
	end
	return currentLevel
end

function Proficiency.getLevelPercent(currentExperience, level, item)
	local vocationType = Proficiency.getWeaponProfessionType(item)
	local prevStage = level > 1 and Proficiency.ExperienceTable[level - 1] or { regular = 0, knight = 0, crossbow = 0 }
	local curStage = Proficiency.ExperienceTable[level] or prevStage
	local xpMin = prevStage[vocationType] or 0
	local xpMax = curStage[vocationType] or (xpMin + 1)
	if xpMax <= xpMin then return 0 end
	return math.floor(math.max(0, math.min(100, (currentExperience - xpMin) * 100 / (xpMax - xpMin))))
end

function Proficiency.getNextLevelExperience(currentExp, item)
	local profile = Proficiency.getProfileForItem(item)
	if not profile then return 0 end
	local vocationType = Proficiency.getWeaponProfessionType(item)
	local maxLevels = #(profile.Levels or {})
	for i = 1, maxLevels + 2 do
		local stageExp = Proficiency.ExperienceTable[i]
		if stageExp and (stageExp[vocationType] or 0) > currentExp then
			return stageExp[vocationType]
		end
	end
	return 0
end

function Proficiency.getNextLevelIndex(currentExp, item)
	local profile = Proficiency.getProfileForItem(item)
	if not profile then return 0 end
	local vocationType = Proficiency.getWeaponProfessionType(item)
	local maxLevels = #(profile.Levels or {})
	for i = 1, maxLevels + 2 do
		local stageExp = Proficiency.ExperienceTable[i]
		if stageExp and (stageExp[vocationType] or 0) > currentExp then
			return i
		end
	end
	return maxLevels + 1
end

function Proficiency.getUnlockedLevelCount(item, currentExp)
	local profile = Proficiency.getProfileForItem(item)
	if not profile then return 0 end
	local vocationType = Proficiency.getWeaponProfessionType(item)
	local maxLevels = #(profile.Levels or {})
	local unlocked = 0
	for i = 1, maxLevels do
		local stageExp = Proficiency.ExperienceTable[i]
		if stageExp and currentExp >= (stageExp[vocationType] or 0) then
			unlocked = unlocked + 1
		end
	end
	return unlocked
end

function Proficiency.hasUnusedPerk(item, currentExp)
	local profile = Proficiency.getProfileForItem(item)
	if not profile then return false end
	local unlocked = Proficiency.getUnlockedLevelCount(item, currentExp)
	if unlocked == 0 then return false end

	local weaponData = Proficiency.loadWeaponData(item)
	if not weaponData then return true end

	local selectedPerks = weaponData.perks or {}
	return unlocked > #selectedPerks
end

function Proficiency.getPerkInfo(profile, level, index)
	if not profile or not profile.Levels then return nil end
	local levelData = profile.Levels[level + 1] -- 0-indexed to 1-indexed
	if not levelData or not levelData.Perks then return nil end
	return levelData.Perks[index + 1]
end

function Proficiency.getPerkName(perkData)
	local name = Proficiency.PerkNames[perkData.Type] or "Unknown Perk"
	if perkData.SkillId and perkData.Type == 3 then
		local skillName = Proficiency.SkillNames[perkData.SkillId] or "Unknown Skill"
		return name .. " (" .. skillName .. ")"
	end
	return name
end

Proficiency.SkillNames = {
	[1]  = "Magic Level",
	[6]  = "Shielding",
	[7]  = "Distance",
	[8]  = "Sword",
	[9]  = "Club",
	[10] = "Axe",
	[11] = "Fist",
}

-- KV storage helpers
function Proficiency.getWeaponKV(player, itemId)
	return player:kv():scoped("weapon-proficiency"):get(tostring(itemId))
end

function Proficiency.saveWeaponData(player, itemId, data)
	local wrapped = {
		experience = data.experience or 0,
		perks = data.perks or {},
		mastered = data.mastered or false,
	}
	player:kv():scoped("weapon-proficiency"):set(tostring(itemId), wrapped)
end

function Proficiency.loadWeaponData(item)
	-- item must be an equipped item with a player context
	-- We pass the data directly from the talkaction/script
	return nil
end

function Proficiency.addWeaponXP(player, amount)
	if not configManager.getBoolean(configKeys.WEAPON_PROFICIENCY_ENABLED) then
		return
	end

	local weapon = player:getSlotItem(CONST_SLOT_LEFT)
	if not weapon then return end

	local itemId = weapon:getId()
	local profile = Proficiency.getProfileForItem(weapon)
	if not profile then return end

	-- Apply multiplier
	local multiplier = configManager.getFloat(configKeys.WEAPON_PROFICIENCY_GAIN_MULTIPLIER) or 0.33
	amount = math.floor(amount * multiplier)
	if amount <= 0 then return end

	-- Load current data from KV
	local kvScope = player:kv():scoped("weapon-proficiency")
	local stored = kvScope:get(tostring(itemId))
	local currentExp = 0
	local currentPerks = {}
	local mastered = false

	if stored then
		if type(stored) == "table" then
			currentExp = stored.experience or 0
			currentPerks = stored.perks or {}
			mastered = stored.mastered or false
		elseif type(stored) == "number" then
			currentExp = stored
		end
	end

	if mastered then
		return -- Already mastered, don't add more XP
	end

	local newExp = currentExp + amount
	local maxExp = Proficiency.getMaxExperience(profile, weapon)
	if newExp >= maxExp then
		newExp = maxExp
		mastered = true
	end

	-- Check if there's an upgrade available (unused perk slot)
	local oldLevel = Proficiency.getCurrentLevelByExp(weapon, currentExp)
	local newLevel = Proficiency.getCurrentLevelByExp(weapon, newExp)
	local hasUnused = Proficiency.hasUnusedPerk(weapon, newExp)

	-- Save
	Proficiency.saveWeaponData(player, itemId, {
		experience = newExp,
		perks = currentPerks,
		mastered = mastered,
	})

	-- Notify client
	sendProficiencyNotification(player, itemId, newExp, hasUnused)

	-- Level up notification
	if newLevel > oldLevel then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE,
			string.format("Your weapon has reached a new mastery level! (%d/%d)", newLevel, #(profile.Levels or {})))
	end
end

function Proficiency.getDisplayInfo(player)
	local weapon = player:getSlotItem(CONST_SLOT_LEFT)
	if not weapon then
		player:sendCancelMessage("You need a weapon equipped in your left hand.")
		return nil
	end

	local itemId = weapon:getId()
	local profile = Proficiency.getProfileForItem(weapon)
	if not profile then
		player:sendCancelMessage("This weapon has no proficiency profile.")
		return nil
	end

	local kvScope = player:kv():scoped("weapon-proficiency")
	local stored = kvScope:get(tostring(itemId))
	local currentExp = 0
	local currentPerks = {}

	if stored then
		if type(stored) == "table" then
			currentExp = stored.experience or 0
			currentPerks = stored.perks or {}
		elseif type(stored) == "number" then
			currentExp = stored
		end
	end

	return {
		item = weapon,
		itemId = itemId,
		profile = profile,
		experience = currentExp,
		perks = currentPerks,
	}
end

function Proficiency.applyPerk(player, slot, perkName)
	local info = Proficiency.getDisplayInfo(player)
	if not info then return false end

	if type(slot) == "string" then
		slot = tonumber(slot)
	end
	if not slot or slot < 0 then
		player:sendCancelMessage("Invalid slot. Use: !perk apply <slot>, <perk name>")
		return false
	end

	if slot >= #(info.profile.Levels or {}) then
		player:sendCancelMessage("Slot " .. slot .. " does not exist (max: " .. (#(info.profile.Levels or {}) - 1) .. ").")
		return false
	end

	-- Check if level is unlocked
	local unlocked = Proficiency.getUnlockedLevelCount(info.item, info.experience)
	if slot >= unlocked then
		player:sendCancelMessage("Slot " .. slot .. " is locked. You need more weapon XP to unlock it.")
		return false
	end

	-- Check if in protection zone
	if not player:isInProtectionZone() then
		player:sendCancelMessage("You can only change perks in a protection zone.")
		return false
	end

	-- Find matching perk
	local levelData = info.profile.Levels[slot + 1]
	if not levelData or not levelData.Perks then
		player:sendCancelMessage("Slot " .. slot .. " has no available perks.")
		return false
	end

	local foundIndex = nil
	local foundPerk = nil
	for i, perk in ipairs(levelData.Perks) do
		local name = Proficiency.getPerkName(perk):lower()
		if name:find(perkName:lower(), 1, true) then
			foundIndex = i - 1
			foundPerk = perk
			break
		end
	end

	if not foundPerk then
		local avail = {}
		for i, perk in ipairs(levelData.Perks) do
			avail[#avail + 1] = Proficiency.getPerkName(perk)
		end
		player:sendCancelMessage("Perk '" .. perkName .. "' not found in slot " .. slot ..
			". Available perks: " .. table.concat(avail, ", "))
		return false
	end

	-- Update perks
	local newPerks = {}
	local updated = false
	for i = 1, unlocked do
		if i - 1 == slot then
			newPerks[i] = foundIndex
			updated = true
		else
			-- Keep existing or leave empty
			newPerks[i] = info.perks[i] or nil
		end
	end

	-- Save
	Proficiency.saveWeaponData(player, info.itemId, {
		experience = info.experience,
		perks = newPerks,
		mastered = info.experience >= Proficiency.getMaxExperience(info.profile, info.item),
	})

	-- Send update to client
	local perkLevels = {}
	for i, index in ipairs(newPerks) do
		if index then
			perkLevels[#perkLevels + 1] = i - 1
		end
	end
	sendWeaponProficiency(player, info.itemId, info.experience, perkLevels)

	player:sendTextMessage(MESSAGE_EVENT_ADVANCE,
		string.format("Applied '%s' to slot %d.", Proficiency.getPerkName(foundPerk), slot))
	return true
end

Proficiency.loadJson()

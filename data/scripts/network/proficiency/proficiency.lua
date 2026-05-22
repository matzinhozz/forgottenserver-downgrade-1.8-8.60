-- Weapon Proficiency Network Handlers
-- Opcode 0xE7: Client -> Server (weapon proficiency action)
-- Opcode 0xEA: Client -> Server (apply perks)

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

local action = PacketHandler(0xE7)

function action.onReceive(player, msg)
	if not configManager.getBoolean(configKeys.WEAPON_PROFICIENCY_ENABLED) then
		return
	end

	local actionType = msg:getByte()
	local itemId = 0
	if actionType ~= 1 then
		itemId = msg:getU16()
	end

	if actionType == 1 then
		-- Request all tracked weapons
		local kvScope = player:kv():scoped("weapon-proficiency")
		for _, key in pairs(kvScope:keys()) do
			local weaponId = tonumber(key)
			if weaponId then
				local stored = kvScope:get(key)
				local exp = 0
				local perks = {}
				if type(stored) == "table" then
					exp = stored.experience or 0
					perks = stored.perks or {}
				elseif type(stored) == "number" then
					exp = stored
				end

				local perkLevels = {}
				for i, index in ipairs(perks) do
					if index ~= nil then
						perkLevels[#perkLevels + 1] = i - 1
					end
				end
				sendWeaponProficiency(player, weaponId, exp, perkLevels)
			end
		end

	elseif actionType == 0 then
		-- Request single weapon info
		if itemId > 0 then
			local kvScope = player:kv():scoped("weapon-proficiency")
			local stored = kvScope:get(tostring(itemId))
			local exp = 0
			local perks = {}
			if type(stored) == "table" then
				exp = stored.experience or 0
				perks = stored.perks or {}
			elseif type(stored) == "number" then
				exp = stored
			end

			local perkLevels = {}
			for i, index in ipairs(perks) do
				if index ~= nil then
					perkLevels[#perkLevels + 1] = i - 1
				end
			end
			sendWeaponProficiency(player, itemId, exp, perkLevels)
		end

	elseif actionType == 2 then
		-- Clear/reset perks
		if itemId > 0 then
			local weapon = player:getSlotItem(CONST_SLOT_LEFT)
			if not weapon then return end

			if not player:isInProtectionZone() then
				player:sendCancelMessage("You can only reset perks in a protection zone.")
				return
			end

			local kvScope = player:kv():scoped("weapon-proficiency")
			local stored = kvScope:get(tostring(itemId))
			local exp = 0
			if type(stored) == "table" then
				exp = stored.experience or 0
			elseif type(stored) == "number" then
				exp = stored
			end

			local maxExp = 0
			local weaponT = player:getSlotItem(CONST_SLOT_LEFT)
			if weaponT and weaponT:getId() == itemId then
				local profile = Proficiency.getProfileForItem(weaponT)
				if profile then
					maxExp = Proficiency.getMaxExperience(profile, weaponT)
				end
			end

			Proficiency.saveWeaponData(player, itemId, {
				experience = exp,
				perks = {},
				mastered = (maxExp > 0 and exp >= maxExp),
			})

			sendWeaponProficiency(player, itemId, exp, {})
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "Weapon perks have been reset.")
		end
	end
end

action:register()

local apply = PacketHandler(0xEA)

function apply.onReceive(player, msg)
	if not configManager.getBoolean(configKeys.WEAPON_PROFICIENCY_ENABLED) then
		return
	end

	local itemId = msg:getU16()
	local perkCount = msg:getByte()

	if not player:isInProtectionZone() then
		player:sendCancelMessage("You can only change perks in a protection zone.")
		return
	end

	local weapon = player:getSlotItem(CONST_SLOT_LEFT)
	if not weapon then
		player:sendCancelMessage("You need a weapon in your left hand.")
		return
	end

	if weapon:getId() ~= itemId then
		player:sendCancelMessage("Weapon mismatch. Unequip and re-equip your left hand weapon.")
		return
	end

	local newPerks = {}
	for i = 1, perkCount do
		local level = msg:getByte()
		local index = msg:getByte()
		newPerks[level + 1] = index
	end

	-- Load current XP
	local kvScope = player:kv():scoped("weapon-proficiency")
	local stored = kvScope:get(tostring(itemId))
	local exp = 0
	if type(stored) == "table" then
		exp = stored.experience or 0
	elseif type(stored) == "number" then
		exp = stored
	end

	local maxExp = 0
	local profile = Proficiency.getProfileForItem(weapon)
	if profile then
		maxExp = Proficiency.getMaxExperience(profile, weapon)
	end

	Proficiency.saveWeaponData(player, itemId, {
		experience = exp,
		perks = newPerks,
		mastered = (maxExp > 0 and exp >= maxExp),
	})

	local perkLevels = {}
	for i, idx in ipairs(newPerks) do
		if idx ~= nil then
			perkLevels[#perkLevels + 1] = i - 1
		end
	end
	sendWeaponProficiency(player, itemId, exp, perkLevels)
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "Weapon perks updated.")
end

apply:register()

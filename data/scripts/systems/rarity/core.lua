-- Rarity System Core
-- rollRarity, itemAttributes, processMonsterLoot

function rollRarity(item, forcedTier, minTier)
	if not item or item:isStackable() then return 0 end

	local itemType = ItemType(item:getId())
	if not itemType then return 0 end

	local available = {}
	for attrKey, attrDef in pairs(rarityConfig.attributes) do
		if attrDef.eligible and attrDef.eligible(itemType) then
			if item:getRarityStat(attrDef.statKey) == 0 then
				available[#available + 1] = attrKey
			end
		end
	end

	if #available == 0 then return 0 end

	local tier
	if type(forcedTier) == "number" and forcedTier >= 1 and forcedTier <= 3 then
		tier = forcedTier
	elseif forcedTier == "rare" then
		tier = 1
	elseif forcedTier == "epic" then
		tier = 2
	elseif forcedTier == "legendary" then
		tier = 3
	elseif forcedTier == true then
		tier = math.random(1, 3)
	else
		local roll = math.random(1, 10000)
		local tiers = rarityConfig.tiers
		local cumulative = 0
		for i = 3, 1, -1 do
			local tierName = ({ "rare", "epic", "legendary" })[i]
			cumulative = cumulative + tiers[tierName].chance
			if roll <= cumulative then tier = i; break end
		end
		if not tier then return 0 end
	end

	if minTier and minTier > 0 and tier < minTier then tier = minTier end

	local tierNames = { "rare", "epic", "legendary" }
	local tierName = tierNames[tier]
	local tierDef = rarityConfig.tiers[tierName]

	local rolledStats = {}
	local statCount = 1
	if math.random(1, 100) <= tierDef.secondStatChance then statCount = 2 end

	local availCopy = {}
	for i = 1, #available do availCopy[i] = available[i] end

	for _ = 1, statCount do
		if #availCopy == 0 then break end
		local idx = math.random(1, #availCopy)
		local attrKey = availCopy[idx]
		table.remove(availCopy, idx)

		local attrDef = rarityConfig.attributes[attrKey]
		if not attrDef then break end

		local range = attrDef[tierName]
		if not range then break end

		local value = math.random(range[1], range[2])
		rolledStats[attrKey] = value

		item:setRarityStat(attrDef.statKey, value)

		local balanceSpell = rarityBalancing.spells[attrKey]
		if balanceSpell then
			item:setRarityStat(attrDef.statKey .. "DmgMin", balanceSpell.dmgMin)
			item:setRarityStat(attrDef.statKey .. "DmgMax", balanceSpell.dmgMax)
			item:setRarityStat("spellScaleLevel", rarityBalancing.spellScale.level)
			item:setRarityStat("spellScaleMagic", rarityBalancing.spellScale.magic)
			item:setRarityStat("spellScaleDivisor", rarityBalancing.spellScale.divisor)
		end

		if attrDef.statKey == "attack" then
			local current = itemType:getAttack()
			item:setAttribute(ITEM_ATTRIBUTE_ATTACK, current + value)
		elseif attrDef.statKey == "defense" then
			local current = itemType:getDefense()
			item:setAttribute(ITEM_ATTRIBUTE_DEFENSE, current + value)
		elseif attrDef.statKey == "armor" then
			local current = itemType:getArmor()
			item:setAttribute(ITEM_ATTRIBUTE_ARMOR, current + value)
		end
	end

	if next(rolledStats) == nil then return 0 end

	item:setRarityTier(tier)

	if item:getRarityStat("onKillBuffDuration") == 0 then
		item:setRarityStat("onKillBuffDuration", rarityBalancing.onKill.buffDuration)
		item:setRarityStat("onKillBuffCritChance", rarityBalancing.onKill.critChance)
		item:setRarityStat("onKillBuffCritAmount", rarityBalancing.onKill.critAmount)
		item:setRarityStat("onKillBuffMaxHpPercent", rarityBalancing.onKill.maxHpPercent)
		item:setRarityStat("onKillBuffMaxMpPercent", rarityBalancing.onKill.maxMpPercent)
	end

	local descParts = {}
	for attrKey, value in pairs(rolledStats) do
		local attrDef = rarityConfig.attributes[attrKey]
		if attrDef then
			local suffix = attrDef.isPercent and "%" or ""
			descParts[#descParts + 1] = "[" .. attrDef.name .. ": +" .. value .. suffix .. "]"
		end
	end

	local desc = table.concat(descParts, "\n")
	local existingDesc = item:getAttribute(ITEM_ATTRIBUTE_DESCRIPTION)
	if existingDesc and existingDesc ~= "" then
		desc = existingDesc .. "\n" .. desc
	end
	item:setAttribute(ITEM_ATTRIBUTE_DESCRIPTION, desc)
	item:setAttribute(ITEM_ATTRIBUTE_ARTICLE, tierDef.article)

	return tier
end

function rollRarityContainer(container, forcedTier, minTier)
	if not container then return 0 end
	local count = 0
	local items = container:getItems()
	if not items then return 0 end
	for _, item in ipairs(items) do
		if item:isContainer() then
			count = count + rollRarityContainer(Container(item:getId()), forcedTier, minTier)
		else
			local tier = rollRarity(item, forcedTier, minTier)
			if tier > 0 then count = count + 1 end
		end
	end
	return count
end

function itemAttributes(player, item, slot, equip)
	if not item or item:getRarityTier() == 0 then return end

	for subId = 100, 2000 do
		player:removeCondition(CONDITION_ATTRIBUTES, CONDITIONID_DEFAULT, subId)
	end

	if not equip then return end

	for attrKey, attrDef in pairs(rarityConfig.attributes) do
		local value = item:getRarityStat(attrDef.statKey)
		if value > 0 and attrDef.onEquip then
			attrDef.onEquip(player, slot, value, true)
		end
	end

	local expValue = item:getRarityStat("experience")
	if expValue > 0 then
		local condition = Condition(CONDITION_ATTRIBUTES)
		condition:setParameter(CONDITION_PARAM_SUBID, 1500 + slot)
		condition:setParameter(CONDITION_PARAM_EXPERIENCE, expValue)
		condition:setParameter(CONDITION_PARAM_TICKS, -1)
		player:addCondition(condition)
	end
end

function getMonsterLootTier(monsterName)
	if not monsterName then return nil end
	local name = monsterName:lower()
	for tierName, tierDef in pairs(rarityConfig.monsterTiers) do
		if tierDef.monsters then
			for _, mName in ipairs(tierDef.monsters) do
				if mName:lower() == name then return tierName end
			end
		end
	end
	return nil
end

function processMonsterLoot(monster, corpse)
	if not RARITY_SYSTEM_ENABLED then return end

	local monsterName = monster:getName():lower()
	local tierName = getMonsterLootTier(monsterName)

	local chance = rarityConfig.defaultMonsterChance
	local minTier = rarityConfig.defaultMinTier

	if tierName and rarityConfig.monsterTiers[tierName] then
		local mt = rarityConfig.monsterTiers[tierName]
		chance = mt.chance
		minTier = mt.minTier
	end

	if math.random(1, 100) > chance then return end

	local count = rollRarityContainer(corpse, nil, minTier)

	if count > 0 and rarityConfig.popupText and rarityConfig.animations then
		local spectators = Game.getSpectators(corpse:getPosition(), false, true, 7, 7, 5, 5)
		for _, spectator in ipairs(spectators) do
			spectator:say("Rare loot!", TALKTYPE_MONSTER_SAY, false, spectator, corpse:getPosition())
		end
		corpse:getPosition():sendMagicEffect(rarityConfig.popupEffect)
	end
end

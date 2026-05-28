-- Rarity Event Registrations

local rarityDropLoot = Event()
function rarityDropLoot.onDropLoot(monster, corpse)
	if not RARITY_SYSTEM_ENABLED then return end
	if not corpse then return end
	processMonsterLoot(monster, corpse)
end
rarityDropLoot:register()

local rarityInventory = Event()
function rarityInventory.onInventoryUpdate(player, item, slot, equip)
	if not RARITY_SYSTEM_ENABLED then return end
	itemAttributes(player, item, slot, equip)
	if not equip then
		for subId = 100, 2000 do
			player:removeCondition(CONDITION_ATTRIBUTES, CONDITIONID_DEFAULT, subId)
		end
		for i = CONST_SLOT_FIRST, CONST_SLOT_LAST do
			local otherItem = player:getSlotItem(i)
			if otherItem and otherItem:getRarityTier() > 0 then
				itemAttributes(player, otherItem, i, true)
			end
		end
	end
end
rarityInventory:register()

local rarityLogin = CreatureEvent("rarityLogin")
function rarityLogin.onLogin(player)
	if not RARITY_SYSTEM_ENABLED then return true end
	player:registerEvent("rarityHealthChange")
	player:registerEvent("rarityManaChange")
	for slot = CONST_SLOT_FIRST, CONST_SLOT_LAST do
		local item = player:getSlotItem(slot)
		if item and item:getRarityTier() > 0 then
			itemAttributes(player, item, slot, true)
		end
	end
	local health = player:getHealth()
	local maxHealth = player:getMaxHealth()
	if health > maxHealth then player:addHealth(maxHealth - health) end
	local mana = player:getMana()
	local maxMana = player:getMaxMana()
	if mana > maxMana then player:addMana(maxMana - mana) end
	return true
end
rarityLogin:register()

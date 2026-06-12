local hirelingLamp = Action()

function hirelingLamp.onUse(player, item, fromPosition, target, toPosition, isHotkey)
	local spawnPosition = player:getPosition()
	local hirelingId = item:getAttribute(ITEM_ATTRIBUTE_ACTIONID)
	if hirelingId == 0 then
		player:getPosition():sendMagicEffect(CONST_ME_POFF)
		player:sendTextMessage(MESSAGE_INFO_DESCR, "This lamp has no hireling bound to it.")
		return true
	end

	local house = spawnPosition and spawnPosition:getTile() and spawnPosition:getTile():getHouse()
	if not house then
		player:getPosition():sendMagicEffect(CONST_ME_POFF)
		player:sendTextMessage(MESSAGE_INFO_DESCR, "You may use this only inside a house.")
		return true
	end

	if house:getDoorIdByPosition(spawnPosition) then
		player:getPosition():sendMagicEffect(CONST_ME_POFF)
		player:sendTextMessage(MESSAGE_INFO_DESCR, "You cannot spawn a hireling on the door.")
		return true
	end

	if getHirelingByPosition(spawnPosition) then
		player:getPosition():sendMagicEffect(CONST_ME_POFF)
		player:sendTextMessage(MESSAGE_INFO_DESCR, "You cannot spawn another hireling here.")
		return true
	end

	if house:getOwnerGuid() ~= player:getGuid() then
		player:getPosition():sendMagicEffect(CONST_ME_POFF)
		player:sendTextMessage(MESSAGE_INFO_DESCR, "You cannot spawn a hireling on another person's house.")
		return true
	end

	local hireling = getHirelingById(hirelingId)
	if not hireling then
		player:getPosition():sendMagicEffect(CONST_ME_POFF)
		player:sendTextMessage(MESSAGE_INFO_DESCR, "This hireling no longer exists.")
		return true
	end

	hireling:setPosition(spawnPosition)
	item:remove(1)
	hireling:spawn()
	spawnPosition:sendMagicEffect(CONST_ME_TELEPORT)
	return true
end

hirelingLamp:id(29432)
hirelingLamp:register()

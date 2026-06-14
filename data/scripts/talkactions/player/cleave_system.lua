local cleaveStorage = 40002

local function isCleaveSystemEnabled()
	if CleaveSystem and CleaveSystem.enabled ~= nil then
		return CleaveSystem.enabled
	end

	if configManager and configKeys then
		if configKeys.CLEAVE_SYSTEM_ENABLED then
			return configManager.getBoolean(configKeys.CLEAVE_SYSTEM_ENABLED)
		end
	end

	return true
end

local cleaveTalk = TalkAction("!cleave")

function cleaveTalk.onSay(player, words, param)
	if not isCleaveSystemEnabled() then
		player:sendTextMessage(MESSAGE_INFO_DESCR, "Cleave system is not enabled on this server.")
		return true
	end

	if not CleaveSystem then
		player:sendTextMessage(MESSAGE_INFO_DESCR, "Cleave system is not configured. Contact an administrator.")
		return true
	end

	local settings = player:kv():scoped("settings")

	param = param:trim():lower()
	if param == "on" then
		settings:set("cleaveSystem", true)
		player:sendTextMessage(MESSAGE_INFO_DESCR, "Cleave system enabled.")
	elseif param == "off" then
		settings:set("cleaveSystem", false)
		player:sendTextMessage(MESSAGE_INFO_DESCR, "Cleave system disabled.")
	else
		local enabled = settings:get("cleaveSystem")
		if enabled == nil then
			local legacy = player:getStorageValue(cleaveStorage)
			enabled = (legacy == nil) or (legacy == 1)
			settings:set("cleaveSystem", enabled)
		end
		local stateText = (enabled == true) and "enabled" or "disabled"
		player:sendTextMessage(MESSAGE_INFO_DESCR, string.format("Cleave system: %s. Use !cleave on or !cleave off.", stateText))
	end
	return false
end

cleaveTalk:separator(" ")
cleaveTalk:register()

local talk = TalkAction("/createhirelinglamp")

function talk.onSay(player, words, param)
	if not player:getGroup():getAccess() then
		return true
	end

	if not player:isUsingAstraClient() then
		player:sendTextMessage(MESSAGE_INFO_DESCR, "This command requires AstraClient.")
		return false
	end

	local hirelingName = param
	if not hirelingName or hirelingName == "" then
		player:sendTextMessage(MESSAGE_INFO_DESCR, "Usage: /createhirelinglamp <name>")
		return false
	end

	local sex = HIRELING_SEX.MALE
	local hireling = player:addNewHireling(hirelingName, sex)
	if hireling then
		player:sendTextMessage(MESSAGE_INFO_DESCR, "Hireling '" .. hirelingName .. "' created successfully. Check your store inbox.")
	else
		player:sendTextMessage(MESSAGE_INFO_DESCR, "Failed to create hireling.")
	end
	return false
end

talk:separator(" ")
talk:register()

local talkaction = TalkAction("!quickloot")

function talkaction.onSay(player, words, param)
	print("[QuickLoot] talkaction: player=" .. player:getName() .. " param=" .. tostring(param))
	local settings = player:kv():scoped("settings")

	if param == "on" then
		settings:set("quickLoot", true)
		player:registerEvent("QuickLootKill")
		player:sendTextMessage(MESSAGE_INFO_DESCR, "QuickLoot auto-loot has been enabled.")
		print("[QuickLoot] talkaction: ENABLED for " .. player:getName())
	elseif param == "off" then
		settings:set("quickLoot", false)
		player:sendTextMessage(MESSAGE_INFO_DESCR, "QuickLoot auto-loot has been disabled.")
		print("[QuickLoot] talkaction: DISABLED for " .. player:getName())
	else
		local current = settings:get("quickLoot")
		player:sendTextMessage(MESSAGE_INFO_DESCR, "QuickLoot is currently " .. (current and "enabled" or "disabled") .. ". Use !quickloot on/off to toggle.")
		print("[QuickLoot] talkaction: status check, current=" .. tostring(current))
	end
	return true
end

talkaction:separator(" ")
talkaction:register()
print("[QuickLoot] talkaction registered: !quickloot")

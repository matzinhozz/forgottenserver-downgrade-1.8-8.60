local loot = ChatChannel(10, "Loot")
loot:public(true)

function loot.onSpeak(player, type, message)
	return false
end

loot:register()

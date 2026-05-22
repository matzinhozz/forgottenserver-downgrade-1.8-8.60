local perkApply = TalkAction("!perk")

function perkApply.onSay(player, words, param)
	if not configManager.getBoolean(configKeys.WEAPON_PROFICIENCY_ENABLED) then
		player:sendCancelMessage("Weapon Proficiency system is disabled.")
		return false
	end

	-- param format: "apply <slot>, <perk name>"
	-- or: "apply, <slot>, <perk name>"
	param = param:trim()
	local rest = param:match("^apply%s*,?%s*(.+)$")
	if not rest then
		player:sendCancelMessage("Usage: !perk apply <slot>, <perk name>")
		player:sendCancelMessage("Example: !perk apply 0, Skill Bonus")
		player:sendCancelMessage("Use !proficiency slot to see available perks.")
		return false
	end

	local slotStr, perkName = rest:match("^%s*(%d+)%s*,%s*(.+)$")
	if not slotStr then
		player:sendCancelMessage("Usage: !perk apply <slot>, <perk name>")
		player:sendCancelMessage("Example: !perk apply 0, Skill Bonus")
		return false
	end

	local slot = tonumber(slotStr)
	perkName = perkName:trim()

	if not slot or slot < 0 then
		player:sendCancelMessage("Invalid slot number. Must be 0 or higher.")
		return false
	end

	Proficiency.applyPerk(player, slot, perkName)
	return false
end

perkApply:separator(" ")
perkApply:register()

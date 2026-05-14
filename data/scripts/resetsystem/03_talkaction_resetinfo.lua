local talkResetInfo = TalkAction("!resetinfo")

function talkResetInfo.onSay(player, words, param)
	if not player or not player:isPlayer() then
		return false
	end

	local resets = player:getResetCount()
	local vocId = player:getVocationId()

	local dmgBonus = player:getResetDamageBonus()
	local defBonus = player:getResetDefenseBonus()
	local healBonus = player:getResetHealingBonus()
	local xpBonus = ResetBonusConfig.getTotalBonus("experience", resets, vocId)
	local atkSpdBonus = player:getResetAttackSpeedBonus()
	local hpBonus = player:getResetHpBonus()
	local manaBonus = player:getResetManaBonus()
	local manaPotBonus = player:getResetManaPotionBonus()
	local manaSpellBonus = player:getResetManaSpellBonus()

	local msg = string.format(
		"[Reset Info] Resets: %d | Damage: %.1f%% | Defense: %.1f%% | Healing: %.1f%% | XP: %.1f%% | AtkSpeed: -%dms | HP+: %d | Mana+: %d | ManaPot: %.1f%% | ManaSpell: %.1f%%",
		resets, dmgBonus, defBonus, healBonus, xpBonus, atkSpdBonus, hpBonus, manaBonus, manaPotBonus, manaSpellBonus
	)

	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, msg)
	return false
end

talkResetInfo:groupType("normal")
talkResetInfo:register()

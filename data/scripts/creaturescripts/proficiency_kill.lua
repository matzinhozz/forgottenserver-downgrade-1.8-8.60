-- Proficiency: Award XP to left-hand weapon on monster kills
local proficiencyKill = CreatureEvent("ProficiencyKill")

function proficiencyKill.onKill(player, target, lastHit)
	if not configManager.getBoolean(configKeys.WEAPON_PROFICIENCY_ENABLED) then
		return true
	end

	if not target or not target:isMonster() then
		return true
	end

	-- Base XP: 1-5 per kill based on monster level/hp proxy
	local monsterType = target:getType()
	if not monsterType then return true end

	local hp = target:getMaxHealth()
	local baseXP = math.max(1, math.min(100, math.floor(math.sqrt(hp) / 20)))
	baseXP = math.max(1, math.min(50, baseXP))

	Proficiency.addWeaponXP(player, baseXP)
	return true
end

proficiencyKill:register()
